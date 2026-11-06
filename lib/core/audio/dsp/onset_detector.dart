import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fretlight/core/audio/dsp/fft.dart';

/// Finds strum attacks in raw audio, to within ~10 ms.
///
/// The chord detector's window is ~85 ms: fine for naming a chord, far too
/// coarse to say whether a strum landed on the beat. And a strum over
/// strings that are still ringing hardly changes the overall level, so a
/// level detector misses it. What a new strum always does is add energy
/// at frequencies that were quieter a moment ago (each string the pick
/// hits starts its partials afresh): spectral flux, the sum of how much
/// every frequency band grew since the last frame (Bello et al., 2005).
///
/// Every ~5 ms (hop of 256 at 48 kHz) a 21 ms window is transformed and
/// each band's log magnitude is compared with its *highest* over the last
/// three frames, as in SuperFlux (Böck & Widmer, 2013): room noise makes
/// every band wobble frame to frame, but rarely past its own recent peak,
/// while a strum's fresh partials clear it easily. An onset is reported
/// when the flux rises well above its recent average.
/// The rest of that strum (the pick crossing six strings takes tens of
/// milliseconds) is ignored for `refractory`.
///
/// Pure Dart, ~190 small FFTs a second: cheap enough for the UI isolate.
final class OnsetDetector {
  OnsetDetector({
    required this.sampleRate,
    this.hop = 256,
    this.window = 1024,
    this.sensitivity = 2.2,
    this.minDb = -55,
    // A strum crosses six strings over 20-150 ms (slow strums, the speaker
    // of a test rig): all one onset. Still well under the fastest pattern
    // taught (eighths at 100 BPM, 300 ms apart).
    Duration refractory = const Duration(milliseconds: 160),
  }) : _fft = Fft(window),
       _hann = Float64List(window),
       _re = Float64List(window),
       _im = Float64List(window),
       _history = List.generate(_memory, (_) => Float64List(window ~/ 2)),
       _ring = Float64List(window),
       _refractoryHops = (refractory.inMicroseconds * 1e-6 * sampleRate / hop).ceil() {
    for (var i = 0; i < window; i++) {
      _hann[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (window - 1));
    }
    _maxBin = math.min(window ~/ 2 - 1, (8000 * window / sampleRate).floor());
  }

  final int sampleRate;
  final int hop;
  final int window;

  /// How many times its recent average the flux must reach.
  final double sensitivity;

  /// Quieter than this (window RMS) is never an onset; raise it from a
  /// room gate.
  double minDb;

  final Fft _fft;
  final Float64List _hann;
  final Float64List _re;
  final Float64List _im;

  /// The last few frames' log magnitudes, newest at [_newest].
  final List<Float64List> _history;
  static const _memory = 3;
  int _newest = 0;
  final Float64List _ring;
  final int _refractoryHops;
  late final int _maxBin;

  final List<double> _fluxHistory = [];
  int _written = 0;
  int _sinceHop = 0;
  int _sinceOnset = 1 << 30;
  bool _primed = false;

  void reset() {
    _fluxHistory.clear();
    _ring.fillRange(0, window, 0);
    for (final h in _history) {
      h.fillRange(0, h.length, 0);
    }
    _newest = 0;
    _written = 0;
    _sinceHop = 0;
    _sinceOnset = 1 << 30;
    _primed = false;
  }

  /// Feeds samples; returns the sample positions (counted from the first
  /// sample fed after [reset]) of any onsets found.
  List<int> push(Float32List samples) {
    final out = <int>[];
    for (final s in samples) {
      _ring[_written % window] = s;
      _written++;
      _sinceHop++;
      if (_sinceHop < hop || _written < window) continue;
      _sinceHop = 0;
      if (_frame()) out.add(_written - hop);
    }
    return out;
  }

  bool _frame() {
    var energy = 0.0;
    for (var i = 0; i < window; i++) {
      final v = _ring[(_written + i) % window];
      energy += v * v;
      _re[i] = v * _hann[i];
      _im[i] = 0;
    }
    _fft.transform(_re, _im);
    var flux = 0.0;
    final slot = (_newest + 1) % _memory;
    final current = _history[slot];
    for (var k = 2; k <= _maxBin; k++) {
      final mag = math.log(1 + 10 * math.sqrt(_re[k] * _re[k] + _im[k] * _im[k]));
      var recent = 0.0;
      for (final h in _history) {
        if (!identical(h, current) && h[k] > recent) recent = h[k];
      }
      final rise = mag - recent;
      if (rise > 0) flux += rise;
      current[k] = mag;
    }
    _newest = slot;
    _sinceOnset++;
    final wasPrimed = _primed;
    _primed = true;
    if (!wasPrimed) return false;

    final avg = _fluxHistory.isEmpty
        ? 0.0
        : _fluxHistory.reduce((a, b) => a + b) / _fluxHistory.length;
    _fluxHistory.add(flux);
    if (_fluxHistory.length > 12) _fluxHistory.removeAt(0);
    // Warm up first: with no history, whatever sound is there when
    // listening starts would look like an onset.
    if (_fluxHistory.length < _memory + 2) return false;

    final db = 10 * math.log(energy / window + 1e-12) / math.ln10;
    final onset =
        _sinceOnset >= _refractoryHops &&
        db >= minDb &&
        flux > sensitivity * avg &&
        // Absolute floor: a strum's attack measures ~70 here, a ringing
        // chord's wobble ~20 at most, a steady hum's window ripple ~4.
        flux > 10;
    if (onset) _sinceOnset = 0;
    return onset;
  }
}
