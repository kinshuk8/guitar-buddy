import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/audio/dsp/mpm.dart';
import 'package:fretlight/core/audio/dsp/pitch_detector.dart';
import 'package:fretlight/core/audio/dsp/pitch_tracker.dart';
import 'package:fretlight/core/audio/engine/dsp_worker.dart';
import 'package:fretlight/core/audio/synth/karplus_strong.dart';
import 'package:fretlight/core/audio/synth/test_signals.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/features/tuner/domain/tuner_session.dart';

const sr = 48000;
const pm = PitchMath();

/// Frames spaced one hop apart, starting after [startSample].
List<PitchFrame> frames(
  List<double?> hz, {
  int startSample = 0,
  double clarity = 0.97,
  double db = -20,
}) {
  final hop = analysisGeometry(sr).hop;
  return [
    for (var i = 0; i < hz.length; i++)
      PitchFrame(endSample: startSample + (i + 1) * hop, hz: hz[i], clarity: clarity, rmsDb: db),
  ];
}

double detune(Note n, double cents) => pm.hz(n) * math.pow(2, cents / 1200).toDouble();

TunerReading? run(TunerSession s, List<PitchFrame> fs) {
  TunerReading? r;
  for (final f in fs) {
    r = s.update(f);
  }
  return r;
}

