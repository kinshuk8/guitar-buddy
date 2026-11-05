import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/painting/chord_diagram.dart';
import 'package:fretlight/core/painting/fretboard.dart';
import 'package:fretlight/core/widgets/glass.dart';
import 'package:fretlight/core/widgets/glass_controls.dart';
import 'package:fretlight/core/widgets/music_text.dart';
import 'package:fretlight/core/widgets/stage_buttons.dart';
import 'package:fretlight/features/chords/application/chord_library_provider.dart';
import 'package:fretlight/features/chords/application/chord_player.dart';
import 'package:fretlight/features/chords/domain/chord_library.dart';
import 'package:fretlight/features/chords/presentation/chord_editor.dart';
import 'package:fretlight/features/chords/presentation/chords_screen.dart';
import 'package:fretlight/features/practice/application/practice_controller.dart';
import 'package:fretlight/features/practice/presentation/practice_screen.dart';
import 'package:fretlight/features/settings/application/appearance.dart';
import 'package:go_router/go_router.dart';

class ChordDetailScreen extends ConsumerWidget {
  const ChordDetailScreen({required this.symbol, super.key});

  final String symbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(chordLibraryProvider).value;
    final entry = library?.bySymbol(symbol);
    return SafeArea(
      bottom: false,
      child: switch ((library, entry)) {
        (null, _) => const Center(child: CircularProgressIndicator.adaptive(strokeWidth: 2)),
        (_, null) => _NotFound(symbol: symbol),
        (_, final ChordEntry e) => _Detail(entry: e),
      },
    );
  }
}

class _Detail extends ConsumerStatefulWidget {
  const _Detail({required this.entry});

  final ChordEntry entry;

  @override
  ConsumerState<_Detail> createState() => _DetailState();
}

class _DetailState extends ConsumerState<_Detail> {
  final _strings = FretboardController();
  int _index = 0;

  ChordEntry get _entry => widget.entry;
  Voicing get _voicing => _entry.voicings[_index];

