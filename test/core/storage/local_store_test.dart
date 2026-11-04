import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/storage/app_database.dart';
import 'package:fretlight/core/storage/local_store.dart';

void main() {
  test('settings, favourites and custom tunings survive a reopen', () async {
    // One in-memory SQLite database shared by two stores = an app restart.
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final first = await LocalStore.open(db);
    expect(first.setting('tuner.a4'), isNull);
    first
      ..setSetting('tuner.a4', '432.0')
      ..setSetting('appearance.theme', 'dark')
      ..setSetting('appearance.theme', 'light')
      ..setFavorite('Am7', favorite: true)
      ..setFavorite('C', favorite: true)
      ..setFavorite('C', favorite: false)
      ..setCustomTunings([
        Tuning.fromNames('custom_1', 'Open D', const [
          'D2',
          'A2',
          'D3',
          'F#3',
          'A3',
          'D4',
        ], isCustom: true),
      ]);
    await first.flushed;

    final second = await LocalStore.open(db);
    expect(second.setting('tuner.a4'), '432.0');
    expect(second.setting('appearance.theme'), 'light');
    expect(second.favorites, {'Am7'});
    final t = second.customTunings.single;
    expect((t.id, t.name, t.isCustom), ('custom_1', 'Open D', true));
    expect(t.strings.map((n) => n.name()).join(' '), 'D2 A2 D3 F#3 A3 D4');

    second.setSetting('tuner.a4', null);
    await second.flushed;
    expect((await LocalStore.open(db)).setting('tuner.a4'), isNull);
  });

  test('a corrupt tuning row is skipped, not fatal', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.customTunings)
        .insert(CustomTuningsCompanion.insert(id: 'x', name: 'Bad', notes: 'E2 nope', position: 0));
    expect((await LocalStore.open(db)).customTunings, isEmpty);
  });

  test('upgrading a version-1 database keeps its data and adds user songs', () async {
    // The schema as shipped in M3-M5, with a saved setting.
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) => raw
          ..execute('CREATE TABLE settings (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)')
          ..execute(
            'CREATE TABLE favorite_chords (symbol TEXT NOT NULL PRIMARY KEY, added_at INTEGER NOT NULL)',
          )
          ..execute(
            'CREATE TABLE custom_tunings (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, '
            'notes TEXT NOT NULL, position INTEGER NOT NULL)',
          )
          ..execute("INSERT INTO settings VALUES ('tuner.a4', '432.0')")
          ..execute('PRAGMA user_version = 1'),
      ),
    );
    addTearDown(db.close);
    final store = await LocalStore.open(db);
    expect(store.setting('tuner.a4'), '432.0', reason: 'old data survives');
    store.putUserSong('u1', '{title: Mine}');
    await store.flushed;
    expect((await LocalStore.open(db)).userSongs, {'u1': '{title: Mine}'});
  });

  test('user songs: add, replace, delete', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = await LocalStore.open(db)
      ..putUserSong('a', 'one')
      ..putUserSong('b', 'two')
      ..putUserSong('a', 'one, edited')
      ..deleteUserSong('b');
    await store.flushed;
    expect((await LocalStore.open(db)).userSongs, {'a': 'one, edited'});
  });
}
