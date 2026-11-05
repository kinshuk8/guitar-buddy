import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/audio/input/mic_lifecycle.dart';
import 'package:fretlight/core/design/motion.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/painting/chord_diagram.dart';
import 'package:fretlight/core/widgets/glass.dart';
import 'package:fretlight/core/widgets/glass_controls.dart';
import 'package:fretlight/core/widgets/listening.dart';
import 'package:fretlight/core/widgets/mic_level.dart';
import 'package:fretlight/core/widgets/music_text.dart';
import 'package:fretlight/core/widgets/stage_buttons.dart';
import 'package:fretlight/features/chords/application/chord_library_provider.dart';
import 'package:fretlight/features/chords/application/chord_player.dart';
import 'package:fretlight/features/practice/application/practice_controller.dart';
import 'package:fretlight/features/practice/domain/practice_session.dart';
import 'package:fretlight/features/settings/application/appearance.dart';
import 'package:go_router/go_router.dart';

/// Starts practising [plan] and opens the practice screen.
void startPractice(BuildContext context, WidgetRef ref, PracticePlan plan) {
  ref.read(practiceProvider.notifier).begin(plan);
  unawaited(context.push('/practice'));
}

class PracticeScreen extends ConsumerWidget {
  const PracticeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(practiceProvider);
    final controller = ref.read(practiceProvider.notifier);
    final plan = state.plan;
    final session = state.session;
    final t = context.stageText;
    final c = context.stage;
    return ListenWhileVisible(
      onChanged: ({required active}) => unawaited(controller.setActive(active: active)),
      // Full screen (no tab bar): practice is one task at a time.
      child: Scaffold(
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
                        icon: Icons.arrow_back_ios_new_rounded,
                        semantics: 'Back',
                        onTap: () => context.pop(),
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plan?.title ?? 'Practice',
                              style: t.heading,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Practice · waits for each chord',
                              style: t.caption.copyWith(color: c.textTertiary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (session != null && !session.done)
                        Text(
                          '${session.index + 1} / ${session.targets.length}',
                          style: t.label.copyWith(
                            color: c.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                  Expanded(
                    child: switch (state.status) {
                      MicStatus.needsPermission => MicBlocked(
                        title: 'Microphone needed',
                        body: 'Practice listens to check each chord. Nothing is recorded.',
                        action: 'Allow microphone',
                        onAction: controller.requestPermission,
                      ),
                      MicStatus.permanentlyDenied => MicBlocked(
                        title: 'Microphone is off',
                        body: 'Turn on microphone access for Fretlight in Settings to practise.',
                        action: 'Open Settings',
                        onAction: controller.openSettings,
                      ),
                      _ when plan == null || session == null => const SizedBox.shrink(),
                      _ when session.done => _Summary(session: session, plan: plan),
                      _ => _Step(state: state, plan: plan, session: session),
                    },
                  ),
                  const MicLevelMeter(),
                  const SizedBox(height: Space.xs),
                  Text(
                    'Made for one guitar in a quiet room',
                    style: t.caption.copyWith(color: c.textTertiary, fontSize: TypeScale.micro),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Step extends ConsumerWidget {
  const _Step({required this.state, required this.plan, required this.session});

  final PracticeState state;
  final PracticePlan plan;
  final PracticeSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.stageText;
    final c = context.stage;
    final motion = Motion.of(context);
    final target = session.current!;
    final shape = plan.shapeOf(target);
    final entry = ref.watch(chordLibraryProvider).value?.byChord(shape);
    final leftHanded = ref.watch(appearanceProvider.select((a) => a.leftHanded));
    final upcoming = session.targets.skip(session.index + 1).take(3).map(plan.shapeOf).toList();
    final line = plan.lines == null ? null : plan.lines![session.index];

    return LayoutBuilder(
      builder: (context, constraints) {
        final diagram = (constraints.maxHeight - 380).clamp(0, 160).toDouble();
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('PLAY', style: t.overline),
            const SizedBox(height: Space.sm),
            AnimatedSwitcher(
              duration: motion.quick,
              child: Semantics(
                key: ValueKey(session.index),
                container: true,
                liveRegion: true,
                label: 'Play ${spokenChord(shape)}',
                excludeSemantics: true,
                child: ChordSymbol(shape, size: TypeScale.chordHero),
              ),
            ),
            if (line != null && line.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text(
                  line.trim(),
                  style: t.bodySecondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (entry != null && diagram >= 80) ...[
              const SizedBox(height: Space.lg),
              SizedBox(
                width: diagram,
                child: ChordDiagram(
                  voicing: entry.voicings.first,
                  compact: true,
                  leftHanded: leftHanded,
                ),
              ),
            ],
            const SizedBox(height: Space.lg),
            _Feedback(state: state, plan: plan),
            const SizedBox(height: Space.lg),
            if (upcoming.isNotEmpty)
              Semantics(
                container: true,
                label: 'Then ${upcoming.map(spokenChord).join(', ')}',
                excludeSemantics: true,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('THEN', style: t.overline),
                    for (final u in upcoming)
                      Padding(
                        padding: const EdgeInsets.only(left: Space.lg),
                        child: ChordSymbol(u, size: 24, color: c.textTertiary),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: Space.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (entry != null)
                  StageButton.glass(
                    label: 'Hear it',
                    icon: Icons.volume_up_rounded,
                    onPressed: () {
                      // Don't let the mic count the app's own strum.
                      ref
                          .read(practiceProvider.notifier)
                          .deafen(const Duration(milliseconds: 2800));
                      unawaited(ref.read(chordPlayerProvider).strum(entry.voicings.first));
                    },
                  ),
                const SizedBox(width: Space.md),
                StageButton.glass(
                  label: 'Skip',
                  icon: Icons.skip_next_rounded,
                  onPressed: () {
                    unawaited(HapticFeedback.selectionClick());
                    ref.read(practiceProvider.notifier).skip();
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// What the last strum sounded like, said with an icon and words.
class _Feedback extends StatelessWidget {
  const _Feedback({required this.state, required this.plan});

  final PracticeState state;
  final PracticePlan plan;

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    final heard = state.heard?.chord;
    final verdict = state.verdict;
    final (IconData icon, String text, Color color) = switch (verdict) {
      null => (Icons.hearing_rounded, 'Listening…', c.textTertiary),
      Verdict.hit => (Icons.check_rounded, 'Nice', c.inTune),
      Verdict.close => (
        Icons.check_rounded,
        'Close enough: ${heard == null ? '' : plan.shapeOf(heard).symbol()}',
        c.inTune,
      ),
      Verdict.miss => (
        Icons.close_rounded,
        'Heard ${heard == null ? 'something else' : plan.shapeOf(heard).symbol()}',
        c.sharp,
      ),
    };
    return Semantics(
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: Space.xs + 2),
          Text(
            text,
            style: t.label.copyWith(color: verdict == null ? c.textTertiary : c.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.session, required this.plan});

  final PracticeSession session;
  final PracticePlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.stageText;
    final c = context.stage;
    final trouble = session.trouble();
    final pct = (session.firstTimeRate * 100).round();
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: Space.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$pct%', style: t.readout, textAlign: TextAlign.center),
          const SizedBox(height: Space.xs),
          Text(
            '${session.targets.length} chords · right first time',
            style: t.caption.copyWith(color: c.textTertiary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.xl),
          if (trouble.isEmpty)
            Text('Every chord, first try.', style: t.title, textAlign: TextAlign.center)
          else ...[
            const SectionLabel('Worth another go'),
            for (final x in trouble)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: GlassPanel(
                  radius: Radii.md,
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
                  child: Row(
                    children: [
                      ChordSymbol(plan.shapeOf(x.chord), size: 28),
                      const Spacer(),
                      Text(
                        [
                          if (x.misses > 0) '${x.misses} wrong ${x.misses == 1 ? 'try' : 'tries'}',
                          if (x.skips > 0) 'skipped ${x.skips}×',
                        ].join(' · '),
                        style: t.caption,
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: Space.xl),
          if (trouble.isNotEmpty)
            StageButton(
              label: 'Practise just these',
              expand: true,
              onPressed: () => ref
                  .read(practiceProvider.notifier)
                  .begin(
                    PracticePlan(
                      title: '${plan.title}: tricky chords',
                      // Each tricky chord three times, in rotation, so the
                      // changes between them get practised too.
                      sounding: [for (var i = 0; i < 3; i++) ...trouble.map((x) => x.chord)],
                      capo: plan.capo,
                    ),
                  ),
            ),
          const SizedBox(height: Space.md),
          StageButton.glass(
            label: 'Start again',
            expand: true,
            onPressed: () => ref.read(practiceProvider.notifier).restart(),
          ),
        ],
      ),
    );
  }
}
