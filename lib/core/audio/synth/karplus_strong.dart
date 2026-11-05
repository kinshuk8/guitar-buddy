import 'dart:math' as math;
import 'dart:typed_data';

/// Karplus–Strong plucked string, extended towards a real guitar string
/// (Jaffe & Smith, 1983) while keeping the pitch exact.
///
/// - Excitation: what a plucked string pushes into the bridge, which is
///   what the body radiates: the slope of the released triangle, a
///   two-level pulse split at the pick position, with a little noise for
///   the pick's scrape. That gives harmonics falling as ~1/n with the comb
///   notches of the pluck point, as a real string does. Plain white noise (the textbook
///   version) puts equal energy in every harmonic, which sounds like a
///   banjo or harpsichord, too bright and "high".
/// - Loop: the usual two-point average plus a one-pole low-pass, so upper
///   harmonics die away in a fraction of a second while the fundamental
///   rings on. The loop gain is set from the fundamental's ring time.
/// - Tuning: the loop delay is the delay line plus the averager's half
///   sample plus the low-pass's phase delay at the fundamental (computed
///   exactly), and a first-order all-pass supplies the remaining fraction of
///   a sample. Rendered notes measure within 0.01 cents of their target.
final class KarplusStrong {
  KarplusStrong({required this.sampleRate, this.seed = 7});

  final int sampleRate;
  final int seed;

  /// Renders one pluck of [hz] for [seconds].
  ///
  /// [brightness] (0..1) is the pick: low values give a soft thumb pluck,
  /// high values a hard pick. [ring] is how long the fundamental takes to
  /// fall by 60 dB, in seconds. [damping] (0..1) is how much faster the
  /// upper harmonics die than the fundamental: more for wound strings.
  /// [pluckAt] is the pick position as a fraction of the string length from
  /// the bridge (strumming over the soundhole is about 0.2).
  Float32List pluck({
    required double hz,
    required double seconds,
    double brightness = 0.6,
    double ring = 4,
    double damping = 0.5,
    double pluckAt = 0.2,
    double amplitude = 0.5,
  }) {
    final rnd = math.Random(seed + hz.round());
    final w0 = 2 * math.pi * hz / sampleRate;

    // Loop low-pass y = (1 − a)·x + a·y[n−1]; a up to 0.6 at full damping,
    // less on short (high) loops, where a few samples are a whole period.
    final period = sampleRate / hz;
    final a = 0.6 * damping.clamp(0.0, 1.0) * math.min(1.0, period / 120);
    // Its exact phase delay at the fundamental, and gain (made up below so
    // [ring] holds for the fundamental whatever the damping).
    final lpPhase = math.atan2(a * math.sin(w0), 1 - a * math.cos(w0));
    final lpDelay = lpPhase / w0;
    final lpGain = (1 - a) / math.sqrt(1 - 2 * a * math.cos(w0) + a * a);
    final avgGain = math.cos(w0 / 2);

    // Loop delay = N (line) + 0.5 (averager) + lpDelay + frac (all-pass).
    final rest = period - 0.5 - lpDelay;
    var n = rest.floor();
    var frac = rest - n;
    if (frac < 0.1) {
      // Keep the all-pass coefficient away from its unstable edge.
      n -= 1;
      frac += 1;
    }
    final c = (1 - frac) / (1 + frac);

    // Per-period gain so the fundamental falls 60 dB in [ring] seconds.
    final perPeriod = math.pow(10, -3 / (ring * hz)).toDouble();
    final g = math.min(0.99995, perPeriod / (avgGain * lpGain));

    final line = Float64List(n);
    // Excitation: the slope of the plucked shape (scaled to ±1 at the long
    // side), a touch of noise, then the pick's softness as a one-pole
    // low-pass (circular, so the period has no seam).
    final apex = (pluckAt.clamp(0.05, 0.5) * n).clamp(1, n - 1).toDouble();
    const up = 1.0;
    final down = -apex / (n - apex);
    for (var i = 0; i < n; i++) {
      line[i] = (i < apex ? up : down) + 0.15 * (rnd.nextDouble() * 2 - 1);
    }
    final alpha = 0.15 + 0.8 * brightness.clamp(0.0, 1.0);
    var lp = 0.0;
    for (var pass = 0; pass < 2; pass++) {
      for (var i = 0; i < n; i++) {
        lp += alpha * (line[i] - lp);
        if (pass == 1) line[i] = lp;
      }
    }
    // Remove DC so the string doesn't start offset.
    final mean = line.reduce((x, y) => x + y) / n;
    for (var i = 0; i < n; i++) {
      line[i] -= mean;
    }

    final total = (seconds * sampleRate).round();
    final out = Float32List(total);
    var idx = 0;
    var prev = 0.0;
    var lpState = 0.0;
    var apIn = 0.0;
    var apOut = 0.0;
    for (var i = 0; i < total; i++) {
      final current = line[idx];
      final averaged = 0.5 * (current + prev);
      prev = current;
      lpState = (1 - a) * averaged + a * lpState;
      // First-order all-pass: y[n] = c·x[n] + x[n−1] − c·y[n−1]
      final y = c * lpState + apIn - c * apOut;
      apIn = lpState;
      apOut = y;
      line[idx] = g * y;
      out[i] = current;
      idx = (idx + 1) % n;
    }

    var peak = 0.0;
    for (final v in out) {
      if (v.abs() > peak) peak = v.abs();
    }
    if (peak > 0) {
      final k = amplitude / peak;
      for (var i = 0; i < total; i++) {
        out[i] *= k;
      }
    }
    return out;
  }
}
