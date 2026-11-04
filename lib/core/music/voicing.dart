import 'package:fretlight/core/music/chord.dart';
import 'package:fretlight/core/music/pitch.dart';
import 'package:fretlight/core/music/tuning.dart';
import 'package:meta/meta.dart';

/// A barre: one finger across strings [lowString]..[highString] (inclusive,
/// 0 = lowest-pitched) at [fret].
@immutable
final class Barre {
  const Barre({
    required this.fret,
    required this.lowString,
    required this.highString,
    this.finger = 1,
  });

  final int fret;
  final int lowString;
  final int highString;
  final int finger;
}

/// One way to finger a chord.
///
/// Frets are *absolute* (chords-db stores them relative to `baseFret`; the
/// converter resolves that once so nothing else has to). Null = muted string.
@immutable
final class Voicing {
  const Voicing({
    required this.frets,
    this.fingers = const [],
    this.barres = const [],
    this.tuning,
  });

  /// One entry per string, lowest first. Null = muted, 0 = open.
  final List<int?> frets;

  /// Finger per string (1 = index … 4 = pinky, 0 or null = none).
  final List<int?> fingers;
  final List<Barre> barres;

  /// Defaults to standard tuning.
  final Tuning? tuning;

  Tuning get _tuning => tuning ?? Tuning.standard;

  /// The fret a diagram window should start at: 1 for open-position shapes,
  /// otherwise the lowest fretted note.
  int get baseFret {
    final fretted = frets.whereType<int>().where((f) => f > 0);
    if (fretted.isEmpty) return 1;
    final lowest = fretted.reduce((a, b) => a < b ? a : b);
    final highest = fretted.reduce((a, b) => a > b ? a : b);
    return highest <= 4 ? 1 : lowest;
  }

  /// Sounding notes, lowest string first (muted strings skipped).
  List<Note> get notes => [
    for (var s = 0; s < frets.length; s++)
      if (frets[s] case final int fret) _tuning.noteAt(s, fret),
  ];

  /// Lowest sounding note — what the ear hears as the bass.
  Note? get bass {
    final n = notes;
    if (n.isEmpty) return null;
    return n.reduce((a, b) => a.midi <= b.midi ? a : b);
  }

  Set<PitchClass> get pitchClasses => {for (final n in notes) n.pitchClass};

  /// Checks this voicing's notes against [chord]'s formula.
  VoicingCheck check(Chord chord) {
    final intervals = {for (final pc in pitchClasses) chord.root.intervalTo(pc)};
    final missing = chord.quality.required.difference(intervals);
    final bassPc = chord.bass;
    final foreign = {
      for (final i in intervals.difference(chord.quality.allowed))
        if (bassPc == null || chord.root.transpose(i) != bassPc) chord.root.transpose(i),
    };
    final b = bass;
    final wrongBass = bassPc != null && b != null && b.pitchClass != bassPc;
    return VoicingCheck(
      missing: {for (final i in missing) chord.root.transpose(i)},
      foreign: foreign,
      wrongBass: wrongBass,
    );
  }
}

/// Result of [Voicing.check].
@immutable
final class VoicingCheck {
  const VoicingCheck({required this.missing, required this.foreign, required this.wrongBass});

  /// Required chord tones the voicing does not play.
  final Set<PitchClass> missing;

  /// Notes the voicing plays that are not in the chord.
  final Set<PitchClass> foreign;

  /// Slash chord whose lowest note is not the named bass.
  final bool wrongBass;

  bool get isValid => missing.isEmpty && foreign.isEmpty && !wrongBass;

  String describe([Spelling spelling = Spelling.sharps]) {
    if (isValid) return 'ok';
    return [
      if (missing.isNotEmpty) 'missing ${missing.map((p) => p.name(spelling)).join(' ')}',
      if (foreign.isNotEmpty) 'foreign ${foreign.map((p) => p.name(spelling)).join(' ')}',
      if (wrongBass) 'wrong bass',
    ].join(', ');
  }
}
