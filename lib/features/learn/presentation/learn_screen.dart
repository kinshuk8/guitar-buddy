import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/widgets/glass.dart';
import 'package:fretlight/core/widgets/music_text.dart';
import 'package:fretlight/core/widgets/stage_buttons.dart';
import 'package:fretlight/features/learn/application/progress_controller.dart';
import 'package:fretlight/features/learn/domain/curriculum.dart';
import 'package:fretlight/features/learn/domain/progress.dart';
import 'package:fretlight/features/learn/presentation/learn_widgets.dart';
import 'package:fretlight/features/learn/presentation/lesson_screen.dart';

/// The Learn tab: where you are, what to play today, and the path ahead.
class LearnScreen extends ConsumerWidget {
  const LearnScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider);
    final now = ref.watch(nowProvider)();
    final t = context.stageText;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, 120),
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(header: true, child: Text('Learn', style: t.display)),
              ),
              _StreakChip(days: p.streak(now)),
            ],
          ),
          const SizedBox(height: Space.lg),
          _LevelCard(progress: p),
          const SizedBox(height: Space.md),
          _TodayCard(progress: p, now: now),
          const SizedBox(height: Space.md),
          _NextCard(lesson: p.next, progress: p),
          const SizedBox(height: Space.xl),
          const SectionLabel('Skills'),
          _Skills(progress: p),
          const SizedBox(height: Space.xl),
          _ChordMastery(progress: p),
          for (final (i, stage) in curriculum.indexed) ...[
            const SizedBox(height: Space.xl),
            _StageSection(index: i, stage: stage, progress: p),
          ],
        ],
      ),
    );
  }
}

