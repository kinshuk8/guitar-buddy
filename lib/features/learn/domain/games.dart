import 'dart:math' as math;

import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/features/identify/domain/chord_smoother.dart';
import 'package:fretlight/features/identify/domain/note_session.dart';
import 'package:fretlight/features/learn/domain/curriculum.dart';
import 'package:fretlight/features/practice/domain/practice_session.dart';
import 'package:meta/meta.dart';

/// How one exercise went.
@immutable
final class StepOutcome {
  const StepOutcome({
    required this.score,
    required this.stars,
    required this.headline,
    this.detail,
    this.chords = const {},
    this.best,
  });

  /// 0..1.
  final double score;

  /// 0 (not finished) to 3.
  final int stars;

  /// The number that matters, in words: "24 changes a minute".
  final String headline;
  final String? detail;

  /// Per chord symbol: strums right first time, and wrong tries or skips.
  final Map<String, ({int clean, int missed})> chords;

  /// A personal best to record: key and value (higher is better).
  final (String, double)? best;
}

int _starsFor(double value, (num, num, num) at) => value >= at.$3
    ? 3
    : value >= at.$2
    ? 2
    : value >= at.$1
    ? 1
    : 0;

/// Chord games: drills, changes, progressions, songs and the one-minute
/// change race. The listening and judging is practice mode's.
final class ChordGame {
  ChordGame._(this.session, {this.race});

  factory ChordGame.steps(List<String> specs) =>
      ChordGame._(PracticeSession([for (final s in specs) Chord.parse(chordSymbolOf(s))]));

  factory ChordGame.song(List<Chord> chords) => ChordGame._(PracticeSession(chords));

  /// Alternates the pair for as long as the clock allows.
  factory ChordGame.race(ChangeRace race) {
    final a = Chord.parse(chordSymbolOf(race.a));
    final b = Chord.parse(chordSymbolOf(race.b));
    // Far more than anyone can play in the time: the clock ends it.
    return ChordGame._(
      PracticeSession([
        for (var i = 0; i < 400; i++)
          if (i.isEven) a else b,
      ]),
      race: race,
    );
  }

  final PracticeSession session;
  final ChangeRace? race;

  /// When the race clock started: at the first chord heard, so finding
  /// the first shape doesn't eat into the minute.
  Duration? _raceStart;
  bool _timeUp = false;

  Duration? get raceStart => _raceStart;

  /// Time left in a race, given the time now.
  Duration? remaining(Duration now) {
    final r = race;
    if (r == null) return null;
    final start = _raceStart;
    if (start == null) return Duration(seconds: r.seconds);
    final left = Duration(seconds: r.seconds) - (now - start);
    return left.isNegative ? Duration.zero : left;
  }

  bool get done => _timeUp || session.done;

  /// Advances the race clock; call regularly with the time now.
  void tick(Duration now) {
    if (race != null && remaining(now) == Duration.zero && _raceStart != null) _timeUp = true;
  }

  Verdict? hear(ChordReading reading, Duration now) {
    if (done) return null;
    final verdict = session.hear(reading);
    if (verdict != null && verdict != Verdict.miss && race != null) _raceStart ??= now;
    return verdict;
  }

  void skip() {
    if (!done) session.skip();
  }

  /// Chords played (not skipped) since the clock started, less the first:
  /// the number of changes.
  int get changes => math.max(0, session.results.where((r) => !r.skipped).length - 1);

  StepOutcome outcome() {
    final results = session.results;
    final chords = <String, ({int clean, int missed})>{};
    for (final r in results) {
      final key = r.target.symbol();
      final prev = chords[key] ?? (clean: 0, missed: 0);
      chords[key] = (
        clean: prev.clean + (r.clean ? 1 : 0),
        missed: prev.missed + r.misses + (r.skipped ? 1 : 0),
      );
    }
    final r = race;
    if (r != null) {
      final perMinute = changes * 60 / r.seconds;
      return StepOutcome(
        score: math.min(1, perMinute / r.targets.$3),
        stars: _starsFor(perMinute, r.targets),
        headline: '${perMinute.round()} changes a minute',
        detail: 'Stars at ${r.targets.$1}, ${r.targets.$2} and ${r.targets.$3}',
        chords: chords,
        best: ('race:${r.pairKey}', perMinute),
      );
    }
    final total = results.length;
    final played = results.where((x) => !x.skipped).length;
    final rate = session.firstTimeRate;
    final finished = total > 0 && played >= total / 2;
    return StepOutcome(
      score: rate,
      stars: finished ? math.max(1, _starsFor(rate, (0, 0.7, 0.9))) : 0,
      headline: '${(rate * 100).round()}% right first time',
      detail: '$played of $total chords played',
      chords: chords,
    );
  }
}

