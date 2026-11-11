import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/app/version.dart';
import 'package:fretlight/core/audio/listening.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/widgets/glass.dart';
import 'package:fretlight/core/widgets/glass_controls.dart';
import 'package:fretlight/core/widgets/stage_buttons.dart';
import 'package:fretlight/features/learn/application/progress_controller.dart';
import 'package:fretlight/features/practice/domain/practice_session.dart';
import 'package:fretlight/features/progressions/data/progression_pack.dart';
import 'package:fretlight/features/settings/application/appearance.dart';
import 'package:fretlight/features/settings/application/chord_matching.dart';
import 'package:fretlight/features/settings/application/sensitivity.dart';
import 'package:fretlight/features/tuner/presentation/tuner_button.dart';
import 'package:go_router/go_router.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.stageText;
    final c = context.stage;
    final appearance = ref.watch(appearanceProvider);
    final controller = ref.read(appearanceProvider.notifier);
    final pack = ref.watch(progressionPackProvider).value;
    final sensitivity = ref.watch(sensitivityProvider);
    final matching = ref.watch(chordMatchingProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.xxl),
            children: [
              Row(
                children: [
                  GlassIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    semantics: 'Back',
                    onTap: () => context.pop(),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Semantics(header: true, child: Text('Settings', style: t.title)),
                  ),
                  const TunerButton(),
                ],
              ),
              const SectionLabel('Appearance'),
              StageSegmented<ThemeMode>(
                options: const [ThemeMode.system, ThemeMode.dark, ThemeMode.light],
                selected: appearance.themeMode,
                labelOf: (m) => switch (m) {
                  ThemeMode.system => 'Auto',
                  ThemeMode.dark => 'Dark',
                  ThemeMode.light => 'Light',
                },
                onChanged: controller.setThemeMode,
              ),
              const SizedBox(height: Space.md),
              _Toggle(
                title: 'Left-handed',
                detail: 'Mirror chord diagrams and the fretboard.',
                value: appearance.leftHanded,
                onChanged: (v) => controller.setLeftHanded(value: v),
              ),
              const SectionLabel('Listening'),
              StageSegmented<Sensitivity>(
                options: Sensitivity.values,
                selected: sensitivity,
                labelOf: (s) => s.label,
                onChanged: ref.read(sensitivityProvider.notifier).set,
              ),
              const SizedBox(height: Space.sm),
              Text(
                '${sensitivity.help} The meter on the Tune, Identify and Practice screens shows '
                'whether the microphone hears you: the line is where it starts listening.',
                style: t.caption.copyWith(color: c.textTertiary),
              ),
              const SizedBox(height: Space.lg),
              Text('Chord matching', style: t.body),
              const SizedBox(height: Space.xs),
              StageSegmented<ChordMatching>(
                options: ChordMatching.values,
                selected: matching,
                labelOf: (m) => m.label,
                onChanged: ref.read(chordMatchingProvider.notifier).set,
              ),
              const SizedBox(height: Space.sm),
              Text(
                '${matching.detail} Lessons and practice use this to decide whether a strum '
                'counts. A different chord whose notes clearly ring (Em for E) still doesn’t.',
                style: t.caption.copyWith(color: c.textTertiary),
              ),
              const SectionLabel('Learning'),
              StageButton.glass(
                label: 'Reset learning progress',
                icon: Icons.restart_alt_rounded,
                expand: true,
                onPressed: () => _confirmReset(context, ref),
              ),
              const SizedBox(height: Space.sm),
              Text(
                'Clears stars, XP, streaks and chord mastery. Your songs, chords and settings stay.',
                style: t.caption.copyWith(color: c.textTertiary),
              ),
              const SectionLabel('Privacy'),
              Text(
                'Fretlight works offline. There is no account, no ads and no analytics, and it '
                'never connects to the internet. The microphone is only on while a listening '
                'screen is open, and audio never leaves your phone or gets saved.',
                style: t.bodySecondary,
              ),
              if (pack != null) ...[
                const SectionLabel('Progression pack'),
                Text(
                  '${pack.items.length} common progressions from Chordonomicon '
                  '(Kantarelis et al., 2024), licensed CC BY-NC 4.0. Only counts are kept: '
                  'no songs, artists or recordings.',
                  style: t.bodySecondary,
                ),
              ],
              const SectionLabel('About'),
              Text('Fretlight $appVersion', style: t.body),
              const SizedBox(height: Space.xs),
              Text(
                'Chord shapes from chords-db (MIT). Starter songs are public domain.',
                style: t.caption.copyWith(color: c.textTertiary),
              ),
              const SizedBox(height: Space.lg),
              StageButton.glass(
                label: 'Licences',
                icon: Icons.description_outlined,
                expand: true,
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'Fretlight',
                  applicationVersion: appVersion,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.title,
    required this.detail,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String detail;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    return MergeSemantics(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.body),
                Text(detail, style: t.caption.copyWith(color: c.textTertiary)),
              ],
            ),
          ),
          Switch.adaptive(value: value, activeTrackColor: c.textSecondary, onChanged: onChanged),
        ],
      ),
    );
  }
}

void _confirmReset(BuildContext context, WidgetRef ref) {
  unawaited(
    showGlassSheet<void>(
      context,
      builder: (sheet) {
        final t = sheet.stageText;
        return Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Reset learning progress?', style: t.title),
              const SizedBox(height: Space.sm),
              Text(
                'Every lesson’s stars, your XP, level, streak, chord mastery and personal bests '
                'are cleared. This can’t be undone.',
                style: t.body,
              ),
              const SizedBox(height: Space.lg),
              StageButton(
                label: 'Reset progress',
                expand: true,
                onPressed: () {
                  ref.read(progressProvider.notifier).reset();
                  Navigator.of(sheet).pop();
                },
              ),
              const SizedBox(height: Space.md),
              StageButton.glass(
                label: 'Keep it',
                expand: true,
                onPressed: () => Navigator.of(sheet).pop(),
              ),
            ],
          ),
        );
      },
    ),
  );
}
