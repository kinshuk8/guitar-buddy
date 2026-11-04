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
}
