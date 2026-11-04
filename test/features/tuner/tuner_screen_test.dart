import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/audio/input/audio_input_source.dart';
import 'package:fretlight/core/audio/synth/karplus_strong.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/storage/local_store.dart';
import 'package:fretlight/features/tuner/application/tuner_controller.dart';

import '../../support/fake_audio_input.dart';
import '../../support/test_app.dart';

Future<FakeAudioInputSource> pumpApp(
  WidgetTester tester, {
  FakeAudioInputSource? mic,
  LocalStore? store,
}) async {
  final devices = TestDevices(mic: mic, store: store);
  final fake = devices.mic;
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(devices.app());
  await tester.pump();
  // Let the controller's async start (permission → start → isolate spawn) finish.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pump();
  return fake;
}

/// Plays a pluck into the fake mic and waits for the isolate to analyse it.
Future<void> pluck(WidgetTester tester, FakeAudioInputSource mic, double hz) async {
  await tester.runAsync(() async {
    mic.feed(KarplusStrong(sampleRate: 48000).pluck(hz: hz, seconds: 0.9));
    await Future<void>.delayed(const Duration(milliseconds: 600));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600)); // let the needle spring settle
}

void main() {
  const pm = PitchMath();
  double detune(String note, double cents) => pm.hz(Note.parse(note)) * math.pow(2, cents / 1200);

  testWidgets('hears a flat A string: note, flat badge, A highlighted', (tester) async {
    final mic = await pumpApp(tester);
    expect(mic.isCapturing, isTrue);
    expect(find.text('Play a single string'), findsOneWidget);

    await pluck(tester, mic, detune('A2', -14));
    expect(find.text('A'), findsWidgets);
    expect(find.textContaining('Flat'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Flat, 14 cents, tune up')), findsOneWidget);
  });

  testWidgets('in tune within ±3 cents', (tester) async {
    final mic = await pumpApp(tester);
    await pluck(tester, mic, detune('D3', 2));
    expect(find.textContaining('In tune'), findsOneWidget);
  });

  testWidgets('switching tabs releases the microphone; coming back reopens it', (tester) async {
    final mic = await pumpApp(tester);
    expect(mic.isCapturing, isTrue);
    await tester.tap(find.bySemanticsLabel('Tempo'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    expect(mic.isCapturing, isFalse);
    await tester.tap(find.bySemanticsLabel('Tune'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    expect(mic.isCapturing, isTrue);
  });

  testWidgets('denied permission asks once, then offers a button', (tester) async {
    final mic = await pumpApp(
      tester,
      mic: FakeAudioInputSource(current: MicPermission.denied, afterRequest: MicPermission.denied),
    );
    expect(mic.requests, 1);
    expect(find.text('Microphone needed'), findsOneWidget);
    mic.afterRequest = MicPermission.granted;
    await tester.tap(find.text('Allow microphone'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    expect(mic.isCapturing, isTrue);
    expect(find.text('Microphone needed'), findsNothing);
  });

  testWidgets('permanently denied points to Settings', (tester) async {
    final mic = await pumpApp(
      tester,
      mic: FakeAudioInputSource(current: MicPermission.permanentlyDenied),
    );
    expect(find.text('Microphone is off'), findsOneWidget);
    await tester.tap(find.text('Open Settings'));
    expect(mic.settingsOpened, isTrue);
  });

  testWidgets('a phone call pauses and resumes capture', (tester) async {
    final mic = await pumpApp(tester);
    mic.interrupt(began: true);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(mic.isCapturing, isFalse);
    expect(find.text('Paused while another app uses the microphone'), findsOneWidget);
    mic.interrupt(began: false);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    expect(mic.isCapturing, isTrue);
  });

  testWidgets('locking a string and changing tuning', (tester) async {
    await pumpApp(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    await tester.tap(find.bySemanticsLabel(RegExp('String 6, E 2')));
    await tester.pump();
    expect(container.read(tunerProvider).lockedString, 0);
    await tester.tap(find.bySemanticsLabel('Auto-detect string'));
    await tester.pump();
    expect(container.read(tunerProvider).lockedString, isNull);

    await tester.tap(find.bySemanticsLabel(RegExp('Tuning: Standard')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drop D'));
    await tester.pumpAndSettle();
    expect(container.read(tunerProvider).tuning.id, 'drop_d');
    expect(find.bySemanticsLabel(RegExp('String 6, D 2')), findsOneWidget);
  });
}
