import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/widgets/glass.dart';
import 'package:fretlight/core/widgets/stage_buttons.dart';
import 'package:fretlight/features/tuner/application/tuner_controller.dart';

/// "E A D G B E" for a tuning.
String tuningNotes(Tuning t) =>
    t.strings.map((n) => n.pitchClass.name(Spelling.forRoot(n.pitchClass))).join(' ');

Future<void> showTuningSheet(BuildContext context) =>
    showGlassSheet<void>(context, builder: (_) => const _TuningSheet());

Future<void> showReferenceSheet(BuildContext context) =>
    showGlassSheet<void>(context, builder: (_) => const _ReferenceSheet());

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.md),
    child: Semantics(header: true, child: Text(text, style: context.stageText.title)),
  );
}

class _TuningSheet extends ConsumerWidget {
  const _TuningSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tunerProvider);
    final controller = ref.read(tunerProvider.notifier);
    final c = context.stage;
    final t = context.stageText;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: Space.lg),
      children: [
        const _SheetTitle('Tuning'),
        for (final tuning in state.allTunings)
          _Row(
            selected: tuning.id == state.tuning.id,
            title: tuning.name,
            detail: tuningNotes(tuning),
            onTap: () {
              controller.selectTuning(tuning);
              Navigator.of(context).pop();
            },
            trailing: tuning.isCustom
                ? IconButton(
                    tooltip: 'Delete ${tuning.name}',
                    icon: Icon(Icons.close_rounded, color: c.textTertiary, size: 20),
                    onPressed: () => controller.deleteCustomTuning(tuning),
                  )
                : null,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 0),
          child: StageButton.glass(
            label: 'New custom tuning',
            icon: Icons.add_rounded,
            expand: true,
            onPressed: () async {
              Navigator.of(context).pop();
              await showGlassSheet<void>(
                context,
                builder: (_) => _CustomTuningEditor(base: state.tuning),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 0),
          child: Text(
            'Custom tunings are kept until the app closes; saving arrives with the library.',
            style: t.caption.copyWith(color: c.textTertiary),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.selected,
    required this.title,
    required this.detail,
    required this.onTap,
    this.trailing,
  });

  final bool selected;
  final String title;
  final String detail;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    final t = context.stageText;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: Space.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.sm),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: selected ? Icon(Icons.check_rounded, size: 20, color: c.textPrimary) : null,
              ),
              Expanded(child: Text(title, style: t.body)),
              Text(
                detail,
                style: t.caption.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Six semitone steppers, starting from the current tuning.
class _CustomTuningEditor extends ConsumerStatefulWidget {
  const _CustomTuningEditor({required this.base});

  final Tuning base;

  @override
  ConsumerState<_CustomTuningEditor> createState() => _CustomTuningEditorState();
}

class _CustomTuningEditorState extends ConsumerState<_CustomTuningEditor> {
  late final List<Note> _notes = List.of(widget.base.strings);

  // Keep strings within a range real guitar strings survive: a fifth below
  // to a fourth above standard pitch.
  static final Note _low = Note.parse('A1');
  static final Note _high = Note.parse('A4');

  void _step(int i, int d) {
    final next = _notes[i].transpose(d);
    if (next.midi < _low.midi || next.midi > _high.midi) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() => _notes[i] = next);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    final customCount = ref.read(tunerProvider).customTunings.length;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: Space.lg),
      children: [
        const _SheetTitle('Custom tuning'),
        // Highest string first, as you look down at the headstock.
        for (var i = _notes.length - 1; i >= 0; i--)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.xs),
            child: Row(
              children: [
                SizedBox(width: 72, child: Text('String ${_notes.length - i}', style: t.caption)),
                const Spacer(),
                IconButton(
                  tooltip: 'Lower string ${_notes.length - i}',
                  onPressed: () => _step(i, -1),
                  icon: Icon(Icons.remove_rounded, color: c.textSecondary),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    _notes[i].name(Spelling.forRoot(_notes[i].pitchClass)),
                    textAlign: TextAlign.center,
                    style: t.heading,
                  ),
                ),
                IconButton(
                  tooltip: 'Raise string ${_notes.length - i}',
                  onPressed: () => _step(i, 1),
                  icon: Icon(Icons.add_rounded, color: c.textSecondary),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, 0),
          child: StageButton(
            label: 'Use this tuning',
            expand: true,
            onPressed: () {
              final tuning = Tuning(
                id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
                name: 'Custom ${customCount + 1}',
                strings: List.unmodifiable(_notes),
                isCustom: true,
              );
              ref.read(tunerProvider.notifier).saveCustomTuning(tuning);
              Navigator.of(context).pop();
            },
          ),
        ),
      ],
    );
  }
}

class _ReferenceSheet extends ConsumerWidget {
  const _ReferenceSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tunerProvider);
    final controller = ref.read(tunerProvider.notifier);
    final t = context.stageText;
    final c = context.stage;
    final input = state.input;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(0, 0, 0, Space.lg),
      children: [
        const _SheetTitle('Reference pitch'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Lower reference by 1 hertz',
                onPressed: () => controller.setA4(state.a4 - 1),
                icon: Icon(Icons.remove_rounded, color: c.textSecondary),
              ),
              Expanded(
                child: Semantics(
                  label: 'A equals ${state.a4.round()} hertz',
                  excludeSemantics: true,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: 'A4 = ', style: t.caption),
                        TextSpan(text: '${state.a4.round()}', style: t.readout),
                        TextSpan(text: ' Hz', style: t.caption),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Raise reference by 1 hertz',
                onPressed: () => controller.setA4(state.a4 + 1),
                icon: Icon(Icons.add_rounded, color: c.textSecondary),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          child: Slider(
            value: state.a4,
            min: PitchMath.minA4,
            max: PitchMath.maxA4,
            divisions: (PitchMath.maxA4 - PitchMath.minA4).round(),
            label: '${state.a4.round()} Hz',
            onChanged: controller.setA4,
          ),
        ),
        if (state.a4 != PitchMath.defaultA4)
          Center(
            child: StageButton.glass(
              label: 'Reset to 440 Hz',
              onPressed: () => controller.setA4(PitchMath.defaultA4),
            ),
          ),
        if (input != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, 0),
            child: Text(
              'Microphone: ${input.label}, ${(input.sampleRate / 1000).toStringAsFixed(1)} kHz. '
              'Audio is analysed on this phone and never recorded.',
              style: t.caption.copyWith(color: c.textTertiary),
            ),
          ),
      ],
    );
  }
}
