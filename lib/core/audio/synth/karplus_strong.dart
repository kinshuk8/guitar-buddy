import 'dart:math' as math;
import 'dart:typed_data';

/// Karplus–Strong plucked string with fractional-delay tuning.
///
/// The basic algorithm (noise burst → delay line → two-point average) can
/// only realise periods of whole samples plus the averager's half-sample
/// delay, so low E at 48 kHz would be off by up to ~1.5 cents and high notes
/// by far more. A first-order all-pass in the loop supplies the remaining
/// fraction of a sample (Jaffe & Smith, 1983), so the pitch is exact enough
/// to test a tuner against and to play chords in tune.
final class KarplusStrong {
  KarplusStrong({required this.sampleRate, this.seed = 7});

  final int sampleRate;
  final int seed;

  /// Renders one pluck of [hz] for [seconds].
  ///
  /// [brightness] (0..1) low-passes the initial excitation: low values give
  /// a thumb-like pluck, high values a pick. [decay] is the loop gain per
  /// period (closer to 1 = longer sustain).
  Float32List pluck({
    required double hz,
    required double seconds,
    double brightness = 0.6,
    double decay = 0.996,
    double amplitude = 0.5,
  }) {
    final rnd = math.Random(seed + hz.round());
    // Loop delay = N (delay line) + 0.5 (averager) + frac (all-pass).
    final period = sampleRate / hz;
    var n = (period - 0.5).floor();
    var frac = period - 0.5 - n;
    if (frac < 0.1) {
      // Keep the all-pass coefficient away from its unstable edge.
      n -= 1;
      frac += 1;
    }
    final c = (1 - frac) / (1 + frac);

    final line = Float64List(n);
    // Excitation: noise, smoothed by a one-pole low-pass for brightness.
    var lp = 0.0;
    final alpha = 0.15 + 0.85 * brightness;
    for (var i = 0; i < n; i++) {
      lp += alpha * ((rnd.nextDouble() * 2 - 1) - lp);
      line[i] = lp;
    }
    // Remove DC from the excitation so the string doesn't start offset.
    final mean = line.reduce((a, b) => a + b) / n;
    for (var i = 0; i < n; i++) {
      line[i] -= mean;
    }

    final total = (seconds * sampleRate).round();
    final out = Float32List(total);
    var idx = 0;
    var prev = 0.0;
    var apIn = 0.0;
    var apOut = 0.0;
    for (var i = 0; i < total; i++) {
      final current = line[idx];
      final averaged = decay * 0.5 * (current + prev);
      prev = current;
      // First-order all-pass: y[n] = c·x[n] + x[n−1] − c·y[n−1]
      final y = c * averaged + apIn - c * apOut;
      apIn = averaged;
      apOut = y;
      line[idx] = y;
      out[i] = current;
      idx = (idx + 1) % n;
    }

    var peak = 0.0;
    for (final v in out) {
      if (v.abs() > peak) peak = v.abs();
    }
    if (peak > 0) {
      final g = amplitude / peak;
      for (var i = 0; i < total; i++) {
        out[i] *= g;
      }
    }
    return out;
  }
}
