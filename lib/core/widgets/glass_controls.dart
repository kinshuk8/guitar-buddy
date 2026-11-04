import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fretlight/core/design/motion.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';

/// A quiet glass capsule: a setting you can change (tuning, reference
/// pitch) or a filter you can toggle.
class GlassPill extends StatelessWidget {
  const GlassPill({
    required this.label,
    required this.semantics,
    required this.onTap,
    this.icon,
    this.chevron = false,
    this.selected,
    super.key,
  });

  final String label;
  final String semantics;
  final VoidCallback onTap;
  final IconData? icon;
  final bool chevron;

  /// Non-null makes it a toggle (announced as selected / not selected).
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    final on = selected ?? false;
    return Semantics(
      button: true,
      selected: selected,
      label: semantics,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          if (selected != null) unawaited(HapticFeedback.selectionClick());
          onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: AnimatedContainer(
            duration: Motion.of(context).quick,
            padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm + 2),
            decoration: BoxDecoration(
              color: on ? c.glassFillStrong : c.glassFill,
              borderRadius: const BorderRadius.all(Radii.pill),
              border: Border.all(color: on ? c.glassHighlight : c.glassBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: on ? c.textPrimary : c.textSecondary),
                  if (label.isNotEmpty) const SizedBox(width: Space.xs + 2),
                ],
                if (label.isNotEmpty)
                  Flexible(
                    child: Text(
                      label,
                      style: context.stageText.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (chevron) ...[
                  const SizedBox(width: Space.xs),
                  Icon(Icons.expand_more_rounded, size: 18, color: c.textTertiary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Round glass button for an icon-only action (back, favourite).
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    required this.icon,
    required this.semantics,
    required this.onTap,
    this.color,
    super.key,
  });

  final IconData icon;
  final String semantics;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: c.glassFill,
            shape: BoxShape.circle,
            border: Border.all(color: c.glassBorder),
          ),
          child: Icon(icon, size: 20, color: color ?? c.textPrimary),
        ),
      ),
    );
  }
}
