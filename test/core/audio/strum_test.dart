import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/audio/dsp/mpm.dart';
import 'package:fretlight/core/audio/dsp/pitch_detector.dart';
import 'package:fretlight/core/audio/synth/strum.dart';
import 'package:fretlight/core/music/music.dart';

void main() {
  const sr = 48000;
  const pm = PitchMath();

  test('a single string plays exactly its pitch (checked with the tuner detector)', () {
    final g = analysisGeometry(sr);
    final mpm = MpmDetector(sampleRate: sr, windowSize: g.window);
    for (final name in ['E2', 'A2', 'G3', 'E4', 'C5']) {
      final hz = pm.hz(Note.parse(name));
      final pcm = renderStrum(stringHz: [hz], sampleRate: sr, seconds: 1);
      final est = mpm.detect(Float32List.sublistView(pcm, sr ~/ 4, sr ~/ 4 + g.window))!;
      expect(PitchMath.cents(est.hz, hz).abs(), lessThan(1), reason: name);
    }
  });

  test('a strum staggers strings low to high, skips muted ones, never clips', () {
    final c = [null, 3, 2, 0, 1, 0]; // open C
    final hz = [
      for (var s = 0; s < 6; s++)
        if (c[s] case final int f) pm.hz(Tuning.standard.noteAt(s, f)) else null,
    ];
    final pcm = renderStrum(stringHz: hz, sampleRate: sr, gap: const Duration(milliseconds: 20));
    var peak = 0.0;
    for (final v in pcm) {
      peak = math.max(peak, v.abs());
    }
    expect(peak, closeTo(0.8, 1e-6));
    // Energy arrives in steps: 5 strings → the 5th starts 4 gaps (80 ms) in.
    double rmsAt(int ms) {
      final start = ms * sr ~/ 1000;
      var sum = 0.0;
      for (var i = start; i < start + 240; i++) {
        sum += pcm[i] * pcm[i];
      }
      return math.sqrt(sum / 240);
    }

    expect(rmsAt(1), greaterThan(0));
    expect(rmsAt(85), greaterThan(rmsAt(5)));
    expect(pcm.last, 0, reason: 'faded out, no click at the end');
  });

  test('all strings muted renders silence', () {
    final pcm = renderStrum(stringHz: List.filled(6, null), sampleRate: sr, seconds: 0.2);
    expect(pcm.every((v) => v == 0), isTrue);
  });

  /// Hann-windowed DFT magnitude of [x] at [hz] (any frequency, not a bin).
  double mag(Float32List x, double hz, {double from = 0, double seconds = 1}) {
    final a = (from * sr).round();
    final n = (seconds * sr).round();
    final w = 2 * math.pi * hz / sr;
    final coeff = 2 * math.cos(w);
    var s1 = 0.0;
    var s2 = 0.0;
    for (var i = 0; i < n; i++) {
      final hann = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
      final s0 = x[a + i] * hann + coeff * s1 - s2;
      s2 = s1;
      s1 = s0;
    }
    return math.sqrt(s1 * s1 + s2 * s2 - coeff * s1 * s2);
  }

  double db(double v) => 20 * math.log(v) / math.ln10;

  test('every string, open to the 12th fret, sounds its exact frequency', () {
    // Independent of the tuner's detector: the spectral peak, searched to
    // a tenth of a cent either side of the true pitch.
    for (var s = 0; s < 6; s++) {
      for (final f in [0, 1, 5, 12]) {
        final hz = pm.hz(Tuning.standard.noteAt(s, f));
        final one = List<double?>.filled(6, null)..[s] = hz;
        final pcm = renderStrum(stringHz: one, sampleRate: sr, seconds: 1.6);
        var best = 0.0;
        var bestCents = 99.0;
        for (var c = -2.0; c <= 2.0001; c += 0.1) {
          final m = mag(pcm, hz * math.pow(2, c / 1200), from: 0.3);
          if (m > best) {
            best = m;
            bestCents = c;
          }
        }
        expect(bestCents.abs(), lessThanOrEqualTo(0.15), reason: 'string ${6 - s} fret $f');
      }
    }
  });

  test('sounds like a guitar string, not noise: harmonics fall off, highs die first', () {
    final e2 = pm.hz(Note.parse('E2'));
    final low = renderStrum(stringHz: [e2], sampleRate: sr, seconds: 1.6);
    List<double> partials(Float32List x, double f0, double from) => [
      for (var h = 1; h <= 12; h++) db(mag(x, f0 * h, from: from, seconds: 0.2)),
    ];
    final attack = partials(low, e2, 0.02);
    final lowest = [attack[0], attack[1], attack[2]].reduce(math.max);
    // The first harmonics carry the note (a white-noise pluck is flat).
    expect(attack[1], greaterThan(lowest - 10));
    expect(attack[2], greaterThan(lowest - 12));
    expect(attack[11], lessThan(lowest - 12), reason: '12th harmonic well below');

    // A treble string loses its upper harmonics within a second; the
    // fundamental rings on.
    final e4 = pm.hz(Note.parse('E4'));
    final high = renderStrum(stringHz: [e4], sampleRate: sr, seconds: 1.6);
    final early = partials(high, e4, 0.02);
    final late = partials(high, e4, 1);
    expect((late[0] - late[5]) - (early[0] - early[5]), greaterThan(10));
  });
}
