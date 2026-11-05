import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/audio/dsp/chord_detector.dart';
import 'package:fretlight/core/audio/dsp/pitch_detector.dart';
import 'package:fretlight/core/audio/dsp/pitch_tracker.dart';
import 'package:fretlight/core/audio/engine/dsp_worker.dart';
import 'package:fretlight/core/audio/input/audio_input_source.dart';
import 'package:fretlight/core/audio/input/mic_lifecycle.dart';
import 'package:fretlight/core/audio/input/shared_mic.dart';
import 'package:fretlight/core/audio/listening.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/storage/local_store.dart';
import 'package:fretlight/core/widgets/mic_level.dart';
import 'package:fretlight/features/identify/domain/chord_smoother.dart';
import 'package:fretlight/features/identify/domain/note_session.dart';
import 'package:fretlight/features/settings/application/sensitivity.dart';
import 'package:fretlight/features/tuner/application/tuner_controller.dart';

enum IdentifyMode { note, chord }

@immutable
final class IdentifyState {
  const IdentifyState({
    this.mode = IdentifyMode.chord,
    this.status = MicStatus.idle,
    this.note,
    this.chord,
    this.input,
  });

  final IdentifyMode mode;
  final MicStatus status;
  final NoteReading? note;
  final ChordReading? chord;
  final InputDescription? input;

  IdentifyState copyWith({
    IdentifyMode? mode,
    MicStatus? status,
    NoteReading? Function()? note,
    ChordReading? Function()? chord,
    InputDescription? input,
  }) => IdentifyState(
    mode: mode ?? this.mode,
    status: status ?? this.status,
    note: note != null ? note() : this.note,
    chord: chord != null ? chord() : this.chord,
    input: input ?? this.input,
  );
}

final identifyProvider = NotifierProvider<IdentifyController, IdentifyState>(
  IdentifyController.new,
);

/// Listens and names what it hears: one note, or a strummed chord.
///
/// Uses the tuner's reference pitch and tuning, so cents and fretboard
/// positions agree with how your guitar is set up.
final class IdentifyController extends Notifier<IdentifyState> {
  static const _modeKey = 'identify.mode';

  late MicLifecycle _mic;
  late LocalStore _store;
  DspWorker? _worker;
  StreamSubscription<PitchFrame>? _pitch;
  StreamSubscription<ChordEstimate>? _chords;
  StreamSubscription<Uint8List>? _pcm;
  NoteSession? _noteSession;
  ChordSmoother? _smoother;

  @override
  IdentifyState build() {
    _store = ref.watch(localStoreProvider);
    _mic = MicLifecycle(
      input: ref.watch(sharedMicProvider).client(),
      onStatus: (s) => state = state.copyWith(
        status: s,
        note: s == MicStatus.listening ? null : () => null,
        chord: s == MicStatus.listening ? null : () => null,
      ),
      onStart: _onStart,
      onStop: _onStop,
      isAlive: () => ref.mounted,
    );
    ref.onDispose(() {
      unawaited(_mic.dispose());
      _worker?.dispose();
    });
    return IdentifyState(
      mode: IdentifyMode.values.asNameMap()[_store.setting(_modeKey)] ?? IdentifyMode.chord,
    );
  }

  Future<void> setActive({required bool active}) => _mic.setActive(active: active);

  Future<void> requestPermission() => _mic.requestPermission();

  Future<void> openSettings() => _mic.openSettings();

  Future<void> retry() => _mic.restart();

  void setMode(IdentifyMode mode) {
    if (mode == state.mode) return;
    state = state.copyWith(mode: mode, note: () => null, chord: () => null);
    _store.setSetting(_modeKey, mode.name);
    _noteSession?.reset();
    _smoother?.reset();
  }

  Future<void> _onStart(InputDescription description, Stream<Uint8List> pcm) async {
    final rate = description.sampleRate;
    final worker = _worker ??= await DspWorker.spawn(sampleRate: rate, chords: true);
    worker.reset();
    final tuner = ref.read(tunerProvider);
    final sensitivity = ref.read(sensitivityProvider);
    final level = ref.read(micLevelProvider.notifier);
    final notes = _noteSession = NoteSession(
      minClarity: sensitivity.noteClarity,
      floor: NoiseFloor(
        marginDb: sensitivity.marginDb,
        frameSeconds: analysisGeometry(rate).hop / rate,
      ),
      sampleRate: rate,
      math: PitchMath(a4: tuner.a4),
    );
    final detector = ChromaChordDetector(sampleRate: rate);
    final chordFloor = NoiseFloor(
      marginDb: sensitivity.marginDb,
      frameSeconds: detector.windowSize / 4 / rate,
    );
    final smoother = _smoother = ChordSmoother(
      hopSeconds: detector.windowSize / 4 / rate,
      floor: chordFloor,
    );
    _pitch = worker.frames.listen((f) {
      if (state.mode != IdentifyMode.note) return;
      level.report(f.rmsDb, notes.floor!.gateDb);
      final before = notes.reading;
      final after = notes.update(f);
      if (!identical(before, after)) state = state.copyWith(note: () => after);
    });
    _chords = worker.chordFrames.listen((e) {
      if (state.mode != IdentifyMode.chord) return;
      level.report(e.rmsDb, chordFloor.gateDb);
      final before = smoother.reading;
      final after = smoother.update(e);
      if (!identical(before, after)) state = state.copyWith(chord: () => after);
    });
    _pcm = pcm.listen(worker.push);
    state = state.copyWith(input: description);
  }

  Future<void> _onStop() async {
    if (ref.mounted) ref.read(micLevelProvider.notifier).clear();
    await _pcm?.cancel();
    await _pitch?.cancel();
    await _chords?.cancel();
    _pcm = null;
    _pitch = null;
    _chords = null;
    _noteSession = null;
    _smoother = null;
  }
}
