import 'dart:typed_data';

import 'package:fretlight/core/audio/dsp/chord_detector.dart';

/// Slides a [ChordDetector] across a PCM stream, one estimate per [hop].
/// Pure Dart; lives in the DSP isolate next to the pitch tracker.
final class ChordTracker {
  ChordTracker({required this.detector, int? hop})
    : hop = hop ?? detector.windowSize ~/ 4,
      _window = Float32List(detector.windowSize);

  final ChordDetector detector;
  final int hop;
  final Float32List _window;
  int _fill = 0;

  double hopSeconds(int sampleRate) => hop / sampleRate;

  List<ChordEstimate> push(Float32List samples) {
    final out = <ChordEstimate>[];
    var offset = 0;
    final size = _window.length;
    while (offset < samples.length) {
      final n = (size - _fill) < (samples.length - offset) ? size - _fill : samples.length - offset;
      _window.setRange(_fill, _fill + n, samples, offset);
      _fill += n;
      offset += n;
      if (_fill == size) {
        out.add(detector.detect(_window));
        _window.setRange(0, size - hop, _window, hop);
        _fill = size - hop;
      }
    }
    return out;
  }

  void reset() => _fill = 0;
}
