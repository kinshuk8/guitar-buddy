import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/storage/local_store.dart';

import '../../support/test_app.dart';

Future<TestDevices> openTempo(WidgetTester tester, {LocalStore? store}) async {
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final devices = TestDevices(store: store);
  await tester.pumpWidget(devices.app());
  await tester.pump();
  goTo(tester, '/tools/metronome');
  await tester.pumpAndSettle();
  return devices;
}

/// The loop is rendered in an isolate: give it real time.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
  await tester.pump();
}

void main() {
  testWidgets('starts and stops a looping click; beats light from the engine clock', (
    tester,
  ) async {
    final devices = await openTempo(tester);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('BPM · Andante'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Beat \d, ')), findsNWidgets(4));

    await tester.tap(find.text('Start'));
    await settle(tester);
    final speaker = devices.speaker;
    expect(speaker.loops, hasLength(1));
    expect(find.text('Stop'), findsOneWidget);

    // Move the fake engine clock into beat 2 and let a frame read it.
    speaker.now = speaker.loops.single.start + const Duration(milliseconds: 650);
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('Stop'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await settle(tester);
    expect(speaker.loops.single.stop, isNotNull);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('nudging, accents and meter', (tester) async {
    final store = LocalStore.memory();
    await openTempo(tester, store: store);
    await tester.tap(find.bySemanticsLabel('Faster'));
    await tester.pump();
    expect(find.text('101'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(RegExp('^Beat 2, normal accent')));
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('^Beat 2, muted')), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(RegExp('^Time signature 4/4')));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('6/8'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(r'^Beat \d, ')), findsNWidgets(6));
    expect(find.bySemanticsLabel(RegExp('^Beat 4, medium accent')), findsOneWidget);
    expect(store.setting('metronome.signature'), '6/8');
  });

  testWidgets('keeps running on another tab; stops when the app is hidden', (tester) async {
    final devices = await openTempo(tester);
    await tester.tap(find.text('Start'));
    await settle(tester);
    goTo(tester, '/tools/chords');
    await tester.pump();
    expect(devices.speaker.loops.single.stop, isNull, reason: 'practise chords to the click');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await settle(tester);
    expect(devices.speaker.loops.single.stop, isNotNull);
  });
}
