import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/features/chords/domain/chord_library.dart';
import 'package:fretlight/features/learn/application/lesson_controller.dart';
import 'package:fretlight/features/learn/domain/curriculum.dart';
import 'package:fretlight/features/learn/presentation/lesson_screen.dart';

import '../../support/test_app.dart';

final library = ChordLibrary.fromJson(
  (jsonDecode(File('assets/chords/guitar.json').readAsStringSync()) as Map).cast<String, Object?>(),
);

/// Opens [lesson], starts it, and walks to step [step] by finishing the
/// steps before it (skipping or ending them).
Future<void> showStep(WidgetTester tester, Lesson lesson, int step) async {
  await tester.pumpWidget(
    TestDevices(library: library).wrap(
      MaterialApp(
        theme: StageThemeData.dark(),
        home: LessonScreen(lesson: lesson),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  final container = ProviderScope.containerOf(tester.element(find.byType(LessonScreen)));
  final controller = container.read(lessonProvider.notifier);
  await tester.runAsync(controller.start);
  await tester.pump();
  for (var i = 0; i < step; i++) {
    final game = container.read(lessonProvider).game;
    for (var guard = 0; guard < 500 && container.read(lessonProvider).step == i; guard++) {
      if (container.read(lessonProvider).phase != LessonPhase.playing) break;
      controller
        ..skip()
        ..stopRace()
        ..answer(0);
    }
    expect(game, isNotNull);
    await tester.runAsync(() async => controller.next());
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  // Every kind of step, on a big phone and a small one: no overflow, the
  // key text is there.
  final cases = <(String, int, String)>[
    ('b.strings', 0, 'Which string is this?'),
    ('b.strings', 1, 'The open low E string'),
    ('b.tune', 0, 'TUNE'),
    ('b.em', 0, 'PLAY'),
    ('b.em-am', 1, 'Clock starts\nwith your first chord'),
    ('b.chord-quiz', 0, 'Which chord is this?'),
    ('b.downs', 0, 'Count me in'),
    ('i.waltz', 0, 'Count me in'),
    ('i.tab', 0, 'Which note does this tab play?'),
    ('i.tab', 1, 'Up and back'),
    ('i.low-e', 0, 'Which note is this?'),
    ('m.e-shape', 0, 'PLAY'),
    ('b.clementine', 0, 'PLAY'),
  ];
  for (final size in [const Size(1206, 2622), const Size(750, 1334)]) {
    for (final (id, step, text) in cases) {
      testWidgets('$id step ${step + 1} at ${size.width ~/ 2}pt wide', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = size.width > 1000 ? 3 : 2;
        addTearDown(tester.view.reset);
        await showStep(tester, lessonById(id)!, step);
        expect(find.textContaining(text), findsWidgets);
      });
    }
  }

  testWidgets('a lesson intro shows its title and tip, in the light theme too', (tester) async {
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TestDevices(library: library).wrap(
        MaterialApp(
          theme: StageThemeData.light(),
          home: LessonScreen(lesson: lessonById('a.f')!),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('F major'), findsWidgets);
    expect(find.textContaining('Roll your first finger'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('the Learn tab fits a small phone, top to bottom', (tester) async {
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(TestDevices(library: library).app());
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('Beautiful Dreamer'),
      find.byType(ListView),
      const Offset(0, -400),
    );
    expect(find.text('Beautiful Dreamer'), findsOneWidget);
  });
}
