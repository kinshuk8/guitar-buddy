import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/design/motion.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/painting/fretboard.dart';
import 'package:fretlight/core/painting/fretboard_painter.dart';
import 'package:fretlight/core/widgets/music_text.dart';
import 'package:fretlight/core/widgets/stage_buttons.dart';
import 'package:fretlight/features/learn/application/lesson_controller.dart';
import 'package:fretlight/features/learn/domain/curriculum.dart';
import 'package:fretlight/features/learn/domain/games.dart';
import 'package:fretlight/features/learn/presentation/learn_widgets.dart';
import 'package:fretlight/features/practice/domain/practice_session.dart';
import 'package:fretlight/features/settings/application/appearance.dart';

/// The running step's game.
class GameView extends StatelessWidget {
  const GameView({required this.state, super.key});

  final LessonState state;

  @override
  Widget build(BuildContext context) => switch (state.game) {
    final ChordGame g => _ChordView(state: state, game: g),
    final NoteGame g => _NoteView(state: state, game: g),
    final RhythmGame g => _RhythmView(state: state, game: g),
    final QuizGame g => _QuizView(state: state, game: g),
    _ => const Center(child: CircularProgressIndicator()),
  };
}

/// The lesson's spec ("G:355433") for the chord the game wants now.
String? _specNow(Exercise? e, ChordGame g) {
  final target = g.session.current;
  if (target == null) return null;
  return switch (e) {
    ChordSteps(:final sequence) => sequence[g.session.index],
    ChangeRace(:final a, :final b) => g.session.index.isEven ? a : b,
    _ => target.symbol(),
  };
}

class _Feedback extends StatelessWidget {
  const _Feedback({
    required this.icon,
    required this.text,
    required this.color,
    this.active = true,
  });

  final IconData icon;
  final String text;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    return Semantics(
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: Space.xs + 2),
          Text(text, style: t.label.copyWith(color: active ? c.textPrimary : c.textTertiary)),
        ],
      ),
    );
  }
}

class _ChordView extends ConsumerWidget {
  const _ChordView({required this.state, required this.game});

