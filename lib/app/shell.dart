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
  Destination('Tune', Icons.tune_rounded, '/tune'),
  Destination('Identify', Icons.graphic_eq_rounded, '/identify'),
  Destination('Chords', Icons.grid_view_rounded, '/chords'),
  Destination('Tempo', Icons.av_timer_rounded, '/tempo'),
  Destination('Songs', Icons.queue_music_rounded, '/songs'),
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
      onSelect: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
    ),
  );
}

/// Floating frosted capsule. Only the active tab shows its label, which keeps
/// the bar calm while still naming where you are (all tabs are labelled for
/// screen readers).
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
                    flex: i == index ? 2 : 1,
                    child: Semantics(
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
                          height: Space.touchTarget,
                          decoration: BoxDecoration(
                            color: i == index ? c.glassFillStrong : null,
                            borderRadius: const BorderRadius.all(Radii.pill),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                destinations[i].icon,
                                size: 22,
                                color: i == index ? c.textPrimary : c.textTertiary,
                              ),
                              if (i == index) ...[
                                const SizedBox(width: Space.sm - 2),
                                Flexible(
                                  child: Text(
                                    destinations[i].label,
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    softWrap: false,
                                    style: context.stageText.label.copyWith(fontSize: 14),
                                  ),
                                ),
                              ],
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
