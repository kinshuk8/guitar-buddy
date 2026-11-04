import 'dart:typed_data';

import 'package:fretlight/core/audio/dsp/correlogram.dart';
import 'package:fretlight/core/audio/dsp/pitch_detector.dart';

/// YIN (de Cheveigné & Kawahara, 2002) on an FFT correlogram.
///
/// Steps: difference function d(τ) = m(τ) − 2r(τ); cumulative-mean
/// normalisation d′; first dip below [threshold], descended to its local
/// minimum; parabolic interpolation for sub-sample period accuracy.
///
/// The search starts at the shortest lag, not at the lag of [maxHz]: a tone
/// above maxHz also dips at twice its period, and skipping its first dip
/// would report it an octave low. Found first, it is out of range → null.
final class YinDetector implements PitchDetector {
  YinDetector({
    required this.sampleRate,
    required this.windowSize,
    this.minHz = 60,
    this.maxHz = 1400,
    this.threshold = 0.15,
  }) : _maxLag = (sampleRate / minHz).ceil(),
       _correlogram = Correlogram(windowSize, (sampleRate / minHz).ceil() + 1),
       _cmnd = Float64List((sampleRate / minHz).ceil() + 2);

  final int sampleRate;
  @override
  final int windowSize;
  final double minHz;
  final double maxHz;
  final double threshold;

  final int _maxLag;
  final Correlogram _correlogram;
  final Float64List _cmnd;

  @override
  PitchEstimate? detect(Float32List window) {
    _correlogram.compute(window);
    final r = _correlogram.r;
    final m = _correlogram.m;
    final searchLag = _correlogram.maxLag;
    final cmnd = _cmnd;

    cmnd[0] = 1;
    var running = 0.0;
    for (var tau = 1; tau <= searchLag; tau++) {
      final d = m[tau] - 2 * r[tau];
      running += d;
      cmnd[tau] = running > 0 ? d * tau / running : 1;
    }

    var tau = 2;
    while (tau <= _maxLag && cmnd[tau] >= threshold) {
      tau++;
    }
    if (tau > _maxLag) return null;
    tau = _descend(tau, _maxLag);

    final (lag, depth) = parabolicVertex(cmnd, tau);
    final hz = sampleRate / lag;
    if (hz < minHz || hz > maxHz) return null;
    return PitchEstimate(hz, (1 - depth).clamp(0.0, 1.0));
  }

  int _descend(int tau, int limit) {
    var t = tau;
    while (t < limit && _cmnd[t + 1] < _cmnd[t]) {
      t++;
    }
    return t;
  }
}
