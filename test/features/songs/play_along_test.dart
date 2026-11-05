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
    // Without the guitar part the song runs on its own clock.
    await tester.tap(find.bySemanticsLabel('Mute the guitar part'));
    await tester.pump();

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

  testWidgets('play schedules the guitar part; the chord shown follows the audio clock', (
    tester,
  ) async {
    final devices = await openSongs(tester);
    await openAmazingGrace(tester);
    final speaker = devices.speaker;
    final clock0 = speaker.now;

    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.pump();
    // Rendering happens in an isolate: real time, interleaved with pumps.
    for (var i = 0; i < 10 && speaker.loops.isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump();
    }
    expect(speaker.loops, hasLength(1));
    final part = speaker.loops.single;
    expect(part.looping, isFalse);
    expect(part.start, clock0 + const Duration(milliseconds: 80));
    // 80 BPM, 3/4, 16 bars per verse × 2 = 96 beats = 72 s, plus a 1.5 s tail.
    expect(part.audio.samples.length / 48000, closeTo(72 + 1.5, 0.1));

    // Five seconds of audio later (G, G, then G7 from 4.5 s): G7 is now.
    speaker.now = part.start + const Duration(seconds: 5);
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.bySemanticsLabel(RegExp('^G dominant 7th')), findsOneWidget);

    // Muting stops the part but keeps the song going.
    await tester.tap(find.bySemanticsLabel('Mute the guitar part'));
    await tester.pump();
    expect(part.stop, isNotNull);
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Pause'));
    await tester.pump();
  });

  testWidgets('the tempo slider in the dock sets the tempo and remembers it', (tester) async {
    final store = LocalStore.memory();
    await openSongs(tester, store: store);
    await openAmazingGrace(tester);
    expect(find.text('80 BPM'), findsOneWidget, reason: 'tempo shown beside its slider');
    // Drag the tempo slider right.
    await tester.drag(find.byType(Slider).last, const Offset(60, 0));
    await tester.pumpAndSettle();
    final saved = store.setting('song.amazing_grace')!.split(',').last;
    expect(int.parse(saved), greaterThan(80));
    expect(find.textContaining('$saved BPM'), findsWidgets);
  });

  testWidgets('writing a song with the editor buttons: section, chords, words', (tester) async {
    final store = LocalStore.memory();
    await openSongs(tester, store: store);
    await tester.tap(find.bySemanticsLabel('Add a song'));
    await tester.pumpAndSettle();
    await tester.showKeyboard(find.byType(TextField));
    await tester.tap(find.bySemanticsLabel('Insert Verse'));
    await tester.pump();
    await tester.ensureVisible(find.bySemanticsLabel('Insert chord G'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Insert chord G'));
    await tester.pump();
    final text = tester.widget<TextField>(find.byType(TextField)).controller!.text;
    expect(text, '{start_of_verse}\n[G]\n{end_of_verse}', reason: 'chord dropped inside the verse');
    expect(find.textContaining('1 chords'), findsOneWidget);
  });
}
