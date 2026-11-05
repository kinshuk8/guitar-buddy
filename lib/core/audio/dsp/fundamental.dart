import 'dart:math' as math;
import 'dart:typed_data';

/// Measures the frequency of the fundamental partial itself, near a pitch
/// a period detector found.
///
/// A period detector (MPM, YIN) locks onto the period of the whole
/// waveform. On a real steel string the partials are slightly sharp of
/// whole multiples (stiffness: f_n = n·f0·√(1 + B·n²)), so the waveform's
/// period comes out a few cents sharp of the fundamental, which is what a
/// strobe tuner tunes to and what the string's pitch is. This finds the
/// fundamental's own spectral peak: a windowed DTFT evaluated at any
/// frequency (Goertzel), a coarse search across the main lobe, then a fine
/// parabola on log magnitude, where the lobe top is very nearly parabolic.
///
/// The window is 4-term Blackman–Harris (sidelobes −92 dB): on low E the
/// 2nd harmonic, often louder than the fundamental, is only ~7 bins away,
/// and a Hann window's sidelobes let enough of it leak in to pull the
/// estimate by a cent.
final class FundamentalRefiner {
  FundamentalRefiner({required this.sampleRate, required this.windowSize})
    : _window = Float64List(windowSize) {
    for (var i = 0; i < windowSize; i++) {
      final x = 2 * math.pi * i / (windowSize - 1);
      _window[i] =
          0.35875 - 0.48829 * math.cos(x) + 0.14128 * math.cos(2 * x) - 0.01168 * math.cos(3 * x);
    }
  }

  final int sampleRate;
  final int windowSize;
  final Float64List _window;

  /// How weak the fundamental may be against the next two partials and
  /// still be trusted (a phone mic loses a lot of a low string's
  /// fundamental): −20 dB.
  static const _minShare = 0.1;

  /// The refined frequency, or null to keep [hz] (fundamental too weak, or
  /// its peak not where [hz] says).
  double? refine(Float32List window, double hz) {
    final bin = sampleRate / windowSize;
    // The main lobe is ±4 bins wide: the fundamental needs that much room.
    if (hz < 5 * bin || hz * 3 >= sampleRate / 2) return null;

    // Coarse: across ±1.5 bins in 0.5-bin steps.
    final coarse = 0.5 * bin;
    var bestK = 0;
    var best = -1.0;
    final m = <int, double>{};
    for (var k = -3; k <= 3; k++) {
      final v = _mag(window, hz + k * coarse);
      m[k] = v;
      if (v > best) {
        best = v;
        bestK = k;
      }
    }
    if (bestK.abs() == 3) return null; // peak outside the search: not ours
    var f = hz + bestK * coarse + coarse * _vertex(m[bestK - 1]!, best, m[bestK + 1]!);

    // Fine: a parabola over ±0.1 bins removes the coarse fit's bias.
    final fine = 0.1 * bin;
    final a = _mag(window, f - fine);
    final b = _mag(window, f);
    final c = _mag(window, f + fine);
    if (b < a || b < c) return null;
    f += fine * _vertex(a, b, c);

    final h = math.max(_mag(window, 2 * f), _mag(window, 3 * f));
    if (b < _minShare * h) return null;
    // Within a quarter tone of the period estimate, or it's another peak.
    if ((1200 * math.log(f / hz) / math.ln2).abs() > 50) return null;
    return f;
  }

  /// Vertex offset (−1..1) of a parabola through log magnitudes.
  static double _vertex(double a, double b, double c) {
    final la = math.log(a + 1e-30);
    final lb = math.log(b + 1e-30);
    final lc = math.log(c + 1e-30);
    final d = la - 2 * lb + lc;
    return d >= 0 ? 0 : (0.5 * (la - lc) / d).clamp(-1.0, 1.0);
  }

  double _mag(Float32List x, double hz) {
    final w = 2 * math.pi * hz / sampleRate;
    final coeff = 2 * math.cos(w);
    var s1 = 0.0;
    var s2 = 0.0;
    final n = math.min(windowSize, x.length);
    for (var i = 0; i < n; i++) {
      final s0 = x[i] * _window[i] + coeff * s1 - s2;
      s2 = s1;
      s1 = s0;
    }
    return math.sqrt(math.max(0, s1 * s1 + s2 * s2 - coeff * s1 * s2));
  }
}
