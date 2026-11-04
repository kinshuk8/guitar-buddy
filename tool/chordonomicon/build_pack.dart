// Builds assets/packs/chordonomicon/progressions.sqlite from the
// Chordonomicon CSV.
//
//   curl -L -o /tmp/chordonomicon_v2.csv \
//     https://huggingface.co/datasets/ailsntua/Chordonomicon/resolve/main/chordonomicon_v2.csv
//   dart run tool/chordonomicon/build_pack.dart /tmp/chordonomicon_v2.csv
//
// Runs on a developer machine only; the app never touches the network.
// It's a CLI, so printing is its output.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'build_pack_lib.dart';

const _keep = 300;
const _minSongs = 25;
const _out = 'assets/packs/chordonomicon/progressions.sqlite';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/chordonomicon/build_pack.dart <chordonomicon_v2.csv>');
    exit(64);
  }
  final lines = File(args.single)
      .openRead()
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  List<String>? header;
  final stats = <String, PatternStats>{};
  var rows = 0;
  await for (final line in lines) {
    final cells = parseCsvLine(line);
    if (header == null) {
      header = cells;
      continue;
    }
    addRow(stats, header, cells);
    if (++rows % 100000 == 0) print('$rows rows, ${stats.length} progressions so far');
  }

  final top = stats.entries.where((e) => e.value.songs >= _minSongs).toList()
    ..sort((a, b) => b.value.songs.compareTo(a.value.songs));
  final kept = top.take(_keep).toList();

  final file = File(_out)..createSync(recursive: true);
  if (file.existsSync()) file.deleteSync();
  final db = sqlite3.open(_out)
    ..execute('''
      CREATE TABLE progressions (
        id INTEGER PRIMARY KEY,
        chords TEXT NOT NULL,       -- in its most common key, space-separated
        in_c TEXT NOT NULL,         -- the same, first chord on C (key-free)
        songs INTEGER NOT NULL,     -- how many songs in the dataset use it
        genres TEXT NOT NULL,       -- up to 3 most common main genres, comma-separated
        decade_from INTEGER,        -- middle 80% of uses
        decade_to INTEGER,
        section TEXT NOT NULL       -- where it's most often found: verse, chorus…
      );
      CREATE TABLE pack_info (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    ''');
  final insert = db.prepare(
    'INSERT INTO progressions (id, chords, in_c, songs, genres, decade_from, decade_to, section) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
  );
  for (final (i, e) in kept.indexed) {
    final s = e.value;
    final span = s.decadeSpan;
    insert.execute([
      i + 1,
      inCommonKey(e.key, s).join(' '),
      e.key,
      s.songs,
      s.topGenres(3).join(','),
      span?.$1,
      span?.$2,
      s.commonSection,
    ]);
  }
  insert.close();
  final info = db.prepare('INSERT INTO pack_info VALUES (?, ?)');
  for (final (k, v) in [
    ('name', 'Chordonomicon progressions'),
    ('source', 'https://huggingface.co/datasets/ailsntua/Chordonomicon'),
    ('licence', 'CC BY-NC 4.0 (https://creativecommons.org/licenses/by-nc/4.0/)'),
    (
      'citation',
      'Kantarelis, Thomas, Lyberatos, Dervakos, Stamou. CHORDONOMICON: A Dataset of '
          '666,000 Songs and their Chord Progressions. arXiv:2410.22046, 2024.',
    ),
    (
      'changes',
      'Reduced to aggregate statistics of repeating 3-4 chord loops; no per-song data, '
          'artists, identifiers or dates are included.',
    ),
    ('rows_scanned', '$rows'),
    ('progressions', '${kept.length}'),
  ]) {
    info.execute([k, v]);
  }
  info.close();
  db.execute('VACUUM');
  db.close();
  print(
    'Scanned $rows songs, found ${stats.length} distinct loops; '
    'kept ${kept.length} used by at least $_minSongs songs → $_out '
    '(${(file.lengthSync() / 1024).toStringAsFixed(0)} KB)',
  );
}
