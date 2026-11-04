import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:fretlight/core/design/motion.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';

/// Screen backdrop: the base colour with two soft pools of light.
///
/// Glass only looks like glass when something sits behind it. The pools are
/// static radial gradients (no blur filter), cached in a RepaintBoundary, so
/// they cost nothing per frame.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(painter: _AmbientPainter(c.background, c.ambientA, c.ambientB)),
        ),
        child,
      ],
    );
  }
}

final class _AmbientPainter extends CustomPainter {
  const _AmbientPainter(this.base, this.a, this.b);

  final Color base;
  final Color a;
  final Color b;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    void pool(Offset centre, double radius, Color color, double alpha) {
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(centre, radius, [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ]),
      );
    }

    final r = size.longestSide;
    pool(Offset(size.width * 0.05, size.height * 0.02), r * 0.65, a, 0.55);
    pool(Offset(size.width * 1.0, size.height * 0.85), r * 0.6, b, 0.45);
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => old.base != base || old.a != a || old.b != b;
}

/// A frosted-glass surface.
///
/// [blur] applies a real backdrop blur. Only floating chrome (nav bar, app
/// bar, sheets) should set it: a backdrop blur re-samples everything behind
/// it every frame, and a scrolling list of blurred cards drops frames on
/// mid-range Android. Content cards sit over the smooth ambient gradient,
/// where a blur would be invisible anyway, so translucency alone reads as
/// glass at a fraction of the cost.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(Space.lg),
    this.radius = Radii.lg,
    this.blur = false,
    this.strong = false,
    this.live = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool blur;

  /// Denser fill, for controls that must stand out from cards.
  final bool strong;

  /// Lit by the lamp: the current chord, beat one, a detected note.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    final shape = BorderRadius.circular(radius);
    Widget panel = AnimatedContainer(
      duration: Motion.of(context).standard,
      curve: MotionTokens.enter,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: shape,
        color: strong ? c.glassFillStrong : c.glassFill,
        // No glow shadow for live panels: a shadow behind a translucent fill
        // shows through it and tints the whole card (amber turned muddy brown).
        // The lamp-coloured edge carries the state instead.
      ),
      foregroundDecoration: _GlassEdge(
        radius: radius,
        highlight: live ? c.accent.withValues(alpha: 0.7) : c.glassHighlight,
        edge: live ? c.accent.withValues(alpha: 0.25) : c.glassBorder,
      ),
      child: child,
    );
    if (blur) {
      panel = ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: GlassTokens.blur, sigmaY: GlassTokens.blur),
          child: panel,
        ),
      );
    }
    return panel;
  }
}

/// Hairline border that is brighter on top, as if lit from above.
/// BoxDecoration borders can't take a gradient, so this paints the stroke.
final class _GlassEdge extends Decoration {
  const _GlassEdge({required this.radius, required this.highlight, required this.edge});

  final double radius;
  final Color highlight;
  final Color edge;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _GlassEdgePainter(this);

  @override
  bool operator ==(Object other) =>
      other is _GlassEdge &&
      other.radius == radius &&
      other.highlight == highlight &&
      other.edge == edge;

  @override
  int get hashCode => Object.hash(radius, highlight, edge);
}

final class _GlassEdgePainter extends BoxPainter {
  _GlassEdgePainter(this.d);

  final _GlassEdge d;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    final rect = (offset & size).deflate(0.5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(d.radius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [d.highlight, d.edge],
          [0, 0.45],
        ),
    );
  }
}

/// Small quiet section label ("PALETTE", "CHORUS").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.xxl, bottom: Space.md, left: Space.xs),
    child: Semantics(
      header: true,
      child: Text(text.toUpperCase(), style: context.stageText.overline),
    ),
  );
}

/// Frosted top bar for pushed screens. Use with
/// `Scaffold(extendBodyBehindAppBar: true)` so content scrolls under it and
/// the blur has something to frost.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({required this.title, super.key});

  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: GlassTokens.blur, sigmaY: GlassTokens.blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.background.withValues(alpha: 0.55),
            border: Border(bottom: BorderSide(color: c.glassBorder)),
          ),
          child: AppBar(
            title: Text(title),
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
          ),
        ),
      ),
    );
  }
}

/// Shows a frosted bottom sheet. Sheets are floating chrome, so they blur.
Future<T?> showGlassSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (context) {
      final c = context.stage;
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.xl)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: GlassTokens.blur, sigmaY: GlassTokens.blur),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.background.withValues(alpha: 0.72),
                border: Border(top: BorderSide(color: c.glassHighlight)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: Space.sm),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: c.textTertiary,
                        borderRadius: const BorderRadius.all(Radii.pill),
                      ),
                    ),
                    Flexible(child: builder(context)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