class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    final t = context.stageText;
    return Semantics(
      label: days == 0 ? 'No streak yet' : '$days day streak',
      excludeSemantics: true,
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_fire_department_rounded,
              size: 20,
              color: days > 0 ? Palette.lamp : c.textTertiary,
            ),
            const SizedBox(width: Space.xs),
            Text(
              '$days',
              style: t.label.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.progress});

  final Progress progress;

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    final p = progress;
    final toNext = Progress.xpForLevel(p.level + 1) - p.xp;
    return GlassPanel(
      child: Row(
        children: [
          ProgressRing(
            value: p.levelProgress,
            size: 60,
            color: Palette.lamp,
            child: Text('${p.level}', style: t.title),
          ),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.rank, style: t.heading),
                const SizedBox(height: 2),
                Text(
                  'Level ${p.level} · ${p.xp} XP · $toNext to level ${p.level + 1}',
                  style: t.caption,
                ),
                const SizedBox(height: Space.sm),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 16, color: Palette.lamp),
                    const SizedBox(width: Space.xs),
                    Text(
                      '${p.totalStars} of ${allLessons.length * 3} stars',
                      style: t.caption.copyWith(color: c.textTertiary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayCard extends ConsumerWidget {
  const _TodayCard({required this.progress, required this.now});

  final Progress progress;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.stageText;
    final c = context.stage;
    final minutes = progress.minutesOn(now);
    final goal = progress.dailyGoalMinutes;
    final met = minutes >= goal;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Semantics(
                label: '$minutes of $goal minutes practised today',
                excludeSemantics: true,
                child: ProgressRing(
                  value: progress.goalProgress(now),
                  child: met
                      ? Icon(Icons.check_rounded, color: c.inTune)
                      : Text('$minutes', style: t.heading),
                ),
              ),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Today', style: t.overline),
                    const SizedBox(height: 2),
                    Text(
                      met ? 'Daily goal reached' : '$minutes of $goal minutes',
                      style: t.heading,
                    ),
                    GestureDetector(
                      onTap: () => _pickGoal(context, ref),
                      child: Text(
                        'Change goal',
                        style: t.caption.copyWith(
                          color: c.textTertiary,
                          decoration: TextDecoration.underline,
                          decorationColor: c.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          StageButton(
            label: 'Daily chord workout',
            icon: Icons.fitness_center_rounded,
            expand: true,
            onPressed: () => openLesson(context, ref, dailyWorkout(progress)),
          ),
          const SizedBox(height: Space.xs),
          Text(
            'Your weakest chords: ${progress.chordsToWork().take(3).join(', ')}',
            style: t.caption.copyWith(color: c.textTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _pickGoal(BuildContext context, WidgetRef ref) {
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
                Text('Daily goal', style: t.title),
                const SizedBox(height: Space.xs),
                Text(
                  'Minutes of practice a day. Little and often is what builds skill.',
                  style: t.caption,
                ),
                const SizedBox(height: Space.lg),
                StageSegmented<int>(
                  options: ProgressController.goals,
                  selected: progress.dailyGoalMinutes,
                  labelOf: (m) => '$m min',
                  onChanged: (m) {
                    ref.read(progressProvider.notifier).setDailyGoal(m);
                    Navigator.of(sheet).pop();
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NextCard extends ConsumerWidget {
  const _NextCard({required this.lesson, required this.progress});

  final Lesson lesson;
  final Progress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.stageText;
    final c = context.stage;
    final stage = stageOf(lesson);
    final replay = progress.completed(lesson);
    return Semantics(
      button: true,
      label: '${replay ? 'Improve' : 'Up next'}: ${lesson.title}, ${stage.title}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => openLesson(context, ref, lesson),
        child: GlassPanel(
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: c.primaryFill, shape: BoxShape.circle),
                child: Icon(Icons.play_arrow_rounded, color: c.onPrimary, size: 30),
              ),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(replay ? 'IMPROVE' : 'UP NEXT', style: t.overline),
                    const SizedBox(height: 2),
                    Text(lesson.title, style: t.heading),
                    Text(
                      '${stage.title} · ${lesson.skill.label}',
                      style: t.caption.copyWith(color: c.textTertiary),
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

class _Skills extends StatelessWidget {
  const _Skills({required this.progress});

  final Progress progress;

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    return GlassPanel(
      child: Column(
        children: [
          for (final s in Skill.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs + 2),
              child: Semantics(
                label: '${s.label}: ${(progress.skillLevel(s) * 100).round()} percent',
                excludeSemantics: true,
                child: Row(
                  children: [
                    Icon(skillIcon(s), size: 18, color: c.textSecondary),
                    const SizedBox(width: Space.sm),
                    SizedBox(width: 78, child: Text(s.label, style: t.label)),
                    Expanded(child: MeterBar(value: progress.skillLevel(s))),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${(progress.skillLevel(s) * 100).round()}%',
                        style: t.caption.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Chords you've met, by how well you know them, and change-race bests.
class _ChordMastery extends StatelessWidget {
  const _ChordMastery({required this.progress});

  final Progress progress;

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    final known = <String>{
      for (final l in allLessons.where(progress.completed)) ...l.chords,
    }.toList()..sort((a, b) => progress.mastery(b).compareTo(progress.mastery(a)));
    final races = [
      for (final MapEntry(:key, :value) in progress.skills.entries)
        if (key.startsWith('race:')) (key.substring(5).replaceAll('|', ' ↔ '), value),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    if (known.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Your chords'),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: Space.md,
                runSpacing: Space.md,
                children: [
                  for (final symbol in known)
                    Semantics(
                      label:
                          '${spokenChord(Chord.parse(symbol))}: ${progress.mastery(symbol).round()} percent mastered',
                      excludeSemantics: true,
                      child: ProgressRing(
                        value: progress.mastery(symbol) / 100,
                        size: 52,
                        stroke: 4,
                        child: ChordSymbol(Chord.parse(symbol), size: 18),
                      ),
                    ),
                ],
              ),
              if (races.isNotEmpty) ...[
                const SizedBox(height: Space.lg),
                Text('CHANGES A MINUTE, YOUR BEST', style: t.overline),
                const SizedBox(height: Space.xs),
                for (final (pair, best) in races.take(5))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(child: Text(pair, style: t.label)),
                        Text(
                          '${best.round()}',
                          style: t.label.copyWith(
                            color: c.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StageSection extends ConsumerWidget {
  const _StageSection({required this.index, required this.stage, required this.progress});

  final int index;
  final Stage stage;
  final Progress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.stageText;
    final c = context.stage;
    final open = index <= progress.openStage;
    final stars = stage.lessons.fold(0, (s, l) => s + progress.starsOf(l.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  stage.title,
                  style: t.title.copyWith(color: open ? null : c.textTertiary),
                ),
              ),
            ),
            const Icon(Icons.star_rounded, size: 16, color: Palette.lamp),
            const SizedBox(width: 2),
            Text('$stars / ${stage.lessons.length * 3}', style: t.caption),
          ],
        ),
        const SizedBox(height: 2),
        Text(stage.about, style: t.caption.copyWith(color: c.textTertiary)),
        if (!open) ...[
          const SizedBox(height: Space.md),
          StageButton.glass(
            label: 'I can already play this: start here',
            icon: Icons.lock_open_rounded,
            expand: true,
            onPressed: () => _confirmJump(context, ref),
          ),
        ],
        for (final unit in stage.units) ...[
          const SizedBox(height: Space.md),
          Text(unit.title.toUpperCase(), style: t.overline),
          const SizedBox(height: Space.xs),
          GlassPanel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, lesson) in unit.lessons.indexed) ...[
                  if (i > 0) Divider(height: 1, color: c.glassBorder),
                  _LessonTile(lesson: lesson, progress: progress),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _confirmJump(BuildContext context, WidgetRef ref) {
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
                Text('Start at ${stage.title}?', style: t.title),
                const SizedBox(height: Space.sm),
                Text(
                  'Opens ${stage.title} without finishing the stages before it. They stay open too, '
                  'so you can go back for their stars any time.',
                  style: t.body,
                ),
                const SizedBox(height: Space.lg),
                StageButton(
                  label: 'Start at ${stage.title}',
                  expand: true,
                  onPressed: () {
                    ref.read(progressProvider.notifier).jumpTo(index);
                    Navigator.of(sheet).pop();
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LessonTile extends ConsumerWidget {
  const _LessonTile({required this.lesson, required this.progress});

  final Lesson lesson;
  final Progress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.stageText;
    final c = context.stage;
    final unlocked = progress.unlocked(lesson);
    final stars = progress.starsOf(lesson.id);
    return Semantics(
      button: unlocked,
      label: '${lesson.title}. ${lesson.skill.label}. ${unlocked ? '$stars of 3 stars' : 'Locked'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: unlocked
            ? () => openLesson(context, ref, lesson)
            : () => unawaited(HapticFeedback.selectionClick()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
          child: Row(
            children: [
              Icon(
                unlocked ? skillIcon(lesson.skill) : Icons.lock_outline_rounded,
                size: 20,
                color: unlocked ? c.textSecondary : c.textTertiary,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  lesson.title,
                  style: t.label.copyWith(color: unlocked ? c.textPrimary : c.textTertiary),
                ),
              ),
              if (unlocked) StarRow(stars, size: 15),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens [lesson] in the lesson screen.
void openLesson(BuildContext context, WidgetRef ref, Lesson lesson) {
  unawaited(HapticFeedback.selectionClick());
  Navigator.of(context, rootNavigator: true).push(LessonScreen.route(lesson));
}
