import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/audio/synth/karplus_strong.dart';
import 'package:fretlight/core/audio/synth/strum.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/storage/local_store.dart';
import 'package:fretlight/features/chords/domain/chord_library.dart';
import 'package:fretlight/features/learn/application/lesson_controller.dart';
import 'package:fretlight/features/learn/application/progress_controller.dart';
import 'package:fretlight/features/learn/domain/games.dart';
import 'package:fretlight/features/learn/presentation/learn_screen.dart';

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

Future<TestDevices> openApp(WidgetTester tester, {LocalStore? store}) async {
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final devices = TestDevices(library: library, store: store);
  await tester.pumpWidget(devices.app());
  await tester.pumpAndSettle();
  return devices;
}

/// Real time for the mic queue and the DSP isolate, interleaved with pumps.
Future<void> settle(WidgetTester tester, {int ms = 400}) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms ~/ 4)));
    await tester.pump();
  }
}

Future<void> play(
  WidgetTester tester,
  FakeAudioInputSource mic,
  Float32List sound, {
  int waitMs = 1400,
}) async {
  await tester.runAsync(() async {
    mic
      ..feed(Float32List(48000 ~/ 2))
      ..feed(sound);
    await Future<void>.delayed(Duration(milliseconds: waitMs));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

LessonState lessonState(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first)).read(lessonProvider);

void main() {
  testWidgets('a fresh start: level 1, the first lesson up next, later ones locked', (
    tester,
  ) async {
    await openApp(tester);
    expect(find.text('Learn'), findsWidgets);
    expect(find.text('Beginner'), findsWidgets);
    expect(find.textContaining('Level 1 · 0 XP'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Up next: The six strings')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('E minor'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final tile = find.ancestor(of: find.text('E minor'), matching: find.byType(InkWell));
    expect(
      find.descendant(of: tile, matching: find.byIcon(Icons.lock_outline_rounded)),
      findsOneWidget,
    );
  });

  testWidgets('the first lesson: name the strings, then play each one; stars and XP are saved', (
    tester,
  ) async {
    final store = LocalStore.memory();
    final devices = await openApp(tester, store: store);
    await tester.tap(find.bySemanticsLabel(RegExp('^Up next: The six strings')));
    await tester.pumpAndSettle();
    expect(find.text('The six strings'), findsWidgets);
    expect(find.textContaining('Eddie Ate Dynamite'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Part 1 of 2'), findsOneWidget);
    expect(find.text('Which string is this?'), findsOneWidget);

    // Answer every question right.
    for (var i = 0; i < 20; i++) {
      final q = lessonState(tester).game;
      if (q is! QuizGame || q.done) break;
      await tester.tap(find.text(q.current!.options[q.current!.answer]).last);
      await tester.pump();
    }
    expect(find.text('8 of 8 right'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump();
    await settle(tester);

    // Now play the six open strings into the microphone.
    expect(devices.mic.isCapturing, isTrue);
    for (final note in ['E2', 'A2', 'D3', 'G3', 'B3', 'E4']) {
      final pluck = KarplusStrong(sampleRate: 48000)
          .pluck(hz: pm.hz(Note.parse(note)), seconds: 1.2);
      await play(tester, devices.mic, pluck, waitMs: 1300);
    }
    await tester.pumpAndSettle();
    expect(find.text('Perfect'), findsOneWidget);
    expect(find.textContaining('+40 XP'), findsOneWidget);
    expect(store.lessons['b.strings']!.stars, 3);
    await settle(tester);
    expect(devices.mic.isCapturing, isFalse, reason: 'mic closes when the steps are done');

    // Back on the path the next lesson is up.
    await tester.tap(find.text('Back to lessons'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('^Up next: Tune up')), findsOneWidget);
    expect(find.textContaining('Level 1 · 40 XP'), findsOneWidget);
  });

  testWidgets('a chord lesson heard through the mic builds chord mastery', (tester) async {
    final store = LocalStore.memory(
      lessons: {
        for (final id in ['b.strings', 'b.tune'])
          id: StoredLesson(stars: 3, bestScore: 1, attempts: 1, lastPlayed: DateTime(2026)),
      },
    );
    final devices = await openApp(tester, store: store);
    await tester.tap(find.bySemanticsLabel(RegExp('^Up next: E minor')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump();
    await settle(tester);
    expect(find.bySemanticsLabel('Play E minor'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await play(tester, devices.mic, strumOf('Em'));
    }
    await tester.pumpAndSettle();
    expect(find.text('Perfect'), findsOneWidget);
    expect(find.text('100% right first time'), findsOneWidget);
    expect(store.lessons['b.em']!.stars, 3);
    expect(store.skills['chord:Em'], greaterThan(40));
  });

  testWidgets('jumping ahead opens a later stage', (tester) async {
    final store = LocalStore.memory();
    await openApp(tester, store: store);
    final jump = find.text('I can already play this: start here');
    await tester.dragUntilVisible(jump, find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(jump.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start at Improver'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(LearnScreen)));
    expect(container.read(progressProvider).openStage, 1);
    expect(store.setting('learn.jumpedTo'), '1');
  });
}
