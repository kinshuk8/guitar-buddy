import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fretlight/core/audio/synth/karplus_strong.dart';

/// How one guitar differs from another: tests use these to check that
/// listening holds up on more than one instrument.
final class GuitarVoice {
  const GuitarVoice(
    this.name, {
    this.brightness = 0,
    this.ring = 1,
    this.damping = 0,
    this.body = true,
  });

  final String name;

  /// Added to each string's brightness (pick attack and upper harmonics).
  final double brightness;

  /// Scales how long strings ring.
  final double ring;

  /// Added to each string's loop damping: how fast the highs die away.
  final double damping;

  /// Through the acoustic body's resonances, or straight from the strings.
  final bool body;

  /// A steel-string acoustic: what the app plays.
  static const steel = GuitarVoice('steel');

  /// New strings, a bright guitar.
  static const bright = GuitarVoice('bright', brightness: 0.25, damping: -0.3, ring: 1.2);

  /// A classical guitar: soft attack, warm, shorter sustain.
  static const nylon = GuitarVoice('nylon', brightness: -0.25, damping: 0.2, ring: 0.7);

  /// Old, dull strings: little top end and a quick decay.
  static const dull = GuitarVoice('old strings', brightness: -0.3, damping: 0.3, ring: 0.45);

  /// A thin, bodiless tone (an electric unplugged, a small travel guitar).
  static const thin = GuitarVoice('thin', brightness: 0.1, body: false, ring: 0.8);

  static const List<GuitarVoice> all = [steel, bright, nylon, dull, thin];
}

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
  GuitarVoice voice = GuitarVoice.steel,
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
      brightness: (0.45 + 0.2 * low + voice.brightness).clamp(0.05, 1.0),
      ring: (6 - 2.5 * low) * voice.ring,
      damping: (0.8 - 0.5 * low + voice.damping).clamp(0.0, 1.0),
      // A strum crosses the strings at slightly different points.
      pluckAt: 0.17 + 0.07 * low,
      // Later strings in a strum are hit a touch softer.
      amplitude: 0.5 * (1 - 0.05 * step),
    );
    for (var i = 0; i < tone.length && start + i < total; i++) {
      out[start + i] += tone[i];
    }
  }

  if (voice.body) GuitarBody(sampleRate).apply(out);

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
