import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fretlight/core/design/motion.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';

enum StageButtonStyle { primary, glass }

/// Buttons: a solid neutral pill for the one main action on a screen, and a
/// glass pill for everything else. Feedback is a press-scale plus a light
/// haptic instead of an ink splash.
class StageButton extends StatefulWidget {
  const StageButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = StageButtonStyle.primary,
    this.expand = false,
    super.key,
  });

  const StageButton.glass({
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    super.key,
  }) : style = StageButtonStyle.glass;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final StageButtonStyle style;
  final bool expand;

  @override
  State<StageButton> createState() => _StageButtonState();
}

class _StageButtonState extends State<StageButton> {
  bool _down = false;

  bool get _enabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    final motion = Motion.of(context);
    final primary = widget.style == StageButtonStyle.primary;
    final fg = primary ? c.onPrimary : c.textPrimary;

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: _enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: _enabled ? (_) => setState(() => _down = false) : null,
        onTap: _enabled
            ? () {
                unawaited(HapticFeedback.selectionClick());
                widget.onPressed!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: motion.quick,
          curve: MotionTokens.enter,
          child: AnimatedOpacity(
            opacity: _enabled ? 1 : 0.4,
            duration: motion.quick,
            child: Container(
              constraints: const BoxConstraints(
                minHeight: Space.touchTarget,
                minWidth: Space.touchTarget,
              ),
              padding: const EdgeInsets.symmetric(horizontal: Space.xl),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radii.pill),
                color: primary ? c.primaryFill : c.glassFillStrong,
                border: primary ? null : Border.all(color: c.glassBorder),
              ),
              child: Row(
                mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 20, color: fg),
                    const SizedBox(width: Space.sm),
                  ],
                  Flexible(
                    child: Text(
                      widget.label,
                      style: context.stageText.label.copyWith(color: fg),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A single-choice control (tunings, time signatures, subdivisions):
/// a glass track with a sliding thumb.
class StageSegmented<T> extends StatelessWidget {
  const StageSegmented({
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.labelOf,
    super.key,
  });

  final List<T> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final String Function(T) labelOf;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    final text = context.stageText;
    final motion = Motion.of(context);
    final index = options.indexOf(selected);
    return Container(
      height: Space.touchTarget - 4,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.glassFill,
        borderRadius: const BorderRadius.all(Radii.pill),
        border: Border.all(color: c.glassBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segment = constraints.maxWidth / options.length;
          return Stack(
            children: [
              // One thumb that slides, rather than per-segment fills that fade:
              // the motion shows where the selection went.
              AnimatedPositioned(
                duration: motion.standard,
                curve: MotionTokens.move,
                left: segment * index,
                top: 0,
                bottom: 0,
                width: segment,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.glassFillStrong,
                    borderRadius: const BorderRadius.all(Radii.pill),
                    border: Border.all(color: c.glassHighlight.withValues(alpha: 0.5)),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final o in options)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: o == selected,
                        label: labelOf(o),
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            unawaited(HapticFeedback.selectionClick());
                            onChanged(o);
                          },
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: motion.quick,
                              style: text.label.copyWith(
                                color: o == selected ? c.textPrimary : c.textTertiary,
                              ),
                              child: Text(
                                labelOf(o),
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