void main() {
  final e2 = Note.parse('E2');
  final a2 = Note.parse('A2');

  test('auto mode finds the string and the cents offset', () {
    final s = TunerSession(tuning: Tuning.standard, sampleRate: sr);
    final r = run(s, frames(List.filled(6, detune(a2, -14))))!;
    expect(r.stringIndex, 1);
    expect(r.target, a2);
    expect(r.cents, closeTo(-14, 0.01));
  });

  test('a single outlier frame is ignored; a sustained change is followed', () {
    final s = TunerSession(tuning: Tuning.standard, sampleRate: sr);
    run(s, frames(List.filled(5, pm.hz(e2))));
    // One stray octave frame.
    final r1 = run(s, frames([pm.hz(e2) * 2], startSample: 6 * 1024))!;
    expect(r1.cents, closeTo(0, 0.01));
    // Two consecutive A2 frames: a new note.
    final r2 = run(s, frames([pm.hz(a2), pm.hz(a2)], startSample: 8 * 1024))!;
    expect(r2.detected, a2);
  });

  test('string highlight needs a few frames to switch (no flicker between strings)', () {
    final s = TunerSession(tuning: Tuning.standard, sampleRate: sr);
    run(s, frames(List.filled(5, pm.hz(e2))));
    // 2.6 semitones above E2: nearer A2 (2.4 away) than E2 (2.6 away)... barely.
    final between = pm.hz(e2) * math.pow(2, 2.6 / 12);
    final first = run(s, frames([between, between], startSample: 6000))!;
    expect(first.stringIndex, 0, reason: 'not switched after 2 frames');
    final later = run(s, frames(List.filled(3, between), startSample: 9000))!;
    expect(later.stringIndex, 1);
  });

  test('locked string folds octaves (12th-fret harmonics work)', () {
    final s = TunerSession(tuning: Tuning.standard, sampleRate: sr, lockedString: 0);
    final r = run(s, frames(List.filled(5, detune(e2, 6) * 2)))!;
    expect(r.stringIndex, 0);
    expect(r.cents, closeTo(6, 0.01));
  });

  test('auto mode folds only implausible readings onto a string', () {
    final s = TunerSession(tuning: Tuning.standard, sampleRate: sr);
    // E1 is far below every open string; an octave up is low E.
    final r = run(s, frames(List.filled(5, pm.hz(e2) / 2)))!;
    expect(r.target, e2);
    expect(r.cents, closeTo(0, 0.01));
    // F#3 (a fretted note) is a semitone from G3: left alone, reads flat.
    final s2 = TunerSession(tuning: Tuning.standard, sampleRate: sr);
    final r2 = run(s2, frames(List.filled(5, pm.hz(Note.parse('F#3')))))!;
    expect(r2.target, Note.parse('G3'));
    expect(r2.cents, closeTo(-100, 0.01));
  });

  test('low clarity and quiet frames are gated; reading holds briefly then clears', () {
    final s = TunerSession(tuning: Tuning.standard, sampleRate: sr);
    expect(run(s, frames(List.filled(5, pm.hz(e2)), clarity: 0.5)), isNull);
    expect(run(s, frames(List.filled(5, pm.hz(e2)), db: -70)), isNull);
    run(s, frames(List.filled(5, pm.hz(e2))));
    // Silence for 0.4 s: still held.
    expect(run(s, frames(List.filled(18, null), startSample: 5 * 1024)), isNotNull);
    // Silence for over a second: cleared.
    expect(run(s, frames(List.filled(50, null), startSample: 5 * 1024)), isNull);
  });

  test('reference pitch moves the target', () {
    final s = TunerSession(tuning: Tuning.standard, sampleRate: sr, math: const PitchMath(a4: 432));
    // A2 at 440 reference is ~31.8 cents sharp against A=432.
    final r = run(s, frames(List.filled(5, pm.hz(a2))))!;
    expect(r.cents, closeTo(31.77, 0.05));
  });

  test('drop D: low string target is D2', () {
    final s = TunerSession(tuning: Tuning.dropD, sampleRate: sr);
    final r = run(s, frames(List.filled(5, detune(Note.parse('D2'), 4))))!;
    expect(r.stringIndex, 0);
    expect(r.cents, closeTo(4, 0.01));
  });

  group('end to end through the DSP isolate', () {
    test('every open string, plucked 7 cents flat, reads within 1 cent and stays put', () async {
      final worker = await DspWorker.spawn(sampleRate: sr);
      addTearDown(worker.dispose);
      final report = StringBuffer(
        '\n== Tuner end-to-end (isolate, MPM, Karplus-Strong plucks) ==\n',
      );
      for (final (i, note) in Tuning.standard.strings.indexed) {
        final hz = detune(note, -7);
        final signal = KarplusStrong(sampleRate: sr).pluck(hz: hz, seconds: 1.5);
        final session = TunerSession(tuning: Tuning.standard, sampleRate: sr);
        worker.reset();
        final readings = <TunerReading>[];
        final done = worker.frames.take(_expectedFrames(signal.length)).forEach((f) {
          final r = session.update(f);
          if (r != null && f.endSample > 0.2 * sr) readings.add(r);
        });
        for (var o = 0; o < signal.length; o += 960) {
          final chunk = Float32List.sublistView(signal, o, math.min(o + 960, signal.length));
          worker.push(floatToPcm16(chunk));
        }
        await done;
        expect(readings, isNotEmpty, reason: note.name());
        expect(
          readings.every((r) => r.stringIndex == i),
          isTrue,
          reason: 'string stable for ${note.name()}',
        );
        final worst = readings.map((r) => (r.cents + 7).abs()).reduce(math.max);
        report.writeln(
          '${note.name()}  readings ${readings.length.toString().padLeft(3)}  worst error ${worst.toStringAsFixed(2)}¢',
        );
        expect(worst, lessThan(1), reason: note.name());
      }
      // Printed on purpose: part of the milestone accuracy report.
      // ignore: avoid_print
      print(report);
    });

    test('a strummed chord does not produce a confident single-string reading', () {
      // Not a hard guarantee, but the tuner must not jump around wildly:
      // whatever it shows must be gated or settle on one string.
      final g = analysisGeometry(sr);
      final chord = TestSignals.mix([
        for (final n in ['E2', 'B2', 'E3', 'G#3', 'B3', 'E4'])
          TestSignals.pluckedTone(hz: pm.hz(Note.parse(n)), sampleRate: sr, seconds: 1),
      ]);
      final tracker = PitchTracker(
        detector: MpmDetector(sampleRate: sr, windowSize: g.window),
        hop: g.hop,
      );
      final session = TunerSession(tuning: Tuning.standard, sampleRate: sr);
      final strings = <int>{};
      for (final f in tracker.push(chord)) {
        final r = session.update(f);
        if (r != null && f.endSample > 0.2 * sr) strings.add(r.stringIndex);
      }
      expect(strings.length, lessThanOrEqualTo(1));
    });
  });
}

int _expectedFrames(int samples) {
  final g = analysisGeometry(sr);
  return (samples - g.window) ~/ g.hop + 1;
}
