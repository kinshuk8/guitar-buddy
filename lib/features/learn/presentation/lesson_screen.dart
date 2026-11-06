import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/audio/input/mic_lifecycle.dart';
import 'package:fretlight/core/design/motion.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/widgets/glass.dart';
import 'package:fretlight/core/widgets/glass_controls.dart';
import 'package:fretlight/core/widgets/listening.dart';
import 'package:fretlight/core/widgets/mic_level.dart';
import 'package:fretlight/core/widgets/stage_buttons.dart';
import 'package:fretlight/features/learn/application/lesson_controller.dart';
import 'package:fretlight/features/learn/application/progress_controller.dart';
import 'package:fretlight/features/learn/domain/curriculum.dart';
import 'package:fretlight/features/learn/domain/games.dart';
import 'package:fretlight/features/learn/presentation/learn_widgets.dart';
import 'package:fretlight/features/learn/presentation/lesson_games.dart';

/// One lesson, full screen: intro, its steps, then the result.
class LessonScreen extends ConsumerStatefulWidget {
  const LessonScreen({required this.lesson, super.key});

  final Lesson lesson;

  static Route<void> route(Lesson lesson) =>
      MaterialPageRoute<void>(builder: (_) => LessonScreen(lesson: lesson));

  @override
  ConsumerState<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends ConsumerState<LessonScreen> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => ref.read(lessonProvider.notifier).tick());
  late final LessonController _controller = ref.read(lessonProvider.notifier);

  @override
  void initState() {
    super.initState();
    // After the first frame: providers can't change while building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.open(widget.lesson);
    });
  }

  /// Runs the per-frame tick only while something is timed (a change race,
  /// a rhythm run): an idle lesson screen shouldn't redraw every frame.
  void _syncTicker(LessonState state) {
    final game = state.game;
    final timed =
        state.phase == LessonPhase.playing &&
        ((game is ChordGame && game.race != null) || (game is RhythmGame && state.beat0 != null));
    if (timed && !_ticker.isActive) {
      _ticker.start();
    } else if (!timed && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _controller.leave();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lessonProvider);
    final controller = ref.read(lessonProvider.notifier);
    _syncTicker(state);
    final t = context.stageText;
    final c = context.stage;
    final lesson = widget.lesson;
    final ready = identical(state.lesson, lesson);
    final steps = lesson.steps.length;
    final body = Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.md),
            child: Column(
              children: [
                Row(
                  children: [
                    GlassIconButton(
                      icon: Icons.close_rounded,
                      semantics: 'Close lesson',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lesson.title,
                            style: t.heading,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            ready && state.phase != LessonPhase.intro && steps > 1
                                ? 'Part ${state.step + 1} of $steps · ${_stepName(lesson.steps[state.step])}'
                                : lesson.skill.label,
                            style: t.caption.copyWith(color: c.textTertiary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (ready && steps > 1 && state.phase != LessonPhase.intro) ...[
                  const SizedBox(height: Space.md),
                  MeterBar(
                    value:
                        (state.outcomes.length + (state.phase == LessonPhase.playing ? 0.5 : 0)) /
                        steps,
                    height: 4,
                  ),
                ],
                Expanded(
                  child: !ready
                      ? const SizedBox.shrink()
                      : switch (state.phase) {
                          LessonPhase.intro => _Intro(lesson: lesson),
                          _
                              when lesson.steps[state.step].listens &&
                                  state.phase == LessonPhase.playing &&
                                  state.status == MicStatus.needsPermission =>
                            MicBlocked(
                              title: 'Microphone needed',
                              body: 'Lessons listen to check what you play. Nothing is recorded.',
                              action: 'Allow microphone',
                              onAction: controller.requestPermission,
                            ),
                          _
                              when lesson.steps[state.step].listens &&
                                  state.phase == LessonPhase.playing &&
                                  state.status == MicStatus.permanentlyDenied =>
                            MicBlocked(
                              title: 'Microphone is off',
                              body: 'Turn on microphone access for Fretlight in Settings to take this lesson.',
                              action: 'Open Settings',
                              onAction: controller.openSettings,
                            ),
                          LessonPhase.playing => GameView(state: state),
                          LessonPhase.stepDone => _StepResult(state: state),
                          LessonPhase.finished => _Finished(state: state),
                        },
                ),
                if (ready &&
                    state.phase == LessonPhase.playing &&
                    lesson.steps[state.step].listens) ...[
                  const MicLevelMeter(),
                  const SizedBox(height: Space.xs),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    // The mic is only open while a step that listens is on screen.
    final listening =
        ready && state.phase == LessonPhase.playing && lesson.steps[state.step].listens;
    return ListenWhileVisible(
      key: ValueKey(listening),
      onChanged: ({required active}) =>
          unawaited(controller.setActive(active: active && listening)),
      child: body,
    );
  }
}

String _stepName(Exercise e) => switch (e) {
  ChordSteps() => 'Play the chords',
  ChangeRace(:final seconds) => '$seconds-second changes',
  SongSteps() => 'Play the song',
  NoteSteps(:final tuneCents) when tuneCents != null => 'Tune each string',
  NoteSteps(:final prompt) when prompt == NotePrompt.tab => 'Play from tab',
  NoteSteps() => 'Find the notes',
  RhythmSteps() => 'Strum in time',
  Quiz() => 'Quick quiz',
};

class _Intro extends ConsumerWidget {
  const _Intro({required this.lesson});

  final Lesson lesson;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.stageText;
    final c = context.stage;
    final record = ref.watch(progressProvider.select((p) => p.lessons[lesson.id]));
    final chords = lesson.steps
        .expand(
          (s) => switch (s) {
            ChordSteps(:final chords) => chords,
            ChangeRace(:final a, :final b) => [a, b],
            RhythmSteps(:final chord) => [chord],
            _ => const <String>[],
          },
        )
        .fold(<String>[], (out, c) => out.contains(c) ? out : (out..add(c)))
        .take(4)
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: Space.xl, bottom: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: c.glassFillStrong, shape: BoxShape.circle),
              child: Icon(skillIcon(lesson.skill), size: 30, color: c.textPrimary),
            ),
          ),
          const SizedBox(height: Space.lg),
          Text(lesson.title, style: t.display, textAlign: TextAlign.center),
          const SizedBox(height: Space.sm),
          Text(lesson.about, style: t.bodySecondary, textAlign: TextAlign.center),
          if (record != null) ...[
            const SizedBox(height: Space.md),
            Center(child: StarRow(record.stars, size: 22)),
          ],
          if (chords.isNotEmpty) ...[
            const SizedBox(height: Space.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final spec in chords)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                    child: SizedBox(
                      width: chords.length > 2 ? 72 : 100,
                      child: Column(
                        children: [
                          Text(chordSymbolOf(spec), style: t.heading),
                          const SizedBox(height: Space.xs),
                          LessonChordDiagram(spec),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (lesson.tip != null) ...[
            const SizedBox(height: Space.xl),
            GlassPanel(
              radius: Radii.md,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline_rounded, size: 20, color: Palette.lamp),
                  const SizedBox(width: Space.md),
                  Expanded(child: Text(lesson.tip!, style: t.body)),
                ],
              ),
            ),
          ],
          const SizedBox(height: Space.xl),
          Text(
            [for (final s in lesson.steps) _stepName(s)].join('  ·  '),
            style: t.caption.copyWith(color: c.textTertiary),
            textAlign: TextAlign.center,
          ),
          if (lesson.listens) ...[
            const SizedBox(height: Space.xs),
            Text(
              'Listens through the microphone. Nothing is recorded.',
              style: t.caption.copyWith(color: c.textTertiary, fontSize: TypeScale.micro),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: Space.lg),
          StageButton(
            label: record == null ? 'Start' : 'Play again',
            icon: Icons.play_arrow_rounded,
            expand: true,
            onPressed: () => unawaited(ref.read(lessonProvider.notifier).start()),
          ),
        ],
      ),
    );
  }
}

