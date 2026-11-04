import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Where frets and strings sit on a horizontal fretboard.
///
/// Shared by the painters and by hit-testing so a tap always maps to the
/// string/fret that was drawn there. Nut on the left (right when
/// [leftHanded]); high E on top, as a player sees the neck looking down.
@immutable
final class FretboardGeometry {
  FretboardGeometry({
    required this.size,
    required this.stringCount,
    this.firstFret = 0,
    this.lastFret = 12,
    this.leftHanded = false,
    this.nutWidth = 10,
    this.openZone = 28,
  }) : assert(lastFret > firstFret, 'Need at least one fret');

  final Size size;
  final int stringCount;

  /// 0 shows the nut and open-string zone; >0 starts mid-neck.
  final int firstFret;
  final int lastFret;
  final bool leftHanded;
  final double nutWidth;

  /// Space left of the nut for open-string markers.
  final double openZone;

  bool get showsNut => firstFret == 0;

  double get _boardLeft => showsNut ? openZone + nutWidth : 0;
  double get _boardWidth => size.width - _boardLeft;

  /// Real fret spacing: fret n sits at 1 - 2^(-n/12) of the scale length,
  /// so frets narrow toward the body. Normalised to the visible window.
  late final List<double> _fretX = () {
    double raw(int n) => 1 - math.pow(2, -n / 12).toDouble();
    final start = raw(firstFret);
    final span = raw(lastFret) - start;
    return [
      for (var n = firstFret; n <= lastFret; n++)
        _boardLeft + (raw(n) - start) / span * _boardWidth,
    ];
  }();

  double _mirror(double x) => leftHanded ? size.width - x : x;

  /// X of the wire *ending* fret [n] (the nut's right edge for n == 0).
  double fretX(int n) => _mirror(_fretX[n - firstFret]);

  /// X centre of the space where fret [n] is pressed (open zone for 0).
  double fretCenterX(int n) {
    if (n == 0) return _mirror(openZone / 2);
    final right = _fretX[n - firstFret];
    final left = n - 1 >= firstFret ? _fretX[n - 1 - firstFret] : 0.0;
    return _mirror(left + (right - left) * 0.55); // fingers sit just behind the wire
  }

  double get _edgeInset => size.height * 0.08;

  /// Y of string [index] (0 = lowest-pitched, drawn at the bottom).
  double stringY(int index) {
    final usable = size.height - 2 * _edgeInset;
    final step = usable / (stringCount - 1);
    return size.height - _edgeInset - index * step;
  }

  double get boardStartX => _mirror(_boardLeft);
  double get boardEndX => _mirror(size.width);
  double get nutX => _mirror(openZone);

  /// String and fret under a point, or null when outside the board.
  ({int string, int fret})? hitTest(Offset p) {
    if (p.dx < 0 || p.dx > size.width || p.dy < 0 || p.dy > size.height) return null;
    var nearest = 0;
    for (var s = 1; s < stringCount; s++) {
      if ((stringY(s) - p.dy).abs() < (stringY(nearest) - p.dy).abs()) nearest = s;
    }
    final x = leftHanded ? size.width - p.dx : p.dx;
    if (showsNut && x < _boardLeft) return (string: nearest, fret: 0);
    for (var i = 1; i < _fretX.length; i++) {
      if (x <= _fretX[i]) return (string: nearest, fret: firstFret + i);
    }
    return (string: nearest, fret: lastFret);
  }

  static const singleInlays = {3, 5, 7, 9, 15, 17, 19, 21};
  static const doubleInlays = {12, 24};
}
