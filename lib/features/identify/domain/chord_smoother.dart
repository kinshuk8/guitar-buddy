import 'dart:math' as math;

import 'package:fretlight/core/audio/dsp/chord_detector.dart';
import 'package:fretlight/core/audio/listening.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:meta/meta.dart';

/// What the chord view shows.
@immutable
final class ChordReading {
  const ChordReading({
    this.chord,
    this.confidence = 0,
    this.singleNote,
    this.bass,
    this.fading = false,
    this.strum = 0,
    this.settled = true,
    this.candidates = const [],
  });

  /// Null while unsure or for a single note.
  final Chord? chord;

  /// 0..1, how clearly this chord beat its nearest real rival.
  final double confidence;

  /// Set when a single string is ringing rather than a chord.
  final PitchClass? singleNote;
  final PitchClass? bass;

  /// The sound has stopped; the last chord is held briefly, dimmed.
  final bool fading;

  /// Which strum this reading belongs to (counts up from 1 per strum heard).
  /// Practice mode judges each strum once.
  final int strum;

  /// The analysis window lies inside the strum, past its attack. The first
  /// frames of a strum mix silence with the pick's click and can read as
  /// anything; practice waits for this before judging.
  final bool settled;

  /// The leading chords by smoothed score, best first. Practice uses these:
  /// it knows which chord you're aiming for, and checking that one chord is
  /// among the closest is far more forgiving than naming it from scratch.
  final List<ChordScore> candidates;

  static const notSureBelow = 0.35;

  /// Sound present but no chord we'd stand behind.
  bool get notSure => chord == null && singleNote == null;
}

/// Turns per-window [ChordEstimate]s into a steady label.
///
/// * Scores are averaged across frames (exponentially), and the average is
///   reset when a new strum starts, so one chord's decay doesn't blur into
///   the next.
/// * The label changes only after the new chord has led for [switchFrames]
///   frames: no flicker between near-ties.
/// * Confidence compares the leader with its best *rival*: a chord that
///   isn't just the same chord with a note added or removed. C vs Cmaj7 is
///   a fine distinction, not doubt about the chord.
/// * After the sound stops, the last chord is held for [hold] and then
///   cleared.
final class ChordSmoother {
  ChordSmoother({
    required this.hopSeconds,
    this.alpha = 0.45,
    this.switchFrames = 2,
    this.hold = const Duration(milliseconds: 1500),
    this.onsetDb = 6,
    this.floor,
  });

  /// Room-relative gate: quieter frames are treated as silence. Without
  /// one, anything the detector analysed counts.
  final NoiseFloor? floor;

  final double hopSeconds;
  final double alpha;
  final int switchFrames;
  final Duration hold;
  final double onsetDb;

  final Map<Chord, double> _avg = {};

  /// Weighted running sums behind [_avg]: early frames of a strum (window
  /// still half silence, half pick attack) count for less.
  final Map<Chord, ({double sum, double weight})> _acc = {};

  /// Levels of the last few frames. A strum's rise is spread over several
  /// overlapping windows, so it's measured from the quietest of them, not
  /// from the frame just before.
  final List<double> _levels = [];

  /// Nothing is named until a strum has been heard: steady background
  /// sound (a fan, a TV, the room) never has the sudden attack of a strum,
  /// so it can't produce a chord label however chord-like its spectrum.
  bool _armed = false;
  int _strums = 0;

  /// Frames since the last strum. While a strum settles any chord may take
  /// over; afterwards the same chord with notes lost (D → D5 as the high E
  /// fades) or "gained" (C → Cmaj7 from harmonics) keeps its name: a
  /// ringing chord doesn't change notes without a new strum.
  int _sinceOnset = 0;
  static const _settleFrames = 6;

  /// About a 16k window's worth of hops at 48 kHz (3 × 85 ms ≈ the window).
  static const _settledFrames = 3;
  Chord? _shown;
  Chord? _challenger;
  int _challengerFrames = 0;
  final List<PitchClass?> _singles = [];
  ChordReading? _reading;
  double _silentFor = 0;

  ChordReading? get reading => _reading;

  void reset() {
    _avg.clear();
    _levels.clear();
    _acc.clear();
    _shown = null;
    _challenger = null;
    _challengerFrames = 0;
    _singles.clear();
    _reading = null;
    _silentFor = 0;
    _armed = false;
  }

