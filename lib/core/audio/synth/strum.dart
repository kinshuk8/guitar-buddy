import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fretlight/core/audio/synth/karplus_strong.dart';

/// Renders a strummed (or single) set of plucked strings to mono PCM.
///
/// [stringHz] is per string, lowest first; null = muted. Strings start
/// [gap] apart in strum order, which is what makes it sound strummed rather
/// than like a piano chord. Lower strings get a slightly softer, longer
/// pluck, as from a thumb or the wound strings of a real guitar.
Float32List renderStrum({
  required List<double?> stringHz,
  required int sampleRate,
  Duration gap = const Duration(milliseconds: 22),
  double seconds = 2.6,
  bool down = true,
  double peak = 0.8,
}) {
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
      brightness: 0.45 + 0.3 * low,
      decay: 0.9965 - 0.0015 * low,
      // Later strings in a strum are hit a touch softer.
      amplitude: 0.5 * (1 - 0.05 * step),
    );
    for (var i = 0; i < tone.length && start + i < total; i++) {
      out[start + i] += tone[i];
    }
  }

  // Short fade-out so the buffer never ends on a click.
  final fade = math.min(total, (0.12 * sampleRate).round());
  for (var i = 0; i < fade; i++) {
    out[total - fade + i] *= 1 - (i + 1) / fade; // last sample exactly 0
  }
  var max = 0.0;
  for (final v in out) {
    if (v.abs() > max) max = v.abs();
  }
  if (max > 0) {
    final g = peak / max;
    for (var i = 0; i < total; i++) {
      out[i] *= g;
    }
  }
  return out;
}
