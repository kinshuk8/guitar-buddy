import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/audio/dsp/mpm.dart';
import 'package:fretlight/core/audio/dsp/pitch_detector.dart';
import 'package:fretlight/core/audio/dsp/pitch_tracker.dart';
import 'package:fretlight/core/audio/synth/karplus_strong.dart';
import 'package:fretlight/core/audio/synth/test_signals.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/features/tuner/domain/tuner_session.dart';

/// Every string, detuned by known amounts, through the tuner's detector
/// and session: the needle must read the true offset of the *fundamental*.
void main() {
  const sr = 48000;
  const pm = PitchMath();
  final g = analysisGeometry(sr);
  const offsets = [-30.0, -10, -3, 0, 2, 8, 25];

  /// Worst error (cents) over every reading after the pluck's attack.
  double worstError(Float32List Function(double hz) make) {
    var worst = 0.0;
    for (final (i, note) in Tuning.standard.strings.indexed) {
      for (final off in offsets) {
        final tracker = PitchTracker(
          detector: MpmDetector(sampleRate: sr, windowSize: g.window),
          hop: g.hop,
        );
        final session = TunerSession(tuning: Tuning.standard, sampleRate: sr);
        final readings = <TunerReading>[];
        for (final f in tracker.push(make(pm.hz(note) * math.pow(2, off / 1200)))) {
          final r = session.update(f);
          if (r != null && f.endSample > 0.25 * sr) readings.add(r);
        }
        expect(readings, isNotEmpty, reason: '${note.name()} $off¢');
        expect(readings.every((r) => r.stringIndex == i), isTrue, reason: '${note.name()} $off¢');
        for (final r in readings) {
          worst = math.max(worst, (r.cents - off).abs());
        }
      }
    }
    return worst;
  }

  Float32List string(double hz, {double fundamentalDb = 0}) => TestSignals.pluckedTone(
    hz: hz,
    sampleRate: sr,
    seconds: 1.5,
    // A steel string's stiffness: partials a little sharp of n·f0.
    inharmonicity: 1e-4,
    fundamentalGainDb: fundamentalDb,
  );

  final cases = <(String, Float32List Function(double), double)>[
    ('synthesised pluck', (hz) => KarplusStrong(sampleRate: sr).pluck(hz: hz, seconds: 1.5), 0.1),
    ('stiff string (partials sharp)', string, 0.3),
    ('stiff string, fundamental −12 dB', (hz) => string(hz, fundamentalDb: -12), 0.3),
    ('stiff string, room noise 15 dB SNR', (hz) => TestSignals.withNoise(string(hz), 15), 1.5),
    ('stiff string, fundamental −26 dB', (hz) => string(hz, fundamentalDb: -26), 0.5),
  ];

  test('the needle reads the fundamental: a few tenths of a cent, ~1¢ in a noisy room', () {
    final report = StringBuffer('\n== Tuner accuracy: 6 strings × 7 offsets each ==\n');
    for (final (name, make, limit) in cases) {
      final worst = worstError(make);
      report.writeln('${name.padRight(38)} worst ${worst.toStringAsFixed(2)}¢');
      expect(worst, lessThan(limit), reason: name);
    }
    // Printed on purpose: part of the accuracy report.
    // ignore: avoid_print
    print(report);
  });
}