/// Find-the-note games: open strings, notes on the neck, tab lines, and
/// tuning (with [NoteSteps.tuneCents]).
final class NoteGame {
  NoteGame(this.steps, {Tuning? tuning})
    : tuning = tuning ?? Tuning.standard,
      targets = [for (final s in steps.spots) (tuning ?? Tuning.standard).noteAt(s.string, s.fret)];

  final NoteSteps steps;
  final Tuning tuning;
  final List<Note> targets;

  /// Consecutive readings needed: the note must hold, not flicker past.
  static const _holdReadings = 3;

  /// When tuning, readings in tune in a row (~0.3 s).
  static const _tuneReadings = 12;

  int _index = 0;
  int _streak = 0;
  int _missesHere = 0;
  int _firstTry = 0;
  Note? _wrongNote;
  int _wrongStreak = 0;
  bool _wrongCounted = false;
  Note? _lastPlayed;

  int get index => _index;
  bool get done => _index >= targets.length;
  Note? get current => done ? null : targets[_index];
  Spot? get currentSpot => done ? null : steps.spots[_index];

  /// How close the current note is to in tune, 0..1 (for a progress ring).
  double tuneProgress = 0;

  /// The last wrong note heard for this target, to say what was heard.
  Note? get wrong => _wrongCounted ? _wrongNote : null;

  /// Feeds the identifier's reading. Returns true when the target was hit.
  bool hear(NoteReading? reading) {
    final target = current;
    if (target == null || reading == null || reading.fading) {
      _streak = 0;
      if (reading == null) _wrongStreak = 0;
      return false;
    }
    if (reading.note == target) {
      _wrongStreak = 0;
      final tol = steps.tuneCents;
      final ok = tol == null || reading.cents.abs() <= tol;
      _streak = ok ? _streak + 1 : 0;
      final need = tol == null ? _holdReadings : _tuneReadings;
      tuneProgress = tol == null ? 0 : (_streak / need).clamp(0, 1).toDouble();
      if (_streak >= need) {
        _advance();
        return true;
      }
      return false;
    }
    _streak = 0;
    // A held wrong note counts once, and never the note just played
    // (it may still be ringing).
    if (reading.note == _lastPlayed) return false;
    if (reading.note == _wrongNote) {
      _wrongStreak++;
    } else {
      _wrongNote = reading.note;
      _wrongStreak = 1;
      _wrongCounted = false;
    }
    if (_wrongStreak >= _holdReadings * 2 && !_wrongCounted) {
      _wrongCounted = true;
      _missesHere++;
    }
    return false;
  }

  void skip() {
    if (done) return;
    _missesHere = 99;
    _advance();
  }

  void _advance() {
    if (_missesHere == 0) _firstTry++;
    _lastPlayed = targets[_index];
    _index++;
    _streak = 0;
    _missesHere = 0;
    _wrongNote = null;
    _wrongStreak = 0;
    _wrongCounted = false;
    tuneProgress = 0;
  }

  StepOutcome outcome() {
    final total = targets.length;
    final rate = total == 0 ? 0.0 : _firstTry / total;
    if (steps.tuneCents != null) {
      return StepOutcome(
        score: done ? 1 : 0,
        stars: done ? 3 : 0,
        headline: done ? 'In tune' : 'Not finished',
        detail: 'Every string within ${steps.tuneCents!.round()} cents',
      );
    }
    return StepOutcome(
      score: rate,
      stars: done ? math.max(1, _starsFor(rate, (0, 0.7, 0.9))) : 0,
      headline: '$_firstTry of $total notes first try',
    );
  }
}

/// Strum-in-time game. Times are seconds from the downbeat of the first
/// scored bar.
final class RhythmGame {
  RhythmGame(this.steps)
    : expected = [
        for (var bar = 0; bar < steps.bars; bar++)
          for (final s in steps.pattern) (bar * steps.beatsPerBar + s.beat) * 60 / steps.bpm,
      ];

