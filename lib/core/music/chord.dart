import 'package:fretlight/core/music/pitch.dart';
import 'package:meta/meta.dart';

/// A chord quality defined by intervals above the root.
///
/// [required] are tones a voicing must contain to count as this chord.
/// [optional] are tones a voicing may omit (usually the 5th, and the lower
/// extensions of 11th and 13th chords). A tone in neither set is foreign.
enum ChordQuality {
  major('', 'major', {0, 4}, {7}, 0),
  minor('m', 'minor', {0, 3}, {7}, 0),
  power('5', 'power', {0, 7}, {}, 1),
  sus2('sus2', 'sus2', {0, 2, 7}, {}, 1),
  sus4('sus4', 'sus4', {0, 5, 7}, {}, 1),
  dominant7('7', 'dominant 7th', {0, 4, 10}, {7}, 1),
  major7('maj7', 'major 7th', {0, 4, 11}, {7}, 1),
  minor7('m7', 'minor 7th', {0, 3, 10}, {7}, 1),
  dim('dim', 'diminished', {0, 3, 6}, {}, 2),
  aug('aug', 'augmented', {0, 4, 8}, {}, 2),
  sixth('6', 'major 6th', {0, 4, 9}, {7}, 2),
  minor6('m6', 'minor 6th', {0, 3, 9}, {7}, 2),
  add9('add9', 'add 9', {0, 2, 4}, {7}, 2),
  minorAdd9('madd9', 'minor add 9', {0, 2, 3}, {7}, 2),
  sus4dominant7('7sus4', '7th sus4', {0, 5, 10}, {7}, 2),
  halfDim7('m7b5', 'half-diminished', {0, 3, 6, 10}, {}, 2),
  dim7('dim7', 'diminished 7th', {0, 3, 6, 9}, {}, 2),
  minorMajor7('mmaj7', 'minor-major 7th', {0, 3, 11}, {7}, 3),
  aug7('aug7', 'augmented 7th', {0, 4, 8, 10}, {}, 3),
  sixNine('69', '6/9', {0, 2, 4, 9}, {7}, 3),
  dominant9('9', 'dominant 9th', {0, 2, 4, 10}, {7}, 3),
  major9('maj9', 'major 9th', {0, 2, 4, 11}, {7}, 3),
  minor9('m9', 'minor 9th', {0, 2, 3, 10}, {7}, 3),
  // 11ths and 13ths are routinely voiced without the 3rd/9th/11th.
  dominant11('11', 'dominant 11th', {0, 5, 10}, {2, 4, 7}, 4),
  dominant13('13', 'dominant 13th', {0, 4, 9, 10}, {2, 5, 7}, 4);

  ChordQuality(this.suffix, this.label, this.required, this.optional, this.complexity);

  /// Symbol suffix after the root: `m7` in `Am7`.
  final String suffix;

  /// Human-readable name for screen readers and the library.
  final String label;

  final Set<int> required;
  final Set<int> optional;

  /// Rough rank for preferring simpler names when two qualities fit equally.
  final int complexity;

  Set<int> get allowed => {...required, ...optional};

  /// The qualities the v1 chord detector recognises.
  static const List<ChordQuality> detectable = [
    major,
    minor,
    dominant7,
    major7,
    minor7,
    sus2,
    sus4,
    power,
  ];

  // Longest aliases first so `maj7` wins over `maj`, and `m7b5` over `m7`.
  static final List<(String, ChordQuality)> _aliases = [
    for (final q in values)
      if (q.suffix.isNotEmpty) (q.suffix, q),
    ('min7', minor7),
    ('-7', minor7),
    ('M7', major7),
    ('Δ7', major7),
    ('Δ', major7),
    ('ø7', halfDim7),
    ('ø', halfDim7),
    ('°7', dim7),
    ('°', dim),
    ('+', aug),
    ('min', minor),
    ('mi', minor),
    ('-', minor),
    ('maj', major),
    ('M', major),
    ('sus', sus4),
    ('7sus', sus4dominant7),
    ('add2', add9),
    ('6/9', sixNine),
    ('mM7', minorMajor7),
  ]..sort((a, b) => b.$1.length.compareTo(a.$1.length));

  /// Parses a suffix exactly (`m7`, `maj7`, `min`, `` for major). Null if unknown.
  static ChordQuality? tryParseSuffix(String suffix) {
    if (suffix.isEmpty) return major;
    for (final (alias, quality) in _aliases) {
      if (alias == suffix) return quality;
    }
    return null;
  }
}

/// A chord: root, quality, and an optional bass note for slash chords.
@immutable
final class Chord {
  const Chord(this.root, this.quality, {this.bass});

  final PitchClass root;
  final ChordQuality quality;

  /// Bass note when it differs from the root (`G/B`). Null means root position.
  final PitchClass? bass;

  /// Parses `C`, `F#m7`, `Bbmaj7`, `G/B`, `Amin` (Chordonomicon), `Cs` (= C#).
  static Chord? tryParse(String symbol) {
    final text = symbol.trim();
    if (text.isEmpty) return null;
    final slash = text.lastIndexOf('/');
    // `6/9` contains a slash but is a quality, not a bass note.
    final hasBass = slash > 0 && !text.endsWith('6/9');
    final main = hasBass ? text.substring(0, slash) : text;
    final bass = hasBass ? PitchClass.tryParse(text.substring(slash + 1)) : null;
    if (hasBass && bass == null) return null;

    for (var rootLength = main.length.clamp(0, 3); rootLength >= 1; rootLength--) {
      final root = PitchClass.tryParse(main.substring(0, rootLength));
      if (root == null) continue;
      final quality = ChordQuality.tryParseSuffix(main.substring(rootLength));
      if (quality == null) continue;
      return Chord(root, quality, bass: bass == root ? null : bass);
    }
    return null;
  }

  static Chord parse(String symbol) =>
      tryParse(symbol) ?? (throw FormatException('Not a chord symbol', symbol));

  /// Pitch classes this chord's formula allows (required + optional).
  Set<PitchClass> get pitchClasses => {for (final i in quality.allowed) root.transpose(i), ?bass};

  Chord transpose(int semitones) =>
      Chord(root.transpose(semitones), quality, bass: bass?.transpose(semitones));

  /// The symbol, e.g. `Bbmaj7` or `G/B`. Defaults to conventional root spelling.
  String symbol([Spelling? spelling]) {
    final s = spelling ?? Spelling.forRoot(root);
    final b = bass;
    return '${root.name(s)}${quality.suffix}${b == null ? '' : '/${b.name(s)}'}';
  }

  @override
  bool operator ==(Object other) =>
      other is Chord && other.root == root && other.quality == quality && other.bass == bass;

  @override
  int get hashCode => Object.hash(root, quality, bass);

  @override
  String toString() => 'Chord(${symbol()})';
}
