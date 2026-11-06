import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Small key/value settings (reference pitch, theme, last tuning…).
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Chords starred in the library, by their library symbol (`C#m7`).
class FavoriteChords extends Table {
  TextColumn get symbol => text()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {symbol};
}

/// User-made tunings. [notes] is space-separated, lowest string first
/// (`D2 A2 D3 G3 A3 D4`).
class CustomTunings extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get notes => text()();
  IntColumn get position => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Songs the user pasted or imported, stored as their ChordPro source (the
/// bundled starter songs are assets, not rows).
class UserSongs extends Table {
  TextColumn get id => text()();
  TextColumn get source => text()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Chord shapes the user drew. [frets] is comma-separated, lowest string
/// first, `x` for muted (`x,3,2,0,1,0`).
class CustomChords extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get frets => text()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The best result in each Learn lesson.
class LessonRecords extends Table {
  TextColumn get lessonId => text()();
  IntColumn get stars => integer()();
  RealColumn get bestScore => real()();
  IntColumn get attempts => integer()();
  DateTimeColumn get lastPlayed => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {lessonId};
}

/// Practice per calendar day (`yyyy-mm-dd`, local time): for streaks, the
/// daily goal and XP.
class PracticeDays extends Table {
  TextColumn get day => text()();
  IntColumn get seconds => integer()();
  IntColumn get xp => integer()();

  @override
  Set<Column<Object>> get primaryKey => {day};
}

/// Named numbers the Learn tab tracks: chord mastery (`chord:G`), personal
/// bests (`race:C|G`).
class SkillRecords extends Table {
  TextColumn get key => text()();
  RealColumn get value => real()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    Settings,
    FavoriteChords,
    CustomTunings,
    UserSongs,
    CustomChords,
    LessonRecords,
    PracticeDays,
    SkillRecords,
  ],
)
final class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// The on-device database. Lives in Application Support, not Documents:
  /// it's app state, not a file the user should see in the Files app.
  factory AppDatabase.device() => AppDatabase(
    driftDatabase(
      name: 'fretlight',
      native: const DriftNativeOptions(databaseDirectory: getApplicationSupportDirectory),
    ),
  );

  /// 1: settings, favourites, custom tunings (M3). 2: user songs (M6).
  /// 3: custom chords. 4: Learn progress (lessons, days, skills).
  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.createTable(userSongs);
      if (from < 3) await m.createTable(customChords);
      if (from < 4) {
        await m.createTable(lessonRecords);
        await m.createTable(practiceDays);
        await m.createTable(skillRecords);
      }
    },
  );
}
