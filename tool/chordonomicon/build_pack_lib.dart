// Offline build tool (never shipped): distils Chordonomicon into a small
// progression pack.
//
// Chordonomicon (Kantarelis et al. 2024, CC BY-NC 4.0) is one CSV,
// `chordonomicon_v2.csv`, inspected at commit 2ad317c (May 2025):
//   id, chords, release_date, genres, decade, rock_genre, artist_id,
//   main_genre, spotify_song_id, spotify_artist_id
// `chords` is a string of section tags and chord tokens:
//   "<verse_1> F C E7 Amin C <chorus_1> G D Fs7 Bmin A/Cs …"
// Tokens spell minor as `min` and sharps as `s`.
//
// The pack keeps **no per-song data**: no ids, artists, Spotify ids or
// dates. Each section is reduced to its repeating loop (if it has one),
// loops are compared independently of key, and only aggregate counts are
// kept: how many songs use the loop, their genres, their decades.

import 'package:fretlight/core/music/music.dart';

/// Qualities practice mode can check by ear (the identifier's v1 set).
final Set<ChordQuality> _practicable = ChordQuality.detectable.toSet();

final Map<String, Chord?> _tokenCache = {};

/// A Chordonomicon chord token as a chord, or null if it isn't one we use
/// (slash chords, extended chords, `N`).
Chord? parseToken(String token) => _tokenCache.putIfAbsent(token, () {
  if (token.contains('/')) return null;
  final normalised = token.replaceAll('min', 'm');
  final c = Chord.tryParse(normalised);
  if (c == null || !_practicable.contains(c.quality)) return null;
  return c;
});

/// Splits the `chords` field into (section kind, chords) pairs. Songs with
/// no section tags (a fair share of the dataset) are one `song` section.
List<(String, List<String>)> sections(String field) {
  final out = <(String, List<String>)>[];
  String? kind = 'song';
  var tokens = <String>[];
  for (final t in field.split(' ')) {
    if (t.isEmpty) continue;
    if (t.startsWith('<') && t.endsWith('>')) {
      if (kind != null && tokens.isNotEmpty) out.add((kind, tokens));
      kind = t.substring(1, t.length - 1).split('_').first;
      tokens = [];
    } else {
      tokens.add(t);
    }
  }
  if (kind != null && tokens.isNotEmpty) out.add((kind, tokens));
  return out;
}

/// The loop a section repeats, or null.
///
/// Consecutive repeats are merged first (G G C → G C). A loop of 3 or 4
/// chords must repeat at least twice, covering the whole section except
/// possibly a trailing partial pass.
List<Chord>? loopOf(List<String> tokens) {
  final chords = <Chord>[];
  for (final t in tokens) {
    final c = parseToken(t);
    if (c == null) return null;
    if (chords.isEmpty || chords.last != c) chords.add(c);
  }
  for (final p in const [3, 4]) {
    if (chords.length < 2 * p) continue;
    var ok = true;
    for (var i = 0; i < chords.length && ok; i++) {
      ok = chords[i] == chords[i % p];
    }
    // A loop that never changes chord isn't a progression.
    if (ok && chords.take(p).toSet().length == p) return chords.sublist(0, p);
  }
  return null;
}

/// The loop transposed so its first chord is on C: one key-free name for
/// the same progression in any key.
String patternKey(List<Chord> loop) {
  final shift = -loop.first.root.value;
  return spellInKey(loop.map((c) => c.transpose(shift)).toList()).join(' ');
}

/// Spells a loop for the key its first chord implies (Cm Ab Eb Bb, not
/// Cm G# D# A#). In sharp keys, borrowed chords a flat 2nd, 3rd, 6th or 7th
/// above still take flats, as musicians write them: C Bb F, not C A# F.
List<String> spellInKey(List<Chord> loop) {
  final first = loop.first;
  final keySpelling = Spelling.forKey(first.root, minor: first.quality == ChordQuality.minor);
  return [
    for (final c in loop)
      c.symbol(
        keySpelling == Spelling.flats || const {1, 3, 8, 10}.contains(first.root.intervalTo(c.root))
            ? Spelling.flats
            : Spelling.sharps,
      ),
  ];
}

/// Aggregates for one progression across the dataset.
final class PatternStats {
  int songs = 0;
  final Map<int, int> firstRoot = {};
  final Map<String, int> genres = {};
  final Map<int, int> decades = {};
  final Map<String, int> sectionKinds = {};

  void add({
    required int root,
    required String? genre,
    required int? decade,
    required String kind,
  }) {
    songs++;
    firstRoot.update(root, (n) => n + 1, ifAbsent: () => 1);
    if (genre != null && genre.isNotEmpty) genres.update(genre, (n) => n + 1, ifAbsent: () => 1);
    if (decade != null) decades.update(decade, (n) => n + 1, ifAbsent: () => 1);
    sectionKinds.update(kind, (n) => n + 1, ifAbsent: () => 1);
  }

  /// The key players most often use it in (by its first chord's root).
  int get commonRoot => _top(firstRoot);

  static K _top<K>(Map<K, int> m) => m.entries.reduce((a, b) => b.value > a.value ? b : a).key;

  List<String> topGenres(int n) {
    final e = genres.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final x in e.take(n)) x.key];
  }

  String get commonSection => _top(sectionKinds);

  /// Decades holding the middle 80% of uses (ignores stray outliers).
  (int, int)? get decadeSpan {
    if (decades.isEmpty) return null;
    final sorted = decades.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final total = sorted.fold(0, (s, e) => s + e.value);
    var acc = 0;
    int? from;
    int? to;
    for (final e in sorted) {
      acc += e.value;
      if (from == null && acc >= total * 0.1) from = e.key;
      if (to == null && acc >= total * 0.9) to = e.key;
    }
    return (from!, to!);
  }
}

/// Minimal CSV line parser (RFC 4180 quoting; the dataset has no embedded
/// newlines).
List<String> parseCsvLine(String line) {
  final out = <String>[];
  final buf = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        buf.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      out.add(buf.toString());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  out.add(buf.toString());
  return out;
}

/// Adds one dataset row to [stats]. Each song counts once per progression.
void addRow(Map<String, PatternStats> stats, List<String> header, List<String> row) {
  if (row.length != header.length) return;
  final get = {for (var i = 0; i < header.length; i++) header[i]: row[i]};
  final field = get['chords'];
  if (field == null) return;
  final seen = <String>{};
  final decade = double.tryParse(get['decade'] ?? '')?.round();
  final genre = get['main_genre'];
  for (final (kind, tokens) in sections(field)) {
    final loop = loopOf(tokens);
    if (loop == null) continue;
    final key = patternKey(loop);
    if (!seen.add(key)) continue;
    (stats[key] ??= PatternStats()).add(
      root: loop.first.root.value,
      genre: genre,
      decade: decade,
      kind: kind,
    );
  }
}

/// The progression in its most common key, as chord symbols.
List<String> inCommonKey(String key, PatternStats s) {
  final chords = key.split(' ').map(Chord.parse).toList();
  return spellInKey([for (final c in chords) c.transpose(s.commonRoot)]);
}
