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
}
