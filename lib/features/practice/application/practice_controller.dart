import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/audio/dsp/chord_detector.dart';
import 'package:fretlight/core/audio/engine/dsp_worker.dart';
import 'package:fretlight/core/audio/input/audio_input_source.dart';
import 'package:fretlight/core/audio/input/mic_lifecycle.dart';
import 'package:fretlight/core/audio/input/shared_mic.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/features/identify/domain/chord_smoother.dart';
import 'package:fretlight/features/practice/domain/practice_session.dart';

/// What to practise, as handed to the practice screen.
@immutable
final class PracticePlan {
  const PracticePlan({required this.title, required this.sounding, this.capo = 0, this.lines});

  final String title;

  /// The chords as they sound (what the mic will hear), in order.
  final List<Chord> sounding;

  /// With a capo, the shapes shown are the sounding chords moved down.
  final int capo;

  /// Optional lyric line per chord, shown under the target.
  final List<String?>? lines;

  Chord shapeOf(Chord sounding) => Transposer.shapeForCapo(sounding, capo);
}

@immutable
final class PracticeState {
  const PracticeState({
    this.plan,
    this.session,
    this.status = MicStatus.idle,
    this.heard,
    this.verdict,
    this.version = 0,
  });

  final PracticePlan? plan;

  /// Mutable session; [version] bumps whenever it changes so widgets rebuild.
  final PracticeSession? session;
  final MicStatus status;
  final ChordReading? heard;
  final Verdict? verdict;
  final int version;

  PracticeState copyWith({
    PracticePlan? plan,
    PracticeSession? session,
    MicStatus? status,
    ChordReading? Function()? heard,
    Verdict? Function()? verdict,
  }) => PracticeState(
    plan: plan ?? this.plan,
    session: session ?? this.session,
    status: status ?? this.status,
    heard: heard != null ? heard() : this.heard,
    verdict: verdict != null ? verdict() : this.verdict,
    version: version + 1,
  );
}

final practiceProvider = NotifierProvider<PracticeController, PracticeState>(
  PracticeController.new,
);

/// Listens while you play through a sequence and moves on when you play
/// the chord shown.
final class PracticeController extends Notifier<PracticeState> {
  late MicLifecycle _mic;
  DspWorker? _worker;
  StreamSubscription<ChordEstimate>? _chords;
  StreamSubscription<Uint8List>? _pcm;
  ChordSmoother? _smoother;

  /// While the app itself strums a reference chord, the mic would hear it
  /// and count it: readings are ignored until then.
  DateTime _deafUntil = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  PracticeState build() {
    _mic = MicLifecycle(
      input: ref.watch(sharedMicProvider).client(),
      onStatus: (s) => state = state.copyWith(status: s),
      onStart: _onStart,
      onStop: _onStop,
      isAlive: () => ref.mounted,
    );
    ref.onDispose(() {
      unawaited(_mic.dispose());
      _worker?.dispose();
    });
    return const PracticeState();
  }

  void begin(PracticePlan plan) {
    _smoother?.reset();
    state = PracticeState(
      plan: plan,
      session: PracticeSession(plan.sounding),
      status: state.status,
      version: state.version + 1,
    );
  }

  Future<void> setActive({required bool active}) => _mic.setActive(active: active);

  Future<void> requestPermission() => _mic.requestPermission();

  Future<void> openSettings() => _mic.openSettings();

  void skip() {
    state.session?.skip();
    state = state.copyWith(heard: () => null, verdict: () => null);
  }

  void restart() {
    final plan = state.plan;
    if (plan != null) begin(plan);
  }

  /// Call before the app plays a reference strum of [duration].
  void deafen(Duration duration) => _deafUntil = DateTime.now().add(duration);

  Future<void> _onStart(InputDescription description, Stream<Uint8List> pcm) async {
    final worker = _worker ??= await DspWorker.spawn(
      sampleRate: description.sampleRate,
      chords: true,
    );
    worker.reset();
    final detector = ChromaChordDetector(sampleRate: description.sampleRate);
    final smoother = _smoother = ChordSmoother(
      hopSeconds: detector.windowSize / 4 / description.sampleRate,
    );
    _chords = worker.chordFrames.listen((e) {
      final reading = smoother.update(e);
      final session = state.session;
      if (reading == null || session == null || session.done) return;
      if (DateTime.now().isBefore(_deafUntil)) return;
      final verdict = session.hear(reading);
      if (verdict != null) {
        state = state.copyWith(heard: () => reading, verdict: () => verdict);
      }
    });
    _pcm = pcm.listen(worker.push);
  }

  Future<void> _onStop() async {
    await _pcm?.cancel();
    await _chords?.cancel();
    _pcm = null;
    _chords = null;
    _smoother = null;
  }
}
