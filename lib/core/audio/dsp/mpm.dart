import 'dart:typed_data';

import 'package:fretlight/core/audio/dsp/correlogram.dart';
import 'package:fretlight/core/audio/dsp/pitch_detector.dart';

/// McLeod Pitch Method (McLeod & Wyvill, 2005) on an FFT correlogram.
///
/// NSDF n(τ) = 2r(τ)/m(τ) lies in [−1, 1]. Between each positive-going and
/// negative-going zero crossing take the highest peak ("key maximum"); the
/// period is the first key maximum within [cutoff] of the tallest one. The
/// cutoff is what stops MPM choosing a sub-harmonic (octave-low) peak.
final class MpmDetector implements PitchDetector {
  MpmDetector({
    required this.sampleRate,
    required this.windowSize,
    this.minHz = 60,
    this.maxHz = 1400,
    this.cutoff = 0.93,
    this.minClarity = 0.5,
  }) : _correlogram = Correlogram(windowSize, (sampleRate / minHz).ceil() + 1),
       _nsdf = Float64List((sampleRate / minHz).ceil() + 2);

  final int sampleRate;
  @override
  final int windowSize;
  final double minHz;
  final double maxHz;
  final double cutoff;
  final double minClarity;

  final Correlogram _correlogram;
  final Float64List _nsdf;
  final List<int> _keyMaxima = [];

  @override
  PitchEstimate? detect(Float32List window) {
    _correlogram.compute(window);
    final r = _correlogram.r;
    final m = _correlogram.m;
    final maxLag = _correlogram.maxLag;
    final n = _nsdf;
    for (var tau = 0; tau <= maxLag; tau++) {
      n[tau] = m[tau] > 0 ? 2 * r[tau] / m[tau] : 0;
    }

    _keyMaxima.clear();
    var tau = 1;
    // Skip the lag-0 lobe.
    while (tau < maxLag && n[tau] > 0) {
      tau++;
    }
    while (tau < maxLag) {
      while (tau < maxLag && n[tau] <= 0) {
        tau++;
      }
      if (tau >= maxLag) break;
      var best = tau;
      while (tau < maxLag && n[tau] > 0) {
        if (n[tau] > n[best]) best = tau;
        tau++;
      }
      // An unfinished lobe at the edge of the search range is not a period.
      if (tau < maxLag) _keyMaxima.add(best);
    }
    if (_keyMaxima.isEmpty) return null;

    var highest = 0.0;
    for (final k in _keyMaxima) {
      if (n[k] > highest) highest = n[k];
    }
    if (highest < minClarity) return null;
    final threshold = cutoff * highest;
    final chosen = _keyMaxima.firstWhere((k) => n[k] >= threshold);
    final (lag, value) = parabolicVertex(n, chosen);
    final hz = sampleRate / lag;
    if (hz < minHz || hz > maxHz) return null;
    return PitchEstimate(hz, value.clamp(0.0, 1.0));
  }
}
