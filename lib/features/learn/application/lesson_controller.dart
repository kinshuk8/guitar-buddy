import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/audio/dsp/chord_detector.dart';
import 'package:fretlight/core/audio/dsp/onset_detector.dart';
import 'package:fretlight/core/audio/dsp/pitch_detector.dart';
import 'package:fretlight/core/audio/dsp/pitch_tracker.dart';
import 'package:fretlight/core/audio/engine/dsp_worker.dart';
import 'package:fretlight/core/audio/input/audio_input_source.dart';
import 'package:fretlight/core/audio/input/mic_lifecycle.dart';
import 'package:fretlight/core/audio/input/shared_mic.dart';
import 'package:fretlight/core/audio/listening.dart';
import 'package:fretlight/core/audio/synth/click.dart';
import 'package:fretlight/core/audio/wav.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/widgets/mic_level.dart';
import 'package:fretlight/features/chords/application/chord_player.dart';
import 'package:fretlight/features/identify/domain/chord_smoother.dart';
import 'package:fretlight/features/identify/domain/note_session.dart';
import 'package:fretlight/features/learn/application/progress_controller.dart';
import 'package:fretlight/features/learn/domain/curriculum.dart';
import 'package:fretlight/features/learn/domain/games.dart';
import 'package:fretlight/features/learn/domain/progress.dart';
import 'package:fretlight/features/practice/domain/practice_session.dart';
import 'package:fretlight/features/settings/application/chord_matching.dart';
import 'package:fretlight/features/settings/application/sensitivity.dart';
import 'package:fretlight/features/songs/application/songs_controller.dart';
import 'package:fretlight/features/songs/domain/song_timeline.dart';
import 'package:fretlight/features/tuner/application/tuner_controller.dart';

/// A monotonic clock for lessons (race timers, rhythm), overridable in tests.
final lessonClockProvider = Provider<Duration Function()>((ref) {
  final sw = Stopwatch()..start();
  return () => sw.elapsed;
});

enum LessonPhase {
  /// What the lesson is about, and Start.
  intro,

  /// A step is running.
  playing,

  /// A step finished and there's another: its result, and Next.
  stepDone,

  /// Every step done: stars, XP, bests.
  finished,
}

@immutable
final class LessonState {
  const LessonState({
    this.lesson,
    this.phase = LessonPhase.intro,
    this.step = 0,
    this.game,
    this.outcomes = const [],
    this.status = MicStatus.idle,
    this.verdict,
    this.heard,
    this.note,
    this.lastAnswer,
    this.lines,
    this.beat0,
    this.award,
    this.version = 0,
  });

  final Lesson? lesson;
  final LessonPhase phase;
  final int step;

  /// The running game: [ChordGame], [NoteGame], [RhythmGame] or
  /// [QuizGame]. Mutable; [version] bumps when it changes.
  final Object? game;
  final List<StepOutcome> outcomes;
  final MicStatus status;

  /// The last chord strum judged, and what was heard.
  final Verdict? verdict;
  final Chord? heard;

  /// The note being heard (note games).
  final NoteReading? note;

  /// Whether the last quiz answer was right.
  final bool? lastAnswer;

  /// Lyric line per chord, for song steps.
  final List<String?>? lines;

  /// Rhythm: when the first scored beat falls, on the lesson clock. Null
  /// until the count-in starts.
  final Duration? beat0;
  final Award? award;
  final int version;

  Exercise? get exercise =>
      lesson == null || step >= lesson!.steps.length ? null : lesson!.steps[step];

  LessonState copyWith({
    LessonPhase? phase,
    int? step,
    Object? Function()? game,
    List<StepOutcome>? outcomes,
    MicStatus? status,
    Verdict? Function()? verdict,
    Chord? Function()? heard,
    NoteReading? Function()? note,
    bool? Function()? lastAnswer,
    List<String?>? Function()? lines,
    Duration? Function()? beat0,
    Award? Function()? award,
  }) => LessonState(
    lesson: lesson,
    phase: phase ?? this.phase,
    step: step ?? this.step,
    game: game != null ? game() : this.game,
    outcomes: outcomes ?? this.outcomes,
    status: status ?? this.status,
    verdict: verdict != null ? verdict() : this.verdict,
    heard: heard != null ? heard() : this.heard,
    note: note != null ? note() : this.note,
    lastAnswer: lastAnswer != null ? lastAnswer() : this.lastAnswer,
    lines: lines != null ? lines() : this.lines,
    beat0: beat0 != null ? beat0() : this.beat0,
    award: award != null ? award() : this.award,
    version: version + 1,
  );
}