  final RhythmSteps steps;
  final List<double> expected;
  final List<double> _onsets = [];

  double get beatSeconds => 60 / steps.bpm;
  double get length => steps.bars * steps.beatsPerBar * beatSeconds;

  /// Strums before the first beat (minus the window) are the count-in's
  /// echo or nerves; strums after the end don't count.
  void onset(double t) {
    final w = steps.windowMs / 1000;
    if (t < -w * 2 || t > length) return;
    _onsets.add(t);
  }

  List<double> get onsets => List.unmodifiable(_onsets);

  /// Each expected stroke, matched to the nearest unused strum after
  /// latency correction: (expected time, offset in seconds or null).
  ///
  /// Microphone and speaker latency shift every strum by the same amount,
  /// which says nothing about your timing; so the median offset (limited to
  /// −60..+200 ms, the range latency can plausibly be) is taken out first.
  /// What's scored is how steady you are against your own beat.
  ({List<double?> offsets, int extras, double latency}) match() {
    final half = beatSeconds / 4;
    final raw = <double>[];
    for (final o in _onsets) {
      final nearest = expected.reduce((a, b) => (a - o).abs() <= (b - o).abs() ? a : b);
      if ((nearest - o).abs() <= half) raw.add(o - nearest);
    }
    raw.sort();
    final latency = raw.isEmpty ? 0.0 : raw[raw.length ~/ 2].clamp(-0.06, 0.2);
    final window = steps.windowMs / 1000;
    final used = <int>{};
    final offsets = <double?>[];
    for (final e in expected) {
      int? best;
      for (var i = 0; i < _onsets.length; i++) {
        if (used.contains(i)) continue;
        final d = (_onsets[i] - latency - e).abs();
        if (d <= window && (best == null || d < (_onsets[best] - latency - e).abs())) best = i;
      }
      if (best == null) {
        offsets.add(null);
      } else {
        used.add(best);
        offsets.add(_onsets[best] - latency - e);
      }
    }
    // An unmatched strum only counts against you when it's off the beat: a
    // second hit right beside a beat that already scored (a slow strum, a
    // pick catching twice) isn't a timing mistake.
    var extras = 0;
    for (var i = 0; i < _onsets.length; i++) {
      if (used.contains(i)) continue;
      final t = _onsets[i] - latency;
      final nearest = expected.reduce((a, b) => (a - t).abs() <= (b - t).abs() ? a : b);
      if ((t - nearest).abs() > 2 * window) extras++;
    }
    return (offsets: offsets, extras: extras, latency: latency);
  }

  StepOutcome outcome() {
    final m = match();
    final hits = m.offsets.whereType<double>().toList();
    final n = expected.length;
    final score = ((hits.length - 0.5 * m.extras) / n).clamp(0.0, 1.0);
    String? detail;
    if (hits.length >= 3) {
      final mean = hits.reduce((a, b) => a + b) / hits.length;
      final sd = math.sqrt(
        hits.map((h) => (h - mean) * (h - mean)).reduce((a, b) => a + b) / hits.length,
      );
      detail = 'Steady to ±${(sd * 1000).round()} ms';
    }
    if (m.extras > 0) {
      detail = [
        detail,
        '${m.extras} extra ${m.extras == 1 ? 'strum' : 'strums'}',
      ].whereType<String>().join(' · ');
    }
    return StepOutcome(
      score: score,
      stars: _starsFor(score, (0.5, 0.75, 0.9)),
      headline: '${hits.length} of $n strums on the beat',
      detail: detail,
      best: ('rhythm:${steps.chord}:${steps.bpm}:${steps.name}', score * 100),
    );
  }
}

@immutable
final class Question {
  const Question({
    required this.kind,
    required this.prompt,
    required this.options,
    required this.answer,
    this.spot,
    this.chord,
  });

  final QuizKind kind;
  final String prompt;
  final List<String> options;
  final int answer;

  /// The string and fret shown (string, fret and tab questions).
  final Spot? spot;

  /// The chord diagram shown (chord questions).
  final String? chord;
}

