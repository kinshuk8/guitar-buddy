import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/widgets/stage_buttons.dart';
import 'package:go_router/go_router.dart';

/// Placeholder for features that land in later milestones.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({
    required this.title,
    required this.milestone,
    required this.icon,
    super.key,
  });

  final String title;
  final int milestone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    final text = context.stageText;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: text.display),
            const Spacer(),
            Center(child: Icon(icon, size: 40, color: c.textTertiary)),
            const SizedBox(height: Space.md),
            Center(child: Text('Coming in milestone $milestone', style: text.caption)),
            const Spacer(),
            if (kDebugMode)
              Center(
                child: StageButton.glass(
                  label: 'Widget gallery',
                  onPressed: () => context.push('/gallery'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