final lessonProvider = NotifierProvider<LessonController, LessonState>(LessonController.new);

/// Runs a lesson step by step, listening with the right detector for each
/// game, and records the result at the end.
final class LessonController extends Notifier<LessonState> {
  late MicLifecycle _mic;
  DspWorker? _worker;
  StreamSubscription<PitchFrame>? _pitch;
  StreamSubscription<ChordEstimate>? _chords;
  StreamSubscription<Uint8List>? _pcm;
  NoteSession? _notes;
  ChordSmoother? _smoother;
  OnsetDetector? _onsets;
  int _sampleRate = 48000;

  /// Mic samples seen, and the lesson-clock time the last chunk arrived:
  /// maps an onset's sample position to clock time.
  int _samples = 0;
  Duration _chunkAt = Duration.zero;

  /// While the app plays a reference chord the mic must not judge it.
  Duration _deafUntil = Duration.zero;

  /// When the lesson started, for practice time.
  Duration? _startedAt;

  Duration _now() => ref.read(lessonClockProvider)();

  @override
  LessonState build() {
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
    return const LessonState();
  }

  void open(Lesson lesson) {
    _startedAt = null;
    state = LessonState(lesson: lesson, status: state.status, version: state.version + 1);
  }

  Future<void> setActive({required bool active}) => _mic.setActive(active: active);

  Future<void> requestPermission() => _mic.requestPermission();

  Future<void> openSettings() => _mic.openSettings();

  Future<void> resumeMic() => _mic.resume();

  /// Starts the lesson from its first step.
  Future<void> start() async {
    if (state.lesson == null) return;
    _startedAt = _now();
    state = state.copyWith(outcomes: const [], award: () => null);
    await _beginStep(0);
  }

  Future<void> _beginStep(int index) async {
    final lesson = state.lesson!;
    final exercise = lesson.steps[index];
    _smoother?.reset();
    _notes?.reset();
    _onsets?.reset();
    List<String?>? lines;
    final Object game;
    switch (exercise) {
      case ChordSteps(:final sequence):
        game = ChordGame.steps(sequence, matching: ref.read(chordMatchingProvider));
      case ChangeRace():
        game = ChordGame.race(exercise, matching: ref.read(chordMatchingProvider));
      case SongSteps(:final songId, :final maxChords):
        final songs = await ref.read(songsProvider.future);
        final song = songs.firstWhere((s) => s.id == songId).song;
        final events = SongTimeline.of(song).events
            .where((e) => e.chord != null)
            .take(maxChords ?? 1 << 30)
            .toList();
        game = ChordGame.song([
          for (final e in events) e.chord!,
        ], matching: ref.read(chordMatchingProvider));
        lines = [for (final e in events) song.sections[e.section].lines[e.line].lyrics];
      case NoteSteps():
        game = NoteGame(exercise);
      case RhythmSteps():
        game = RhythmGame(exercise);
      case Quiz():
        game = QuizGame(exercise, seed: DateTime.now().millisecondsSinceEpoch);
    }
    if (!ref.mounted) return;
    state = state.copyWith(
      phase: LessonPhase.playing,
      step: index,
      game: () => game,
      verdict: () => null,
      heard: () => null,
      note: () => null,
      lastAnswer: () => null,
      lines: () => lines,
      beat0: () => null,
    );
  }

