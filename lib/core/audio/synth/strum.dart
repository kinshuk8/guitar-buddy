import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fretlight/core/audio/synth/karplus_strong.dart';

/// Renders a strummed (or single) set of plucked strings to mono PCM.
///
/// [stringHz] is per string, lowest first; null = muted. Strings start
/// [gap] apart in strum order, which is what makes it sound strummed rather
/// than like a piano chord. Lower (wound) strings ring longer and lose
/// their upper harmonics faster, as on a real guitar; the sum then goes
/// through [GuitarBody], whose resonances give the low-mid warmth a bare
/// string lacks.
Float32List renderStrum({
  required List<double?> stringHz,
  required int sampleRate,
  Duration gap = const Duration(milliseconds: 22),
  double seconds = 2.6,
  bool down = true,
  double peak = 0.8,
}) {
  // [peak] <= 0 leaves the level as synthesised (for comparing strings).
  final total = (seconds * sampleRate).round();
  final out = Float32List(total);
  final order = [
    for (var i = 0; i < stringHz.length; i++)
      if (stringHz[i] != null) i,
  ];
  if (!down) order.setAll(0, order.reversed.toList());
  final gapSamples = (gap.inMicroseconds * sampleRate / 1e6).round();
  final synth = KarplusStrong(sampleRate: sampleRate);

  for (final (step, s) in order.indexed) {
    final hz = stringHz[s]!;
    final start = step * gapSamples;
    if (start >= total) break;
    final low = s / math.max(1, stringHz.length - 1); // 0 = lowest string
    final tone = synth.pluck(
      hz: hz,
      seconds: (total - start) / sampleRate,
      brightness: 0.45 + 0.2 * low,
      ring: 6 - 2.5 * low,
      damping: 0.8 - 0.5 * low,
      // A strum crosses the strings at slightly different points.
      pluckAt: 0.17 + 0.07 * low,
      // Later strings in a strum are hit a touch softer.
      amplitude: 0.5 * (1 - 0.05 * step),
    );
    for (var i = 0; i < tone.length && start + i < total; i++) {
      out[start + i] += tone[i];
    }
  }

  GuitarBody(sampleRate).apply(out);

  // Short fade-out so the buffer never ends on a click.
  final fade = math.min(total, (0.12 * sampleRate).round());
  for (var i = 0; i < fade; i++) {
    out[total - fade + i] *= 1 - (i + 1) / fade; // last sample exactly 0
  }
  var max = 0.0;
  for (final v in out) {
    if (v.abs() > max) max = v.abs();
  }
  if (max > 0 && peak > 0) {
    final g = peak / max;
    for (var i = 0; i < total; i++) {
      out[i] *= g;
    }
  }
  return out;
}

/// A guitar body as a few resonances added to the string sound, plus a
/// gentle top-end roll-off. The modes are typical of a steel-string
/// acoustic: the air in the body (Helmholtz, ~100 Hz), the top plate
/// (~200 Hz) and a higher plate/air mode (~400 Hz). It is linear and
/// time-invariant, so it colours the tone without moving any pitch.
final class GuitarBody {
  GuitarBody(this.sampleRate);

  final int sampleRate;

  static const List<({double hz, double q, double gain})> _modes = [
    (hz: 102.0, q: 9.0, gain: 0.5),
    (hz: 204.0, q: 8.0, gain: 0.7),
    (hz: 410.0, q: 5.0, gain: 0.35),
  ];

  void apply(Float32List x) {
    final wet = Float64List(x.length);
    for (final m in _modes) {
      // RBJ band-pass, 0 dB peak.
      final w = 2 * math.pi * m.hz / sampleRate;
      final alpha = math.sin(w) / (2 * m.q);
      final a0 = 1 + alpha;
      final b0 = alpha / a0;
      final b2 = -alpha / a0;
      final a1 = -2 * math.cos(w) / a0;
      final a2 = (1 - alpha) / a0;
      var x1 = 0.0;
      var x2 = 0.0;
      var y1 = 0.0;
      var y2 = 0.0;
      for (var i = 0; i < x.length; i++) {
        final xi = x[i];
        final y = b0 * xi + b2 * x2 - a1 * y1 - a2 * y2;
        x2 = x1;
        x1 = xi;
        y2 = y1;
        y1 = y;
        wet[i] += m.gain * y;
      }
    }
    // One-pole low-pass at ~6 kHz on the dry string: takes the wire edge
    // off without dulling the pick.
    final k = 1 - math.exp(-2 * math.pi * 6000 / sampleRate);
    var lp = 0.0;
    for (var i = 0; i < x.length; i++) {
      lp += k * (x[i] - lp);
      x[i] = lp + wet[i];
    }
  }
}
