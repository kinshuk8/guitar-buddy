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

Future<TestDevices> openChords(WidgetTester tester, {LocalStore? store}) async {
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final devices = TestDevices(store: store, library: library);
  await tester.pumpWidget(devices.app());
  await tester.pump();
  goTo(tester, '/tools/chords');
  await tester.pumpAndSettle();
  return devices;
}

void main() {
  testWidgets('drawing a chord: it names itself, saves, and shows under Your chords', (
    tester,
  ) async {
    final store = LocalStore.memory();
    await openChords(tester, store: store);
    await tester.tap(find.bySemanticsLabel('Draw your own chord'));
    await tester.pumpAndSettle();
    expect(find.text('New chord'), findsOneWidget);

    // All open to start: that's an Em11-ish cluster; draw a plain Em.
    await tester.tap(find.bySemanticsLabel('String 5, fret 2'));
    await tester.tap(find.bySemanticsLabel('String 4, fret 2'));
    await tester.pump();
    expect(find.textContaining('sounds like Em'), findsOneWidget);
    expect(find.text('Em'), findsWidgets, reason: 'the name field is filled in');

    // Mute the low E: still Em (now with the B in the bass).
    await tester.tap(find.bySemanticsLabel(RegExp('^String 6: open')));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.customChords.values.single.frets, [null, 2, 2, 0, 0, 0]);
    expect(find.text('YOUR CHORDS'), findsOneWidget);
  });

  testWidgets('a chord page offers practice: alone, or switching with another', (tester) async {
    await openChords(tester);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^C major, \d+ shapes$')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Practise'));
    await tester.pumpAndSettle();
    expect(find.text('Just C, 5 times'), findsOneWidget);
    expect(find.bySemanticsLabel('Switch between C and G'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Switch between C and G'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(find.text('C ⇄ G'), findsOneWidget);
    expect(find.textContaining('1 / 12'), findsOneWidget);
  });
}
