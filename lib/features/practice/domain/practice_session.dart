import 'dart:math' as math;

import 'package:fretlight/core/audio/dsp/chord_detector.dart' show ChordScore;
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/features/identify/domain/chord_smoother.dart';
import 'package:meta/meta.dart';

/// How closely a strum must match the chord asked for. Guitars, strings
/// and microphones colour a chord differently: a quiet G string makes Em
/// sound like E5, a barre with one dead string loses a note.
enum ChordMatching {
  /// Only the chord itself counts.
  exact(
    'Exact',
    'Only the exact chord counts. For checking your shapes are clean.',
    margin: 0.01,
    wrongConfidence: 0.5,
    maxClash: 0.15,
  ),

  /// The chord, or the same chord give or take a note (E5 for Em, G for G7).
  normal(
    'Normal',
    'The chord, or the same chord with a note missing or added (E5 for Em).',
    margin: 0.03,
    wrongConfidence: 0.6,
    maxClash: 0.15,
  ),

  /// Also any same-root reading that doesn't contradict major or minor
  /// (sus, power, add), from further down the identifier's list; and a
  /// strum is only called wrong when the identifier is sure.
  forgiving(
    'Forgiving',
    'For guitars that sound unusual, old strings, or barre chords that don’t ring fully.',
    margin: 0.08,
    wrongConfidence: 0.8,
    maxClash: 0.2,
  );

  ChordMatching(
    this.label,
    this.detail, {
    required this.margin,
    required this.wrongConfidence,
    required this.maxClash,
  });

  final String label;
  final String detail;

  /// How far below the top candidate the target may score and still count.
  final double margin;

  /// How sure the identifier must be before a different chord counts
  /// against you (otherwise it keeps listening).
  final double wrongConfidence;

  /// A near miss only counts if the notes heard back it up: the opposite
  /// third (minor for a major chord) no louder than this, relative to the
  /// loudest note, than the chord's own third...
  final double maxClash;

  /// ...and no more than this share of the sound on notes outside the
  /// chord. Measured on many guitars and mics: the right chord stays under
  /// 0.45; a different chord starts around 0.48.
  static const maxOutside = 0.47;
}

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
  PracticeSession(this.targets, {this.matching = ChordMatching.normal})
    : assert(targets.isNotEmpty, 'nothing to practise');

  final List<Chord> targets;
  final ChordMatching matching;
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
    if (target == null || reading.fading || !reading.settled) return null;
    if (reading.strum <= _lastJudgedStrum) return null;
    final heard = reading.chord ?? reading.candidates.firstOrNull?.chord;
    if (heard == null) return null;
    var verdict = judge(target, heard, matching: matching);
    if (verdict == Verdict.miss &&
        closeEnough(target, reading.candidates, margin: matching.margin, matching: matching)) {
      // Not the identifier's top answer, but within a hair of it: with the
      // target known, that's the chord you played (real guitars and phone
      // mics blur the top few candidates together).
      verdict = Verdict.hit;
    }
    // Anything short of the identifier naming the chord outright must agree
    // with the notes heard. Without this, Dm passes for D: its notes look
    // like "D5", and D5 is D missing a note.
    final named =
        reading.chord != null &&
        judge(target, reading.chord!, matching: ChordMatching.exact) == Verdict.hit;
    if (verdict != Verdict.miss && !named) {
      final e = evidence(target, reading.chroma);
      if (e.thirdClash > matching.maxClash || e.outside > ChordMatching.maxOutside) {
        verdict = Verdict.miss;
      }
    }
    // A strum the identifier couldn't name at all, and nowhere near the
    // target, isn't judged: better to keep listening than to scold noise.
    if (reading.chord == null && verdict == Verdict.miss) return null;
    // A wrong chord needs real confidence before it counts against you;
    // a right one only needs to be the identifier's answer.
    if (verdict == Verdict.miss && reading.confidence < matching.wrongConfidence) return null;
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

  /// Whether [target] (or the same chord give or take a note) scores within
  /// [margin] of the best candidate.
  static bool closeEnough(
    Chord target,
    List<ChordScore> candidates, {
    double margin = 0.03,
    ChordMatching matching = ChordMatching.normal,
  }) {
    if (candidates.isEmpty) return false;
    final best = candidates.first.score;
    return candidates.any(
      (c) => c.score >= best - margin && judge(target, c.chord, matching: matching) != Verdict.miss,
    );
  }

  /// What the notes heard say about [target]: the share of energy on notes
  /// outside it, and how much louder the opposite third is than its own
  /// (relative to the loudest note; negative when its own third is louder).
  /// Both 0 when there's nothing to go on.
  static ({double outside, double thirdClash}) evidence(Chord target, List<double> chroma) {
    if (chroma.length != 12) return (outside: 0, thirdClash: 0);
    final total = chroma.fold<double>(0, (a, b) => a + b);
    final loudest = chroma.reduce(math.max);
    if (total <= 0 || loudest <= 0) return (outside: 0, thirdClash: 0);
    final tones = {for (final pc in target.pitchClasses) pc.value};
    var inside = 0.0;
    for (final t in tones) {
      inside += chroma[t];
    }
    final own = target.quality.required.where((i) => i == 3 || i == 4).firstOrNull;
    var clash = 0.0;
    if (own != null) {
      final ownPc = target.root.transpose(own).value;
      final otherPc = target.root.transpose(own == 4 ? 3 : 4).value;
      clash = (chroma[otherPc] - chroma[ownPc]) / loudest;
    }
    return (outside: 1 - inside / total, thirdClash: clash);
  }

  static Verdict judge(Chord target, Chord heard, {ChordMatching matching = ChordMatching.normal}) {
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
    if (matching == ChordMatching.exact) return Verdict.miss;
    if (pt.containsAll(ph) || ph.containsAll(pt)) return Verdict.close;
    // Same root, no clash between major and minor: the shape was right and
    // the guitar or a dead string coloured it (A heard as Asus4 or Aadd9).
    if (matching == ChordMatching.forgiving) return Verdict.close;
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
