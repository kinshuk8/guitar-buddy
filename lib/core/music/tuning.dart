import 'package:fretlight/core/music/pitch.dart';
import 'package:meta/meta.dart';

/// Open-string pitches, lowest (6th string) first.
@immutable
final class Tuning {
  const Tuning({
    required this.id,
    required this.name,
    required this.strings,
    this.isCustom = false,
  });

  /// Builds a tuning from note names like `['E2', 'A2', 'D3', 'G3', 'B3', 'E4']`.
  factory Tuning.fromNames(String id, String name, List<String> notes, {bool isCustom = false}) =>
      Tuning(
        id: id,
        name: name,
        strings: [for (final n in notes) Note.parse(n)],
        isCustom: isCustom,
      );

  final String id;
  final String name;

  /// Index 0 is the lowest-pitched string (low E in standard).
  final List<Note> strings;

  final bool isCustom;

  int get stringCount => strings.length;

  /// Sounding note at [fret] on string [index] (0 = lowest).
  Note noteAt(int index, int fret) => strings[index].transpose(fret);

  /// Index of the string whose open pitch is nearest [midi], for auto-detect.
  /// Ties go to the lower string (it is the one more often out of tune).
  int nearestString(double midi) {
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < strings.length; i++) {
      final d = (strings[i].midi - midi).abs();
      if (d < bestDistance) {
        best = i;
        bestDistance = d;
      }
    }
    return best;
  }

  /// Every (string, fret) where [note] can be played, up to [maxFret].
  List<FretPosition> positionsOf(Note note, {int maxFret = 15}) => [
    for (var s = 0; s < strings.length; s++)
      if (note.midi - strings[s].midi case final fret when fret >= 0 && fret <= maxFret)
        FretPosition(s, fret),
  ];

  static final standard = Tuning.fromNames('standard', 'Standard', const [
    'E2',
    'A2',
    'D3',
    'G3',
    'B3',
    'E4',
  ]);
  static final dropD = Tuning.fromNames('drop_d', 'Drop D', const [
    'D2',
    'A2',
    'D3',
    'G3',
    'B3',
    'E4',
  ]);
  static final dadgad = Tuning.fromNames('dadgad', 'DADGAD', const [
    'D2',
    'A2',
    'D3',
    'G3',
    'A3',
    'D4',
  ]);
  static final openG = Tuning.fromNames('open_g', 'Open G', const [
    'D2',
    'G2',
    'D3',
    'G3',
    'B3',
    'D4',
  ]);
  static final halfStepDown = Tuning.fromNames('half_step_down', 'Half-step Down', const [
    'Eb2',
    'Ab2',
    'Db3',
    'Gb3',
    'Bb3',
    'Eb4',
  ]);

  static final List<Tuning> presets = [standard, dropD, dadgad, openG, halfStepDown];
}

/// A spot on the fretboard. [string] 0 is the lowest-pitched string; fret 0 is open.
@immutable
final class FretPosition {
  const FretPosition(this.string, this.fret);

  final int string;
  final int fret;

  @override
  bool operator ==(Object other) =>
      other is FretPosition && other.string == string && other.fret == fret;

  @override
  int get hashCode => Object.hash(string, fret);

  @override
  String toString() => 'FretPosition(string: $string, fret: $fret)';
}
