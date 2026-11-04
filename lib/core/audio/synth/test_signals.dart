import 'dart:math' as math;
import 'dart:typed_data';

/// Deterministic synthetic guitar-like signals for offline detector tests.
///
/// Real recordings are the final word (see `test/fixtures/wav/`), but these
/// cover the failure modes that matter and can be generated for any pitch:
/// a weak fundamental (phone mics roll off below ~150 Hz), inharmonic
/// partials (stiff strings), decay, and background noise.
abstract final class TestSignals {
  /// A plucked-string tone built from [partials] harmonics.
  ///
  /// * [fundamentalGainDb] attenuates partial 1 (−12 dB ≈ a phone mic on low E).
  /// * [inharmonicity] is the string stiffness B: partial n sits at
  ///   n·f0·√(1 + B·n²). Steel guitar strings are ~1e-5..1e-4.
  /// * [decaySeconds] is the amplitude time constant of the fundamental;
  ///   higher partials decay faster, as on a real string.
  static Float32List pluckedTone({
    required double hz,
    required int sampleRate,
    required double seconds,
    int partials = 12,
    double fundamentalGainDb = 0,
    double inharmonicity = 5e-5,
    double decaySeconds = 2.5,
    double amplitude = 0.4,
    double phaseSeed = 0,
  }) {
    final n = (seconds * sampleRate).round();
    final out = Float32List(n);
    final rnd = math.Random(phaseSeed.toInt() + hz.round());
    for (var k = 1; k <= partials; k++) {
      final f = k * hz * math.sqrt(1 + inharmonicity * k * k);
      if (f >= sampleRate / 2) break;
      // Plucked-string spectrum: roughly 1/k, with a mid-string pluck's
      // missing-ish even partials softened rather than removed.
      var gain = 1 / k;
      if (k == 1) gain *= math.pow(10, fundamentalGainDb / 20).toDouble();
      final tau = decaySeconds / (1 + 0.35 * (k - 1));
      final phase = rnd.nextDouble() * 2 * math.pi;
      final w = 2 * math.pi * f / sampleRate;
      for (var i = 0; i < n; i++) {
        out[i] += gain * math.exp(-i / (tau * sampleRate)) * math.sin(w * i + phase);
      }
    }
    _normalise(out, amplitude);
    return out;
  }

  /// A pure sine (for exactness checks of the math, not realism).
  static Float32List sine({
    required double hz,
    required int sampleRate,
    required double seconds,
    double amplitude = 0.5,
  }) {
    final n = (seconds * sampleRate).round();
    final w = 2 * math.pi * hz / sampleRate;
    return Float32List.fromList([for (var i = 0; i < n; i++) amplitude * math.sin(w * i)]);
  }

  /// Several tones summed (a strummed chord), each with its own delay.
  static Float32List mix(List<Float32List> parts, {double amplitude = 0.5}) {
    final n = parts.map((p) => p.length).reduce(math.max);
    final out = Float32List(n);
    for (final p in parts) {
      for (var i = 0; i < p.length; i++) {
        out[i] += p[i];
      }
    }
    _normalise(out, amplitude);
    return out;
  }

  /// Adds white noise so the signal-to-noise ratio is [snrDb] (by RMS).
  static Float32List withNoise(Float32List signal, double snrDb, {int seed = 1}) {
    final rnd = math.Random(seed);
    var e = 0.0;
    for (final v in signal) {
      e += v * v;
    }
    final signalRms = math.sqrt(e / signal.length);
    final noiseRms = signalRms / math.pow(10, snrDb / 20);
    // Uniform noise in [-a, a] has RMS a/√3.
    final a = noiseRms * math.sqrt(3);
    return Float32List.fromList([for (final v in signal) v + (rnd.nextDouble() * 2 - 1) * a]);
  }

  static Float32List silence(int sampleRate, double seconds) =>
      Float32List((seconds * sampleRate).round());

  static void _normalise(Float32List x, double peak) {
    var max = 0.0;
    for (final v in x) {
      if (v.abs() > max) max = v.abs();
    }
    if (max == 0) return;
    final g = peak / max;
    for (var i = 0; i < x.length; i++) {
      x[i] *= g;
    }
  }
}
