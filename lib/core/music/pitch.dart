/// Pitch primitives: pitch classes, notes and how to spell them.
///
/// Everything in `core/music` is pure Dart (no Flutter imports) so it can be
/// used from the DSP isolate, offline `tool/` scripts and fast unit tests.
library;

/// Whether to name black keys with sharps or flats.
enum Spelling {
  sharps,
  flats;

  /// Conventional guitar-chart spelling for a chord root:
  /// C C# D Eb E F F# G Ab A Bb B (what most chord books and chords-db use).
  static Spelling forRoot(PitchClass root) =>
      const {3, 8, 10}.contains(root.value) ? Spelling.flats : Spelling.sharps;

  /// Spelling for a key signature, so a song transposed to F uses Bb, not A#.
  static Spelling forKey(PitchClass tonic, {bool minor = false}) {
    // Major keys written with flats: F Bb Eb Ab Db Gb. Relative minors are
    // a minor third below, so shift minor tonics up 3 before looking up.
    final major = minor ? tonic.transpose(3) : tonic;
    return const {5, 10, 3, 8, 1, 6}.contains(major.value) ? Spelling.flats : Spelling.sharps;
  }
}

/// One of the 12 pitch classes, 0 = C. Always normalised to 0..11.
///
/// An extension type rather than a class: it is a plain `int` at runtime, so
/// it costs nothing in DSP loops and crosses isolate boundaries for free,
/// while still being a distinct type at compile time.
extension type const PitchClass._(int value) {
  factory PitchClass(int value) => PitchClass._(value % 12);

  static const c = PitchClass._(0);
  static const a = PitchClass._(9);

  static const _sharpNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  static const _flatNames = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'];
  static const _letterOffsets = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};

  /// Parses a note name without octave: `C`, `F#`, `Bb`, `E♭`, `Cs` (Chordonomicon's sharp).
  /// Returns null if [name] is not a note name.
  static PitchClass? tryParse(String name) {
    final (offset, length) = _parsePrefix(name) ?? (null, 0);
    if (offset == null || length != name.length) return null;
    return PitchClass(offset);
  }

  /// Parses the longest note-name prefix of [text]. Returns the *unwrapped*
  /// semitone offset (B# = 12, Cb = -1, so octave math stays right) and how
  /// many characters were consumed.
  static (int offset, int length)? _parsePrefix(String text) {
    if (text.isEmpty) return null;
    final letter = _letterOffsets[text[0].toUpperCase()];
    if (letter == null) return null;
    var offset = letter;
    var i = 1;
    while (i < text.length && i <= 2) {
      final ch = text[i];
      if (ch == '#' || ch == '♯' || ch == 's') {
        // Only treat 's' as a sharp when it is not the start of "sus".
        if (ch == 's' && text.startsWith('sus', i)) break;
        offset++;
      } else if (ch == 'b' || ch == '♭') {
        offset--;
      } else {
        break;
      }
      i++;
    }
    return (offset, i);
  }

  String name([Spelling spelling = Spelling.sharps]) =>
      (spelling == Spelling.sharps ? _sharpNames : _flatNames)[value];

  PitchClass transpose(int semitones) => PitchClass(value + semitones);

  /// Ascending interval in semitones (0..11) from this pitch class to [other].
  int intervalTo(PitchClass other) => (other.value - value) % 12;
}

/// A concrete pitch as a MIDI note number (60 = C4, 69 = A4).
///
/// Notes are stored by number, not spelling. The app is guitar-centric, so
/// spelling is a display concern decided by context ([Spelling]).
extension type const Note(int midi) {
  static final _octaveSuffix = RegExp(r'^-?\d+$');

  /// Parses scientific pitch notation: `E2`, `C#4`, `Bb3`, `Cb4` (= B3).
  static Note? tryParse(String text) {
    final prefix = PitchClass._parsePrefix(text);
    if (prefix == null) return null;
    final (offset, length) = prefix;
    final octaveText = text.substring(length);
    if (!_octaveSuffix.hasMatch(octaveText)) return null;
    return Note((int.parse(octaveText) + 1) * 12 + offset);
  }

  static Note parse(String text) =>
      tryParse(text) ?? (throw FormatException('Not a note name', text));

  PitchClass get pitchClass => PitchClass(midi);

  /// Octave in scientific pitch notation (C4 is middle C).
  int get octave => (midi ~/ 12) - 1;

  Note transpose(int semitones) => Note(midi + semitones);

  String name([Spelling spelling = Spelling.sharps]) => '${pitchClass.name(spelling)}$octave';
}
