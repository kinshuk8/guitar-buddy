import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fretlight/core/design/motion.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/widgets/glass.dart';
import 'package:go_router/go_router.dart';

/// A top-level destination in the bottom bar.
@immutable
final class Destination {
  const Destination(this.label, this.icon, this.path);

  final String label;
  final IconData icon;
  final String path;
}

const destinations = [
  Destination('Home', Icons.home_rounded, '/home'),
  Destination('Practice', Icons.school_rounded, '/practice'),
  Destination('Songs', Icons.queue_music_rounded, '/songs'),
  Destination('Tools', Icons.handyman_rounded, '/tools'),
];

/// App frame: ambient backdrop + a floating glass tab bar in thumb reach.
class StageShell extends StatelessWidget {
  const StageShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    extendBody: true,
    body: AmbientBackground(child: shell),
    bottomNavigationBar: StageNavBar(
      index: shell.currentIndex,
      // Tapping the tab you're on takes you back to its first screen.
      onSelect: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
    ),
  );
}

/// Floating frosted capsule. Four tabs of equal width, each always showing
/// its name: a tab is in the same place, saying the same thing, wherever
/// you are.
class StageNavBar extends StatelessWidget {
  const StageNavBar({required this.index, required this.onSelect, super.key});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    final motion = Motion.of(context);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: Space.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.all(Radii.pill),
            boxShadow: Glows.float,
          ),
          child: GlassPanel(
            blur: true,
            strong: true,
            radius: 999,
            padding: const EdgeInsets.all(Space.xs + 2),
            child: Row(
              children: [
                for (var i = 0; i < destinations.length; i++)
                  Expanded(
                    child: Semantics(
                      container: true,
                      button: true,
                      selected: i == index,
                      label: destinations[i].label,
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          unawaited(HapticFeedback.selectionClick());
                          onSelect(i);
                        },
                        child: AnimatedContainer(
                          duration: motion.standard,
                          curve: MotionTokens.move,
                          height: 52,
                          decoration: BoxDecoration(
                            color: i == index ? c.glassFillStrong : null,
                            borderRadius: const BorderRadius.all(Radii.pill),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                destinations[i].icon,
                                size: 22,
                                color: i == index ? c.textPrimary : c.textTertiary,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                destinations[i].label,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.fade,
                                style: context.stageText.label.copyWith(
                                  fontSize: 11,
                                  height: 1.1,
                                  color: i == index ? c.textPrimary : c.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