  @override
  void dispose() {
    _strings.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final next = (_index + delta).clamp(0, _entry.voicings.length - 1);
    if (next == _index) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() => _index = next);
  }

  /// Practise this chord alone, or switching to and from another one:
  /// the change is usually the hard part.
  Future<void> _showPracticeSheet(BuildContext context) => showGlassSheet<void>(
    context,
    builder: (sheet) {
      final t = sheet.stageText;
      final c = sheet.stage;
      final favorites = ref.read(favoritesProvider);
      final library = ref.read(chordLibraryProvider).value;
      final partners = <ChordEntry>{
        for (final s in const ['C', 'G', 'D', 'A', 'E', 'Am', 'Em', 'Dm', 'F'])
          ?library?.bySymbol(s),
        for (final s in favorites) ?library?.bySymbol(s),
      }.where((e) => e.chord != _entry.chord).toList();
      void go(List<Chord> sounding, String title) {
        Navigator.of(sheet).pop();
        startPractice(context, ref, PracticePlan(title: title, sounding: sounding));
      }

      return Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text('Practise ${_entry.symbol}', style: t.title)),
            const SizedBox(height: Space.lg),
            StageButton(
              label: 'Just ${_entry.symbol}, 5 times',
              expand: true,
              onPressed: () => go(List.filled(5, _entry.chord), '${_entry.symbol} × 5'),
            ),
            const SizedBox(height: Space.lg),
            Text('Or switch between it and…', style: t.caption.copyWith(color: c.textTertiary)),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final p in partners)
                  GlassPill(
                    label: p.symbol,
                    semantics: 'Switch between ${_entry.symbol} and ${p.symbol}',
                    onTap: () => go([
                      for (var i = 0; i < 6; i++) ...[_entry.chord, p.chord],
                    ], '${_entry.symbol} ⇄ ${p.symbol}'),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );

  void _play() {
    unawaited(HapticFeedback.lightImpact());
    unawaited(ref.read(chordPlayerProvider).strum(_voicing));
    // Same 22 ms spacing as the synthesised strum, so sight matches sound.
    unawaited(_strings.strum(6, gap: const Duration(milliseconds: 22)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    final text = context.stageText;
    final favorite = ref.watch(favoritesProvider.select((f) => f.contains(_entry.symbol)));
    final leftHanded = ref.watch(appearanceProvider.select((a) => a.leftHanded));
    final spelling = chordSpelling(_entry);
    final count = _entry.voicings.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Big enough to read from a music stand, small enough that Play
        // stays on screen on an iPhone SE.
        final diagramWidth = math
            .min(300, math.min(constraints.maxWidth * 0.74, (constraints.maxHeight - 380) * 0.78))
            .clamp(170, 300)
            .toDouble();
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 132),
          child: Column(
            children: [
              Row(
                children: [
                  GlassIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    semantics: 'Back',
                    onTap: () => context.pop(),
                  ),
                  const Spacer(),
                  GlassIconButton(
                    icon: favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    semantics: favorite ? 'Remove from favourites' : 'Add to favourites',
                    onTap: () {
                      unawaited(HapticFeedback.selectionClick());
                      ref.read(favoritesProvider.notifier).toggle(_entry.symbol);
                    },
                  ),
                ],
              ),
              const SizedBox(height: Space.lg),
              ChordSymbol(_entry.chord, spelling: spelling),
              const SizedBox(height: Space.sm),
              Text(_capitalised(spokenChord(_entry.chord, spelling)), style: text.caption),
              const SizedBox(height: Space.xl),
              GestureDetector(
                // Swipe between shapes; the fingers slide to the new one.
                onHorizontalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v.abs() > 200) _go(v < 0 ? 1 : -1);
                },
                child: SizedBox(
                  width: diagramWidth,
                  child: ChordDiagram(
                    voicing: _voicing,
                    root: _entry.chord.root,
                    leftHanded: leftHanded,
                    controller: _strings,
                    onStringTap: (s) => unawaited(ref.read(chordPlayerProvider).pluck(_voicing, s)),
                    semanticLabel:
                        'Shape ${_index + 1} of $count. ${describeVoicing(_voicing)} '
                        'Tap a string to hear it.',
                  ),
                ),
              ),
              const SizedBox(height: Space.md),
              _ShapeStepper(index: _index, count: count, onStep: _go),
              if (_entry.customIds[_index] case final id?)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: GlassPill(
                    label: 'Your shape · Edit',
                    icon: Icons.edit_rounded,
                    semantics: 'Your own shape. Edit it',
                    onTap: () => showChordEditor(
                      context,
                      id: id,
                      name: ref.read(customChordsProvider)[id]?.name,
                      frets: _voicing.frets,
                    ),
                  ),
                ),
              const SizedBox(height: Space.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  StageButton(label: 'Play', icon: Icons.play_arrow_rounded, onPressed: _play),
                  const SizedBox(width: Space.md),
                  StageButton.glass(
                    label: 'Practise',
                    icon: Icons.hearing_rounded,
                    onPressed: () => _showPracticeSheet(context),
                  ),
                ],
              ),
              const SizedBox(height: Space.xl),
              _Tones(chord: _entry.chord, spelling: spelling),
              const SizedBox(height: Space.md),
              Text(
                'Tap a string on the diagram to hear it alone.',
                style: text.caption.copyWith(color: c.textTertiary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ShapeStepper extends StatelessWidget {
  const _ShapeStepper({required this.index, required this.count, required this.onStep});

  final int index;
  final int count;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    Widget arrow(IconData icon, int delta, String label) {
      final enabled = index + delta >= 0 && index + delta < count;
      return Semantics(
        button: true,
        enabled: enabled,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => onStep(delta) : null,
          child: SizedBox(
            width: 48,
            height: 44,
            child: Icon(
              icon,
              size: 22,
              color: enabled ? c.textSecondary : c.textTertiary.withValues(alpha: 0.35),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        arrow(Icons.chevron_left_rounded, -1, 'Previous shape'),
        SizedBox(
          width: 96,
          child: Text(
            'Shape ${index + 1} of $count',
            textAlign: TextAlign.center,
            style: context.stageText.caption.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        arrow(Icons.chevron_right_rounded, 1, 'Next shape'),
      ],
    );
  }
}

/// The chord's notes with their degrees: what makes it this chord.
class _Tones extends StatelessWidget {
  const _Tones({required this.chord, required this.spelling});

  final Chord chord;
  final Spelling spelling;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    final text = context.stageText;
    final intervals = chord.quality.allowed.toList()..sort();
    return Semantics(
      label:
          'Notes: ${[for (final i in intervals) chord.root.transpose(i).name(spelling)].join(', ')}',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final i in intervals)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md - 2),
              child: Column(
                children: [
                  Text(
                    _pretty(chord.root.transpose(i).name(spelling)),
                    style: text.label.copyWith(
                      color: chord.quality.required.contains(i) ? c.textPrimary : c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    degreeName(i, chord.quality),
                    style: text.caption.copyWith(color: c.textTertiary, fontSize: TypeScale.micro),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Degree of [interval] as a guitarist names it in [quality]: `b3`, `5`,
/// and above-the-octave names (`9`, `#11`, `13`) in extended chords.
String degreeName(int interval, ChordQuality quality) {
  final i = quality.allowed;
  final extended = i.contains(10) || i.contains(11);
  final s = switch (interval) {
    0 => '1',
    9 when quality == ChordQuality.dim7 => 'bb7',
    1 => extended ? 'b9' : 'b2',
    2 => extended || quality == ChordQuality.add9 || quality == ChordQuality.minorAdd9 ? '9' : '2',
    3 => i.contains(4) ? '#9' : 'b3',
    4 => '3',
    5 => extended || quality == ChordQuality.add11 ? '11' : '4',
    6 => i.contains(7) ? '#11' : 'b5',
    7 => '5',
    8 => '#5',
    9 => extended ? '13' : '6',
    10 => 'b7',
    _ => '7',
  };
  return _pretty(s);
}

String _pretty(String s) => s.replaceAll('#', '♯').replaceAll('b', '♭');

String _capitalised(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class _NotFound extends StatelessWidget {
  const _NotFound({required this.symbol});

  final String symbol;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Space.gutter),
    child: Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: GlassIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            semantics: 'Back',
            onTap: () => context.pop(),
          ),
        ),
        const Spacer(),
        Text('No chord “$symbol” in the library.', style: context.stageText.bodySecondary),
        const Spacer(),
      ],
    ),
  );
}
