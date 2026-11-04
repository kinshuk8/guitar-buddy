import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/painting/fretboard_geometry.dart';

/// String gauges (inches) for a light acoustic set, lowest string first.
/// Drawn thickness is proportional, so the low E visibly outweighs the high E.
const acousticGauges = [0.053, 0.042, 0.032, 0.024, 0.016, 0.012];

/// Unlit marker colour: ivory, readable on ebony in both themes.
const _markerWhite = Color(0xF2F3F4F6);

/// A marker on the fretboard (a note position or a chord finger).
@immutable
final class FretMarker {
  const FretMarker({required this.string, required this.fret, this.label, this.emphasis = 0});

  final int string;
  final int fret;
  final String? label;

  /// 0..1. 0 = plain ivory dot (a chord shape), 1 = lit by the lamp
  /// (the note being played now).
  final double emphasis;
}

/// Static layer: wood, grain, inlays, frets and nut.
///
/// Kept separate from [FretboardStringsPainter] and wrapped in its own
/// RepaintBoundary, so string vibration (60 fps) never re-rasterises the
/// grain. The grain itself is deterministic (seeded) so it doesn't shimmer
/// between rebuilds.
final class FretboardWoodPainter extends CustomPainter {
  const FretboardWoodPainter({
    required this.colors,
    required this.stringCount,
    this.firstFret = 0,
    this.lastFret = 12,
    this.leftHanded = false,
  });

  final StageColors colors;
  final int stringCount;
  final int firstFret;
  final int lastFret;
  final bool leftHanded;

  @override
  void paint(Canvas canvas, Size size) {
    final g = FretboardGeometry(
      size: size,
      stringCount: stringCount,
      firstFret: firstFret,
      lastFret: lastFret,
      leftHanded: leftHanded,
    );
    final boardRect = Rect.fromLTRB(
      math.min(g.boardStartX, g.boardEndX),
      0,
      math.max(g.boardStartX, g.boardEndX),
      size.height,
    );

    // Wood with a gentle cylindrical shading (the neck is rounded).
    canvas.drawRRect(
      RRect.fromRectAndRadius(boardRect, const Radius.circular(4)),
      Paint()
        ..shader = ui.Gradient.linear(
          boardRect.topCenter,
          boardRect.bottomCenter,
          [
            Color.lerp(colors.fretboardWood, colors.fretboardGrain, 0.5)!,
            colors.fretboardWood,
            Color.lerp(colors.fretboardWood, const Color(0xFF000000), 0.35)!,
          ],
          [0, 0.45, 1],
        ),
    );

    // Grain: long, low-contrast, slightly wavy strokes.
    canvas
      ..save()
      ..clipRect(boardRect);
    final rnd = math.Random(7);
    final grain = Paint()
      ..style = PaintingStyle.stroke
      ..color = colors.fretboardGrain.withValues(alpha: 0.6);
    for (var i = 0; i < 38; i++) {
      final y = rnd.nextDouble() * size.height;
      final amp = 1 + rnd.nextDouble() * 3;
      final wave = 80 + rnd.nextDouble() * 200;
      grain.strokeWidth = 0.4 + rnd.nextDouble() * 1.2;
      final path = Path()..moveTo(boardRect.left, y);
      for (var x = boardRect.left; x <= boardRect.right; x += 8) {
        path.lineTo(x, y + math.sin(x / wave + i) * amp);
      }
      canvas.drawPath(path, grain);
    }
    canvas.restore();

    // Inlays: mother-of-pearl dots with a faint sheen.
    final midY = size.height / 2;
    // Inlays are kept small and translucent so they never compete with markers.
    final inlayR = size.height * 0.032;
    void inlay(Offset c) {
      canvas.drawCircle(
        c,
        inlayR,
        Paint()
          ..shader = ui.Gradient.radial(c.translate(-inlayR * 0.3, -inlayR * 0.3), inlayR * 1.4, [
            colors.inlay.withValues(alpha: 0.55),
            colors.inlay.withValues(alpha: 0.3),
          ]),
      );
    }

    for (var n = math.max(1, firstFret); n <= lastFret; n++) {
      final x = g.fretCenterX(n);
      if (FretboardGeometry.singleInlays.contains(n)) inlay(Offset(x, midY));
      if (FretboardGeometry.doubleInlays.contains(n)) {
        inlay(Offset(x, size.height * 0.3));
        inlay(Offset(x, size.height * 0.7));
      }
    }

    // Fret wires: a bright crown line over a darker body reads as rounded metal.
    final wireBody = Paint()
      ..color = Color.lerp(colors.fretWire, colors.fretboardWood, 0.55)!
      ..strokeWidth = 2.4;
    final wireCrown = Paint()
      ..color = colors.fretWire.withValues(alpha: 0.5)
      ..strokeWidth = 1.1;
    for (var n = math.max(1, firstFret); n <= lastFret; n++) {
      final x = g.fretX(n);
      canvas
        ..drawLine(Offset(x, 0), Offset(x, size.height), wireBody)
        ..drawLine(Offset(x - 0.6, 0), Offset(x - 0.6, size.height), wireCrown);
    }

    // Nut (bone).
    if (g.showsNut) {
      final nutRight = g.fretX(0);
      final nutRect = Rect.fromLTRB(
        math.min(g.nutX, nutRight),
        0,
        math.max(g.nutX, nutRight),
        size.height,
      );
      canvas.drawRect(
        nutRect,
        Paint()
          ..shader = ui.Gradient.linear(nutRect.centerLeft, nutRect.centerRight, [
            colors.nut,
            Color.lerp(colors.nut, const Color(0xFF8A7A60), 0.4)!,
          ]),
      );
    }
  }

