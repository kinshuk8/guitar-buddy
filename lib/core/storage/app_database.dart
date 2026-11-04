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

@DriftDatabase(tables: [Settings, FavoriteChords, CustomTunings])
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

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) => m.createAll());
}
