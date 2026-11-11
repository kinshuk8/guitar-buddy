import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/storage/local_store.dart';
import 'package:fretlight/features/practice/application/practice_controller.dart';
import 'package:fretlight/features/practice/domain/practice_session.dart';

import '../../support/test_app.dart';

void main() {
  testWidgets('settings: theme and handedness are saved; privacy and licences are there', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = LocalStore.memory();
    await tester.pumpWidget(TestDevices(store: store).app());
    await tester.pump();
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    // Further down the page: scroll to it, then back up.
    final privacy = find.textContaining('never connects to the internet');
    await tester.scrollUntilVisible(privacy, 300);
    expect(privacy, findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Light'));
    await tester.pumpAndSettle();
    expect(store.setting('appearance.theme'), 'light');
    expect(Theme.of(tester.element(find.text('Settings'))).brightness, Brightness.light);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(store.setting('appearance.leftHanded'), 'true');

    await tester.scrollUntilVisible(find.textContaining('Chordonomicon'), 200);
    expect(find.textContaining('Chordonomicon'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Licences'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Licences'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });

  testWidgets('reset learning progress asks first, then clears only learning', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = LocalStore.memory(
      settings: {'appearance.theme': 'dark'},
      days: {'2026-11-06': const StoredDay(seconds: 600, xp: 80)},
      skills: {'chord:Em': 50},
    );
    await tester.pumpWidget(TestDevices(store: store).app());
    await tester.pump();
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Reset learning progress'), 200);
    await tester.tap(find.text('Reset learning progress'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    expect(store.days, isNotEmpty, reason: 'cancel keeps it');

    await tester.tap(find.text('Reset learning progress'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset progress'));
    await tester.pumpAndSettle();
    expect(store.days, isEmpty);
    expect(store.skills, isEmpty);
    expect(store.setting('appearance.theme'), 'dark');
  });

  testWidgets('chord matching: normal by default, forgiving is saved and used by practice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = LocalStore.memory();
    await tester.pumpWidget(TestDevices(store: store).app());
    await tester.pumpAndSettle();
    goTo(tester, '/settings');
    await tester.pumpAndSettle();
    final forgiving = find.bySemanticsLabel('Forgiving');
    await tester.scrollUntilVisible(forgiving, 200);
    expect(find.textContaining('The chord, or the same chord with a note missing'), findsOneWidget);
    await tester.tap(forgiving);
    await tester.pumpAndSettle();
    expect(store.setting('listen.chordMatching'), 'forgiving');
    expect(find.textContaining('barre chords that don’t ring fully'), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.byType(Navigator).first));
    container
        .read(practiceProvider.notifier)
        .begin(PracticePlan(title: 'x', sounding: [Chord.parse('Em')]));
    expect(container.read(practiceProvider).session!.matching, ChordMatching.forgiving);
  });
}
