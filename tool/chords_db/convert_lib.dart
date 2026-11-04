// Offline build tool (never shipped): converts tombatossals/chords-db's
// `lib/guitar.json` into the app's bundled chord asset.
//
// chords-db schema (inspected at commit df06fa7, Oct 2025):
//   { main: {strings: 6, fretsOnChord: 4}, tunings: {standard: [E2..E4]},
//     keys: [...], suffixes: [...],
//     chords: { C: [ {key, suffix, positions: [
//       { frets: [-1,3,2,0,1,0],   // relative to baseFret; -1 muted, 0 open
//         fingers: [0,3,2,0,1,0],  // 0 = no finger
//         baseFret: 1,
//         barres: [1],             // relative frets that are barred
//         capo: true,              // optional: barre drawn across the neck
//         midi: [48,52,...] } ]}]}} // sounding notes, cross-checked below
// Keys spell sharps as `Csharp`/`Fsharp`.

import 'package:fretlight/core/music/music.dart';

/// chords-db suffix → our quality. Slash suffixes are handled separately.
const Map<String, ChordQuality> suffixQualities = {
  'major': ChordQuality.major,
  'minor': ChordQuality.minor,
  'dim': ChordQuality.dim,
  'dim7': ChordQuality.dim7,
  'sus': ChordQuality.sus4, // chords-db's `sus` voicings all play 1 4 5.
  'sus2': ChordQuality.sus2,
  'sus4': ChordQuality.sus4,
  'sus2sus4': ChordQuality.sus2sus4,
  '7sus4': ChordQuality.sus4dominant7,
  'alt': ChordQuality.majorFlat5, // all `alt` voicings play 1 3 b5, not an altered dominant.
  'aug': ChordQuality.aug,
  '5': ChordQuality.power,
  '6': ChordQuality.sixth,
  '69': ChordQuality.sixNine,
  '7': ChordQuality.dominant7,
  '7b5': ChordQuality.dominant7flat5,
  'aug7': ChordQuality.aug7,
  '9': ChordQuality.dominant9,
  '9b5': ChordQuality.dominant9flat5,
  'aug9': ChordQuality.aug9,
  '7b9': ChordQuality.dominant7flat9,
  '7#9': ChordQuality.dominant7sharp9,
  '11': ChordQuality.dominant11,
  '9#11': ChordQuality.dominant9sharp11,
  '13': ChordQuality.dominant13,
  'maj7': ChordQuality.major7,
  'maj7b5': ChordQuality.major7flat5,
  'maj7#5': ChordQuality.major7sharp5,
  'maj7sus2': ChordQuality.major7sus2,
  'maj9': ChordQuality.major9,
  'maj11': ChordQuality.major11,
  'maj13': ChordQuality.major13,
  'm6': ChordQuality.minor6,
  'm69': ChordQuality.minor6add9,
  'm7': ChordQuality.minor7,
  'm7b5': ChordQuality.halfDim7,
  'm9': ChordQuality.minor9,
  'm11': ChordQuality.minor11,
  'mmaj7': ChordQuality.minorMajor7,
  'mmaj7b5': ChordQuality.minorMajor7flat5,
  'mmaj9': ChordQuality.minorMajor9,
  'mmaj11': ChordQuality.minorMajor11,
  'add9': ChordQuality.add9,
  'madd9': ChordQuality.minorAdd9,
  'add11': ChordQuality.add11,
};

/// Parses a chords-db key (`C`, `Csharp`, `Eb`) to a pitch class.
PitchClass parseKey(String key) =>
    PitchClass.tryParse(key.replaceAll('sharp', '#')) ?? (throw FormatException('Bad key', key));

/// The root as chords-db spells it, which is how guitarists name these keys.
String keySpelling(String key) => key.replaceAll('sharp', '#');

/// Parses a suffix: plain qualities, `7/G`, `/E` (major over E), `m/B`, `m9/Bb`.
({ChordQuality quality, PitchClass? bass})? parseSuffix(String suffix) {
  final slash = suffix.indexOf('/');
  if (slash < 0) {
    final q = suffixQualities[suffix];
    return q == null ? null : (quality: q, bass: null);
  }
  final head = suffix.substring(0, slash);
  final bass = PitchClass.tryParse(suffix.substring(slash + 1));
  final q = head.isEmpty
      ? ChordQuality.major
      : (suffixQualities[head] ?? ChordQuality.tryParseSuffix(head));
  if (q == null || bass == null) return null;
  return (quality: q, bass: bass);
}

/// One problem found in the source data.
final class Issue {
  Issue(this.chord, this.position, this.frets, this.message);

  final String chord;
  final int position;
  final List<int?> frets;
  final String message;

