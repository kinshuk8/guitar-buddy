import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/painting/fretboard_geometry.dart';

void main() {
  FretboardGeometry geometry({bool leftHanded = false, int first = 0, int last = 12}) =>
      FretboardGeometry(
        size: const Size(800, 200),
        stringCount: 6,
        firstFret: first,
        lastFret: last,
        leftHanded: leftHanded,
      );

  test('frets get narrower toward the body, like a real neck', () {
    final g = geometry();
    var previous = double.infinity;
    for (var n = 1; n <= 12; n++) {
      final width = g.fretX(n) - g.fretX(n - 1);
      expect(width, lessThan(previous), reason: 'fret $n');
      previous = width;
    }
    // Fret 12 is half the scale; fret 1 is ~1.89x wider than fret 12.
    expect((g.fretX(1) - g.fretX(0)) / (g.fretX(12) - g.fretX(11)), closeTo(1.888, 0.01));
  });

  test('low string at the bottom, high string at the top', () {
    final g = geometry();
    expect(g.stringY(0), greaterThan(g.stringY(5)));
  });

  test('hit test round-trips every drawn position', () {
    for (final lefty in [false, true]) {
      final g = geometry(leftHanded: lefty);
      for (var s = 0; s < 6; s++) {
        for (var f = 0; f <= 12; f++) {
          final hit = g.hitTest(Offset(g.fretCenterX(f), g.stringY(s)));
          expect(hit, (string: s, fret: f), reason: 'lefty=$lefty s=$s f=$f');
        }
      }
    }
  });

  test('left-handed mirrors horizontally', () {
    final right = geometry();
    final left = geometry(leftHanded: true);
    expect(left.fretX(5), closeTo(800 - right.fretX(5), 1e-9));
  });

  test('mid-neck windows have no nut', () {
    final g = geometry(first: 5, last: 9);
    expect(g.showsNut, isFalse);
    expect(g.hitTest(Offset(g.fretCenterX(7), g.stringY(2))), (string: 2, fret: 7));
  });

  test('outside the board is not a hit', () {
    expect(geometry().hitTest(const Offset(-1, 50)), isNull);
  });
}