  @override
  bool shouldRepaint(FretboardWoodPainter old) =>
      old.colors != colors ||
      old.stringCount != stringCount ||
      old.firstFret != firstFret ||
      old.lastFret != lastFret ||
      old.leftHanded != leftHanded;
}

/// Dynamic layer: strings (with vibration) and markers.
final class FretboardStringsPainter extends CustomPainter {
  FretboardStringsPainter({
    required this.colors,
    required this.stringCount,
    required this.vibration,
    this.markers = const [],
    this.firstFret = 0,
    this.lastFret = 12,
    this.leftHanded = false,
    this.gauges = acousticGauges,
    this.woundCount = 4,
    super.repaint,
  });

  final StageColors colors;
  final int stringCount;

  /// Per string: current displacement amplitude (px) and phase (radians).
  /// Read on every paint (driven by the repaint listenable), so the ticker never rebuilds widgets.
  final List<({double amplitude, double phase})> Function() vibration;
  final List<FretMarker> markers;
  final int firstFret;
  final int lastFret;
  final bool leftHanded;
  final List<double> gauges;

  /// How many of the lowest strings are wound (bronze). 4 on acoustic sets.
  final int woundCount;

  @override
  void paint(Canvas canvas, Size size) {
    final g = FretboardGeometry(
      size: size,
      stringCount: stringCount,
      firstFret: firstFret,
      lastFret: lastFret,
      leftHanded: leftHanded,
    );
    final startX = g.showsNut ? g.nutX : g.boardStartX;
    final endX = g.boardEndX;
    final left = math.min(startX, endX);
    final right = math.max(startX, endX);
    final vib = vibration();
    final scale = size.height / 220; // px per 0.01" at the reference height

    for (var s = 0; s < stringCount; s++) {
      final y = g.stringY(s);
      final gauge = s < gauges.length ? gauges[s] : gauges.last;
      final width = math.max(1, gauge * 100 * scale * 1.6).toDouble();
      final wound = s < woundCount;
      final base = wound ? colors.woundString : colors.plainString;
      final v = s < vib.length ? vib[s] : (amplitude: 0.0, phase: 0.0);
      final path = _stringPath(left, right, y, v.amplitude * math.cos(v.phase));

      // Shadow on the wood gives the string height off the board.
      canvas.drawPath(
        path.shift(Offset(0, width * 0.9 + 1)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = const Color(0xFF000000).withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
      // Body.
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(
            Offset(0, y - width / 2),
            Offset(0, y + width / 2),
            [
              Color.lerp(base, const Color(0xFFFFFFFF), 0.45)!,
              base,
              Color.lerp(base, const Color(0xFF000000), 0.45)!,
            ],
            [0, 0.4, 1],
          ),
      );
      // Winding texture: fine dashes across wound strings.
      if (wound && width > 2.5 && v.amplitude < 0.5) {
        final wind = Paint()
          ..color = const Color(0xFF000000).withValues(alpha: 0.18)
          ..strokeWidth = 0.6;
        for (var x = left; x < right; x += 2.2) {
          canvas.drawLine(Offset(x, y - width / 2 + 0.5), Offset(x + 1, y + width / 2 - 0.5), wind);
        }
      }
      // Glow while vibrating: the "lit" string.
      if (v.amplitude > 0.2) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width + 6
            ..color = colors.accent.withValues(alpha: (v.amplitude / 8).clamp(0, 0.35))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
    }

    for (final m in markers) {
      _paintMarker(canvas, g, m, size);
    }
  }

  /// A string vibrating in its fundamental mode: displacement peaks mid-span.
  Path _stringPath(double left, double right, double y, double displacement) {
    final path = Path()..moveTo(left, y);
    if (displacement.abs() < 0.05) return path..lineTo(right, y);
    const segments = 32;
    for (var i = 1; i <= segments; i++) {
      final t = i / segments;
      path.lineTo(left + (right - left) * t, y + math.sin(math.pi * t) * displacement);
    }
    return path;
  }

  void _paintMarker(Canvas canvas, FretboardGeometry g, FretMarker m, Size size) {
    final c = Offset(g.fretCenterX(m.fret), g.stringY(m.string));
    final r = size.height * 0.065;
    final e = m.emphasis.clamp(0.0, 1.0);
    if (e > 0) {
      canvas.drawCircle(
        c,
        r * 1.9,
        Paint()
          ..color = colors.accent.withValues(alpha: 0.35 * e)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r),
      );
    }
    if (m.fret == 0) {
      // Open string: ring, not a filled dot.
      canvas.drawCircle(
        c,
        r * 0.8,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          // Drawn left of the nut, off the wood, so it follows the theme's
          // text colour rather than the ivory used on the dark board.
          ..color = colors.textPrimary.withValues(alpha: 0.85),
      );
    } else {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = ui.Gradient.radial(c.translate(-r * 0.3, -r * 0.4), r * 1.3, [
            Color.lerp(_markerWhite, colors.accent, e)!,
            Color.lerp(const Color(0xFFD9DCE1), colors.accent, e)!,
          ]),
      );
    }
    final label = m.label;
    if (label != null && m.fret > 0) {
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontFamily: FontFamilies.ui,
            fontFamilyFallback: FontFamilies.fallback,
            fontSize: r * 0.9,
            fontWeight: FontWeight.w600,
            fontVariations: const [FontVariation('wght', 600)],
            color: const Color(0xFF0B0D12),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(FretboardStringsPainter old) =>
      old.colors != colors ||
      old.markers != markers ||
      old.stringCount != stringCount ||
      old.firstFret != firstFret ||
      old.lastFret != lastFret ||
      old.leftHanded != leftHanded;
}
