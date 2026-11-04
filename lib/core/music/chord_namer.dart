import 'package:fretlight/core/music/chord.dart';
import 'package:fretlight/core/music/pitch.dart';
import 'package:meta/meta.dart';

/// One way of naming a set of pitch classes, with a score for ranking.
@immutable
final class ChordCandidate {
  const ChordCandidate(this.chord, this.score);

  final Chord chord;

  /// Higher is better. Only meaningful relative to other candidates.
  final double score;

  @override
  String toString() => '${chord.symbol()} (${score.toStringAsFixed(2)})';
}

/// Names chords from the notes actually sounding.
///
/// Used three ways: labelling fretted voicings, validating chord data, and
/// turning detected pitch classes into a chord name. The ranking rules are
/// what a guitarist expects: every required tone present, no foreign tones,
/// the bass note as root if possible, and the simplest name otherwise.
abstract final class ChordNamer {
  /// All plausible names for [pitchClasses], best first. Empty if none fit.
  ///
  /// [bass] is the lowest sounding note; it disambiguates C6 / Am7 and G/B.
  /// [qualities] limits the search, e.g. to what the detector supports.
  static List<ChordCandidate> candidates(
    Set<PitchClass> pitchClasses, {
    PitchClass? bass,
    Iterable<ChordQuality> qualities = ChordQuality.values,
  }) {
    if (pitchClasses.length < 2) return const [];
    final result = <ChordCandidate>[];
    for (final root in pitchClasses) {
      final intervals = {for (final pc in pitchClasses) root.intervalTo(pc)};
      for (final quality in qualities) {
        if (!intervals.containsAll(quality.required)) continue;
        // A foreign tone is allowed only as a slash bass (C/B style), never
        // anywhere else; otherwise it is a different chord.
        final foreign = intervals.difference(quality.allowed);
        final bassInterval = bass == null ? null : root.intervalTo(bass);
        if (foreign.isNotEmpty && !(foreign.length == 1 && foreign.first == bassInterval)) {
          continue;
        }
        var score = 10.0;
        score -= quality.complexity * 0.5;
        // Fewer omitted optional tones = more complete chord.
        score -= quality.optional.difference(intervals).length * 0.3;
        if (bass != null && bass != root) {
          // Inversions (bass is a chord tone) beat added-bass slash chords.
          score -= foreign.isEmpty ? 1.5 : 2.5;
        }
        result.add(ChordCandidate(Chord(root, quality, bass: bass == root ? null : bass), score));
      }
    }
    result.sort((a, b) => b.score.compareTo(a.score));
    return result;
  }

  /// The best name, or null if nothing fits.
  static Chord? name(Set<PitchClass> pitchClasses, {PitchClass? bass}) {
    final list = candidates(pitchClasses, bass: bass);
    return list.isEmpty ? null : list.first.chord;
  }
}
