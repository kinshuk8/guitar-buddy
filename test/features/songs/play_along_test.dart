import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/storage/local_store.dart';
import 'package:fretlight/features/chords/domain/chord_library.dart';

import '../../support/test_app.dart';

final library = ChordLibrary.fromJson(
  (jsonDecode(File('assets/chords/guitar.json').readAsStringSync()) as Map).cast<String, Object?>(),
);

Future<TestDevices> openSongs(WidgetTester tester, {LocalStore? store}) async {
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final devices = TestDevices(store: store, library: library);
  await tester.pumpWidget(devices.app());
  await tester.pump();
  await tester.tap(find.bySemanticsLabel('Songs'));
  await tester.pumpAndSettle();
  return devices;
}

Future<void> openAmazingGrace(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel(RegExp('^Amazing Grace, ')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists the starter songs; a song opens with key, tempo and chords', (tester) async {
    await openSongs(tester);
    expect(find.text('Starter songs'.toUpperCase()), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Amazing Grace, John Newton')), findsOneWidget);

    await openAmazingGrace(tester);
    expect(find.text('Amazing Grace'), findsOneWidget);
    expect(find.text('Key G · 80 BPM'), findsOneWidget);
    expect(find.text('NOW'), findsOneWidget);
    expect(find.text('NEXT'), findsOneWidget);
    // Chords sit above their syllables, spoken as one line.
    expect(
      find.bySemanticsLabel('Amazing grace, how sweet the sound. Chords: G, G, G7, C'),
      findsOneWidget,
    );
  });

  testWidgets('playing moves through the chords at the song tempo', (tester) async {
    await openSongs(tester);
    await openAmazingGrace(tester);
    expect(find.bySemanticsLabel(RegExp('^G major')), findsWidgets);

    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.pump();
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
    // 80 BPM in 3/4: a bar is 2.25 s. G, G, then G7 from 4.5 s.
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.bySemanticsLabel(RegExp('^G dominant 7th')),
      findsOneWidget,
      reason: 'now playing G7',
    );
    expect(find.bySemanticsLabel(RegExp('^C major')), findsWidgets, reason: 'C is next');

    await tester.tap(find.bySemanticsLabel('Pause'));
    await tester.pump();
    expect(find.bySemanticsLabel('Play'), findsOneWidget);
  });

  testWidgets('a section can be looped; tapping a line jumps to it', (tester) async {
    await openSongs(tester);
    await openAmazingGrace(tester);
    final verse2 = find.bySemanticsLabel(RegExp('^Verse 2. Tap to loop'));
    // Bring it clear of the floating dock before tapping.
    await tester.runAsync(() => Scrollable.ensureVisible(tester.element(verse2)));
    await tester.pumpAndSettle();
    await tester.tap(verse2);
    await tester.pumpAndSettle();
    expect(find.text('Looping Verse 2'), findsOneWidget);
    await tester.tap(find.text('Looping Verse 2'));
    await tester.pumpAndSettle();
    expect(find.text('Looping Verse 2'), findsNothing);
  });

  testWidgets('capo and transpose change the shapes shown, and are remembered', (tester) async {
    final store = LocalStore.memory();
    await openSongs(tester, store: store);
    await openAmazingGrace(tester);
    await tester.tap(find.bySemanticsLabel('Key, capo and tempo'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('More Capo'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('More Transpose'));
    await tester.tap(find.bySemanticsLabel('More Transpose'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(200, 100)); // close the sheet
    await tester.pumpAndSettle();
    // Sounding key A (G + 2); with a capo on 1 the shapes are G# shapes.
    expect(find.text('Key A · Capo 1 · 80 BPM'), findsOneWidget);
    expect(store.setting('song.amazing_grace'), '2,1,');
  });

  testWidgets('pasting ChordPro adds a song and opens it', (tester) async {
    final store = LocalStore.memory();
    await openSongs(tester, store: store);
    await tester.tap(find.bySemanticsLabel('Add a song'));
    await tester.pumpAndSettle();
    expect(find.text('Save and open'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '{title: My Tune}\n{key: C}\n[C]Hello [G]there');
    await tester.pumpAndSettle();
    expect(find.text('My Tune · 2 chords'), findsOneWidget);
    await tester.tap(find.text('Save and open'));
    await tester.pumpAndSettle();
    expect(find.text('My Tune'), findsOneWidget);
    expect(store.userSongs.values.single, contains('[C]Hello'));
  });
}
