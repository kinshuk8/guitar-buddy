import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/features/identify/domain/chord_smoother.dart';
import 'package:meta/meta.dart';

/// How a strum compared with the chord asked for.
enum Verdict {
  /// Exactly the chord.
  hit,

  /// The same chord with a note more or less (G for G7): counts, noted.
  close,

  /// A different chord.
  miss,
}

/// One strum, judged.
@immutable
final class Attempt {
  const Attempt({required this.target, required this.heard, required this.verdict});

  final Chord target;
  final Chord heard;
  final Verdict verdict;
}

/// What happened at one chord of the sequence.
@immutable
final class StepResult {
  const StepResult({
    required this.target,
    required this.misses,
    required this.skipped,
    required this.close,
  });

  final Chord target;
  final int misses;
  final bool skipped;
  final bool close;

  bool get clean => misses == 0 && !skipped;
}

/// Wait-for-me practice: shows a chord, listens, and moves on when you play
/// it. Wrong chords and skips are counted per chord so the summary can say
/// which changes need work.
///
/// Each strum is judged once (by its strum number), so a ringing chord
/// can't tick off two bars of the same chord, and a wrong chord isn't
/// counted again on every frame while it rings.
final class PracticeSession {
  PracticeSession(this.targets) : assert(targets.isNotEmpty, 'nothing to practise');

  final List<Chord> targets;
  final List<StepResult> _results = [];
  int _index = 0;
  int _missesHere = 0;
  int _lastJudgedStrum = 0;
  Attempt? _last;

  int get index => _index;
  bool get done => _index >= targets.length;
  Chord? get current => done ? null : targets[_index];
  Attempt? get lastAttempt => _last;
  List<StepResult> get results => List.unmodifiable(_results);

  /// Feeds the identifier's latest reading. Returns the verdict if this
  /// reading was a new strum that got judged.
  Verdict? hear(ChordReading reading) {
    final target = current;
    final heard = reading.chord;
    if (target == null || heard == null || reading.fading || !reading.settled) return null;
    if (reading.strum <= _lastJudgedStrum) return null;
    final verdict = judge(target, heard);
    // A wrong chord needs real confidence before it counts against you;
    // a right one only needs to be the identifier's answer.
    if (verdict == Verdict.miss && reading.confidence < 0.6) return null;
    _lastJudgedStrum = reading.strum;
    _last = Attempt(target: target, heard: heard, verdict: verdict);
    if (verdict == Verdict.miss) {
      _missesHere++;
    } else {
      _advance(skipped: false, close: verdict == Verdict.close);
    }
    return verdict;
  }

  /// Moves on without playing it; counts as missed.
  void skip() {
    if (done) return;
    _last = null;
    _advance(skipped: true, close: false);
  }

  void _advance({required bool skipped, required bool close}) {
    _results.add(
      StepResult(target: targets[_index], misses: _missesHere, skipped: skipped, close: close),
    );
    _missesHere = 0;
    _index++;
  }

  static Verdict judge(Chord target, Chord heard) {
    if (heard == target) return Verdict.hit;
    // Ignore a slash bass the identifier may or may not hear.
    final t = Chord(target.root, target.quality);
    final h = Chord(heard.root, heard.quality);
    if (t == h) return Verdict.hit;
    if (t.root != h.root) return Verdict.miss;
    final pt = t.pitchClasses;
    final ph = h.pitchClasses;
    // Same chord give or take a note: G for G7, C for Cmaj7, A for Asus2...
    // but a different third (A vs Am) is a different chord.
    final third = {3, 4};
    final tThird = t.quality.required.intersection(third);
    final hThird = h.quality.required.intersection(third);
    if (tThird.isNotEmpty && hThird.isNotEmpty && tThird.first != hThird.first) return Verdict.miss;
    if (pt.containsAll(ph) || ph.containsAll(pt)) return Verdict.close;
    return Verdict.miss;
  }

  /// Chords that needed more than one try or were skipped, worst first (a
  /// skip, giving up, weighs as three wrong tries).
  List<({Chord chord, int misses, int skips, int times})> trouble() {
    final byChord = <Chord, ({int misses, int skips, int times})>{};
    for (final r in _results) {
      final prev = byChord[r.target] ?? (misses: 0, skips: 0, times: 0);
      byChord[r.target] = (
        misses: prev.misses + r.misses,
        skips: prev.skips + (r.skipped ? 1 : 0),
        times: prev.times + 1,
      );
    }
    final list = [
      for (final MapEntry(:key, :value) in byChord.entries)
        if (value.misses > 0 || value.skips > 0)
          (chord: key, misses: value.misses, skips: value.skips, times: value.times),
    ]..sort((a, b) => (b.misses + 3 * b.skips).compareTo(a.misses + 3 * a.skips));
    return list;
  }

  /// Share of chords played right first time.
  double get firstTimeRate =>
      _results.isEmpty ? 0 : _results.where((r) => r.clean).length / _results.length;
}