  final LessonState state;
  final ChordGame game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.stageText;
    final c = context.stage;
    final motion = Motion.of(context);
    final controller = ref.read(lessonProvider.notifier);
    final spec = _specNow(state.exercise, game);
    final race = game.race;
    if (spec == null) return const SizedBox.shrink();
    final chord = Chord.parse(chordSymbolOf(spec));
    final voicing = lessonVoicing(ref, spec);
    final s = game.session;
    final upcoming = race != null ? const <Chord>[] : s.targets.skip(s.index + 1).take(3).toList();
    final line = state.lines == null || s.index >= state.lines!.length
        ? null
        : state.lines![s.index];
    final (icon, text, color) = switch (state.verdict) {
      null => (Icons.hearing_rounded, 'Listening…', c.textTertiary),
      Verdict.hit => (Icons.check_rounded, 'Nice', c.inTune),
      Verdict.close => (
        Icons.check_rounded,
        'Close enough: ${state.heard?.symbol() ?? ''}',
        c.inTune,
      ),
      Verdict.miss => (
        Icons.close_rounded,
        'Heard ${state.heard?.symbol() ?? 'something else'}',
        c.sharp,
      ),
    };
    return LayoutBuilder(
      builder: (context, box) {
        final diagram = (box.maxHeight - (race == null ? 380 : 450)).clamp(0, 150).toDouble();
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (race != null) _RaceClock(game: game),
            Text('PLAY', style: t.overline),
            const SizedBox(height: Space.sm),
            AnimatedSwitcher(
              duration: motion.quick,
              child: Semantics(
                key: ValueKey(s.index),
                liveRegion: true,
                label: 'Play ${spokenChord(chord)}',
                excludeSemantics: true,
                child: ChordSymbol(chord, size: race == null ? TypeScale.chordHero : 96),
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
            if (voicing != null && diagram >= 80) ...[
              const SizedBox(height: Space.lg),
              SizedBox(width: diagram, child: LessonChordDiagram(spec)),
            ],
            const SizedBox(height: Space.lg),
            _Feedback(icon: icon, text: text, color: color, active: state.verdict != null),
            if (upcoming.isNotEmpty) ...[
              const SizedBox(height: Space.lg),
              Row(
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
            ],
            const SizedBox(height: Space.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (voicing != null)
                  StageButton.glass(
                    label: 'Hear it',
                    icon: Icons.volume_up_rounded,
                    onPressed: () => controller.hear(voicing),
                  ),
                const SizedBox(width: Space.md),
                if (race == null)
                  StageButton.glass(
                    label: 'Skip',
                    icon: Icons.skip_next_rounded,
                    onPressed: () {
                      unawaited(HapticFeedback.selectionClick());
                      controller.skip();
                    },
                  )
                else
                  StageButton.glass(
                    label: 'Stop',
                    icon: Icons.stop_rounded,
                    onPressed: controller.stopRace,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The race's clock and score, ticking every frame.
class _RaceClock extends ConsumerStatefulWidget {
  const _RaceClock({required this.game});

  final ChordGame game;

  @override
  ConsumerState<_RaceClock> createState() => _RaceClockState();
}

class _RaceClockState extends ConsumerState<_RaceClock> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    final now = ref.read(lessonClockProvider)();
    final left = widget.game.remaining(now)!;
    final started = widget.game.raceStart != null;
    final secs = (left.inMilliseconds / 1000).ceil();
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Semantics(
            label: started ? '$secs seconds left' : 'Timer starts with your first chord',
            excludeSemantics: true,
            child: ProgressRing(
              value: left.inMilliseconds / (widget.game.race!.seconds * 1000),
              size: 72,
              color: secs <= 10 ? c.sharp : c.inTune,
              child: Text(
                '$secs',
                style: t.title.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          ),
          const SizedBox(width: Space.lg),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.game.changes}',
                  style: t.readout.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                Text(
                  started ? 'changes' : 'Clock starts\nwith your first chord',
                  style: t.caption.copyWith(color: c.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteView extends ConsumerWidget {
  const _NoteView({required this.state, required this.game});

  final LessonState state;
  final NoteGame game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.stageText;
    final c = context.stage;
    final controller = ref.read(lessonProvider.notifier);
    final leftHanded = ref.watch(appearanceProvider.select((a) => a.leftHanded));
    final spot = game.currentSpot;
    final target = game.current;
    if (spot == null || target == null) return const SizedBox.shrink();
    final steps = game.steps;
    final tuning = steps.tuneCents != null;
    final heard = state.note;
    final onTarget = heard != null && !heard.fading && heard.note == target;
    final name = QuizGame.noteName(target.pitchClass);

    final (icon, text, color) = switch (heard) {
      null => (Icons.hearing_rounded, 'Listening…', c.textTertiary),
      _ when onTarget && tuning && heard.cents.abs() > steps.tuneCents! => (
        heard.cents > 0 ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
        heard.cents > 0
            ? '${formatCents(heard.cents)}: tune down a little'
            : '${formatCents(heard.cents)}: tune up a little',
        heard.cents > 0 ? c.sharp : c.flat,
      ),
      _ when onTarget => (Icons.check_rounded, tuning ? 'In tune: hold it' : 'That’s it', c.inTune),
      _ when game.wrong != null => (Icons.close_rounded, 'Heard ${game.wrong!.name()}', c.sharp),
      _ => (Icons.hearing_rounded, 'Listening…', c.textTertiary),
    };

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (steps.prompt == NotePrompt.tab) ...[
          if (steps.title != null) Text(steps.title!, style: t.heading),
          const SizedBox(height: Space.lg),
          TabStrip(spots: steps.spots, current: game.index),
          const SizedBox(height: Space.lg),
          Text('Play ${QuizStringNames.spot(spot)}', style: t.bodySecondary),
        ] else ...[
          Text(tuning ? 'TUNE' : 'PLAY', style: t.overline),
          const SizedBox(height: Space.sm),
          Semantics(
            liveRegion: true,
            label: 'Play $name on ${QuizStringNames.spot(spot)}',
            excludeSemantics: true,
            child: ProgressRing(
              value: tuning ? game.tuneProgress : 0,
              size: 150,
              stroke: 6,
              child: Text(name, style: t.chordHero.copyWith(fontSize: 88)),
            ),
          ),
          const SizedBox(height: Space.sm),
          Text(
            spot.fret == 0
                ? 'The open ${QuizStringNames.of(spot.string)} string'
                : QuizStringNames.spot(spot).replaceFirst('the', 'On the'),
            style: t.bodySecondary,
          ),
          const SizedBox(height: Space.lg),
          SizedBox(
            height: 120,
            child: Fretboard(
              leftHanded: leftHanded,
              lastFret: spot.fret > 5 ? 9 : 5,
              markers: [FretMarker(string: spot.string, fret: spot.fret, emphasis: 1)],
              semanticLabel: 'Fretboard showing ${QuizStringNames.spot(spot)}',
            ),
          ),
        ],
        const SizedBox(height: Space.lg),
        _Feedback(icon: icon, text: text, color: color, active: heard != null),
        const SizedBox(height: Space.xs),
        Text(
          '${game.index + 1} of ${game.targets.length}',
          style: t.caption.copyWith(color: c.textTertiary),
        ),
        const SizedBox(height: Space.xl),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StageButton.glass(
              label: 'Hear it',
              icon: Icons.volume_up_rounded,
              onPressed: () => controller.hearNote(spot),
            ),
            const SizedBox(width: Space.md),
            StageButton.glass(
              label: 'Skip',
              icon: Icons.skip_next_rounded,
              onPressed: controller.skip,
            ),
          ],
        ),
      ],
    );
  }
}

class _RhythmView extends ConsumerStatefulWidget {
  const _RhythmView({required this.state, required this.game});

  final LessonState state;
  final RhythmGame game;

  @override
  ConsumerState<_RhythmView> createState() => _RhythmViewState();
}

class _RhythmViewState extends ConsumerState<_RhythmView> with SingleTickerProviderStateMixin {
  // Redraws every frame, but only once the count-in has started.
  late final Ticker _ticker = createTicker((_) => setState(() {}));

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    final game = widget.game;
    final steps = game.steps;
    if (widget.state.beat0 != null && !_ticker.isActive) _ticker.start();
    final b0 = widget.state.beat0;
    final now = ref.read(lessonClockProvider)();
    final elapsed = b0 == null ? null : (now - b0).inMicroseconds / 1e6;
    final beatPos = elapsed == null ? null : elapsed / game.beatSeconds;
    final counting = beatPos != null && beatPos < 0;
    final bar = beatPos == null || beatPos < 0 ? 0 : (beatPos / steps.beatsPerBar).floor();
    final beatInBar = beatPos == null ? null : (beatPos % steps.beatsPerBar).floor();
    final match = game.match();
    final chord = Chord.parse(chordSymbolOf(steps.chord));

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ChordSymbol(chord, size: 56),
        const SizedBox(height: Space.xs),
        Text('${steps.name}  ·  ${steps.bpm} BPM', style: t.caption),
        const SizedBox(height: Space.xl),
        // The pattern: an arrow per stroke, placed in its beat.
        _PatternRow(steps: steps, offsets: match.offsets, bar: bar, beatPos: beatPos),
        const SizedBox(height: Space.xl),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var b = 0; b < steps.beatsPerBar; b++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 60),
                margin: const EdgeInsets.symmetric(horizontal: Space.sm),
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: beatInBar == b ? (counting ? Palette.lamp : c.primaryFill) : c.glassFill,
                  border: Border.all(color: c.glassBorder),
                ),
                child: Text(
                  '${b + 1}',
                  style: t.label.copyWith(color: beatInBar == b ? c.onPrimary : c.textTertiary),
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.lg),
        Text(
          b0 == null
              ? 'Strum along when the count-in ends. Watch the dots: they show the beat.'
              : counting
              ? 'Count in: ${(-beatPos).ceil()}…'
              : 'Bar ${bar + 1} of ${steps.bars}',
          style: t.bodySecondary,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Space.xl),
        if (b0 == null)
          StageButton(
            label: 'Count me in',
            icon: Icons.play_arrow_rounded,
            onPressed: () => unawaited(ref.read(lessonProvider.notifier).startRhythm()),
          ),
      ],
    );
  }
}

class _PatternRow extends StatelessWidget {
  const _PatternRow({
    required this.steps,
    required this.offsets,
    required this.bar,
    required this.beatPos,
  });

