import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/storage/local_store.dart';

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
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.textContaining('never connects to the internet'), findsOneWidget);
    expect(find.textContaining('Chordonomicon'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Light'));
    await tester.pumpAndSettle();
    expect(store.setting('appearance.theme'), 'light');
    expect(Theme.of(tester.element(find.text('Settings'))).brightness, Brightness.light);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(store.setting('appearance.leftHanded'), 'true');

    await tester.scrollUntilVisible(find.text('Licences'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Licences'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });
}
