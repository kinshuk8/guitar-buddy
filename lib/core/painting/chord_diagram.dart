import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:fretlight/core/design/motion.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/painting/fretboard.dart';

/// A chord box: strings vertical (low E on the left, mirrored for
/// left-handed players), nut at the top, five frets.
///
/// Changing [voicing] slides the fingers to the new shape rather than
/// cutting, so you can see how your hand has to move. Strings plucked
/// through [controller] shimmer and catch the lamp while they ring.
class ChordDiagram extends StatefulWidget {
  const ChordDiagram({
    required this.voicing,
    this.tuning,
    this.root,
    this.compact = false,
    this.leftHanded = false,
    this.controller,
    this.onStringTap,
    this.semanticLabel,
    super.key,
  });

  final Voicing voicing;
  final Tuning? tuning;

  /// Emphasises root notes in the note row under the diagram.
  final PitchClass? root;

  /// Thumbnail mode: no finger numbers, no note row, no animation.
  final bool compact;
  final bool leftHanded;
  final FretboardController? controller;
  final ValueChanged<int>? onStringTap;
  final String? semanticLabel;

  /// Width / height for laying the widget out without clipping.
  static double aspectRatio({required bool compact}) => compact ? 0.86 : 0.78;

  @override
  State<ChordDiagram> createState() => _ChordDiagramState();
}

class _ChordDiagramState extends State<ChordDiagram> with TickerProviderStateMixin {
  late final AnimationController _move = AnimationController(vsync: this, value: 1);
  late _Shape _from = _Shape.of(widget.voicing);
  late _Shape _to = _from;

