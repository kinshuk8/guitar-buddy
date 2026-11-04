import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/widgets/glass.dart';
import 'package:fretlight/core/widgets/glass_controls.dart';
import 'package:fretlight/core/widgets/music_text.dart';
import 'package:fretlight/core/widgets/stage_buttons.dart';
import 'package:fretlight/features/chords/application/chord_library_provider.dart';
import 'package:fretlight/features/chords/application/chord_player.dart';
import 'package:fretlight/features/practice/application/practice_controller.dart';
import 'package:fretlight/features/practice/presentation/practice_screen.dart';
import 'package:fretlight/features/progressions/data/progression_pack.dart';

/// Slivers listing the pack's progressions, most used first.
List<Widget> progressionSlivers(BuildContext context, ProgressionPack pack) {
  final t = context.stageText;
  final c = context.stage;
  return [
    SliverPadding(
      padding: const EdgeInsets.fromLTRB(Space.gutter + Space.xs, Space.lg, Space.gutter, Space.md),
      sliver: SliverToBoxAdapter(
        child: Text(
          'The loops songs use most. Practise the changes until they’re automatic.',
          style: t.caption.copyWith(color: c.textTertiary),
        ),
      ),
    ),
    SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      sliver: SliverList.separated(
        itemCount: pack.items.length,
        separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
        itemBuilder: (context, i) => _Row(p: pack.items[i]),
      ),
    ),
    // Attribution, as the licence asks.
    SliverPadding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, 0),
      sliver: SliverToBoxAdapter(
        child: Text(
          'Progressions from Chordonomicon (Kantarelis et al., 2024), CC BY-NC 4.0. '
          'Only counts are kept: no songs, artists or recordings.',
          style: t.caption.copyWith(color: c.textTertiary, fontSize: TypeScale.micro),
          textAlign: TextAlign.center,
        ),
      ),
    ),
  ];
}

String _usage(Progression p) {
  final n = p.songs >= 1000 ? '${(p.songs / 1000).toStringAsFixed(1)}k' : '${p.songs}';
  return [
    'In $n songs',
    if (p.genres.isNotEmpty) p.genres.take(2).join(', '),
    if (p.section != 'song') 'often a ${p.section}',
  ].join(' · ');
}

class _Row extends StatelessWidget {
  const _Row({required this.p});

  final Progression p;

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    return Semantics(
      button: true,
      label: '${p.chords.map(spokenChord).join(', ')}. ${_usage(p)}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => showGlassSheet<void>(context, builder: (_) => _Sheet(p: p)),
        child: GlassPanel(
          radius: Radii.md,
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: Space.md,
                      children: [for (final ch in p.chords) ChordSymbol(ch, size: 24)],
                    ),
                    const SizedBox(height: Space.xs),
                    Text(_usage(p), style: t.caption.copyWith(color: c.textTertiary)),
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

class _Sheet extends ConsumerStatefulWidget {
  const _Sheet({required this.p});

  final Progression p;

  @override
  ConsumerState<_Sheet> createState() => _SheetState();
}

class _SheetState extends ConsumerState<_Sheet> {
  int _shift = 0;
  bool _playing = false;

  List<Chord> get _chords => [for (final c in widget.p.chords) c.transpose(_shift)];

  /// Plays the loop once, a chord per beat-and-a-bit: a preview, not a
  /// timed performance (that's the metronome's job).
  Future<void> _hear() async {
    if (_playing) return;
    setState(() => _playing = true);
    final library = ref.read(chordLibraryProvider).value;
    final player = ref.read(chordPlayerProvider);
    for (final c in _chords) {
      if (!mounted) return;
      final v = library?.byChord(c)?.voicings.first;
      if (v != null) unawaited(player.strum(v));
      await Future<void>.delayed(const Duration(milliseconds: 1100));
    }
    if (mounted) setState(() => _playing = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    final chords = _chords;
    final key = chords.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: chords.map(spokenChord).join(', '),
            excludeSemantics: true,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: Space.lg,
              children: [for (final ch in chords) ChordSymbol(ch, size: 44)],
            ),
          ),
          const SizedBox(height: Space.sm),
          Text(
            _usage(widget.p),
            style: t.caption.copyWith(color: c.textTertiary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GlassIconButton(
                icon: Icons.remove_rounded,
                semantics: 'Key down a semitone',
                onTap: () => setState(() => _shift = (_shift - 1) % 12),
              ),
              SizedBox(
                width: 140,
                child: Text(
                  'Starts on ${key.symbol()}',
                  style: t.label,
                  textAlign: TextAlign.center,
                ),
              ),
              GlassIconButton(
                icon: Icons.add_rounded,
                semantics: 'Key up a semitone',
                onTap: () => setState(() => _shift = (_shift + 1) % 12),
              ),
            ],
          ),
          const SizedBox(height: Space.xl),
          Row(
            children: [
              Expanded(
                child: StageButton.glass(
                  label: _playing ? 'Playing…' : 'Hear it',
                  icon: Icons.volume_up_rounded,
                  expand: true,
                  onPressed: _playing ? null : () => unawaited(_hear()),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: StageButton(
                  label: 'Practise',
                  icon: Icons.hearing_rounded,
                  expand: true,
                  onPressed: () {
                    Navigator.of(context).pop();
                    startPractice(
                      context,
                      ref,
                      PracticePlan(
                        title: chords.map((ch) => ch.symbol()).join(' – '),
                        // Four times round: enough to make the changes stick.
                        sounding: [for (var i = 0; i < 4; i++) ...chords],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The pack, or null when it isn't in this build.
final hasProgressionPackProvider = Provider<bool>(
  (ref) => ref.watch(progressionPackProvider).value != null,
);
