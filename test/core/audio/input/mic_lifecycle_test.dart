import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/audio/input/mic_lifecycle.dart';

import '../../../support/fake_audio_input.dart';

/// A lifecycle on the fake mic, recording the statuses it reports.
({MicLifecycle mic, FakeAudioInputSource input, List<MicStatus> statuses}) make() {
  final input = FakeAudioInputSource();
  final statuses = <MicStatus>[];
  final mic = MicLifecycle(
    input: input,
    onStatus: statuses.add,
    onStart: (description, pcm) async => pcm.listen((_) {}),
    onStop: () async {},
    isAlive: () => true,
  );
  addTearDown(mic.dispose);
  return (mic: mic, input: input, statuses: statuses);
}

/// Lets the event listener and the mic's queue run.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  test('a call pauses listening and its end resumes it', () async {
    final m = make();
    await m.mic.setActive(active: true);
    expect(m.mic.status, MicStatus.listening);
    m.input.interrupt(began: true);
    await settle();
    expect(m.mic.status, MicStatus.interrupted);
    expect(m.input.isCapturing, isFalse);
    m.input.interrupt(began: false);
    await settle();
    expect(m.mic.status, MicStatus.listening);
    expect(m.input.isCapturing, isTrue);
  });

  test('an interruption whose end never comes: Resume listens again', () async {
    final m = make();
    await m.mic.setActive(active: true);
    m.input.interrupt(began: true);
    await settle();
    expect(m.mic.status, MicStatus.interrupted);
    await m.mic.resume();
    expect(m.mic.status, MicStatus.listening);
    expect(m.input.isCapturing, isTrue);
  });

  test('an interruption whose end never comes: leaving and coming back listens again', () async {
    final m = make();
    await m.mic.setActive(active: true);
    m.input.interrupt(began: true);
    await settle();
    // The app goes to the background and comes back (or the screen is
    // left and opened again).
    await m.mic.setActive(active: false);
    await m.mic.setActive(active: true);
    expect(m.mic.status, MicStatus.listening);
    expect(m.input.isCapturing, isTrue);
  });

  test('an interruption while the screen was hidden does not block it later', () async {
    final m = make();
    m.input.interrupt(began: true);
    await settle();
    await m.mic.setActive(active: true);
    expect(m.mic.status, MicStatus.listening);
    expect(m.input.isCapturing, isTrue);
  });

  test('try again also clears an interruption', () async {
    final m = make();
    await m.mic.setActive(active: true);
    m.input.interrupt(began: true);
    await settle();
    await m.mic.restart();
    expect(m.mic.status, MicStatus.listening);
    unawaited(m.mic.setActive(active: false));
  });
}
