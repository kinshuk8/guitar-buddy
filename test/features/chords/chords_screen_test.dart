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

Future<TestDevices> openChords(
  WidgetTester tester, {
  LocalStore? store,
  bool realAsset = false,
}) async {
  tester.view.physicalSize = const Size(1179, 2556); // iPhone 15 at 3x
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final devices = TestDevices(store: store, library: realAsset ? null : library);
  await tester.pumpWidget(devices.app());
  await tester.pump();
  goTo(tester, '/tools/chords');
  await tester.pump();
  // Asset read + background-isolate parse: real time, interleaved with pumps
  // so each step's completion is delivered.
  for (var i = 0; i < 40 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
  return devices;
}

/// Scrolls [finder] to mid-screen (clear of the floating tab bar), then taps.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() => Scrollable.ensureVisible(tester.element(finder), alignment: 0.4));
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The library's vertical list (the root picker scrolls too, sideways).
Finder get chordList =>
    find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first;

Future<void> settleAudio(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens on C with only the everyday chords expanded', (tester) async {
    // The one test that loads the real asset through the app's own path.
    await openChords(tester, realAsset: true);
    expect(find.text('Chord library'), findsWidgets);
    for (final name in ['C major', 'C minor', 'C dominant 7th', 'C major 7th']) {
      // The header now has a row of labelled actions: later groups start
      // below the fold.
      await tester.scrollUntilVisible(
        find.bySemanticsLabel(RegExp('^$name, \\d+ shapes?\$')),
        200,
        scrollable: chordList,
      );
      expect(find.bySemanticsLabel(RegExp('^$name, \\d+ shapes?\$')), findsOneWidget, reason: name);
    }
    // Other groups are there, folded.
    await tester.scrollUntilVisible(
      find.bySemanticsLabel(RegExp(r'^Colour, \d+ chords$')),
      200,
      scrollable: chordList,
    );
    expect(find.bySemanticsLabel(RegExp(r'^Colour, \d+ chords$')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^C add 9, ')), findsNothing);
    await tapVisible(tester, find.bySemanticsLabel(RegExp(r'^Colour, \d+ chords$')));
    await tester.scrollUntilVisible(
      find.bySemanticsLabel(RegExp('^C add 9, ')),
      200,
      scrollable: chordList,
    );
    expect(find.bySemanticsLabel(RegExp('^C add 9, ')), findsOneWidget);
  });

  testWidgets('choosing a root, opening a chord, playing it and stepping shapes', (tester) async {
    final devices = await openChords(tester);
    // A is past the edge of the root row: swipe it into view.
    await tester.drag(find.bySemanticsLabel('Root C'), const Offset(-400, 0));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.bySemanticsLabel('Root A'));
    await tapVisible(tester, find.bySemanticsLabel(RegExp(r'^A minor, \d+ shapes$')));

    expect(find.text('A minor'), findsOneWidget);
    // One shape to start with; the rest are under Advanced.
    expect(find.textContaining('Shape 1 of'), findsNothing);
    await tapVisible(tester, find.bySemanticsLabel(RegExp('^Advanced')));
    expect(find.textContaining('Shape 1 of'), findsOneWidget);

    await tester.tap(find.text('Play'));
    await settleAudio(tester);
    expect(devices.speaker.played, ['strum:standard:null,0,2,2,1,0']);
    final pcm = devices.speaker.rendered.values.single;
    expect(pcm.sampleRate, 48000);
    expect(pcm.samples.length, greaterThan(48000 * 2));

    await tapVisible(tester, find.bySemanticsLabel('Next shape'));
    expect(find.textContaining('Shape 2 of'), findsOneWidget);
    await tester.tap(find.text('Play'));
    await settleAudio(tester);
    expect(devices.speaker.played, hasLength(2));
    expect(devices.speaker.played.last, isNot(devices.speaker.played.first));
  });

  testWidgets('favourites are saved and filter the library', (tester) async {
    final store = LocalStore.memory();
    await openChords(tester, store: store);
    await tapVisible(tester, find.bySemanticsLabel(RegExp(r'^C major 7th, \d+ shapes$')));
    await tapVisible(tester, find.bySemanticsLabel('Add to favourites'));
    await tester.pump();
    expect(store.favorites, {'Cmaj7'});
    expect(find.bySemanticsLabel('Remove from favourites'), findsOneWidget);

    await tapVisible(tester, find.bySemanticsLabel('Back'));
    // Back at the list, still scrolled down: return to the top for the header.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.bySemanticsLabel('Favourites only'));
    expect(find.bySemanticsLabel(RegExp('^C major 7th, ')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^C major, ')), findsNothing);
  });

  testWidgets('search finds slash chords and says so when nothing matches', (tester) async {
    await openChords(tester);
    await tester.enterText(find.byType(EditableText), 'g/b');
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('^G major over B, ')), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'Xyz');
    await tester.pumpAndSettle();
    expect(find.text('No chord matches “Xyz”.'), findsOneWidget);
  });

  testWidgets('the last browsed root is remembered', (tester) async {
    final store = LocalStore.memory();
    await openChords(tester, store: store);
    await tapVisible(tester, find.bySemanticsLabel('Root E'));
    expect(store.setting('chords.root'), '4');
  });
}