/// Quick-fire questions with a combo for answers right in a row.
final class QuizGame {
  QuizGame(this.quiz, {int seed = 1}) : questions = _generate(quiz, math.Random(seed));

  final Quiz quiz;
  final List<Question> questions;
  int _index = 0;
  int _correct = 0;
  int _combo = 0;
  int _bestCombo = 0;

  int get index => _index;
  bool get done => _index >= questions.length;
  Question? get current => done ? null : questions[_index];
  int get correct => _correct;
  int get combo => _combo;
  int get bestCombo => _bestCombo;

  /// Answers the current question; returns whether it was right.
  bool answer(int option) {
    final q = current;
    if (q == null) return false;
    final right = option == q.answer;
    if (right) {
      _correct++;
      _combo++;
      _bestCombo = math.max(_bestCombo, _combo);
    } else {
      _combo = 0;
    }
    _index++;
    return right;
  }

  StepOutcome outcome() {
    final rate = questions.isEmpty ? 0.0 : _correct / questions.length;
    return StepOutcome(
      score: rate,
      stars: done ? _starsFor(rate, (0.6, 0.8, 1)) : 0,
      headline: '$_correct of ${questions.length} right',
      detail: _bestCombo >= 3 ? 'Best run: $_bestCombo in a row' : null,
    );
  }

  static const stringNames = ['Low E', 'A', 'D', 'G', 'B', 'High E'];

  static String noteName(PitchClass pc) => pc.name(Spelling.forRoot(pc));

  static List<Question> _generate(Quiz quiz, math.Random rnd) {
    final kinds = quiz.kinds.toList();
    final out = <Question>[];
    Spot? last;
    while (out.length < quiz.questions) {
      final kind = kinds[rnd.nextInt(kinds.length)];
      final q = switch (kind) {
        QuizKind.stringName => _stringName(rnd),
        QuizKind.fretNote => _fretNote(rnd, quiz.maxFret, tab: false),
        QuizKind.tabNote => _fretNote(rnd, quiz.maxFret, tab: true),
        QuizKind.chordName => _chordName(rnd, quiz.chords),
      };
      // Never the same spot twice running.
      if (q.spot != null && q.spot == last) continue;
      last = q.spot;
      out.add(q);
    }
    return out;
  }

  static Question _stringName(math.Random rnd) {
    final s = rnd.nextInt(6);
    return Question(
      kind: QuizKind.stringName,
      prompt: 'Which string is this?',
      spot: Spot(s, 0),
      options: stringNames,
      answer: s,
    );
  }

  static Question _fretNote(math.Random rnd, int maxFret, {required bool tab}) {
    final s = rnd.nextInt(6);
    final f = rnd.nextInt(maxFret + 1);
    final pc = Tuning.standard.noteAt(s, f).pitchClass;
    final options = <PitchClass>{pc};
    while (options.length < 4) {
      // Distractors close by: the notes a fret or two either side.
      options.add(pc.transpose(rnd.nextInt(5) - 2));
    }
    final list = options.toList()..shuffle(rnd);
    return Question(
      kind: tab ? QuizKind.tabNote : QuizKind.fretNote,
      prompt: tab ? 'Which note does this tab play?' : 'Which note is this?',
      spot: Spot(s, f),
      options: [for (final p in list) noteName(p)],
      answer: list.indexOf(pc),
    );
  }

  static Question _chordName(math.Random rnd, List<String> chords) {
    final pool = chords.isEmpty ? const ['C', 'G', 'D', 'Em', 'Am'] : chords;
    final spec = pool[rnd.nextInt(pool.length)];
    final symbol = chordSymbolOf(spec);
    final options = <String>{symbol};
    final others = pool.map(chordSymbolOf).where((c) => c != symbol).toList()..shuffle(rnd);
    options.addAll(others.take(3));
    // Too few chords to choose from: add near relatives (major/minor twin).
    for (final extra in [
      if (symbol.endsWith('m')) symbol.substring(0, symbol.length - 1) else '${symbol}m',
      '${symbol}7',
    ]) {
      if (options.length >= 4) break;
      options.add(extra);
    }
    final list = options.toList()..shuffle(rnd);
    return Question(
      kind: QuizKind.chordName,
      prompt: 'Which chord is this?',
      chord: spec,
      options: list,
      answer: list.indexOf(symbol),
    );
  }
}