  late final Ticker _ticker = createTicker(_onTick);
  final _frame = ValueNotifier<int>(0);
  final List<Duration?> _pluckedAt = List.filled(6, null);
  Duration _now = Duration.zero;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onPluck);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = Motion.of(context);
    _reduced = motion.reduced;
    _move.duration = motion.fingerTravel;
  }

  @override
  void didUpdateWidget(ChordDiagram old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onPluck);
      widget.controller?.addListener(_onPluck);
    }
    if (!identical(old.voicing, widget.voicing)) {
      _from = _Shape.lerp(_from, _to, MotionTokens.move.transform(_move.value));
      _to = _Shape.of(widget.voicing);
      if (widget.compact || _reduced) {
        _from = _to;
        _move.value = 1;
      } else {
        _move.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onPluck);
    _move.dispose();
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _onPluck() {
    // Shared with Fretboard; the diagram reads the same queue.
    for (final s in widget.controller!.drainPlucks()) {
      if (s < 0 || s >= _pluckedAt.length || widget.voicing.frets[s] == null) continue;
      _pluckedAt[s] = _now;
    }
    if (!_ticker.isActive) _ticker.start();
  }

  void _onTick(Duration elapsed) {
    _now = elapsed;
    _frame.value++;
    final active = _pluckedAt.any((t) => t != null && elapsed - t < MotionTokens.stringDecay);
    if (!active) {
      _ticker.stop();
      _now = Duration.zero;
      _pluckedAt.fillRange(0, _pluckedAt.length, null);
    }
  }

  List<double> _ring() => [
    for (final at in _pluckedAt)
      if (at == null)
        0
      else
        math.max(
          0,
          math.exp(-4 * (_now - at).inMicroseconds / MotionTokens.stringDecay.inMicroseconds) -
              0.02,
        ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.stage;
    final tuning = widget.tuning ?? Tuning.standard;
    final notes = [
      for (var s = 0; s < 6; s++)
        if (widget.voicing.frets[s] case final int f) tuning.noteAt(s, f).pitchClass else null,
    ];
    final spelling = widget.root == null ? Spelling.sharps : Spelling.forRoot(widget.root!);
    return Semantics(
      label: widget.semanticLabel ?? describeVoicing(widget.voicing),
      image: true,
      child: AspectRatio(
        aspectRatio: ChordDiagram.aspectRatio(compact: widget.compact),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final geometry = _Geometry(
              size,
              compact: widget.compact,
              leftHanded: widget.leftHanded,
            );
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: widget.onStringTap == null
                  ? null
                  : (d) {
                      final s = geometry.stringAt(d.localPosition.dx);
                      if (widget.voicing.frets[s] == null) return;
                      widget.controller?.pluck(s);
                      widget.onStringTap!(s);
                    },
              child: CustomPaint(
                size: size,
                painter: _DiagramPainter(
                  geometry: geometry,
                  colors: colors,
                  shape: () => _Shape.lerp(_from, _to, MotionTokens.move.transform(_move.value)),
                  ring: _ring,
                  seconds: () => _now.inMicroseconds / 1e6,
                  reduced: _reduced,
                  noteNames: widget.compact ? null : [for (final n in notes) n?.name(spelling)],
                  rootIndex: [
                    for (final n in notes) n != null && widget.root != null && n == widget.root,
                  ],
                  repaint: Listenable.merge([_move, _frame]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Spoken form of a voicing: `Low to high: muted, fret 3, fret 2, open, fret 1, open.`
String describeVoicing(Voicing v) {
  final parts = [
    for (final f in v.frets)
      switch (f) {
        null => 'muted',
        0 => 'open',
        _ => 'fret $f',
      },
  ];
  return 'Strings low to high: ${parts.join(', ')}.';
}

const _rows = 5;

final class _Geometry {
  _Geometry(this.size, {required this.compact, required this.leftHanded}) {
    final w = size.width;
    // Side margins hold the base-fret label (left) and balance it (right).
    cell = w / (compact ? 6.6 : 7.2);
    left = (w - cell * 5) / 2;
    top = cell * (compact ? 0.9 : 1.05);
    cellH = (size.height - top - (compact ? cell * 0.35 : cell * 1.15)) / _rows;
  }

  final Size size;
  final bool compact;
  final bool leftHanded;
  late final double cell;
  late final double cellH;
  late final double left;
  late final double top;

  double stringX(int s) => left + cell * (leftHanded ? 5 - s : s);

  /// Centre of fret row [row] (0 = first row below the nut), fractional.
  double rowY(double row) => top + cellH * (row + 0.5);

  double get bottom => top + cellH * _rows;

  int stringAt(double dx) {
    final raw = ((dx - left) / cell).round().clamp(0, 5);
    return leftHanded ? 5 - raw : raw;
  }
}

/// A voicing reduced to what's drawn, so two can be interpolated.
final class _Shape {
  const _Shape(this.base, this.rows, this.open, this.muted, this.fingers, this.barres);

  factory _Shape.of(Voicing v) {
    final base = v.baseFret;
    final barred = <int>{};
    final barres = <_Bar>[];
    for (final b in v.barres) {
      barres.add(_Bar(b.lowString, b.highString, (b.fret - base).toDouble(), b.finger, 1));
      for (var s = b.lowString; s <= b.highString; s++) {
        if (v.frets[s] == b.fret) barred.add(s);
      }
    }
    return _Shape(
      base.toDouble(),
      [
        for (var s = 0; s < 6; s++)
          if (v.frets[s] case final int f when f > 0 && !barred.contains(s))
            (row: (f - base).toDouble(), alpha: 1.0)
          else
            null,
      ],
      [
        for (final f in v.frets)
          if (f == 0) 1.0 else 0.0,
      ],
      [
        for (final f in v.frets)
          if (f == null) 1.0 else 0.0,
      ],
      [
        for (var s = 0; s < 6; s++)
          if (s < v.fingers.length) v.fingers[s] else null,
      ],
      barres,
    );
  }

  /// Interpolates: shared notes slide, others fade; the window glides.
  // A static, not a factory: it returns an endpoint unchanged at t = 0 or 1.
  // ignore: prefer_constructors_over_static_methods
  static _Shape lerp(_Shape a, _Shape b, double t) {
    if (t <= 0) return a;
    if (t >= 1) return b;
    final rows = <({double row, double alpha})?>[];
    for (var s = 0; s < 6; s++) {
      final ra = a.rows[s];
      final rb = b.rows[s];
      if (ra != null && rb != null) {
        rows.add((row: lerpDouble(ra.row, rb.row, t)!, alpha: lerpDouble(ra.alpha, rb.alpha, t)!));
      } else if (ra != null) {
        rows.add((row: ra.row, alpha: ra.alpha * (1 - t)));
      } else if (rb != null) {
        rows.add((row: rb.row, alpha: rb.alpha * t));
      } else {
        rows.add(null);
      }
    }
    List<double> mix(List<double> x, List<double> y) => [
      for (var i = 0; i < 6; i++) lerpDouble(x[i], y[i], t)!,
    ];
    return _Shape(
      lerpDouble(a.base, b.base, t)!,
      rows,
      mix(a.open, b.open),
      mix(a.muted, b.muted),
      t < 0.5 ? a.fingers : b.fingers,
      [
        for (final bar in a.barres) bar.withAlpha(bar.alpha * (1 - t)),
        for (final bar in b.barres) bar.withAlpha(bar.alpha * t),
      ],
    );
  }

  final double base;
  final List<({double row, double alpha})?> rows;
  final List<double> open;
  final List<double> muted;
  final List<int?> fingers;
  final List<_Bar> barres;
}

final class _Bar {
  const _Bar(this.low, this.high, this.row, this.finger, this.alpha);

  final int low;
  final int high;
  final double row;
  final int finger;
  final double alpha;

  _Bar withAlpha(double a) => _Bar(low, high, row, finger, a);
}

final class _DiagramPainter extends CustomPainter {
  _DiagramPainter({
    required this.geometry,
    required this.colors,
    required this.shape,
    required this.ring,
    required this.seconds,
    required this.reduced,
    required this.noteNames,
    required this.rootIndex,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final _Geometry geometry;
  final StageColors colors;
  final _Shape Function() shape;
  final List<double> Function() ring;
  final double Function() seconds;
  final bool reduced;
  final List<String?>? noteNames;
  final List<bool> rootIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    final s = shape();
    final ringing = ring();
    final compact = g.compact;
    final lineW = math.max(1, g.cell * 0.045).toDouble();

    // Frets.
    final fretPaint = Paint()
      ..color = colors.textTertiary.withValues(alpha: 0.45)
      ..strokeWidth = lineW;
    final x0 = g.stringX(0);
    final x5 = g.stringX(5);
    final (xl, xr) = (math.min(x0, x5), math.max(x0, x5));
    for (var r = 1; r <= _rows; r++) {
      final y = g.top + g.cellH * r;
      canvas.drawLine(Offset(xl, y), Offset(xr, y), fretPaint);
    }
    // Nut, fading out as the window moves up the neck.
    final atNut = (1 - (s.base - 1)).clamp(0.0, 1.0);
    final nutPaint = Paint()
      ..color = Color.lerp(
        colors.textTertiary.withValues(alpha: 0.45),
        colors.textPrimary.withValues(alpha: 0.85),
        atNut,
      )!
      ..strokeWidth = lerpDouble(lineW, g.cell * 0.16, atNut)!
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(xl, g.top), Offset(xr, g.top), nutPaint);

    // Strings: wound strings a little heavier; ringing ones shimmer.
    for (var str = 0; str < 6; str++) {
      final x = g.stringX(str);
      final amp = str < ringing.length ? ringing[str] : 0.0;
      final width = lerpDouble(g.cell * 0.075, g.cell * 0.035, str / 5)!.clamp(0.8, 4.0);
      final paint = Paint()
        ..color = Color.lerp(colors.textSecondary.withValues(alpha: 0.7), colors.accent, amp)!
        ..strokeWidth = width + amp * 0.8
        ..style = PaintingStyle.stroke;
      if (amp <= 0 || reduced) {
        canvas.drawLine(Offset(x, g.top), Offset(x, g.bottom), paint);
      } else {
        // Standing-wave wobble: nodes at both ends, slow "visual" frequency.
        final path = Path()..moveTo(x, g.top);
        final phase = seconds() * (22 - str * 1.5) * 2 * math.pi;
        const steps = 24;
        for (var i = 1; i <= steps; i++) {
          final f = i / steps;
          final dx = math.sin(math.pi * f) * math.sin(phase) * amp * g.cell * 0.07;
          path.lineTo(x + dx, g.top + (g.bottom - g.top) * f);
        }
        canvas.drawPath(path, paint);
      }
    }

    // Base fret label, e.g. "5fr", when the window is up the neck.
    final up = (s.base - 1).clamp(0.0, 1.0);
    if (up > 0) {
      _text(
        canvas,
        '${s.base.round()}fr',
        Offset(xl - g.cell * 0.62, g.rowY(0)),
        size: g.cell * (compact ? 0.42 : 0.36),
        color: colors.textSecondary.withValues(alpha: up),
        weight: 500,
        align: _Align.right,
      );
    }

    // Open and muted markers above the nut.
    final markY = g.top - g.cell * (compact ? 0.48 : 0.55);
    final markR = g.cell * (compact ? 0.2 : 0.18);
    for (var str = 0; str < 6; str++) {
      final x = g.stringX(str);
      if (s.open[str] > 0) {
        canvas.drawCircle(
          Offset(x, markY),
          markR,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.2, g.cell * 0.06)
            ..color = colors.textSecondary.withValues(alpha: s.open[str]),
        );
      }
      if (s.muted[str] > 0) {
        final p = Paint()
          ..strokeWidth = math.max(1.2, g.cell * 0.06)
          ..strokeCap = StrokeCap.round
          ..color = colors.textTertiary.withValues(alpha: s.muted[str]);
        final d = markR * 0.8;
        canvas
          ..drawLine(Offset(x - d, markY - d), Offset(x + d, markY + d), p)
          ..drawLine(Offset(x - d, markY + d), Offset(x + d, markY - d), p);
      }
    }

    final dotR = g.cell * (compact ? 0.38 : 0.36);
    final numberSize = g.cell * 0.4;

    // Barres: one rounded bar under the barring finger.
    for (final bar in s.barres) {
      if (bar.alpha <= 0) continue;
      final y = g.rowY(bar.row);
      final xa = g.stringX(bar.low);
      final xb = g.stringX(bar.high);
      final rect = Rect.fromLTRB(
        math.min(xa, xb) - dotR,
        y - dotR,
        math.max(xa, xb) + dotR,
        y + dotR,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(dotR)),
        Paint()..color = colors.primaryFill.withValues(alpha: bar.alpha),
      );
      if (!compact) {
        _text(
          canvas,
          '${bar.finger}',
          rect.center,
          size: numberSize,
          color: colors.onPrimary.withValues(alpha: bar.alpha),
          weight: 600,
        );
      }
    }

    // Finger dots.
    for (var str = 0; str < 6; str++) {
      final r = s.rows[str];
      if (r == null || r.alpha <= 0) continue;
      final c = Offset(g.stringX(str), g.rowY(r.row));
      canvas.drawCircle(c, dotR, Paint()..color = colors.primaryFill.withValues(alpha: r.alpha));
      final finger = s.fingers[str];
      if (!compact && finger != null && finger > 0) {
        _text(
          canvas,
          '$finger',
          c,
          size: numberSize,
          color: colors.onPrimary.withValues(alpha: r.alpha),
          weight: 600,
        );
      }
    }

    // Sounding notes under each string; roots stand out.
    final names = noteNames;
    if (names != null) {
      final y = g.bottom + g.cell * 0.62;
      for (var str = 0; str < 6; str++) {
        final n = names[str];
        if (n == null) continue;
        final root = rootIndex[str];
        _text(
          canvas,
          n.replaceAll('#', '♯').replaceAll('b', '♭'),
          Offset(g.stringX(str), y),
          size: g.cell * 0.36,
          color: root ? colors.textPrimary : colors.textTertiary,
          weight: root ? 650 : 450,
        );
      }
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at, {
    required double size,
    required Color color,
    required int weight,
    _Align align = _Align.center,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: StageText.style(size, weight: weight, color: color, height: 1, tabular: true),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      _Align.center => at.dx - tp.width / 2,
      _Align.right => at.dx - tp.width,
    };
    tp
      ..paint(canvas, Offset(dx, at.dy - tp.height / 2))
      ..dispose();
  }

  @override
  bool shouldRepaint(_DiagramPainter old) =>
      old.colors != colors ||
      old.geometry.size != geometry.size ||
      old.geometry.leftHanded != geometry.leftHanded ||
      old.reduced != reduced ||
      !_listEquals(old.noteNames, noteNames) ||
      !_listEquals(old.rootIndex, rootIndex) ||
      // A new voicing comes with a new shape closure.
      old.shape != shape;
}

enum _Align { center, right }

bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
