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
  LocalStore._(
    this._db,
    this._settings,
    this._favorites,
    this._tunings,
    this._songs,
    this._chords, {
    Map<String, StoredLesson>? lessons,
    Map<String, StoredDay>? days,
    Map<String, double>? skills,
  }) : _lessons = lessons ?? {},
       _days = days ?? {},
       _skills = skills ?? {};

  /// Store with no database, for tests and previews.
  LocalStore.memory({
    Map<String, String>? settings,
    Set<String>? favorites,
    List<Tuning>? customTunings,
    Map<String, String>? userSongs,
    Map<String, CustomChordData>? customChords,
    Map<String, StoredLesson>? lessons,
    Map<String, StoredDay>? days,
    Map<String, double>? skills,
  }) : this._(
         null,
         {...?settings},
         {...?favorites},
         [...?customTunings],
         {...?userSongs},
         {...?customChords},
         lessons: {...?lessons},
         days: {...?days},
         skills: {...?skills},
       );

  static Future<LocalStore> open(AppDatabase db) async {
    final settings = await db.select(db.settings).get();
    final favorites = await (db.select(
      db.favoriteChords,
    )..orderBy([(f) => OrderingTerm.asc(f.addedAt)])).get();
    final tunings = await (db.select(
      db.customTunings,
    )..orderBy([(t) => OrderingTerm.asc(t.position)])).get();
    final songs = await (db.select(
      db.userSongs,
    )..orderBy([(s) => OrderingTerm.asc(s.addedAt)])).get();
    final chords = await (db.select(
      db.customChords,
    )..orderBy([(c) => OrderingTerm.asc(c.addedAt)])).get();
    final lessons = await db.select(db.lessonRecords).get();
    final days = await db.select(db.practiceDays).get();
    final skills = await db.select(db.skillRecords).get();
    return LocalStore._(
      db,
      {for (final s in settings) s.key: s.value},
      {for (final f in favorites) f.symbol},
      [for (final t in tunings) ?_tuningFromRow(t)],
      {for (final s in songs) s.id: s.source},
      {for (final c in chords) c.id: ?CustomChordData.tryParse(c.name, c.frets)},
      lessons: {
        for (final l in lessons)
          l.lessonId: StoredLesson(
            stars: l.stars,
            bestScore: l.bestScore,
            attempts: l.attempts,
            lastPlayed: l.lastPlayed,
          ),
      },
      days: {for (final d in days) d.day: StoredDay(seconds: d.seconds, xp: d.xp)},
      skills: {for (final k in skills) k.key: k.value},
    );
  }

  final AppDatabase? _db;
  final Map<String, String> _settings;
  final Set<String> _favorites;
  final List<Tuning> _tunings;

  /// User songs: id → ChordPro source, oldest first.
  final Map<String, String> _songs;

  /// User chord shapes, oldest first.
  final Map<String, CustomChordData> _chords;

  final Map<String, StoredLesson> _lessons;
  final Map<String, StoredDay> _days;
  final Map<String, double> _skills;

  Map<String, StoredLesson> get lessons => Map.unmodifiable(_lessons);
  Map<String, StoredDay> get days => Map.unmodifiable(_days);
  Map<String, double> get skills => Map.unmodifiable(_skills);

  void putLesson(String id, StoredLesson r) {
    _lessons[id] = r;
    _write(
      (db) => db
          .into(db.lessonRecords)
          .insertOnConflictUpdate(
            LessonRecordsCompanion.insert(
              lessonId: id,
              stars: r.stars,
              bestScore: r.bestScore,
              attempts: r.attempts,
              lastPlayed: r.lastPlayed,
            ),
          ),
    );
  }

  void putDay(String day, StoredDay d) {
    _days[day] = d;
    _write(
      (db) => db
          .into(db.practiceDays)
          .insertOnConflictUpdate(
            PracticeDaysCompanion.insert(day: day, seconds: d.seconds, xp: d.xp),
          ),
    );
  }

  void putSkill(String key, double value) {
    _skills[key] = value;
    _write(
      (db) => db
          .into(db.skillRecords)
          .insertOnConflictUpdate(
            SkillRecordsCompanion.insert(key: key, value: value, updatedAt: DateTime.now()),
          ),
    );
  }

  /// Forgets all Learn progress (Settings → Reset progress).
  void clearLearning() {
    _lessons.clear();
    _days.clear();
    _skills.clear();
    _write(
      (db) => db.transaction<void>(() async {
        await db.delete(db.lessonRecords).go();
        await db.delete(db.practiceDays).go();
        await db.delete(db.skillRecords).go();
      }),
    );
  }

  Map<String, CustomChordData> get customChords => Map.unmodifiable(_chords);

  void putCustomChord(String id, CustomChordData chord) {
    _chords[id] = chord;
    _write(
      (db) => db
          .into(db.customChords)
          .insertOnConflictUpdate(
            CustomChordsCompanion.insert(
              id: id,
              name: chord.name,
              frets: chord.fretsText,
              addedAt: DateTime.now(),
            ),
          ),
    );
  }

  void deleteCustomChord(String id) {
    if (_chords.remove(id) == null) return;
    _write((db) => (db.delete(db.customChords)..where((c) => c.id.equals(id))).go());
  }

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

  Map<String, String> get userSongs => Map.unmodifiable(_songs);

  void putUserSong(String id, String source) {
    _songs[id] = source;
    _write(
      (db) => db
          .into(db.userSongs)
          .insertOnConflictUpdate(
            UserSongsCompanion.insert(id: id, source: source, addedAt: DateTime.now()),
          ),
    );
  }

  void deleteUserSong(String id) {
    if (_songs.remove(id) == null) return;
    _write((db) => (db.delete(db.userSongs)..where((s) => s.id.equals(id))).go());
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

/// A Learn lesson's best result, as stored.
@immutable
final class StoredLesson {
  const StoredLesson({
    required this.stars,
    required this.bestScore,
    required this.attempts,
    required this.lastPlayed,
  });

  final int stars;
  final double bestScore;
  final int attempts;
  final DateTime lastPlayed;
}

/// One day's practice, as stored.
@immutable
final class StoredDay {
  const StoredDay({required this.seconds, required this.xp});

  final int seconds;
  final int xp;
}

/// A chord shape the user drew.
@immutable
final class CustomChordData {
  const CustomChordData({required this.name, required this.frets});

  /// What the user called it (normally a chord symbol like `Gadd9`).
  final String name;

  /// Lowest string first; null = muted.
  final List<int?> frets;

  String get fretsText => frets.map((f) => f?.toString() ?? 'x').join(',');

  static CustomChordData? tryParse(String name, String frets) {
    final parts = frets.split(',');
    if (parts.length != 6) return null;
    final parsed = <int?>[];
    for (final p in parts) {
      if (p == 'x') {
        parsed.add(null);
      } else {
        final f = int.tryParse(p);
        if (f == null || f < 0 || f > 24) return null;
        parsed.add(f);
      }
    }
    return CustomChordData(name: name, frets: parsed);
  }
}
