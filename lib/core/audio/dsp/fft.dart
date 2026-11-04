import 'dart:math' as math;
import 'dart:typed_data';

/// In-place iterative radix-2 complex FFT with precomputed twiddles and
/// bit-reversal table. Sized once, reused every frame: no allocation in the
/// hot path.
final class Fft {
  Fft(this.size)
    : assert(size > 1 && (size & (size - 1)) == 0, 'FFT size must be a power of two'),
      _cos = Float64List(size ~/ 2),
      _sin = Float64List(size ~/ 2),
      _rev = Int32List(size) {
    for (var i = 0; i < size ~/ 2; i++) {
      final a = -2 * math.pi * i / size;
      _cos[i] = math.cos(a);
      _sin[i] = math.sin(a);
    }
    final bits = (math.log(size) / math.ln2).round();
    for (var i = 0; i < size; i++) {
      var r = 0;
      for (var b = 0; b < bits; b++) {
        r |= ((i >> b) & 1) << (bits - 1 - b);
      }
      _rev[i] = r;
    }
  }

  final int size;
  final Float64List _cos;
  final Float64List _sin;
  final Int32List _rev;

  /// Forward transform of ([re], [im]) in place. [inverse] computes the
  /// unscaled inverse (caller divides by [size]).
  void transform(Float64List re, Float64List im, {bool inverse = false}) {
    final n = size;
    for (var i = 0; i < n; i++) {
      final j = _rev[i];
      if (j > i) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    final sign = inverse ? -1.0 : 1.0;
    for (var len = 2; len <= n; len <<= 1) {
      final half = len >> 1;
      final step = n ~/ len;
      for (var start = 0; start < n; start += len) {
        for (var k = 0; k < half; k++) {
          final wr = _cos[k * step];
          final wi = sign * _sin[k * step];
          final a = start + k;
          final b = a + half;
          final xr = re[b] * wr - im[b] * wi;
          final xi = re[b] * wi + im[b] * wr;
          re[b] = re[a] - xr;
          im[b] = im[a] - xi;
          re[a] += xr;
          im[a] += xi;
        }
      }
    }
  }
}