  /// Rhythm: plays a bar of count-in clicks; scoring starts after it.
  Future<void> startRhythm() async {
    final game = state.game;
    if (game is! RhythmGame || state.beat0 != null) return;
    final steps = game.steps;
    final beat = game.beatSeconds;
    const sr = 48000;
    final pcm = Float32List((steps.beatsPerBar * beat * sr).round() + sr ~/ 10);
    for (var b = 0; b < steps.beatsPerBar; b++) {
      final click = renderClick(b == 0 ? ClickVoice.strong : ClickVoice.normal, sr);
      final at = (b * beat * sr).round();
      for (var i = 0; i < click.length && at + i < pcm.length; i++) {
        pcm[at + i] += click[i];
      }
    }
    final out = ref.read(audioOutputProvider);
    const lead = Duration(milliseconds: 150);
    try {
      await out.warmUp();
      await out.scheduleOnce(encodeWav16(pcm, sr), at: out.clock + lead);
    } on Object catch (e) {
      debugPrint('Count-in failed: $e');
    }
    if (!ref.mounted) return;
    final countIn = Duration(microseconds: (steps.beatsPerBar * beat * 1e6).round());
    state = state.copyWith(beat0: () => _now() + lead + countIn);
  }

  /// Call every frame while playing: runs race clocks and ends rhythm runs.
  void tick() {
    final game = state.game;
    if (state.phase != LessonPhase.playing) return;
    final now = _now();
    if (game is ChordGame && game.race != null) {
      game.tick(now);
      if (game.done) _finishStep();
    } else if (game is RhythmGame) {
      final b0 = state.beat0;
      if (b0 != null && now > b0 + Duration(microseconds: ((game.length + 0.4) * 1e6).round())) {
        _finishStep();
      }
    }
  }

  void skip() {
    switch (state.game) {
      case final ChordGame g:
        g.skip();
        if (g.done) {
          _finishStep();
        } else {
          state = state.copyWith(verdict: () => null, heard: () => null);
        }
      case final NoteGame g:
        g.skip();
        if (g.done) {
          _finishStep();
        } else {
          state = state.copyWith(note: () => null);
        }
      default:
    }
  }

  /// Ends a race early (counts what's been played).
  void stopRace() {
    if (state.game is ChordGame) _finishStep();
  }

  void answer(int option) {
    final game = state.game;
    if (game is! QuizGame || game.done) return;
    final right = game.answer(option);
    if (game.done) {
      _finishStep(lastAnswer: right);
    } else {
      state = state.copyWith(lastAnswer: () => right);
    }
  }

  /// Plays a chord for reference without the mic counting it.
  void hear(Voicing voicing) {
    _deafUntil = _now() + const Duration(milliseconds: 2800);
    unawaited(ref.read(chordPlayerProvider).strum(voicing));
  }

  /// Plucks a note for reference.
  void hearNote(Spot spot) {
    _deafUntil = _now() + const Duration(milliseconds: 2000);
    final frets = List<int?>.filled(6, null)..[spot.string] = spot.fret;
    unawaited(ref.read(chordPlayerProvider).pluck(Voicing(frets: frets), spot.string));
  }

  void next() {
    if (state.phase != LessonPhase.stepDone) return;
    unawaited(_beginStep(state.step + 1));
  }

  void _finishStep({bool? lastAnswer}) {
    final game = state.game;
    final outcome = switch (game) {
      final ChordGame g => g.outcome(),
      final NoteGame g => g.outcome(),
      final RhythmGame g => g.outcome(),
      final QuizGame g => g.outcome(),
      _ => null,
    };
    if (outcome == null) return;
    final outcomes = [...state.outcomes, outcome];
    final lesson = state.lesson!;
    // Between steps and after the last, nothing is listening: release the
    // mic (the screen reopens it when a listening step starts).
    unawaited(_mic.setActive(active: false));
    if (outcomes.length < lesson.steps.length) {
      state = state.copyWith(
        phase: LessonPhase.stepDone,
        outcomes: outcomes,
        lastAnswer: () => lastAnswer,
      );
      return;
    }
    final started = _startedAt;
    final time = started == null ? Duration.zero : _now() - started;
    _startedAt = null;
    final award = ref.read(progressProvider.notifier).record(lesson, outcomes, time: time);
    state = state.copyWith(
      phase: LessonPhase.finished,
      outcomes: outcomes,
      award: () => award,
      lastAnswer: () => lastAnswer,
    );
  }

