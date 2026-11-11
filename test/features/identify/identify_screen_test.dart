import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/audio/synth/strum.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/painting/chord_diagram.dart';
import 'package:fretlight/features/chords/domain/chord_library.dart';

import '../../support/fake_audio_input.dart';
import '../../support/test_app.dart';

final library = ChordLibrary.fromJson(
  (jsonDecode(File('assets/chords/guitar.json').readAsStringSync()) as Map).cast<String, Object?>(),
);
const pm = PitchMath();

Future<TestDevices> openIdentify(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final devices = TestDevices(library: library);
  await tester.pumpWidget(devices.app());
  await tester.pump();
  goTo(tester, '/tools/identify');
  await tester.pump();
  await settle(tester);
  return devices;
}

/// Real time for the mic queue and the DSP isolate, interleaved with pumps.
Future<void> settle(WidgetTester tester, {int ms = 400}) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms ~/ 4)));
    await tester.pump();
  }
}

Future<void> play(WidgetTester tester, FakeAudioInputSource mic, Float32List pcm) async {
  await tester.runAsync(() async {
    mic.feed(pcm);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

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

void main() {
  testWidgets('names a strummed chord and shows its shape', (tester) async {
    final devices = await openIdentify(tester);
    expect(devices.mic.isCapturing, isTrue);
    expect(find.text('Strum a chord'), findsOneWidget);
    expect(find.text('Made for one guitar in a quiet room'), findsOneWidget);

    await play(tester, devices.mic, strumOf('G'));
    expect(find.bySemanticsLabel(RegExp('^G major, (confident|fairly sure)')), findsOneWidget);
    expect(find.byType(ChordDiagram), findsOneWidget);
    expect(find.bySemanticsLabel('Open G major in the chord library'), findsOneWidget);
  });

  testWidgets('note mode: name, octave and every place on the neck', (tester) async {
    final devices = await openIdentify(tester);
    await tester.tap(find.text('Note'));
    await tester.pump();
    expect(find.text('Play a note'), findsOneWidget);

    final a3 = renderStrum(stringHz: [pm.hz(Note.parse('A3'))], sampleRate: 48000, seconds: 1.2);
    await play(tester, devices.mic, a3);
    expect(find.bySemanticsLabel(RegExp(r'^A 3, 220\.\d hertz')), findsOneWidget);
    // A3: 5th string 12th fret, 4th string 7th fret, 3rd string 2nd fret
    // (6th string 17th fret is beyond the 12 shown).
    expect(
      find.bySemanticsLabel('Fretboard: string 5 fret 12, string 4 fret 7, string 3 fret 2'),
      findsOneWidget,
    );
  });

  testWidgets('a single string in chord mode says so instead of guessing', (tester) async {
    final devices = await openIdentify(tester);
    final e2 = renderStrum(stringHz: [pm.hz(Note.parse('E2'))], sampleRate: 48000, seconds: 1.4);
    await play(tester, devices.mic, e2);
    expect(find.textContaining('That’s one note: E'), findsOneWidget);
  });

  testWidgets('tuner and identifier share the mic across tab switches', (tester) async {
    final devices = await openIdentify(tester);
    expect(devices.mic.isCapturing, isTrue);
    goTo(tester, '/tuner');
    await tester.pump();
    await settle(tester);
    expect(devices.mic.isCapturing, isTrue, reason: 'the tuner now holds it');
    goTo(tester, '/tools/chords');
    await tester.pump();
    await settle(tester);
    expect(devices.mic.isCapturing, isFalse, reason: 'nobody is listening');
    expect(devices.mic.starts, devices.mic.stops, reason: 'every start was stopped');
  });
}
