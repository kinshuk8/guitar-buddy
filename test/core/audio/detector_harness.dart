import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fretlight/core/audio/dsp/pitch_detector.dart';
import 'package:fretlight/core/audio/dsp/pitch_tracker.dart';

/// Result of running a detector over one signal.
final class DetectorScore {
  DetectorScore(this.label, this.expectedHz, this.errorsCents, this.frames);

  final String label;
  final double expectedHz;

  /// Cents error of each voiced frame after the attack.
  final List<double> errorsCents;

  /// Frames analysed after the attack (voiced or not).
  final int frames;

  double get detectionRate => frames == 0 ? 0 : errorsCents.length / frames;

  /// Frames more than 600 cents off: octave (or fifth/twelfth) errors.
  int get grossErrors => errorsCents.where((e) => e.abs() > 600).length;

  double get medianAbsError {
    final fine = errorsCents.where((e) => e.abs() <= 600).map((e) => e.abs()).toList()..sort();
    if (fine.isEmpty) return double.nan;
    return fine[fine.length ~/ 2];
  }

  double get maxAbsFineError {
    final fine = errorsCents.where((e) => e.abs() <= 600).map((e) => e.abs());
    return fine.isEmpty ? double.nan : fine.reduce(math.max);
  }
}

/// Runs [detector] over [signal] in 512-sample chunks (like a mic stream)
/// and scores frames that end after [skipSeconds] (the pluck transient,
/// where real strings are briefly sharp).
DetectorScore evaluate(
  String label,
  PitchDetector detector,
  Float32List signal, {
  required double expectedHz,
  required int sampleRate,
  double skipSeconds = 0.15,
}) {
  final hop = analysisGeometry(sampleRate).hop;
  final tracker = PitchTracker(detector: detector, hop: hop);
  final frames = <PitchFrame>[];
  for (var i = 0; i < signal.length; i += 512) {
    frames.addAll(
      tracker.push(Float32List.sublistView(signal, i, math.min(i + 512, signal.length))),
    );
  }
  final skip = (skipSeconds * sampleRate).round() + detector.windowSize;
  final scored = frames.where((f) => f.endSample >= skip).toList();
  final errors = [
    for (final f in scored)
      if (f.hz != null) 1200 * math.log(f.hz! / expectedHz) / math.ln2,
  ];
  return DetectorScore(label, expectedHz, errors, scored.length);
}

String formatReport(String title, List<DetectorScore> rows) {
  final b = StringBuffer()
    ..writeln()
    ..writeln('== $title ==')
    ..writeln(
      '${'case'.padRight(34)}${'detect'.padLeft(8)}${'median¢'.padLeft(9)}${'max¢'.padLeft(8)}${'gross'.padLeft(7)}',
    );
  for (final r in rows) {
    b.writeln(
      '${r.label.padRight(34)}'
      '${'${(r.detectionRate * 100).toStringAsFixed(0)}%'.padLeft(8)}'
      '${r.medianAbsError.toStringAsFixed(2).padLeft(9)}'
      '${r.maxAbsFineError.toStringAsFixed(2).padLeft(8)}'
      '${r.grossErrors.toString().padLeft(7)}',
    );
  }
  final gross = rows.fold<int>(0, (a, r) => a + r.grossErrors);
  final frames = rows.fold<int>(0, (a, r) => a + r.errorsCents.length);
  b.writeln('total voiced frames: $frames, gross (octave) errors: $gross');
  return b.toString();
}
