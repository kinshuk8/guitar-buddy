import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/audio/dsp/chord_detector.dart';
import 'package:fretlight/core/audio/engine/dsp_worker.dart';
import 'package:fretlight/core/audio/input/audio_input_source.dart';
import 'package:fretlight/core/audio/input/mic_lifecycle.dart';
import 'package:fretlight/core/audio/input/shared_mic.dart';
import 'package:fretlight/core/audio/listening.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/widgets/mic_level.dart';
import 'package:fretlight/features/identify/domain/chord_smoother.dart';
import 'package:fretlight/features/learn/application/progress_controller.dart';
import 'package:fretlight/features/practice/domain/practice_session.dart';
import 'package:fretlight/features/settings/application/chord_matching.dart';
import 'package:fretlight/features/settings/application/sensitivity.dart';

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

  /// When the current stretch of listening began: practice time counts
  /// while the screen is open and listening, not while it sits behind
  /// another screen.
  DateTime? _since;
  bool _active = false;

  /// The finished run has been added to progress (once per run).
  bool _recorded = false;

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
    _addTime();
    _since = _active ? DateTime.now() : null;
    _recorded = false;
    _smoother?.reset();
    state = PracticeState(
      plan: plan,
      session: PracticeSession(plan.sounding, matching: ref.read(chordMatchingProvider)),
      status: state.status,
      version: state.version + 1,
    );
  }

  Future<void> setActive({required bool active}) {
    _active = active;
    if (active) {
      _since ??= state.session?.done ?? true ? null : DateTime.now();
    } else {
      _addTime();
    }
    return _mic.setActive(active: active);
  }

  /// The practice screen closed: count the time so far.
  void leave() {
    _active = false;
    _addTime();
  }

  /// Adds the listening time since [_since] to today's practice.
  void _addTime() {
    final since = _since;
    _since = null;
    if (since == null) return;
    // Long idle stretches (the phone left on the stand) don't count past
    // a reasonable session.
    var time = DateTime.now().difference(since);
    if (time > const Duration(minutes: 30)) time = const Duration(minutes: 30);
    final progress = ref.read(progressProvider.notifier);
    // Can be called while widgets are being torn down: save a moment later.
    scheduleMicrotask(() => progress.addPractice(time: time));
  }

  /// When a run is finished: its time, and each chord's clean and missed
  /// strums for mastery.
  void _finishIfDone() {
    final session = state.session;
    final plan = state.plan;
    if (session == null || plan == null || !session.done || _recorded) return;
    _recorded = true;
    _addTime();
    final chords = <String, ({int clean, int missed})>{};
    for (final r in session.results) {
      final symbol = plan.shapeOf(r.target).symbol();
      final prev = chords[symbol] ?? (clean: 0, missed: 0);
      chords[symbol] = (
        clean: prev.clean + (r.clean ? 1 : 0),
        missed: prev.missed + r.misses + (r.skipped ? 1 : 0),
      );
    }
    final progress = ref.read(progressProvider.notifier);
    scheduleMicrotask(() => progress.recordFree(chords));
  }

  Future<void> requestPermission() => _mic.requestPermission();

  Future<void> openSettings() => _mic.openSettings();

  void skip() {
    state.session?.skip();
    state = state.copyWith(heard: () => null, verdict: () => null);
    _finishIfDone();
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
    // The screen can close while the worker spawns: nothing left to feed.
    if (!ref.mounted) {
      worker.dispose();
      _worker = null;
      return;
    }
    worker.reset();
    final detector = ChromaChordDetector(sampleRate: description.sampleRate);
    final hop = detector.windowSize / 4 / description.sampleRate;
    final floor = NoiseFloor(marginDb: ref.read(sensitivityProvider).marginDb, frameSeconds: hop);
    final level = ref.read(micLevelProvider.notifier);
    final smoother = _smoother = ChordSmoother(hopSeconds: hop, floor: floor);
    _chords = worker.chordFrames.listen((e) {
      level.report(e.rmsDb, floor.gateDb);
      final reading = smoother.update(e);
      final session = state.session;
      if (reading == null || session == null || session.done) return;
      if (DateTime.now().isBefore(_deafUntil)) return;
      final verdict = session.hear(reading);
      if (verdict != null) {
        state = state.copyWith(heard: () => reading, verdict: () => verdict);
        _finishIfDone();
      }
    });
    _pcm = pcm.listen(worker.push);
  }

  Future<void> _onStop() async {
    if (ref.mounted) ref.read(micLevelProvider.notifier).clear();
    await _pcm?.cancel();
    await _chords?.cancel();
    _pcm = null;
    _chords = null;
    _smoother = null;
  }
}
