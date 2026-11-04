import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:meta/meta.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// A common chord loop from the Chordonomicon pack.
@immutable
final class Progression {
  const Progression({
    required this.id,
    required this.symbols,
    required this.chords,
    required this.songs,
    required this.genres,
    required this.decades,
    required this.section,
  });

  final int id;

  /// As written in its most common key.
  final List<String> symbols;
  final List<Chord> chords;

  /// How many songs in the dataset use it.
  final int songs;
  final List<String> genres;
  final (int, int)? decades;

  /// Where it's most often heard: verse, chorus…
  final String section;
}

/// The optional progression pack (Chordonomicon, CC BY-NC 4.0).
///
/// Removable by design: it lives in its own asset folder with its own
/// attribution. Delete `assets/packs/chordonomicon/` and its pubspec line
/// and the app simply hides the progressions section.
final class ProgressionPack {
  ProgressionPack._(this.items, this.info, this.columns);

  /// Opens a pack file directly (tests, tools).
  factory ProgressionPack.openFile(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      final info = {
        for (final r in db.select('SELECT key, value FROM pack_info'))
          r['key'] as String: r['value'] as String,
      };
      final columns = [
        for (final r in db.select('PRAGMA table_info(progressions)')) r['name'] as String,
      ];
      final items = <Progression>[];
      for (final r in db.select('SELECT * FROM progressions ORDER BY songs DESC, id')) {
        final symbols = (r['chords'] as String).split(' ');
        final chords = symbols.map(Chord.tryParse).toList();
        if (chords.contains(null)) continue;
        final from = r['decade_from'] as int?;
        final to = r['decade_to'] as int?;
        items.add(
          Progression(
            id: r['id'] as int,
            symbols: symbols,
            chords: chords.cast<Chord>(),
            songs: r['songs'] as int,
            genres: (r['genres'] as String).split(',').where((g) => g.isNotEmpty).toList(),
            decades: from == null || to == null ? null : (from, to),
            section: r['section'] as String,
          ),
        );
      }
      return ProgressionPack._(List.unmodifiable(items), Map.unmodifiable(info), columns);
    } finally {
      db.close();
    }
  }

  static const asset = 'assets/packs/chordonomicon/progressions.sqlite';

  final List<Progression> items;
  final Map<String, String> info;

  /// Column names, so a test can prove no per-song data ships.
  final List<String> columns;

  /// Loads the bundled pack, or null if it has been removed from the build.
  /// SQLite needs a real file, so the asset is copied to the cache once.
  static Future<ProgressionPack?> load() async {
    final ByteData data;
    try {
      data = await rootBundle.load(asset);
    } on Object {
      return null;
    }
    final dir = await getApplicationCacheDirectory();
    final file = File('${dir.path}/chordonomicon-progressions.sqlite');
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    if (!file.existsSync() || file.lengthSync() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return ProgressionPack.openFile(file.path);
  }
}

final progressionPackProvider = FutureProvider<ProgressionPack?>((ref) => ProgressionPack.load());
