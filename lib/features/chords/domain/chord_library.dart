import 'package:fretlight/core/music/music.dart';
import 'package:meta/meta.dart';

/// One chord in the library with all its voicings.
@immutable
final class ChordEntry {
  const ChordEntry({
    required this.symbol,
    required this.rootName,
    required this.chord,
    required this.voicings,
    this.customIds = const {},
  });

  /// Voicing index → id of the user's own shape (shown first, deletable).
  final Map<int, String> customIds;

  bool get hasCustom => customIds.isNotEmpty;

  /// As shown and as stored in favourites: `C#m7`, `Bb/D`.
  final String symbol;

  /// Root as spelled in the library (`C#`, `Eb`): the conventional guitar names.
  final String rootName;
  final Chord chord;
  final List<Voicing> voicings;

  /// Spoken and secondary label: `C sharp minor 7th`.
  String get description {
    final b = chord.bass;
    final over = b == null ? '' : ' over ${b.name(Spelling.forRoot(chord.root))}';
    return '$rootName ${chord.quality.label}$over';
  }

  bool get isSlash => chord.bass != null;
}

/// How the library groups qualities when browsing a root.
enum QualityGroup {
  /// What most songs use; shown first.
  essentials('Essentials', [
    ChordQuality.major,
    ChordQuality.minor,
    ChordQuality.dominant7,
    ChordQuality.major7,
    ChordQuality.minor7,
    ChordQuality.sus2,
    ChordQuality.sus4,
    ChordQuality.power,
  ]),
  colour('Colour', [
    ChordQuality.add9,
    ChordQuality.minorAdd9,
    ChordQuality.sixth,
    ChordQuality.minor6,
    ChordQuality.sus4dominant7,
    ChordQuality.dominant9,
    ChordQuality.major9,
    ChordQuality.minor9,
    ChordQuality.sixNine,
    ChordQuality.minor6add9,
    ChordQuality.add11,
    ChordQuality.sus2sus4,
  ]),
  tension('Tension', [
    ChordQuality.dim,
    ChordQuality.dim7,
    ChordQuality.halfDim7,
    ChordQuality.aug,
    ChordQuality.aug7,
    ChordQuality.majorFlat5,
    ChordQuality.minorMajor7,
  ]),
  extended('Extended', []),
  slash('Slash', []);

  QualityGroup(this.label, this.qualities);

  final String label;
  final List<ChordQuality> qualities;

  static QualityGroup of(ChordEntry e) {
    if (e.isSlash) return slash;
    for (final g in values) {
      if (g.qualities.contains(e.chord.quality)) return g;
    }
    return extended;
  }
}

/// The bundled chord library.
final class ChordLibrary {
  ChordLibrary(this.entries, {required this.sourceCommit})
    : _bySymbol = {for (final e in entries) e.symbol: e},
      _byChord = {for (final e in entries) e.chord: e};

  /// Parses the asset written by `tool/chords_db/convert.dart` (format 1).
  /// Pure Dart: safe to run in a background isolate.
  factory ChordLibrary.fromJson(Map<String, Object?> json) {
    if (json['format'] != 1) throw FormatException('Unknown chord asset format', json['format']);
    final source = (json['source']! as Map).cast<String, Object?>();
    final entries = <ChordEntry>[];
    for (final raw in (json['chords']! as List).cast<Map<String, Object?>>()) {
      final rootName = raw['root']! as String;
      final root = PitchClass.tryParse(rootName);
      final quality = ChordQuality.values.asNameMap()[raw['quality']];
      final bassName = raw['bass'] as String?;
      final bass = bassName == null ? null : PitchClass.tryParse(bassName);
      if (root == null || quality == null || (bassName != null && bass == null)) {
        throw FormatException('Bad chord in asset', raw['symbol']);
      }
      entries.add(
        ChordEntry(
          symbol: raw['symbol']! as String,
          rootName: rootName,
          chord: Chord(root, quality, bass: bass),
          voicings: [
            for (final v in (raw['voicings']! as List).cast<Map<String, Object?>>())
              Voicing(
                frets: (v['frets']! as List).cast<int?>(),
                fingers: [
                  for (final f in (v['fingers']! as List).cast<int>())
                    if (f == 0) null else f,
                ],
                barres: [
                  for (final b in ((v['barres'] as List?) ?? const []).cast<List<Object?>>())
                    Barre(
                      fret: b[0]! as int,
                      lowString: b[1]! as int,
                      highString: b[2]! as int,
                      finger: b[3]! as int,
                    ),
                ],
              ),
          ],
        ),
      );
    }
    return ChordLibrary(entries, sourceCommit: source['commit']! as String);
  }

  final List<ChordEntry> entries;
  final String sourceCommit;
  final Map<String, ChordEntry> _bySymbol;
  final Map<Chord, ChordEntry> _byChord;

  ChordEntry? bySymbol(String symbol) => _bySymbol[symbol];

