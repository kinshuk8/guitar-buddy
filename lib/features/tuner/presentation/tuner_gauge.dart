import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';
import 'package:fretlight/core/design/motion.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/widgets/music_text.dart';

/// Arc gauge from −50 to +50 cents with a spring-driven needle.
///
/// Each new reading restarts a spring simulation from the needle's current
/// position *and velocity*, so a stream of readings (~47/s) reads as one
/// continuous physical motion rather than a series of tweens. Under reduced
/// motion the needle jumps.
class TunerGauge extends StatefulWidget {
  const TunerGauge({required this.cents, super.key});

  /// Null when nothing is being heard: the needle rests at 0, dimmed.
  final double? cents;

  static const range = 50.0;

  @override
  State<TunerGauge> createState() => _TunerGaugeState();
}

class _TunerGaugeState extends State<TunerGauge> with SingleTickerProviderStateMixin {
  late final AnimationController _needle = AnimationController.unbounded(vsync: this);

  @override
  void didUpdateWidget(TunerGauge old) {
    super.didUpdateWidget(old);
    final target = (widget.cents ?? 0).clamp(-TunerGauge.range, TunerGauge.range);
    if (Motion.of(context).reduced) {
      _needle.value = target;
    } else if ((target - _needle.value).abs() > 0.01 || _needle.isAnimating) {
      _needle.animateWith(
        SpringSimulation(MotionTokens.needle, _needle.value, target, _needle.velocity),
      );
    }
  }

  @override
  void dispose() {
    _needle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    final cents = widget.cents;
    final state = cents == null ? null : TuningState.fromCents(cents);
    return RepaintBoundary(
      child: CustomPaint(
        painter: _GaugePainter(
          needle: _needle,
          colors: c,
          active: cents != null,
          inTune: state == TuningState.inTune,
          labelStyle: context.stageText.heading.copyWith(color: c.textTertiary),
        ),
      ),
    );
  }
}

final class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.needle,
    required this.colors,
    required this.active,
    required this.inTune,
    required this.labelStyle,
  }) : super(repaint: needle);

  final Animation<double> needle;
  final StageColors colors;
  final bool active;
  final bool inTune;
  final TextStyle labelStyle;

  /// Arc spans ±55° around straight up.
  static const double _sweep = 55 * math.pi / 180;

  double _angle(double cents) => -math.pi / 2 + cents / TunerGauge.range * _sweep;

  @override
  void paint(Canvas canvas, Size size) {
    // The pivot sits at the bottom edge and is never drawn: the indicator is
    // a short bar riding the tick ring, which reads cleaner than a long
    // needle from a visible hub.
    final radius = math.min(size.width / 2 / math.sin(_sweep) * 0.96, size.height * 1.15);
    final pivot = Offset(size.width / 2, radius + 12);
    Offset at(double cents, double r) {
      final a = _angle(cents);
      return pivot + Offset(math.cos(a), math.sin(a)) * r;
    }

    // In-tune band on the ring, always visible so the target is clear.
    const zoneSweep = TuningState.inTuneCents / TunerGauge.range * _sweep;
    canvas.drawArc(
      Rect.fromCircle(center: pivot, radius: radius - 9),
      -math.pi / 2 - zoneSweep,
      zoneSweep * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 20
        ..strokeCap = StrokeCap.round
        ..color = colors.inTune.withValues(alpha: inTune ? 0.3 : 0.12),
    );

    // Ticks every 5 cents; longer every 10 and at the centre.
    final tick = Paint()..strokeCap = StrokeCap.round;
    for (var cents = -50; cents <= 50; cents += 5) {
      final major = cents % 10 == 0;
      final len = cents == 0 ? 20.0 : (major ? 12.0 : 6.0);
      tick
        ..strokeWidth = cents == 0 ? 2 : 1.4
        ..color = cents == 0 ? colors.textSecondary : colors.textTertiary;
      canvas.drawLine(at(cents.toDouble(), radius - len), at(cents.toDouble(), radius), tick);
    }

    // ♭ / ♯ under the ends, so direction never relies on colour.
    void label(String text, double cents) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at(cents, radius - 34) - Offset(tp.width / 2, tp.height / 2));
    }

    label('♭', -50);
    label('♯', 50);

    // Indicator.
    final v = needle.value.clamp(-TunerGauge.range, TunerGauge.range);
    final color = !active
        ? colors.textTertiary.withValues(alpha: 0.35)
        : inTune
        ? colors.inTune
        : colors.textPrimary;
    canvas.drawLine(
      at(v, radius - 30),
      at(v, radius + 6),
      Paint()
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.colors != colors ||
      old.active != active ||
      old.inTune != inTune ||
      old.labelStyle != labelStyle;
}
