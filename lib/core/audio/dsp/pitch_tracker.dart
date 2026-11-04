import 'dart:typed_data';

import 'package:fretlight/core/audio/dsp/pitch_detector.dart';
import 'package:meta/meta.dart';

/// Analysis result for one window.
@immutable
final class PitchFrame {
  const PitchFrame({
    required this.endSample,
    required this.hz,
    required this.clarity,
    required this.rmsDb,
  });

  /// Sample index (since capture start) of the window's last sample.
  /// Counted from the audio itself, so timing survives UI jank.
  final int endSample;

  /// Null when the window had no clear pitch.
  final double? hz;
  final double clarity;
  final double rmsDb;
}

/// Turns arbitrarily-chunked mono PCM into overlapping analysis windows and
/// runs a [PitchDetector] on each. Pure Dart; lives in the DSP isolate.
final class PitchTracker {
  PitchTracker({required this.detector, required this.hop, this.silenceDb = -60})
    : _window = Float32List(detector.windowSize);

  final PitchDetector detector;
  final int hop;

  /// Windows quieter than this skip detection entirely (saves CPU, and
  /// noise-floor "pitches" never reach the UI).
  final double silenceDb;

  final Float32List _window;
  int _fill = 0;
  int _consumed = 0;

  /// Feeds samples; returns one frame per completed hop.
  List<PitchFrame> push(Float32List samples) {
    final frames = <PitchFrame>[];
    var offset = 0;
    final size = _window.length;
    while (offset < samples.length) {
      final n = (size - _fill) < (samples.length - offset) ? size - _fill : samples.length - offset;
      _window.setRange(_fill, _fill + n, samples, offset);
      _fill += n;
      offset += n;
      _consumed += n;
      if (_fill == size) {
        frames.add(_analyse());
        // Slide by one hop.
        _window.setRange(0, size - hop, _window, hop);
        _fill = size - hop;
      }
    }
    return frames;
  }

  void reset() {
    _fill = 0;
    _consumed = 0;
  }

  PitchFrame _analyse() {
    final level = rmsDb(_window);
    if (level < silenceDb) {
      return PitchFrame(endSample: _consumed, hz: null, clarity: 0, rmsDb: level);
    }
    final estimate = detector.detect(_window);
    return PitchFrame(
      endSample: _consumed,
      hz: estimate?.hz,
      clarity: estimate?.clarity ?? 0,
      rmsDb: level,
    );
  }
}