  /// This library plus the user's own shapes. A shape named like an
  /// existing chord is added to it (shown first); one with a new name, or
  /// with a name that isn't a chord symbol, becomes its own entry named
  /// from its notes.
  ChordLibrary withCustom(Map<String, ({String name, List<int?> frets})> custom) {
    if (custom.isEmpty) return this;
    final entries = [...this.entries];
    final index = {for (final (i, e) in entries.indexed) e.chord: i};
    for (final MapEntry(key: id, value: c) in custom.entries) {
      final voicing = Voicing(frets: c.frets);
      final chord =
          Chord.tryParse(c.name) ??
          ChordNamer.name(voicing.pitchClasses, bass: voicing.bass?.pitchClass);
      if (chord == null) continue;
      final at = index[chord];
      if (at != null) {
        final e = entries[at];
        entries[at] = ChordEntry(
          symbol: e.symbol,
          rootName: e.rootName,
          chord: e.chord,
          voicings: [voicing, ...e.voicings],
          customIds: {0: id, for (final x in e.customIds.entries) x.key + 1: x.value},
        );
      } else {
        index[chord] = entries.length;
        entries.add(
          ChordEntry(
            symbol: chord.symbol(),
            rootName: chord.root.name(Spelling.forRoot(chord.root)),
            chord: chord,
            voicings: [voicing],
            customIds: {0: id},
          ),
        );
      }
    }
    return ChordLibrary(entries, sourceCommit: sourceCommit);
  }

  /// Entries holding at least one of the user's shapes.
  List<ChordEntry> get custom => [
    for (final e in entries)
      if (e.hasCustom) e,
  ];

  /// Looks a chord up regardless of spelling (`Db` finds `C#`).
  ChordEntry? byChord(Chord chord) => _byChord[chord];

  /// The twelve roots, as the library spells them, C first.
  List<String> get roots {
    final seen = <int, String>{};
    for (final e in entries) {
      seen.putIfAbsent(e.chord.root.value, () => e.rootName);
    }
    final keys = seen.keys.toList()..sort();
    return [for (final k in keys) seen[k]!];
  }

  /// Every chord on [root], grouped for browsing, in a stable musical order.
  Map<QualityGroup, List<ChordEntry>> browse(PitchClass root) {
    final onRoot = entries.where((e) => e.chord.root == root).toList();
    // A group's own list sets its order (C, Cm, C7…); others follow the enum.
    int rank(ChordEntry e) {
      final inGroup = QualityGroup.of(e).qualities.indexOf(e.chord.quality);
      return inGroup >= 0 ? inGroup : 100 + e.chord.quality.index;
    }

    onRoot.sort((a, b) {
      final q = rank(a).compareTo(rank(b));
      if (q != 0) return q;
      return (a.chord.bass?.value ?? -1).compareTo(b.chord.bass?.value ?? -1);
    });
    final groups = <QualityGroup, List<ChordEntry>>{};
    for (final e in onRoot) {
      (groups[QualityGroup.of(e)] ??= []).add(e);
    }
    // Map literal order is insertion order; rebuild in enum order.
    return {for (final g in QualityGroup.values) g: ?groups[g]};
  }

  /// Finds chords by symbol or name.
  ///
  /// A query that parses as a chord (`am7`, `Bbmaj7`, `F#/A#`, `Db`) puts
  /// that exact chord first, whatever the spelling. Then symbols starting
  /// with the query, then descriptions containing every word (`minor 7`).
  List<ChordEntry> search(String query, {int limit = 60}) {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final results = <ChordEntry>[];
    void add(ChordEntry e) {
      if (!results.contains(e)) results.add(e);
    }

    final asChord = Chord.tryParse(_capitaliseRoot(q));
    if (asChord != null) {
      if (byChord(asChord) case final e?) add(e);
      // Same root, any quality starting with the typed suffix: `Am` → Am7, Am9…
      final typed = _capitaliseRoot(q);
      final typedSuffix = typed.substring(_rootLength(typed));
      if (!q.contains('/')) {
        for (final e in entries) {
          final suffix = e.chord.quality.suffix;
          // `m` means minor: don't offer `maj7` for `Am`.
          final minorTyped = typedSuffix.startsWith('m') && !typedSuffix.startsWith('ma');
          if (e.chord.root == asChord.root &&
              !e.isSlash &&
              suffix.startsWith(typedSuffix) &&
              !(minorTyped && suffix.startsWith('maj'))) {
            add(e);
          }
        }
      }
    }
    final lower = q.toLowerCase();
    for (final e in entries) {
      if (e.symbol.toLowerCase().startsWith(lower)) add(e);
    }
    final words = lower.split(RegExp(r'\s+'));
    for (final e in entries) {
      final d = e.description.toLowerCase();
      if (words.every(d.contains)) add(e);
    }
    return results.take(limit).toList();
  }

  /// `am7` → `Am7`, `f#` → `F#`, `bbmaj7` → `Bbmaj7`. Only the root letter
  /// changes: `m` vs `M` in the suffix means minor vs major.
  static String _capitaliseRoot(String q) => q[0].toUpperCase() + q.substring(1);

  static int _rootLength(String q) {
    for (var n = q.length.clamp(0, 2); n >= 1; n--) {
      if (PitchClass.tryParse(q.substring(0, n)) != null) return n;
    }
    return 0;
  }
}
