import 'dart:math' as math;

import 'package:fretlight/core/audio/dsp/chord_detector.dart';
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
  });

  final double hopSeconds;
  final double alpha;
  final int switchFrames;
  final Duration hold;
  final double onsetDb;

  final Map<Chord, double> _avg = {};
  double? _lastDb;

  /// Nothing is named until a strum has been heard: steady background
  /// sound (a fan, a TV, the room) never has the sudden attack of a strum,
  /// so it can't produce a chord label however chord-like its spectrum.
  bool _armed = false;

  /// Frames since the last strum. While a strum settles any chord may take
  /// over; afterwards the same chord with notes lost (D → D5 as the high E
  /// fades) or "gained" (C → Cmaj7 from harmonics) keeps its name: a
  /// ringing chord doesn't change notes without a new strum.
  int _sinceOnset = 0;
  static const _settleFrames = 4;
  Chord? _shown;
  Chord? _challenger;
  int _challengerFrames = 0;
  final List<PitchClass?> _singles = [];
  ChordReading? _reading;
  double _silentFor = 0;

  ChordReading? get reading => _reading;

  void reset() {
    _avg.clear();
    _lastDb = null;
    _shown = null;
    _challenger = null;
    _challengerFrames = 0;
    _singles.clear();
    _reading = null;
    _silentFor = 0;
    _armed = false;
  }

  ChordReading? update(ChordEstimate e) {
    if (e.ranked.isEmpty) {
      _silentFor += hopSeconds;
      // Remember the quiet level: the next strum is measured against it.
      _lastDb = e.rmsDb;
      final last = _reading;
      if (last == null) return null;
      if (_silentFor * 1e6 > hold.inMicroseconds) {
        reset();
        _lastDb = e.rmsDb;
        return null;
      }
      return _reading = ChordReading(
        chord: last.chord,
        confidence: last.confidence,
        singleNote: last.singleNote,
        bass: last.bass,
        fading: true,
      );
    }
    _silentFor = 0;

    // A clear jump in level is a new strum: start averaging afresh.
    // With no earlier level to compare (the mic just opened), only a clearly
    // loud sound counts as a strum.
    final onset = _lastDb == null ? e.rmsDb > -30 : e.rmsDb > _lastDb! + onsetDb;
    _lastDb = e.rmsDb;
    if (onset) _armed = true;
    if (!_armed) return null;
    if (onset) {
      _avg.clear();
      _singles.clear();
      _sinceOnset = 0;
    }
    _sinceOnset++;
    for (final r in e.ranked) {
      final prev = _avg[r.chord];
      _avg[r.chord] = prev == null ? r.score : prev + alpha * (r.score - prev);
    }

    _singles.add(e.singleNote);
    if (_singles.length > 3) _singles.removeAt(0);
    final single = _majoritySingle();
    if (single != null) {
      _shown = null;
      return _reading = ChordReading(singleNote: single, bass: e.bass);
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
      chord: confidence >= ChordReading.notSureBelow ? shown : null,
      confidence: confidence,
      bass: e.bass,
    );
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
