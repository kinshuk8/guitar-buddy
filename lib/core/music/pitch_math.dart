import 'dart:math' as math;

import 'package:fretlight/core/music/pitch.dart';

/// Equal-temperament frequency math against an adjustable A4 reference.
class PitchMath {
  const PitchMath({this.a4 = defaultA4});

  static const double defaultA4 = 440;

  /// Range the reference-pitch setting allows. 415 covers baroque pitch;
  /// 466 is a half step above 440.
  static const double minA4 = 415;
  static const double maxA4 = 466;

  final double a4;

  /// Frequency of [note] in Hz.
  double hz(Note note) => a4 * math.pow(2, (note.midi - 69) / 12).toDouble();

  /// Fractional MIDI number for a frequency (69.5 = a quarter tone above A4).
  double midiFloat(double hz) => 69 + 12 * _log2(hz / a4);

  /// The nearest equal-tempered note to [hz].
  Note nearest(double hz) => Note(midiFloat(hz).round());

  /// Signed distance in cents from [targetHz] to [hz]. Positive = sharp.
  static double cents(double hz, double targetHz) => 1200 * _log2(hz / targetHz);

  /// Cents relative to a target note.
  double centsFrom(double hz, Note target) => cents(hz, this.hz(target));

  /// Nearest note and the cents offset from it in one call.
  ({Note note, double cents}) analyse(double hz) {
    final note = nearest(hz);
    return (note: note, cents: centsFrom(hz, note));
  }

  static double _log2(double x) => math.log(x) / math.ln2;
}
