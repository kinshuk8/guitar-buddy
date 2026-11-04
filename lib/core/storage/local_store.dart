import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/storage/app_database.dart';

/// Everything the app persists, read once at launch and written through.
///
/// The data is tiny (a few settings, favourites, custom tunings), so loading
/// it up front lets controllers build synchronously, with no loading states
/// and no flash of defaults on startup. Writes go to SQLite in the
/// background; a failed write is logged and the in-memory value still holds
/// for this session.
final class LocalStore {
  LocalStore._(this._db, this._settings, this._favorites, this._tunings);

  /// Store with no database, for tests and previews.
  LocalStore.memory({
    Map<String, String>? settings,
    Set<String>? favorites,
    List<Tuning>? customTunings,
  }) : this._(null, {...?settings}, {...?favorites}, [...?customTunings]);

  static Future<LocalStore> open(AppDatabase db) async {
    final settings = await db.select(db.settings).get();
    final favorites = await (db.select(
      db.favoriteChords,
    )..orderBy([(f) => OrderingTerm.asc(f.addedAt)])).get();
    final tunings = await (db.select(
      db.customTunings,
    )..orderBy([(t) => OrderingTerm.asc(t.position)])).get();
    return LocalStore._(
      db,
      {for (final s in settings) s.key: s.value},
      {for (final f in favorites) f.symbol},
      [for (final t in tunings) ?_tuningFromRow(t)],
    );
  }

  final AppDatabase? _db;
  final Map<String, String> _settings;
  final Set<String> _favorites;
  final List<Tuning> _tunings;

  /// Completes when every write issued so far has finished (for tests).
  Future<void> get flushed => _writes;
  Future<void> _writes = Future.value();

  String? setting(String key) => _settings[key];

  void setSetting(String key, String? value) {
    if (value == null) {
      _settings.remove(key);
      _write((db) => (db.delete(db.settings)..where((s) => s.key.equals(key))).go());
    } else {
      _settings[key] = value;
      _write(
        (db) => db
            .into(db.settings)
            .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value)),
      );
    }
  }

  Set<String> get favorites => Set.unmodifiable(_favorites);

  void setFavorite(String symbol, {required bool favorite}) {
    if (favorite) {
      if (!_favorites.add(symbol)) return;
      _write(
        (db) => db
            .into(db.favoriteChords)
            .insertOnConflictUpdate(
              FavoriteChordsCompanion.insert(symbol: symbol, addedAt: DateTime.now()),
            ),
      );
    } else {
      if (!_favorites.remove(symbol)) return;
      _write((db) => (db.delete(db.favoriteChords)..where((f) => f.symbol.equals(symbol))).go());
    }
  }

  List<Tuning> get customTunings => List.unmodifiable(_tunings);

  /// Replaces the whole list, keeping its order.
  void setCustomTunings(List<Tuning> tunings) {
    _tunings
      ..clear()
      ..addAll(tunings);
    final rows = [
      for (final (i, t) in tunings.indexed)
        CustomTuningsCompanion.insert(
          id: t.id,
          name: t.name,
          notes: t.strings.map((n) => n.name()).join(' '),
          position: i,
        ),
    ];
    _write(
      (db) => db.transaction<void>(() async {
        await db.delete(db.customTunings).go();
        await db.batch((b) => b.insertAll(db.customTunings, rows));
      }),
    );
  }

  void _write(Future<Object?> Function(AppDatabase db) op) {
    final db = _db;
    if (db == null) return;
    // Chained so writes land in the order they were made.
    _writes = _writes
        .then((_) => op(db))
        .then<void>(
          (_) {},
          onError: (Object e, StackTrace st) => debugPrint('LocalStore write failed: $e\n$st'),
        );
  }

  static Tuning? _tuningFromRow(CustomTuning row) {
    final notes = row.notes.split(' ').map(Note.tryParse).toList();
    if (notes.length != 6 || notes.contains(null)) return null;
    return Tuning(id: row.id, name: row.name, strings: notes.cast<Note>(), isCustom: true);
  }
}

/// Opened in `main` and injected with an override; tests use
/// [LocalStore.memory].
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw UnimplementedError('localStoreProvider must be overridden'),
);