  String get fretsText => frets.map((f) => f?.toString() ?? 'x').join(' ');
}

/// One chord after conversion: what gets written to the asset.
final class ConvertedChord {
  ConvertedChord(this.symbol, this.rootSpelling, this.chord, this.voicings);

  final String symbol;
  final String rootSpelling;
  final Chord chord;
  final List<Voicing> voicings;
}

final class ConversionResult {
  ConversionResult(this.chords, this.issues, this.sourcePositions, this.mergedDuplicates);

  final List<ConvertedChord> chords;

  /// Voicings excluded from the asset, with why.
  final List<Issue> issues;
  final int sourcePositions;

  /// Identical voicings listed under two suffixes (e.g. `sus` and `sus4`).
  final int mergedDuplicates;

  int get keptVoicings => chords.fold(0, (n, c) => n + c.voicings.length);
}

/// Converts one chords-db position. Returns the voicing or a reason to reject it.
({Voicing? voicing, String? problem}) convertPosition(Map<String, Object?> p) {
  final rel = (p['frets']! as List).cast<int>();
  final fingersRaw = (p['fingers']! as List).cast<int>();
  final base = p['baseFret']! as int;
  final barresRel = (p['barres']! as List).cast<int>();
  final midi = (p['midi']! as List).cast<int>();
  if (rel.length != 6 || fingersRaw.length != 6) {
    return (voicing: null, problem: 'expected 6 strings');
  }
  int? abs(int f) => f < 0 ? null : (f == 0 ? 0 : f + base - 1);
  final frets = [for (final f in rel) abs(f)];

  final barres = <Barre>[];
  for (final b in barresRel) {
    final onFret = [
      for (var s = 0; s < 6; s++)
        if (rel[s] == b) s,
    ];
    if (onFret.length < 2) return (voicing: null, problem: 'barre at $b covers <2 strings');
    // The barring finger is the one used on the most strings at that fret.
    final counts = <int, int>{};
    for (final s in onFret) {
      if (fingersRaw[s] > 0) counts.update(fingersRaw[s], (n) => n + 1, ifAbsent: () => 1);
    }
    final finger = counts.isEmpty
        ? 1
        : counts.entries.reduce((a, c) => c.value > a.value ? c : a).key;
    final barred = onFret.where((s) => fingersRaw[s] == finger || fingersRaw[s] == 0).toList();
    final low = barred.first;
    final high = barred.last;
    // An open or lower-fretted string under the barre can't ring.
    for (var s = low; s <= high; s++) {
      if (rel[s] >= 0 && rel[s] < b) {
        return (voicing: null, problem: 'string ${s + 1} rings below the barre at fret ${abs(b)}');
      }
    }
    barres.add(Barre(fret: abs(b)!, lowString: low, highString: high, finger: finger));
  }

  final voicing = Voicing(
    frets: frets,
    fingers: [
      for (final f in fingersRaw)
        if (f == 0) null else f,
    ],
    barres: barres,
  );
  final computed = voicing.notes.map((n) => n.midi).toList();
  if (computed.length != midi.length ||
      [for (var i = 0; i < midi.length; i++) computed[i] == midi[i]].contains(false)) {
    return (voicing: null, problem: 'frets give MIDI $computed but source lists $midi');
  }
  return (voicing: voicing, problem: null);
}

/// Converts the whole chords-db guitar file.
ConversionResult convert(Map<String, Object?> db) {
  final tuning = ((db['tunings']! as Map)['standard']! as List).cast<String>();
  if (tuning.join(' ') != 'E2 A2 D3 G3 B3 E4') {
    throw const FormatException('Expected standard tuning in chords-db');
  }
  final byChord = <Chord, ConvertedChord>{};
  final issues = <Issue>[];
  var positions = 0;
  var duplicates = 0;
  final chordsByKey = (db['chords']! as Map).cast<String, Object?>();
  for (final MapEntry(:key, value: list) in chordsByKey.entries) {
    final root = parseKey(key);
    for (final c in (list! as List).cast<Map<String, Object?>>()) {
      final suffix = c['suffix']! as String;
      final parsed = parseSuffix(suffix);
      final sourcePositions = (c['positions']! as List).cast<Map<String, Object?>>();
      positions += sourcePositions.length;
      final label = '${keySpelling(key)} $suffix';
      if (parsed == null) {
        for (final (i, _) in sourcePositions.indexed) {
          issues.add(Issue(label, i + 1, const [], 'unknown suffix'));
        }
        continue;
      }
      final chord = Chord(root, parsed.quality, bass: parsed.bass == root ? null : parsed.bass);
      final spelling = keySpelling(key);
      final entry = byChord.putIfAbsent(
        chord,
        () => ConvertedChord(_symbol(spelling, chord), spelling, chord, []),
      );
      for (final (i, p) in sourcePositions.indexed) {
        final r = convertPosition(p);
        final v = r.voicing;
        if (v == null) {
          final rel = (p['frets']! as List).cast<int>();
          final base = p['baseFret']! as int;
          final abs = [
            for (final f in rel)
              if (f < 0) null else if (f == 0) 0 else f + base - 1,
          ];
          issues.add(Issue(label, i + 1, abs, r.problem!));
          continue;
        }
        final check = v.check(chord);
        if (!check.isValid) {
          issues.add(Issue(label, i + 1, v.frets, check.describe(Spelling.forRoot(root))));
          continue;
        }
        if (entry.voicings.any((e) => _sameFrets(e.frets, v.frets))) {
          duplicates++;
          continue;
        }
        entry.voicings.add(v);
      }
    }
  }
  final chords = byChord.values.where((c) => c.voicings.isNotEmpty).toList();
  return ConversionResult(chords, issues, positions, duplicates);
}

