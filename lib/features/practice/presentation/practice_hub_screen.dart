import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/widgets/glass.dart';
import 'package:fretlight/core/widgets/screen_header.dart';
import 'package:fretlight/features/learn/application/progress_controller.dart';
import 'package:fretlight/features/learn/domain/curriculum.dart';
import 'package:fretlight/features/learn/domain/progress.dart';
import 'package:fretlight/features/learn/presentation/learn_screen.dart';
import 'package:fretlight/features/practice/presentation/chord_practice.dart';
import 'package:fretlight/features/tuner/presentation/tuner_button.dart';
import 'package:go_router/go_router.dart';

/// The Practice tab: the next thing to play, then every way to practise.
class PracticeHubScreen extends ConsumerWidget {
  const PracticeHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider);
    final weakest = p.chordsToWork().take(3).join(', ');
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 132),
        children: [
          const ScreenHeader(title: 'Practice', large: true, actions: [TunerButton()]),
          const SizedBox(height: Space.lg),
          NextLessonCard(lesson: p.next, progress: p),
          const SectionLabel('Drill a chord'),
          const YourChordsStrip(),
          const SectionLabel('Ways to practise'),
          NavRow(
            icon: Icons.school_rounded,
            title: 'Lessons',
            detail:
                '${allLessons.length} short lessons, beginner to mastery. '
                '${p.totalStars} of ${allLessons.length * 3} stars.',
            onTap: () => context.push('/practice/lessons'),
          ),
          const SizedBox(height: Space.sm),
          NavRow(
            icon: Icons.fitness_center_rounded,
            title: 'Daily chord workout',
            detail: 'Drills your weakest chords: $weakest.',
            onTap: () => openLesson(context, ref, dailyWorkout(p)),
          ),
          const SizedBox(height: Space.sm),
          NavRow(
            icon: Icons.grid_view_rounded,
            title: 'Chords',
            detail: 'Every chord in the course, with how well you know each one.',
            onTap: () => context.push('/practice/chords'),
          ),
          const SizedBox(height: Space.sm),
          NavRow(
            icon: Icons.swap_horiz_rounded,
            title: 'Changes',
            detail: 'Any two chords: switch between them, or race the clock.',
            onTap: () => context.push('/practice/changes'),
          ),
          const SizedBox(height: Space.sm),
          NavRow(
            icon: Icons.repeat_rounded,
            title: 'Progressions',
            detail: 'The chord loops most songs are built from.',
            onTap: () => context.push('/practice/progressions'),
          ),
          const SizedBox(height: Space.sm),
          NavRow(
            icon: Icons.insights_rounded,
            title: 'Your progress',
            detail: 'Level ${p.level} · ${p.xp} XP · skills and chord mastery.',
            onTap: () => context.push('/practice/progress'),
          ),
        ],
      ),
    );
  }
}