  /// Leaving mid-lesson still counts the practice time.
  ///
  /// Called from the lesson screen's dispose, while the widget tree is
  /// unmounting: the save waits a microtask, when providers may change.
  void leave() {
    final started = _startedAt;
    if (started != null && state.phase != LessonPhase.finished) {
      final time = _now() - started;
      final progress = ref.read(progressProvider.notifier);
      scheduleMicrotask(() => progress.addPractice(time: time));
    }
    _startedAt = null;
  }

  Future<void> _onStart(InputDescription description, Stream<Uint8List> pcm) async {
    final rate = _sampleRate = description.sampleRate;
    final worker = _worker ??= await DspWorker.spawn(sampleRate: rate, chords: true);
    // The screen can close while the worker spawns: nothing left to feed.
    if (!ref.mounted) {
      worker.dispose();
      _worker = null;
      return;
    }
    worker.reset();
    final sensitivity = ref.read(sensitivityProvider);
    final level = ref.read(micLevelProvider.notifier);
    final notes = _notes = NoteSession(
      sampleRate: rate,
      minClarity: sensitivity.noteClarity,
      floor: NoiseFloor(
        marginDb: sensitivity.marginDb,
        frameSeconds: analysisGeometry(rate).hop / rate,
      ),
      math: PitchMath(a4: ref.read(tunerProvider).a4),
    );
    final detector = ChromaChordDetector(sampleRate: rate);
    final hop = detector.windowSize / 4 / rate;
    final chordFloor = NoiseFloor(marginDb: sensitivity.marginDb, frameSeconds: hop);
    final smoother = _smoother = ChordSmoother(hopSeconds: hop, floor: chordFloor);
    final onsets = _onsets = OnsetDetector(sampleRate: rate);
    _samples = 0;

    _pitch = worker.frames.listen((f) {
      final game = state.game;
      final reading = notes.update(f);
      if (game is! ChordGame) level.report(f.rmsDb, notes.floor!.gateDb);
      // The room gate also keeps onsets from firing on background noise.
      onsets.minDb = notes.floor!.gateDb - 6;
      if (game is! NoteGame || state.phase != LessonPhase.playing) return;
      if (_now() < _deafUntil) return;
      final hit = game.hear(reading);
      if (game.done) {
        _finishStep();
      } else if (hit || !identical(reading, state.note)) {
        state = state.copyWith(note: () => reading);
      }
    });
    _chords = worker.chordFrames.listen((e) {
      final game = state.game;
      if (game is ChordGame) level.report(e.rmsDb, chordFloor.gateDb);
      final reading = smoother.update(e);
      if (game is! ChordGame || reading == null || state.phase != LessonPhase.playing) return;
      if (_now() < _deafUntil) return;
      final verdict = game.hear(reading, _now());
      if (verdict == null) return;
      if (game.done && game.race == null) {
        _finishStep();
      } else {
        state = state.copyWith(
          verdict: () => verdict,
          heard: () => reading.chord ?? game.session.lastAttempt?.heard,
        );
      }
    });
    _pcm = pcm.listen((bytes) {
      worker.push(bytes);
      _chunk(bytes);
    });
  }

  void _chunk(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final floats = Float32List(bytes.length ~/ 2);
    for (var i = 0; i < floats.length; i++) {
      floats[i] = data.getInt16(i * 2, Endian.little) / 32768;
    }
    _samples += floats.length;
    _chunkAt = _now();
    final found = _onsets?.push(floats) ?? const [];
    final game = state.game;
    final b0 = state.beat0;
    if (game is! RhythmGame || b0 == null || state.phase != LessonPhase.playing) return;
    for (final at in found) {
      final t = _chunkAt - Duration(microseconds: ((_samples - at) / _sampleRate * 1e6).round());
      game.onset((t - b0).inMicroseconds / 1e6);
    }
    if (found.isNotEmpty) state = state.copyWith();
  }

  Future<void> _onStop() async {
    if (ref.mounted) ref.read(micLevelProvider.notifier).clear();
    await _pcm?.cancel();
    await _pitch?.cancel();
    await _chords?.cancel();
    _pcm = null;
    _pitch = null;
    _chords = null;
    _notes = null;
    _smoother = null;
    _onsets = null;
  }
}
