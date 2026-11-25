import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/audio/dsp/chord_detector.dart';
import 'package:fretlight/core/audio/dsp/chord_tracker.dart';
import 'package:fretlight/core/audio/listening.dart';
import 'package:fretlight/core/audio/synth/strum.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/features/identify/domain/chord_smoother.dart';
import 'package:fretlight/features/practice/domain/practice_session.dart';

import 'practice_tolerance_test.dart' show band;

const sr = 48000;
const pm = PitchMath();

/// A bright steel-string acoustic, built partial by partial: strummed
/// [pick] of the way from the bridge (each partial scaled by
/// |sin(pi n pick)|), upper partials falling off as 1/n^[tilt], decaying
/// faster the higher they are, and slightly sharp up the series (stiff
/// steel). Unlike the plucked-string synth, the wound low strings keep their
/// upper harmonics: an open E's 5th harmonic, a G#, rings clearly. Then a
/// phone mic's bass roll-off at [lowCut] Hz.
Float32List brightSteel(
  List<int?> frets, {
  required double pick,
  required double tilt,
  required double lowCut,
}) {
  final rnd = math.Random(1);
  final n = (2.2 * sr).round();
  final out = Float32List(n);
  var step = 0;
  for (var s = 0; s < 6; s++) {
    final f = frets[s];
    if (f == null) continue;
    final f0 = pm.hz(Tuning.standard.noteAt(s, f));
    final stiffness = s < 3 ? 6e-5 : 1.5e-4;
    final at = step * 22 * sr ~/ 1000;
    step++;
    final p = pick + (rnd.nextDouble() - 0.5) * 0.04;
    final amp = 0.5 * (1 - 0.05 * step);
    for (var k = 1; k * f0 < 7000; k++) {
      final fk = k * f0 * math.sqrt(1 + stiffness * k * k);
      final a = amp * math.sin(math.pi * k * p).abs() / math.pow(k, tilt);
      final tau = 3.0 / (1 + fk / 600);
      final phase = rnd.nextDouble() * 2 * math.pi;
      final w = 2 * math.pi * fk / sr;
      for (var i = 0; i + at < n; i++) {
        out[i + at] += a * math.exp(-i / (tau * sr)) * math.sin(w * i + phase);
      }
    }
  }
  GuitarBody(sr).apply(out);
  var x = out;
  if (lowCut > 0) x = band(band(x, lowCut, high: true), lowCut, high: true);
  var peak = 0.0;
  for (final v in x) {
    peak = math.max(peak, v.abs());
  }
  for (var i = 0; i < x.length; i++) {
    x[i] *= 0.5 / peak;
  }
  return x;
}

/// The first verdict practice reaches on one strum (null: not judged).
Verdict? judgeStrum(Float32List pcm, Chord target) {
  final tracker = ChordTracker(detector: ChromaChordDetector(sampleRate: sr));
  final hop = tracker.hopSeconds(sr);
  final sm = ChordSmoother(hopSeconds: hop, floor: NoiseFloor(marginDb: 10, frameSeconds: hop));
  final session = PracticeSession([target]);
  for (final e in tracker.push(Float32List.fromList([...Float32List(sr ~/ 2), ...pcm]))) {
    final r = sm.update(e);
    if (r == null) continue;
    final v = session.hear(r);
    if (v != null) return v;
  }
  return null;
}

const shapes = <String, List<int?>>{
  'E': [0, 2, 2, 1, 0, 0],
  'Em': [0, 2, 2, 0, 0, 0],
  'A': [null, 0, 2, 2, 2, 0],
  'Am': [null, 0, 2, 2, 1, 0],
  'D': [null, null, 0, 2, 3, 2],
  'Dm': [null, null, 0, 2, 3, 1],
  'G': [3, 2, 0, 0, 0, 3],
  'C': [null, 3, 2, 0, 1, 0],
};

/// Where the pick crosses the strings, how bright they are, and how much
/// bass the mic loses: 5 × 3 × 3 ways to strum.
final List<({double pick, double tilt, double lowCut})> ways = [
  for (final pick in [0.12, 0.2, 0.25, 0.3, 0.35])
    for (final tilt in [0.6, 0.9, 1.3])
      for (final lowCut in [0.0, 120.0, 250.0]) (pick: pick, tilt: tilt, lowCut: lowCut),
];

void main() {
  test('a bright steel-string acoustic: the chord played is counted', () {
    final missed = <String>[];
    var total = 0;
    for (final MapEntry(key: name, value: frets) in shapes.entries) {
      for (final w in ways) {
        total++;
        final pcm = brightSteel(frets, pick: w.pick, tilt: w.tilt, lowCut: w.lowCut);
        final v = judgeStrum(pcm, Chord.parse(name));
        if (v != Verdict.hit && v != Verdict.close) missed.add('$name $w: ${v?.name}');
      }
    }
    if (Platform.environment['REPORT'] != null) {
      // A report, on request.
      // ignore: avoid_print
      print('counted ${total - missed.length}/$total; missed:\n${missed.join('\n')}');
    }
    // Before overtones were told apart from notes, a third of E and Em
    // strums (and a fifth of A, G and C) on this guitar weren't counted.
    expect(missed.length / total, lessThanOrEqualTo(0.03), reason: missed.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('a bright steel-string acoustic: the other third is not counted', () {
    const pairs = [('E', 'Em'), ('Em', 'E'), ('A', 'Am'), ('Am', 'A'), ('D', 'Dm'), ('Dm', 'D')];
    final passed = <String>[];
    var total = 0;
    for (final (want, played) in pairs) {
      for (final w in ways) {
        total++;
        final pcm = brightSteel(shapes[played]!, pick: w.pick, tilt: w.tilt, lowCut: w.lowCut);
        final v = judgeStrum(pcm, Chord.parse(want));
        if (v == Verdict.hit || v == Verdict.close) passed.add('asked $want, played $played $w');
      }
    }
    if (Platform.environment['REPORT'] != null) {
      // A report, on request.
      // ignore: avoid_print
      print('wrongly counted ${passed.length}/$total:\n${passed.join('\n')}');
    }
    // Before, an Em could be named E outright on this guitar (its low E
    // strings ring a G# about as loud as its G), and a Dm named D.
    expect(passed.length / total, lessThanOrEqualTo(0.02), reason: passed.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