class _OutcomeCard extends StatelessWidget {
  const _OutcomeCard({required this.outcome, required this.title});

  final StepOutcome outcome;
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    return GlassPanel(
      radius: Radii.md,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.toUpperCase(), style: t.overline),
                const SizedBox(height: 2),
                Text(outcome.headline, style: t.heading),
                if (outcome.detail != null)
                  Text(outcome.detail!, style: t.caption.copyWith(color: c.textTertiary)),
              ],
            ),
          ),
          StarRow(outcome.stars, size: 18),
        ],
      ),
    );
  }
}

class _StepResult extends ConsumerWidget {
  const _StepResult({required this.state});

  final LessonState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.stageText;
    final outcome = state.outcomes.last;
    final next = state.lesson!.steps[state.step + 1];
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: StarRow(outcome.stars, size: 40)),
        const SizedBox(height: Space.lg),
        Text(outcome.headline, style: t.title, textAlign: TextAlign.center),
        if (outcome.detail != null) ...[
          const SizedBox(height: Space.xs),
          Text(outcome.detail!, style: t.caption, textAlign: TextAlign.center),
        ],
        const SizedBox(height: Space.xxl),
        Text('Next: ${_stepName(next)}', style: t.bodySecondary, textAlign: TextAlign.center),
        const SizedBox(height: Space.lg),
        StageButton(
          label: 'Next',
          icon: Icons.arrow_forward_rounded,
          expand: true,
          onPressed: ref.read(lessonProvider.notifier).next,
        ),
      ],
    );
  }
}

