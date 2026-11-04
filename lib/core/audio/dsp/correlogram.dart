import 'dart:typed_data';

import 'package:fretlight/core/audio/dsp/fft.dart';

/// Linear autocorrelation `r[τ] = Σ x[j]·x[j+τ]` and the matching energy
/// term `m[τ] = Σ (x[j]² + x[j+τ]²)` for lags 0..[maxLag].
///
/// Both YIN (`d = m − 2r`) and MPM (`nsdf = 2r / m`) are built from these,
/// so one O(N log N) pass serves either detector. The window is zero-padded
/// to 2N before the FFT so lags don't wrap around (circular correlation
/// would leak the window's end into its start). `m` comes from prefix sums
/// of squares. Design after khuur_pitch (MIT), reimplemented here.
final class Correlogram {
  Correlogram(this.windowSize, this.maxLag)
    : assert(maxLag < windowSize, 'maxLag must be shorter than the window'),
      r = Float64List(maxLag + 1),
      m = Float64List(maxLag + 1),
      _fft = Fft(2 * windowSize),
      _re = Float64List(2 * windowSize),
      _im = Float64List(2 * windowSize),
      _prefix = Float64List(windowSize + 1);

  final int windowSize;
  final int maxLag;
  final Float64List r;
  final Float64List m;

  final Fft _fft;
  final Float64List _re;
  final Float64List _im;
  final Float64List _prefix;

  void compute(Float32List window) {
    final n = windowSize;
    for (var j = 0; j < n; j++) {
      final v = window[j];
      _re[j] = v;
      _im[j] = 0;
      _prefix[j + 1] = _prefix[j] + v * v;
    }
    for (var j = n; j < 2 * n; j++) {
      _re[j] = 0;
      _im[j] = 0;
    }
    _fft.transform(_re, _im);
    // Power spectrum -> inverse FFT = autocorrelation (Wiener–Khinchin).
    for (var k = 0; k < 2 * n; k++) {
      _re[k] = _re[k] * _re[k] + _im[k] * _im[k];
      _im[k] = 0;
    }
    _fft.transform(_re, _im, inverse: true);
    final scale = 1 / (2 * n);
    final total = _prefix[n];
    for (var tau = 0; tau <= maxLag; tau++) {
      r[tau] = _re[tau] * scale;
      // Σ_{j<n−τ} x[j]² + Σ_{j≥τ} x[j]²
      m[tau] = _prefix[n - tau] + (total - _prefix[tau]);
    }
  }
}
