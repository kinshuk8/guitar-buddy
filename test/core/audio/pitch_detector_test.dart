import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/audio/dsp/correlogram.dart';
import 'package:fretlight/core/audio/dsp/fft.dart';
import 'package:fretlight/core/audio/dsp/mpm.dart';
import 'package:fretlight/core/audio/dsp/pitch_detector.dart';
import 'package:fretlight/core/audio/dsp/yin.dart';
import 'package:fretlight/core/audio/synth/karplus_strong.dart';
import 'package:fretlight/core/audio/synth/test_signals.dart';
import 'package:fretlight/core/music/music.dart';

import 'detector_harness.dart';

const sr = 48000;
final ({int hop, int window}) geometry = analysisGeometry(sr);
const math440 = PitchMath();
final List<Note> openStrings = Tuning.standard.strings;

PitchDetector yin() => YinDetector(sampleRate: sr, windowSize: geometry.window);
PitchDetector mpm() => MpmDetector(sampleRate: sr, windowSize: geometry.window);

/// The conditions every detector is scored on, per open string:
/// (label, signal, expected Hz, allowed median cents error).
List<(String, Float32List, double, double)> conditions(Note note) {
  final f0 = math440.hz(note);
  final name = note.name();
  double detune(double cents) => f0 * math.pow(2, cents / 1200).toDouble();
  Float32List tone(double hz, {double fundamentalDb = 0, double b = 0}) => TestSignals.pluckedTone(
    hz: hz,
    sampleRate: sr,
    seconds: 1.2,
    fundamentalGainDb: fundamentalDb,
    inharmonicity: b,
  );
  return [
    ('$name clean', tone(f0), f0, 0.5),
    ('$name weak fundamental -15dB', tone(f0, fundamentalDb: -15), f0, 0.5),
    // Harder than a real phone mic: fundamental nearly gone.
    ('$name weak fundamental -30dB', tone(f0, fundamentalDb: -30), f0, 0.5),
    ('$name +12 cents', tone(detune(12)), detune(12), 0.5),
    ('$name -27 cents', tone(detune(-27)), detune(-27), 0.5),
    ('$name noise 20dB SNR', TestSignals.withNoise(tone(f0, fundamentalDb: -6), 20), f0, 1),
    // Stiff strings stretch upper partials sharp, which genuinely shifts the
    // waveform period; every tuner reads these slightly high. Not a detector
    // error, so it gets its own tolerance.
    ('$name stiff string B=5e-5', tone(f0, b: 5e-5), f0, 2),
    ('$name Karplus-Strong', KarplusStrong(sampleRate: sr).pluck(hz: f0, seconds: 1.2), f0, 0.5),
  ];
}

void main() {
  group('FFT and correlogram', () {
    test('FFT of a unit impulse is flat; inverse round-trips', () {
      final fft = Fft(16);
      final re = Float64List(16)..[0] = 1;
      final im = Float64List(16);
      fft.transform(re, im);
      for (var k = 0; k < 16; k++) {
        expect(re[k], closeTo(1, 1e-12));
        expect(im[k], closeTo(0, 1e-12));
      }
      fft.transform(re, im, inverse: true);
      expect(re[0] / 16, closeTo(1, 1e-12));
      expect(re[5] / 16, closeTo(0, 1e-12));
    });

    test('correlogram matches the direct O(n²) sums', () {
      final rnd = math.Random(3);
      final x = Float32List.fromList([for (var i = 0; i < 256; i++) rnd.nextDouble() * 2 - 1]);
      final c = Correlogram(256, 100)..compute(x);
      for (final tau in [0, 1, 17, 64, 100]) {
        var r = 0.0;
        var m = 0.0;
        for (var j = 0; j + tau < 256; j++) {
          r += x[j] * x[j + tau];
          m += x[j] * x[j] + x[j + tau] * x[j + tau];
        }
        expect(c.r[tau], closeTo(r, 1e-6), reason: 'r[$tau]');
        expect(c.m[tau], closeTo(m, 1e-6), reason: 'm[$tau]');
      }
    });

    test('analysis window holds several periods of low E at common rates', () {
      for (final rate in [44100, 48000]) {
        final g = analysisGeometry(rate);
        expect(g.window / (rate / 82.41), greaterThan(6), reason: '$rate');
        expect(rate / g.hop, greaterThan(40), reason: 'updates per second at $rate');
      }
    });
  });

  for (final (name, make) in [('YIN', yin), ('MPM', mpm)]) {
    group('$name on synthesized open strings', () {
      final rows = <DetectorScore>[];

      for (final note in openStrings) {
        for (final (label, signal, hz, tolerance) in conditions(note)) {
          test(label, () {
            final e = evaluate(label, make(), signal, expectedHz: hz, sampleRate: sr);
            rows.add(e);
            expect(e.grossErrors, 0, reason: 'octave errors in $label');
            expect(e.detectionRate, greaterThan(0.9), reason: 'detection rate in $label');
            expect(e.medianAbsError, lessThan(tolerance), reason: 'median cents in $label');
          });
        }
      }

      tearDownAll(() {
        // Printed on purpose: `flutter test` doubles as the accuracy report.
        // ignore: avoid_print
        print(formatReport('$name accuracy, synthesized open strings @ $sr Hz', rows));
      });
    });
  }

  group('rejection', () {
    test('silence and white noise give no pitch', () {
      for (final make in [yin, mpm]) {
        final d = make();
        expect(d.detect(Float32List(geometry.window)), isNull);
        final noise = TestSignals.withNoise(Float32List(geometry.window)..[0] = 1e-3, -40);
        final e = d.detect(noise);
        expect(e == null || e.clarity < 0.6, isTrue, reason: '$e');
      }
    });

    test('a tone above maxHz is not reported an octave low', () {
      final d = YinDetector(sampleRate: sr, windowSize: geometry.window, maxHz: 1000);
      final tone = TestSignals.sine(hz: 1500, sampleRate: sr, seconds: 0.2);
      final e = d.detect(Float32List.sublistView(tone, 0, geometry.window));
      expect(e, isNull);
    });
  });

  test('YIN frame cost is small enough for 47 frames/s', () {
    final d = yin();
    final signal = TestSignals.pluckedTone(hz: 82.41, sampleRate: sr, seconds: 0.2);
    final window = Float32List.sublistView(signal, 0, geometry.window);
    for (var i = 0; i < 20; i++) {
      d.detect(window); // warm up the JIT
    }
    final sw = Stopwatch()..start();
    const runs = 100;
    for (var i = 0; i < runs; i++) {
      d.detect(window);
    }
    final perFrameMs = sw.elapsedMicroseconds / runs / 1000;
    // Printed on purpose: timing is part of the accuracy report.
    // ignore: avoid_print
    print('YIN: ${perFrameMs.toStringAsFixed(2)} ms per 4096-sample frame (JIT, test VM)');
    // Budget: 21 ms between frames at 47/s. Leave a wide margin for slow phones.
    expect(perFrameMs, lessThan(6));
  });
}