  ChordReading? update(ChordEstimate e) {
    final playing = floor?.update(e.rmsDb) ?? true;
    if (e.ranked.isEmpty || !playing) {
      _silentFor += hopSeconds;
      // Remember the quiet level: the next strum is measured against it.
      _pushLevel(e.rmsDb);
      final last = _reading;
      if (last == null) return null;
      if (_silentFor * 1e6 > hold.inMicroseconds) {
        reset();
        _pushLevel(e.rmsDb);
        return null;
      }
      return _reading = ChordReading(
        chord: last.chord,
        confidence: last.confidence,
        singleNote: last.singleNote,
        bass: last.bass,
        fading: true,
        strum: last.strum,
      );
    }
    _silentFor = 0;

    // A clear jump in level is a new strum: start averaging afresh.
    // With no earlier level to compare (the mic just opened), only a clearly
    // loud sound counts as a strum.
    final recentMin = _levels.isEmpty ? null : _levels.reduce(math.min);
    final rising = recentMin == null
        ? e.rmsDb > (floor?.gateDb ?? -36) + onsetDb
        : e.rmsDb > recentMin + onsetDb;
    // One strum, one onset: the rise spans several frames.
    final onset = rising && (!_armed || _sinceOnset >= 3);
    _pushLevel(e.rmsDb);
    if (onset) {
      _armed = true;
      _strums++;
      // Measure the next strum from this one's level, not the silence before.
      _levels
        ..clear()
        ..add(e.rmsDb);
    }
    if (!_armed) return null;
    if (onset) {
      _avg.clear();
      _acc.clear();
      _singles.clear();
      _sinceOnset = 0;
    }
    _sinceOnset++;
    final w = switch (_sinceOnset) {
      1 => 0.2,
      2 => 0.5,
      _ => 1.0,
    };
    for (final r in e.ranked) {
      final prev = _acc[r.chord] ?? (sum: 0.0, weight: 0.0);
      final next = (
        sum: prev.sum * (1 - alpha) + w * r.score,
        weight: prev.weight * (1 - alpha) + w,
      );
      _acc[r.chord] = next;
      _avg[r.chord] = next.sum / next.weight;
    }

    _singles.add(e.singleNote);
    if (_singles.length > 3) _singles.removeAt(0);
    final single = _majoritySingle();
    if (single != null) {
      _shown = null;
      return _reading = ChordReading(
        singleNote: single,
        bass: e.bass,
        strum: _strums,
        settled: _sinceOnset >= _settledFrames,
      );
    }

    final ranked = _avg.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    var leader = ranked.first;
    if (_shown != null && _sinceOnset > _settleFrames && _family(leader.key, _shown!)) {
      leader = MapEntry(_shown!, _avg[_shown!] ?? leader.value);
    }
    if (_shown == null || leader.key == _shown) {
      _shown = leader.key;
      _challenger = null;
      _challengerFrames = 0;
    } else if (leader.key == _challenger) {
      if (++_challengerFrames >= switchFrames) {
        _shown = leader.key;
        _challenger = null;
        _challengerFrames = 0;
      }
    } else {
      _challenger = leader.key;
      _challengerFrames = 1;
    }

    final shown = _shown!;
    // The chord family's best score: once the high E fades from a D, "D5"
    // still says the D is there.
    final shownScore = ranked
        .where((r) => r.key == shown || _family(r.key, shown))
        .map((r) => r.value)
        .fold<double>(_avg[shown] ?? -1, math.max);
    final rival = ranked
        .where((r) => r.key != shown && !_family(r.key, shown))
        .map((r) => r.value)
        .fold<double>(-1, math.max);
    final level = ((shownScore - 0.7) / 0.15).clamp(0.0, 1.0);
    final margin = ((shownScore - rival) / 0.05).clamp(0.0, 1.0);
    final confidence = 0.4 * level + 0.6 * margin;
    return _reading = ChordReading(
      candidates: [for (final r in ranked.take(6)) (chord: r.key, score: r.value)],
      chord: confidence >= ChordReading.notSureBelow ? shown : null,
      confidence: confidence,
      bass: e.bass,
      strum: _strums,
      settled: _sinceOnset >= _settledFrames,
    );
  }

  void _pushLevel(double db) {
    _levels.add(db);
    if (_levels.length > 4) _levels.removeAt(0);
  }

  PitchClass? _majoritySingle() {
    final counts = <PitchClass, int>{};
    for (final s in _singles) {
      if (s != null) counts[s] = (counts[s] ?? 0) + 1;
    }
    for (final MapEntry(:key, :value) in counts.entries) {
      if (value >= 2) return key;
    }
    return null;
  }

  /// Same root, and one chord's notes contain the other's (C ⊂ Cmaj7,
  /// C5 ⊂ C): variations of one chord rather than rivals.
  static bool _family(Chord a, Chord b) {
    if (a.root != b.root) return false;
    final pa = a.pitchClasses;
    final pb = b.pitchClasses;
    return pa.containsAll(pb) || pb.containsAll(pa);
  }
}
