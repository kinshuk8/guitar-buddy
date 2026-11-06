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

  test('custom chords: saved, replaced, deleted, and a bad row is skipped', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = await LocalStore.open(db)
      ..putCustomChord('a', const CustomChordData(name: 'Gadd9', frets: [3, 2, 0, 2, 0, 3]))
      ..putCustomChord('b', const CustomChordData(name: 'X', frets: [null, 0, 2, 2, 2, 0]))
      ..deleteCustomChord('b');
    await store.flushed;
    await db
        .into(db.customChords)
        .insert(
          CustomChordsCompanion.insert(
            id: 'bad',
            name: 'Bad',
            frets: '1,2',
            addedAt: DateTime(2026),
          ),
        );
    final again = await LocalStore.open(db);
    expect(again.customChords.keys, ['a']);
    expect(again.customChords['a']!.frets, [3, 2, 0, 2, 0, 3]);
    expect(again.customChords['a']!.fretsText, '3,2,0,2,0,3');
  });

  test('upgrading a version-2 database adds custom chords and keeps songs', () async {
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
          ..execute(
            'CREATE TABLE user_songs (id TEXT NOT NULL PRIMARY KEY, source TEXT NOT NULL, added_at INTEGER NOT NULL)',
          )
          ..execute("INSERT INTO user_songs VALUES ('s1', '{title: Kept}', 0)")
          ..execute('PRAGMA user_version = 2'),
      ),
    );
    addTearDown(db.close);
    final store = await LocalStore.open(db);
    expect(store.userSongs, {'s1': '{title: Kept}'});
    store.putCustomChord('c', const CustomChordData(name: 'Em7', frets: [0, 2, 0, 0, 0, 0]));
    await store.flushed;
    expect((await LocalStore.open(db)).customChords.keys, ['c']);
  });

  test('learning progress survives a reopen and can be reset', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = await LocalStore.open(db)
      ..putLesson(
        'b.em',
        StoredLesson(stars: 2, bestScore: 0.8, attempts: 3, lastPlayed: DateTime(2026, 11, 6)),
      )
      ..putDay('2026-11-06', const StoredDay(seconds: 420, xp: 60))
      ..putSkill('chord:Em', 42.5)
      ..putSkill('chord:Em', 50);
    await store.flushed;
    final again = await LocalStore.open(db);
    expect(again.lessons['b.em']!.stars, 2);
    expect(again.lessons['b.em']!.attempts, 3);
    expect(again.days['2026-11-06']!.xp, 60);
    expect(again.skills, {'chord:Em': 50});

    again
      ..setSetting('tuner.a4', '440.0')
      ..clearLearning();
    await again.flushed;
    final cleared = await LocalStore.open(db);
    expect(cleared.lessons, isEmpty);
    expect(cleared.days, isEmpty);
    expect(cleared.skills, isEmpty);
    expect(cleared.setting('tuner.a4'), '440.0', reason: 'only learning is reset');
  });

  test('upgrading a version-3 database adds learning progress and keeps chords', () async {
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
          ..execute(
            'CREATE TABLE user_songs (id TEXT NOT NULL PRIMARY KEY, source TEXT NOT NULL, added_at INTEGER NOT NULL)',
          )
          ..execute(
            'CREATE TABLE custom_chords (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, '
            'frets TEXT NOT NULL, added_at INTEGER NOT NULL)',
          )
          ..execute("INSERT INTO custom_chords VALUES ('c1', 'Gadd9', '3,2,0,2,0,3', 0)")
          ..execute('PRAGMA user_version = 3'),
      ),
    );
    addTearDown(db.close);
    final store = await LocalStore.open(db);
    expect(store.customChords.keys, ['c1']);
    store.putDay('2026-11-06', const StoredDay(seconds: 60, xp: 20));
    await store.flushed;
    expect((await LocalStore.open(db)).days.keys, ['2026-11-06']);
  });
}