  final RhythmSteps steps;
  final List<double?> offsets;
  final int bar;
  final double? beatPos;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    final t = context.stageText;
    final perBar = steps.pattern.length;
    return Semantics(
      label: 'Pattern: ${steps.pattern.map((s) => s.down ? 'down' : 'up').join(', ')}',
      excludeSemantics: true,
      child: SizedBox(
        height: 64,
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            return Stack(
              children: [
                for (var b = 0; b < steps.beatsPerBar; b++)
                  Positioned(
                    left: w * (b + 0.5) / steps.beatsPerBar - 10,
                    bottom: 0,
                    child: SizedBox(
                      width: 20,
                      child: Text('${b + 1}', style: t.caption, textAlign: TextAlign.center),
                    ),
                  ),
                for (final (i, s) in steps.pattern.indexed)
                  Positioned(
                    left: w * (s.beat + 0.5) / steps.beatsPerBar - 16,
                    top: 0,
                    child: Icon(
                      s.down ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                      size: 32,
                      color: _color(c, bar * perBar + i, bar * steps.beatsPerBar + s.beat),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Color _color(StageColors c, int index, double beat) {
    final pos = beatPos;
    if (pos == null || pos < beat + 0.3 || index >= offsets.length) {
      return pos != null && (pos - beat).abs() < 0.3 ? c.textPrimary : c.textSecondary;
    }
    return offsets[index] != null ? c.inTune : c.sharp;
  }
}

class _QuizView extends ConsumerWidget {
  const _QuizView({required this.state, required this.game});

  final LessonState state;
  final QuizGame game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.stageText;
    final c = context.stage;
    final q = game.current;
    final leftHanded = ref.watch(appearanceProvider.select((a) => a.leftHanded));
    if (q == null) return const SizedBox.shrink();
    final last = state.lastAnswer;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('${game.index + 1} / ${game.questions.length}', style: t.caption),
            const Spacer(),
            if (game.combo >= 2)
              Row(
                children: [
                  const Icon(Icons.bolt_rounded, size: 18, color: Palette.lamp),
                  Text('${game.combo} in a row', style: t.caption.copyWith(color: Palette.lamp)),
                ],
              ),
          ],
        ),
        const SizedBox(height: Space.lg),
        Text(q.prompt, style: t.title, textAlign: TextAlign.center),
        if (q.kind == QuizKind.stringName)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(
              'As you look down at your guitar: the thickest string is at the bottom.',
              style: t.caption.copyWith(color: c.textTertiary),
              textAlign: TextAlign.center,
            ),
          ),
        const SizedBox(height: Space.lg),
        SizedBox(
          height: 170,
          child: switch (q.kind) {
            QuizKind.stringName || QuizKind.fretNote => Center(
              child: SizedBox(
                height: 130,
                child: Fretboard(
                  leftHanded: leftHanded,
                  lastFret: q.spot!.fret > 5 ? 9 : 5,
                  markers: [FretMarker(string: q.spot!.string, fret: q.spot!.fret, emphasis: 1)],
                  semanticLabel: q.kind == QuizKind.stringName
                      ? 'A string is lit'
                      : 'A note on ${QuizStringNames.spot(q.spot!)}',
                ),
              ),
            ),
            QuizKind.tabNote => Center(child: TabStrip(spots: [q.spot!], current: 0)),
            QuizKind.chordName => Center(
              child: SizedBox(width: 130, child: LessonChordDiagram(q.chord!)),
            ),
          },
        ),
        const SizedBox(height: Space.md),
        SizedBox(
          height: 22,
          child: last == null
              ? null
              : Text(
                  last ? 'Right' : 'Not quite',
                  style: t.label.copyWith(color: last ? c.inTune : c.sharp),
                  textAlign: TextAlign.center,
                ),
        ),
        const SizedBox(height: Space.md),
        Wrap(
          spacing: Space.md,
          runSpacing: Space.md,
          alignment: WrapAlignment.center,
          children: [
            for (final (i, o) in q.options.indexed)
              SizedBox(
                width: q.options.length > 4 ? 104 : 160,
                child: StageButton.glass(
                  label: o,
                  expand: true,
                  onPressed: () {
                    unawaited(HapticFeedback.selectionClick());
                    ref.read(lessonProvider.notifier).answer(i);
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }
}
