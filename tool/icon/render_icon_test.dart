// Renders the app icon from code (not part of the normal test run).
//
//   flutter test tool/icon/render_icon_test.dart
//   tool/icon/install_icons.sh
//
// Writes build/icon/{icon,foreground,background}.png at 1024 px. The mark:
// six strings and a fret on deep ink, with one amber "fret light" where a
// finger would go. Glassy, minimal, no brown.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/design/tokens.dart';

const _size = 1024.0;

void _background(Canvas canvas, Size s) {
  final rect = Offset.zero & s;
  canvas.drawRect(rect, Paint()..color = Palette.ink);
  // Two soft pools of light, like the app's ambient background.
  for (final (centre, color, r) in [
    (Offset(s.width * 0.18, s.height * 0.12), Palette.indigoMist, 0.85),
    (Offset(s.width * 0.92, s.height * 0.95), Palette.tealMist, 0.75),
  ]) {
    canvas.drawCircle(
      centre,
      s.width * r,
      Paint()
        ..shader = ui.Gradient.radial(centre, s.width * r, [
          color.withValues(alpha: 0.95),
          color.withValues(alpha: 0),
        ]),
    );
  }
}

/// The mark, drawn within [area] (the adaptive-icon safe zone when needed).
void _mark(Canvas canvas, Rect area) {
  final w = area.width;
  final left = area.left + w * 0.2;
  final right = area.right - w * 0.2;
  final top = area.top + w * 0.14;
  final bottom = area.bottom - w * 0.14;
  final gap = (right - left) / 5;

  // Fret wires: two quiet horizontal lines.
  final fret = Paint()
    ..color = Colors.white.withValues(alpha: 0.18)
    ..strokeWidth = w * 0.012
    ..strokeCap = StrokeCap.round;
  final fretYs = [area.top + w * 0.36, area.top + w * 0.64];
  for (final y in fretYs) {
    canvas.drawLine(Offset(left - gap * 0.35, y), Offset(right + gap * 0.35, y), fret);
  }

  // Strings: heavier on the left (low E), like the real thing.
  for (var i = 0; i < 6; i++) {
    final x = left + gap * i;
    canvas.drawLine(
      Offset(x, top),
      Offset(x, bottom),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.72 - i * 0.05)
        ..strokeWidth = w * (0.022 - i * 0.0026)
        ..strokeCap = StrokeCap.round,
    );
  }

  // The fret light: a finger's place, lit by the lamp.
  final dot = Offset(left + gap * 2, (fretYs[0] + fretYs[1]) / 2);
  final r = w * 0.085;
  canvas
    // A tight halo: a wide, strong one goes muddy brown over the ink.
    ..drawCircle(
      dot,
      r * 2,
      Paint()
        ..shader = ui.Gradient.radial(dot, r * 2, [
          Palette.lamp.withValues(alpha: 0.32),
          Palette.lamp.withValues(alpha: 0),
        ]),
    )
    ..drawCircle(dot, r, Paint()..color = Palette.lamp)
    ..drawCircle(
      dot.translate(-r * 0.3, -r * 0.3),
      r * 0.35,
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );
}

Future<void> _write(String name, void Function(Canvas, Size) paint) async {
  final recorder = ui.PictureRecorder();
  const s = Size(_size, _size);
  paint(Canvas(recorder), s);
  final image = await recorder.endRecording().toImage(_size.toInt(), _size.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File('build/icon/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  test('render icon', () async {
    await _write('icon', (c, s) {
      _background(c, s);
      _mark(c, Offset.zero & s);
    });
    await _write('background', _background);
    // Android adaptive icons crop to a circle/squircle of the middle ~66%:
    // keep the mark inside it.
    await _write('foreground', (c, s) {
      final inset = s.width * (1 - 0.62) / 2;
      _mark(c, Rect.fromLTWH(inset, inset, s.width - 2 * inset, s.height - 2 * inset));
    });
    expect(math.max(1, 0), 1);
  });
}
