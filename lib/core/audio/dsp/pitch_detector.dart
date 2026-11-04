import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// A pitch estimate for one analysis window.
@immutable
final class PitchEstimate {
  const PitchEstimate(this.hz, this.clarity);

  final double hz;

  /// Periodicity confidence in 0..1 (1 = perfectly periodic).
  final double clarity;

  @override
  String toString() =>
      'PitchEstimate(${hz.toStringAsFixed(2)} Hz, clarity ${clarity.toStringAsFixed(2)})';
}

/// Detects the fundamental of a single monophonic note in one window.
///
/// Implementations are swappable (YIN, MPM, or a package under evaluation)
/// and must be pure Dart so they can run in the DSP isolate.
abstract interface class PitchDetector {
  int get windowSize;

  /// Returns null when the window has no clear pitch in range.
  PitchEstimate? detect(Float32List window);
}

/// Window and hop for a sample rate.
///
/// The window must hold several periods of the lowest note for a stable
/// cents reading: low E (82.41 Hz) at 48 kHz is 582 samples per period, so
/// 4096 samples (85 ms) holds ~7 periods. Shorter windows (2048) detect low E
/// but jitter by several cents; longer ones (8192) are steadier but lag the
/// needle by ~170 ms. Hop is a quarter window: ~47 updates/s at 48 kHz.
({int window, int hop}) analysisGeometry(int sampleRate) {
  var window = 1024;
  while (window < sampleRate * 0.08) {
    window *= 2;
  }
  return (window: window, hop: window ~/ 4);
}

/// Refines a discrete extremum at [i] by fitting a parabola through its
/// neighbours. Returns (position, value) of the vertex.
(double, double) parabolicVertex(Float64List y, int i) {
  if (i <= 0 || i >= y.length - 1) return (i.toDouble(), y[i]);
  final a = y[i - 1];
  final b = y[i];
  final c = y[i + 1];
  final denom = a - 2 * b + c;
  if (denom == 0) return (i.toDouble(), b);
  final offset = 0.5 * (a - c) / denom;
  return (i + offset, b - 0.25 * (a - c) * offset);
}

/// RMS level of [x] in dBFS, floored at -120.
double rmsDb(Float32List x) {
  var e = 0.0;
  for (final v in x) {
    e += v * v;
  }
  final rms = math.sqrt(e / x.length);
  return rms <= 1e-6 ? -120 : 20 * math.log(rms) / math.ln10;
}