class _Finished extends ConsumerWidget {
  const _Finished({required this.state});

  final LessonState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.stageText;
    final c = context.stage;
    final award = state.award!;
    final lesson = state.lesson!;
    final progress = ref.watch(progressProvider);
    final motion = Motion.of(context);
    final next = progress.next;
    final headline = switch (award.stars) {
      0 => 'Keep going',
      1 => award.firstClear ? 'Lesson complete' : 'Done',
      2 => 'Nicely played',
      _ => 'Perfect',
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: Space.xl, bottom: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: motion.emphasized,
            curve: Curves.elasticOut,
            builder: (context, v, child) => Transform.scale(scale: v, child: child),
            child: Center(child: StarRow(award.stars, size: 52)),
          ),
          const SizedBox(height: Space.lg),
          Text(headline, style: t.display, textAlign: TextAlign.center),
          const SizedBox(height: Space.xs),
          Text(
            award.stars == 0
                ? 'Finish every part to earn a star. Practice time still counts.'
                : award.stars > award.previousStars && award.previousStars > 0
                ? 'A new best: ${award.stars} stars.'
                : award.stars < 3
                ? 'Play it again for ${award.stars + 1} stars.'
                : 'Every star earned.',
            style: t.bodySecondary,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.lg),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
              decoration: BoxDecoration(
                color: Palette.lamp.withValues(alpha: 0.16),
                borderRadius: const BorderRadius.all(Radii.pill),
              ),
              child: Text(
                '+${award.xp} XP  ·  Level ${progress.level}',
                style: t.label.copyWith(color: Palette.lamp),
              ),
            ),
          ),
          for (final (key, old, value) in award.newBests) ...[
            const SizedBox(height: Space.md),
            Text(
              old == null
                  ? 'First record: ${_bestText(key, value)}'
                  : 'Personal best: ${_bestText(key, value)} (was ${_bestText(key, old)})',
              style: t.label.copyWith(color: c.inTune),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: Space.xl),
          for (final (i, o) in state.outcomes.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: _OutcomeCard(outcome: o, title: _stepName(lesson.steps[i])),
            ),
          const SizedBox(height: Space.lg),
          if (lesson.id != 'workout' && next.id != lesson.id && award.stars > 0)
            StageButton(
              label: 'Next: ${next.title}',
              icon: Icons.arrow_forward_rounded,
              expand: true,
              onPressed: () => Navigator.of(context).pushReplacement(LessonScreen.route(next)),
            ),
          const SizedBox(height: Space.md),
          StageButton.glass(
            label: 'Play again',
            icon: Icons.replay_rounded,
            expand: true,
            onPressed: () => unawaited(ref.read(lessonProvider.notifier).start()),
          ),
          const SizedBox(height: Space.md),
          StageButton.glass(
            label: 'Back to lessons',
            expand: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  static String _bestText(String key, double v) =>
      key.startsWith('race:') ? '${v.round()} changes a minute' : '${v.round()}%';
}