bool _sameFrets(List<int?> a, List<int?> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _symbol(String rootSpelling, Chord chord) {
  final b = chord.bass;
  final spelling = rootSpelling.contains('b') ? Spelling.flats : Spelling.sharps;
  return '$rootSpelling${chord.quality.suffix}${b == null ? '' : '/${b.name(spelling)}'}';
}

/// The asset's JSON (format 1). Frets are absolute; null = muted.
Map<String, Object?> toAssetJson(ConversionResult r, {required String commit}) => {
  'format': 1,
  'source': {
    'name': 'chords-db',
    'url': 'https://github.com/tombatossals/chords-db',
    'commit': commit,
    'licence': 'MIT',
    'copyright': 'Copyright (c) 2016 David Rubert',
  },
  'tuning': 'standard',
  'chords': [
    for (final c in r.chords)
      {
        'symbol': c.symbol,
        'root': c.rootSpelling,
        'quality': c.chord.quality.name,
        if (c.chord.bass case final b?) 'bass': b.name(Spelling.forRoot(c.chord.root)),
        'voicings': [
          for (final v in c.voicings)
            {
              'frets': v.frets,
              'fingers': [for (final f in v.fingers) f ?? 0],
              if (v.barres.isNotEmpty)
                'barres': [
                  for (final b in v.barres) [b.fret, b.lowString, b.highString, b.finger],
                ],
            },
        ],
      },
  ],
};

/// Markdown report of what was kept and what was rejected.
String report(ConversionResult r, {required String commit}) {
  final buf = StringBuffer()
    ..writeln('# Chord data report')
    ..writeln()
    ..writeln(
      'Generated by `tool/chords_db/convert.dart` from '
      '[chords-db](https://github.com/tombatossals/chords-db) (MIT) at commit `$commit`.',
    )
    ..writeln()
    ..writeln(
      'Every voicing is checked twice: the notes its frets produce must match '
      "chords-db's own `midi` list, and those notes must fit the chord's "
      'formula (all required tones, nothing foreign, the right bass for slash '
      'chords). Voicings that fail are left out of the app and listed below.',
    )
    ..writeln()
    ..writeln('| | Count |')
    ..writeln('|---|---|')
    ..writeln('| Source voicings | ${r.sourcePositions} |')
    ..writeln('| Bundled voicings | ${r.keptVoicings} |')
    ..writeln('| Chords | ${r.chords.length} |')
    ..writeln('| Rejected | ${r.issues.length} |')
    ..writeln('| Duplicates merged | ${r.mergedDuplicates} |')
    ..writeln()
    ..writeln('## Naming decisions')
    ..writeln()
    ..writeln(
      '- `sus` is listed as sus4: every `sus` voicing plays 1 4 5, and duplicates of `sus4` were merged.',
    )
    ..writeln(
      '- `alt` is listed as (b5): every `alt` voicing plays 1 3 b5 with no 7th, '
      'so calling it an altered dominant would mislead.',
    )
    ..writeln()
    ..writeln('## Rejected voicings')
    ..writeln()
    ..writeln('Frets are absolute, low E to high E (x = muted).')
    ..writeln();
  if (r.issues.isEmpty) {
    buf.writeln('None.');
  } else {
    buf
      ..writeln('| Chord | # | Frets | Problem |')
      ..writeln('|---|---|---|---|');
    for (final i in r.issues) {
      buf.writeln('| ${i.chord} | ${i.position} | `${i.fretsText}` | ${i.message} |');
    }
  }
  return buf.toString();
}
