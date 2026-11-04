import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/audio/synth/strum.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/features/chords/domain/chord_library.dart';

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

Future<TestDevices> openSongs(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final devices = TestDevices(library: library);
  await tester.pumpWidget(devices.app());
  await tester.pump();
  await tester.tap(find.bySemanticsLabel('Songs'));
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

Future<void> play(WidgetTester tester, FakeAudioInputSource mic, String chord) async {
  // A moment of quiet first, so the strum is heard as a new strum.
  await tester.runAsync(() async {
    mic
      ..feed(Float32List(48000 ~/ 2))
      ..feed(strumOf(chord));
    await Future<void>.delayed(const Duration(milliseconds: 1400));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('practising a song: waits for each chord and moves on when it hears it', (
    tester,
  ) async {
    final devices = await openSongs(tester);
    await tester.tap(find.bySemanticsLabel(RegExp('^Amazing Grace, ')));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp('^Practise this song')));
    await tester.pump();
    await settle(tester);

    expect(devices.mic.isCapturing, isTrue);
    expect(find.bySemanticsLabel('Play G major'), findsOneWidget);
    expect(find.text('Listening…'), findsOneWidget);
    expect(find.textContaining('1 / '), findsOneWidget);

    await play(tester, devices.mic, 'G');
    expect(find.textContaining('2 / '), findsOneWidget, reason: 'G heard: next chord');
    expect(find.text('Nice'), findsOneWidget);

    // Wrong chord: stays put and says what it heard.
    await play(tester, devices.mic, 'D');
    expect(find.textContaining('2 / '), findsOneWidget);
    expect(find.text('Heard D'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(find.textContaining('3 / '), findsOneWidget);
  });

  testWidgets('progressions from the pack: listed with attribution, practised four times round', (
    tester,
  ) async {
    await openSongs(tester);
    await tester.tap(find.text('Progressions'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp(r'^E minor, C major, G major, D major\. In ')),
      findsOneWidget,
    );

    await tester.tap(find.bySemanticsLabel(RegExp(r'^E minor, C major, G major, D major\. In ')));
    await tester.pumpAndSettle();
    expect(find.text('Starts on Em'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Key up a semitone'));
    await tester.pumpAndSettle();
    expect(find.text('Starts on Fm'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Key down a semitone'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Practise'));
    await tester.pump();
    await settle(tester);
    expect(find.text('Em – C – G – D'), findsOneWidget);
    expect(find.textContaining('1 / 16'), findsOneWidget);
  });

  testWidgets('the summary names the chords that need work', (tester) async {
    final devices = await openSongs(tester);
    await tester.tap(find.text('Progressions'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp(r'^E minor, C major, G major, D major\. In ')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Practise'));
    await tester.pump();
    await settle(tester);
    expect(devices.mic.isCapturing, isTrue);
    for (var i = 0; i < 16; i++) {
      await tester.tap(find.text('Skip'));
      await tester.pump();
    }
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('WORTH ANOTHER GO'), findsOneWidget);
    expect(find.text('Practise just these'), findsOneWidget);
  });
}
