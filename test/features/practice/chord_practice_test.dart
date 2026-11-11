import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/app/shell.dart';
import 'package:fretlight/core/audio/synth/strum.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/storage/local_store.dart';
import 'package:fretlight/features/chords/domain/chord_library.dart';
import 'package:fretlight/features/learn/application/progress_controller.dart';
import 'package:fretlight/features/learn/domain/progress.dart';

import '../../support/fake_audio_input.dart';
import '../../support/test_app.dart';

final library = ChordLibrary.fromJson(
  (jsonDecode(File('assets/chords/guitar.json').readAsStringSync()) as Map).cast<String, Object?>(),
);
const pm = PitchMath();

Float32List strumOf(String symbol) {
  final v = library.bySymbol(symbol)!.voicings.first;
  return renderStrum(
    stringHz: [
      for (var s = 0; s < 6; s++)
        if (v.frets[s] case final int f) pm.hz(Tuning.standard.noteAt(s, f)) else null,
    ],
    sampleRate: 48000,
    seconds: 1.6,
  );
}

Future<TestDevices> launch(WidgetTester tester, {LocalStore? store}) async {
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final devices = TestDevices(library: library, store: store);
  await tester.pumpWidget(devices.app());
  await tester.pumpAndSettle();
  return devices;
}

Finder tab(String label) =>
    find.descendant(of: find.byType(StageNavBar), matching: find.bySemanticsLabel(label));

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

/// Real time for the mic queue and the DSP isolate, interleaved with pumps.
Future<void> settle(WidgetTester tester, {int ms = 400}) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms ~/ 4)));
    await tester.pump();
  }
}

Future<void> play(WidgetTester tester, FakeAudioInputSource mic, String chord) async {
  await tester.runAsync(() async {
    mic
      ..feed(Float32List(48000 ~/ 2))
      ..feed(strumOf(chord));
    await Future<void>.delayed(const Duration(milliseconds: 1400));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Progress progressOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Navigator).first)).read(progressProvider);

/// Starts the lesson-style drill on screen and lets the mic open.
Future<void> start(WidgetTester tester) async {
  await tester.tap(find.text('Start'));
  await tester.pump();
  await tester.pump();
  await settle(tester);
}

void main() {
  testWidgets('drilling a chord: two taps from launch, builds mastery, adds no stars', (
    tester,
  ) async {
    final devices = await launch(tester);
    await tap(tester, tab('Practice'));
    expect(find.text('Drill a chord'.toUpperCase()), findsOneWidget);
    // A new player's first chords, weakest first.
    await tap(tester, find.bySemanticsLabel(RegExp('^E minor, 0 percent')));
    expect(find.text('Em drill'), findsWidgets);
    await start(tester);
    for (var i = 0; i < 5; i++) {
      await play(tester, devices.mic, 'Em');
    }
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget, reason: 'a drill finishes with Done, not Next');
    final p = progressOf(tester);
    expect(p.mastery('Em'), greaterThan(30));
    expect(p.totalStars, 0, reason: 'drills earn mastery and time, not stars');
    expect(devices.store.lessons, isEmpty);
    expect(p.xp, greaterThan(0));
    await tap(tester, find.text('Done'));
    // Back on Practice, the ring shows it.
    expect(find.bySemanticsLabel(RegExp(r'^E minor, [1-9]\d* percent')), findsOneWidget);
  });

  testWidgets('every taught chord is on the Chords screen, by stage', (tester) async {
    await launch(tester);
    goTo(tester, '/practice/chords');
    await tester.pumpAndSettle();
    for (final stage in ['Beginner', 'Improver', 'Adept', 'Mastery']) {
      await tester.scrollUntilVisible(find.text(stage.toUpperCase()), 300);
      expect(find.text(stage.toUpperCase()), findsOneWidget, reason: stage);
    }
    await tester.scrollUntilVisible(find.bySemanticsLabel(RegExp('^B minor, ')), 300);
    await tap(tester, find.bySemanticsLabel(RegExp('^B minor, ')));
    expect(find.text('Bm drill'), findsWidgets);
  });

  testWidgets('changes: pick two chords, switch between them, and it counts', (tester) async {
    final devices = await launch(tester);
    await tap(tester, tab('Practice'));
    await tap(tester, find.bySemanticsLabel(RegExp(r'^Changes\.')));
    expect(find.text('No race between these yet.'), findsOneWidget);
    expect(find.textContaining('Race a pair to set your first best'), findsOneWidget);

    // The same chord twice can't be practised.
    final firstRow = find.byType(SingleChildScrollView).at(0);
    await tap(tester, find.descendant(of: firstRow, matching: find.bySemanticsLabel('Am')));
    expect(find.text('Pick two different chords.'), findsOneWidget);
    await tap(tester, find.descendant(of: firstRow, matching: find.bySemanticsLabel('Em')));

    await tap(tester, find.text('Switch between them'));
    expect(find.text('Em to Am'), findsWidgets);
    await start(tester);
    for (var i = 0; i < 4; i++) {
      await play(tester, devices.mic, 'Em');
      await play(tester, devices.mic, 'Am');
    }
    await tester.pumpAndSettle();
    final p = progressOf(tester);
    expect(p.mastery('Em'), greaterThan(0));
    expect(p.mastery('Am'), greaterThan(0));
    expect(p.totalStars, 0);
  });

  testWidgets('a race opens from Changes and shows your best for that pair', (tester) async {
    final store = LocalStore.memory(skills: {'race:Am|Em': 22, 'chord:Em': 50, 'chord:Am': 30});
    await launch(tester, store: store);
    goTo(tester, '/practice/changes');
    await tester.pumpAndSettle();
    expect(find.text('Em ↔ Am'), findsNothing);
    expect(find.text('Am ↔ Em'), findsOneWidget);
    await tap(tester, find.bySemanticsLabel(RegExp('^Am and Em: 22 a minute')));
    expect(find.text('Your best: 22 changes a minute.'), findsOneWidget);
    await tap(tester, find.text('One-minute race'));
    expect(find.textContaining('race'), findsWidgets);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('free practice (a progression) counts toward today and XP', (tester) async {
    final devices = await launch(tester);
    goTo(tester, '/practice/progressions');
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp(r'^E minor, C major, G major, D major\. In ')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Practise'));
    await tester.pump();
    await settle(tester);
    // Play the first chord, skip the rest.
    await play(tester, devices.mic, 'Em');
    for (var i = 0; i < 15; i++) {
      await tester.tap(find.text('Skip'));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.pump();
    final p = progressOf(tester);
    // Every chord in the run is tracked; Em came round four times, played
    // once and skipped three times, so skips outweigh it.
    expect(p.skills.keys, containsAll(['chord:Em', 'chord:C', 'chord:G', 'chord:D']));
    expect(p.xp, 6, reason: '5 for the run, 1 for the one clean chord');
    final today = devices.store.days.values.single;
    expect(today.seconds, greaterThan(0), reason: 'time spent listening is saved');
  });
}
