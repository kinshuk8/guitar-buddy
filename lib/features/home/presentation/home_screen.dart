import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/widgets/glass.dart';
import 'package:fretlight/core/widgets/glass_controls.dart';
import 'package:fretlight/core/widgets/screen_header.dart';
import 'package:fretlight/features/learn/application/progress_controller.dart';
import 'package:fretlight/features/learn/domain/curriculum.dart';
import 'package:fretlight/features/learn/presentation/learn_screen.dart';
import 'package:fretlight/features/onboarding/application/onboarding.dart';
import 'package:fretlight/features/songs/application/songs_controller.dart';
import 'package:fretlight/features/tuner/presentation/tuner_button.dart';
import 'package:go_router/go_router.dart';

/// Where the app opens: what to do next, today's practice, the tools you
/// reach for most, and the songs you had open.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider);
    final now = ref.watch(nowProvider)();
    if (ref.watch(firstSessionPendingProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted || !ref.read(firstSessionPendingProvider)) return;
        ref.read(firstSessionPendingProvider.notifier).set(value: false);
        openLesson(context, ref, firstSession);
      });
    }
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 132),
        children: [
          ScreenHeader(
            title: 'Home',
            large: true,
            actions: [
              StreakChip(days: p.streak(now)),
              const TunerButton(),
            ],
          ),
          const SectionLabel('Continue where you left off'),
          NextLessonCard(lesson: p.next, progress: p),
          const SizedBox(height: Space.md),
          TodayCard(progress: p, now: now),
          const SectionLabel('Quick tools'),
          Row(
            children: [
              Expanded(
                child: _Tool(
                  icon: Icons.av_timer_rounded,
                  label: 'Metronome',
                  onTap: () => context.go('/tools/metronome'),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: _Tool(
                  icon: Icons.hearing_rounded,
                  label: 'Identify',
                  onTap: () => context.go('/tools/identify'),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: _Tool(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  onTap: () => context.push('/settings'),
                ),
              ),
            ],
          ),
          const SectionLabel('Recent songs'),
          const _RecentSongs(),
        ],
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    return Semantics(
      container: true,
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: GlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.md),
          child: Column(
            children: [
              Icon(icon, size: 24, color: c.textPrimary),
              const SizedBox(height: Space.xs),
              Text(
                label,
                style: context.stageText.label.copyWith(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentSongs extends ConsumerWidget {
  const _RecentSongs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.stageText;
    final c = context.stage;
    final songs = ref.watch(songsProvider).value ?? const [];
    final recent = [
      for (final id in ref.watch(recentSongsProvider)) ...songs.where((e) => e.id == id),
    ].take(3).toList();
    if (recent.isEmpty) {
      return GlassPanel(
        child: EmptyState(
          message: 'Songs you play along with show up here.',
          action: 'Pick a first song',
          onAction: () => context.go('/songs'),
        ),
      );
    }
    return Column(
      children: [
        for (final e in recent) ...[
          Semantics(
            container: true,
            button: true,
            label: 'Open ${e.song.title}',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Into the Songs tab, so Back leads to the song list.
              onTap: () => context.go('/songs/play?id=${Uri.encodeQueryComponent(e.id)}'),
              child: GlassPanel(
                radius: Radii.md,
                padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
                child: Row(
                  children: [
                    Icon(Icons.music_note_rounded, size: 20, color: c.textSecondary),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Text(
                        e.song.title,
                        style: t.heading,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: c.textTertiary),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.sm),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: GlassPill(
            label: 'All songs',
            semantics: 'All songs',
            onTap: () => context.go('/songs'),
          ),
        ),
      ],
    );
  }
}
