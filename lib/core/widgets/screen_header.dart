import 'package:flutter/material.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/widgets/glass.dart';
import 'package:fretlight/core/widgets/glass_controls.dart';

/// The one header every screen uses: an optional Back (or Close) button,
/// the screen's name, and its actions on the right.
///
/// Tab screens pass [large] and no [onBack]; screens you arrive at from
/// somewhere else pass [onBack], so "how do I get out of here?" always has
/// the same answer in the same corner.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    required this.title,
    this.subtitle,
    this.onBack,
    this.close = false,
    this.large = false,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;

  /// Show an "X" instead of a chevron: this screen is a task you leave,
  /// not a page you came from.
  final bool close;
  final bool large;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    return Row(
      children: [
        if (onBack case final back?) ...[
          GlassIconButton(
            icon: close ? Icons.close_rounded : Icons.arrow_back_ios_new_rounded,
            semantics: close ? 'Close' : 'Back',
            onTap: back,
          ),
          const SizedBox(width: Space.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: large ? t.display : t.heading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (subtitle case final s?)
                Text(
                  s,
                  style: t.caption.copyWith(color: c.textTertiary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        for (final a in actions) ...[const SizedBox(width: Space.sm), a],
      ],
    );
  }
}

/// A labelled row that takes you somewhere: icon, name, one line saying
/// what's there, and a chevron.
class NavRow extends StatelessWidget {
  const NavRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    return Semantics(
      container: true,
      button: true,
      label: '$title. $detail',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: GlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: c.glassFillStrong, shape: BoxShape.circle),
                child: Icon(icon, size: 20, color: c.textPrimary),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.heading),
                    Text(
                      detail,
                      style: t.caption.copyWith(color: c.textTertiary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nothing here yet: says so, and offers the next step.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.message,
    required this.action,
    required this.onAction,
    super.key,
  });

  final String message;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.lg),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, style: context.stageText.bodySecondary, textAlign: TextAlign.center),
        const SizedBox(height: Space.md),
        GlassPill(label: action, semantics: action, onTap: onAction),
      ],
    ),
  );
}
