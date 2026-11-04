import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/audio/input/mic_lifecycle.dart';
import 'package:fretlight/core/design/motion.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/painting/chord_diagram.dart';
import 'package:fretlight/core/painting/fretboard.dart';
import 'package:fretlight/core/painting/fretboard_painter.dart';
import 'package:fretlight/core/widgets/glass.dart';
import 'package:fretlight/core/widgets/listening.dart';
import 'package:fretlight/core/widgets/music_text.dart';
import 'package:fretlight/core/widgets/stage_buttons.dart';
import 'package:fretlight/features/chords/application/chord_library_provider.dart';
import 'package:fretlight/features/chords/presentation/chords_screen.dart' show openChord;
import 'package:fretlight/features/identify/application/identify_controller.dart';
import 'package:fretlight/features/identify/domain/chord_smoother.dart';
import 'package:fretlight/features/identify/domain/note_session.dart';
import 'package:fretlight/features/settings/application/appearance.dart';
import 'package:fretlight/features/tuner/application/tuner_controller.dart';

/// Hear a note or a chord and name it.
class IdentifyScreen extends ConsumerWidget {
  const IdentifyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(identifyProvider);
    final controller = ref.read(identifyProvider.notifier);
    final text = context.stageText;
    final c = context.stage;
    return ListenWhileVisible(
      onChanged: ({required active}) => unawaited(controller.setActive(active: active)),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 112),
          child: Column(
            children: [
              Center(
                child: SizedBox(
                  width: 240,
                  child: StageSegmented<IdentifyMode>(
                    options: IdentifyMode.values,
                    selected: state.mode,
                    labelOf: (m) => switch (m) {
                      IdentifyMode.note => 'Note',
                      IdentifyMode.chord => 'Chord',
                    },
                    onChanged: controller.setMode,
                  ),
                ),
              ),
              Expanded(
                child: switch (state.status) {
                  MicStatus.needsPermission => MicBlocked(
                    title: 'Microphone needed',
                    body: 'Fretlight listens to name what you play. Nothing is recorded or leaves your phone.',
                    action: 'Allow microphone',
                    onAction: controller.requestPermission,
                  ),
                  MicStatus.permanentlyDenied => MicBlocked(
                    title: 'Microphone is off',
                    body: 'Turn on microphone access for Fretlight in Settings to identify notes and chords.',
                    action: 'Open Settings',
                    onAction: controller.openSettings,
                  ),
                  MicStatus.error => MicBlocked(
                    title: 'Couldn’t start the microphone',
                    body: 'Another app may be using it.',
                    action: 'Try again',
                    onAction: controller.retry,
                  ),
                  _ => switch (state.mode) {
                    IdentifyMode.chord => _ChordView(reading: state.chord),
                    IdentifyMode.note => _NoteView(reading: state.note),
                  },
                },
              ),
              if (state.status == MicStatus.interrupted)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: Text('Paused while another app uses the microphone', style: text.caption),
                ),
              // Honest about the limits, without shouting.
              Text(
                'Made for one guitar in a quiet room',
                style: text.caption.copyWith(color: c.textTertiary, fontSize: TypeScale.micro),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChordView extends ConsumerWidget {
  const _ChordView({required this.reading});

  final ChordReading? reading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.stageText;
    final c = context.stage;
    final r = reading;
    final motion = Motion.of(context);

    final Widget body;
    if (r == null) {
      body = const _Hint(
        key: ValueKey('idle'),
        title: 'Strum a chord',
        detail: 'Let all the strings ring',
      );
    } else if (r.singleNote case final pc?) {
      body = _Hint(
        key: const ValueKey('single'),
        title: 'That’s one note: ${_pretty(pc.name(Spelling.forRoot(pc)))}',
        detail: 'Strum more strings, or switch to Note',
      );
    } else if (r.chord case final chord?) {
      body = _HeardChord(key: ValueKey(chord), reading: r, chord: chord);
    } else {
      body = _Hint(
        key: const ValueKey('unsure'),
        title: 'Not sure',
        detail: 'Strum again, a little firmer, closer to the phone',
        titleStyle: t.display.copyWith(color: c.textSecondary),
      );
    }
    return Semantics(
      liveRegion: true,
      child: AnimatedOpacity(
        duration: motion.standard,
        opacity: r?.fading ?? false ? 0.45 : 1,
        child: AnimatedSwitcher(duration: motion.quick, child: body),
      ),
    );
  }
}

class _HeardChord extends ConsumerWidget {
  const _HeardChord({required this.reading, required this.chord, super.key});

  final ChordReading reading;
  final Chord chord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.stageText;
    final c = context.stage;
    final entry = ref.watch(chordLibraryProvider).value?.byChord(chord);
    final leftHanded = ref.watch(appearanceProvider.select((a) => a.leftHanded));
    final bass = reading.bass;
    final sure = reading.confidence >= 0.75;
    final details = [
      if (sure) 'Confident' else 'Fairly sure',
      if (bass != null && bass != chord.root)
        'bass ${_pretty(bass.name(Spelling.forRoot(chord.root)))}',
    ].join(' · ');
    return LayoutBuilder(
      builder: (context, constraints) {
        final diagramWidth = (constraints.maxHeight - 260).clamp(0, 170).toDouble();
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Semantics(
              container: true,
              label: '${spokenChord(chord)}, ${sure ? 'confident' : 'fairly sure'}',
              excludeSemantics: true,
              child: ChordSymbol(chord, size: TypeScale.chordHero),
            ),
            const SizedBox(height: Space.sm),
            Text(details, style: t.caption.copyWith(color: c.textTertiary)),
            if (entry != null && diagramWidth >= 90) ...[
              const SizedBox(height: Space.xl),
              Semantics(
                container: true,
                button: true,
                label: 'Open ${spokenChord(chord)} in the chord library',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () => openChord(context, entry),
                  child: GlassPanel(
                    radius: Radii.md,
                    padding: const EdgeInsets.all(Space.md),
                    child: SizedBox(
                      width: diagramWidth,
                      child: ChordDiagram(
                        voicing: entry.voicings.first,
                        compact: true,
                        leftHanded: leftHanded,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _NoteView extends ConsumerWidget {
  const _NoteView({required this.reading});

  final NoteReading? reading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.stageText;
    final c = context.stage;
    final r = reading;
    final tuning = ref.watch(tunerProvider.select((s) => s.tuning));
    final leftHanded = ref.watch(appearanceProvider.select((a) => a.leftHanded));
    final motion = Motion.of(context);
    final note = r?.note;
    final positions = note == null ? const <FretPosition>[] : tuning.positionsOf(note, maxFret: 12);

    return Column(
      children: [
        const Spacer(),
        AnimatedOpacity(
          duration: motion.standard,
          opacity: r?.fading ?? false ? 0.45 : 1,
          child: note == null
              ? const _Hint(title: 'Play a note', detail: 'One string at a time')
              : Semantics(
                  liveRegion: true,
                  label:
                      '${_spoken(note)}, ${r!.hz.toStringAsFixed(1)} hertz, '
                      '${r.cents.round().abs()} cents ${r.cents >= 0 ? 'sharp' : 'flat'}',
                  excludeSemantics: true,
                  child: Column(
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _pretty(note.pitchClass.name(Spelling.forRoot(note.pitchClass))),
                            style: t.chordHero,
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14, left: 4),
                            child: Text(
                              '${note.octave}',
                              style: t.title.copyWith(color: c.textTertiary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.sm),
                      Text(
                        '${r.hz.toStringAsFixed(1)} Hz · '
                        '${r.cents >= 0 ? '+' : '−'}${r.cents.abs().round()}¢',
                        style: t.caption.copyWith(
                          color: c.textTertiary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        const Spacer(),
        if (positions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Text(
              positions.length == 1 ? 'Played here' : 'Every place to play it',
              style: t.overline,
            ),
          ),
        SizedBox(
          height: 150,
          child: Fretboard(
            leftHanded: leftHanded,
            markers: [
              for (final p in positions) FretMarker(string: p.string, fret: p.fret, emphasis: 1),
            ],
            semanticLabel: positions.isEmpty
                ? 'Fretboard'
                : 'Fretboard: ${positions.map((p) => 'string ${6 - p.string} fret ${p.fret}').join(', ')}',
          ),
        ),
        const SizedBox(height: Space.lg),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.title, required this.detail, this.titleStyle, super.key});

  final String title;
  final String detail;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: titleStyle ?? t.title.copyWith(color: c.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.sm),
          Text(
            detail,
            style: t.caption.copyWith(color: c.textTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

String _pretty(String name) => name.replaceAll('#', '♯').replaceAll('b', '♭');

String _spoken(Note n) {
  final name = n.pitchClass.name(Spelling.forRoot(n.pitchClass));
  return '${name.replaceFirst('#', ' sharp').replaceFirst(RegExp(r'b$'), ' flat')} ${n.octave}';
}
