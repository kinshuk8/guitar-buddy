import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/design/motion.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/painting/fretboard.dart';
import 'package:fretlight/core/painting/fretboard_painter.dart';
import 'package:fretlight/core/widgets/glass.dart';
import 'package:fretlight/core/widgets/music_text.dart';
import 'package:fretlight/core/widgets/stage_buttons.dart';
import 'package:fretlight/features/settings/application/appearance.dart';

/// Every design token and shared component on one page, so the look can be
/// reviewed (both themes, reduced motion) before features are built on it.
class GalleryScreen extends ConsumerWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.stage;
    final text = context.stageText;
    final appearance = ref.watch(appearanceProvider);
    final controller = ref.read(appearanceProvider.notifier);
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: 'Gallery'),
      body: AmbientBackground(
        child: CustomScrollView(
          slivers: [
            SliverSafeArea(
              sliver: SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.sm,
                  Space.gutter,
                  Space.xxxl,
                ),
                sliver: SliverList.list(
                  children: [
                    StageSegmented<ThemeMode>(
                      options: const [ThemeMode.system, ThemeMode.dark, ThemeMode.light],
                      selected: appearance.themeMode,
                      onChanged: controller.setThemeMode,
                      labelOf: (m) => switch (m) {
                        ThemeMode.system => 'Auto',
                        ThemeMode.dark => 'Night',
                        ThemeMode.light => 'Day',
                      },
                    ),
                    const SizedBox(height: Space.sm),
                    Center(
                      child: Text(
                        Motion.of(context).reduced ? 'Reduced motion on' : 'Reduced motion off',
                        style: text.caption.copyWith(color: c.textTertiary),
                      ),
                    ),
                    const SectionLabel('Now playing'),
                    const _NowNext(),
                    const SectionLabel('Fretboard'),
                    _FretboardDemo(
                      leftHanded: appearance.leftHanded,
                      onLeftHanded: (v) => controller.setLeftHanded(value: v),
                    ),
                    const SectionLabel('Tuning'),
                    const _TuningStates(),
                    const SectionLabel('Controls'),
                    const _Controls(),
                    const SectionLabel('Chord symbols'),
                    const _ChordSymbols(),
                    const SectionLabel('Type'),
                    const _TypeSamples(),
                    const SectionLabel('Colour'),
                    const _Palette(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NowNext extends StatelessWidget {
  const _NowNext();

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    final t = context.stageText;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: GlassPanel(
              live: true,
              padding: const EdgeInsets.all(Space.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('NOW', style: t.overline.copyWith(color: c.accent)),
                  const SizedBox(height: Space.sm),
                  ChordSymbol(Chord.parse('Am'), size: 72),
                ],
              ),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            flex: 2,
            child: GlassPanel(
              padding: const EdgeInsets.all(Space.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('NEXT', style: t.overline),
                  const SizedBox(height: Space.sm),
                  ChordSymbol(Chord.parse('G/B'), size: 44, color: c.textSecondary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FretboardDemo extends StatefulWidget {
  const _FretboardDemo({required this.leftHanded, required this.onLeftHanded});

  final bool leftHanded;
  final ValueChanged<bool> onLeftHanded;

  @override
  State<_FretboardDemo> createState() => _FretboardDemoState();
}

class _FretboardDemoState extends State<_FretboardDemo> {
  final _controller = FretboardController();
  final Tuning _tuning = Tuning.standard;
  final PitchMath _math = const PitchMath();
  String _readout = 'Tap a string';
  List<FretMarker> _markers = const [
    // Open C: x 3 2 0 1 0
    FretMarker(string: 1, fret: 3, label: '3'),
    FretMarker(string: 2, fret: 2, label: '2'),
    FretMarker(string: 3, fret: 0),
    FretMarker(string: 4, fret: 1, label: '1'),
    FretMarker(string: 5, fret: 0),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTap(int string, int fret) {
    final note = _tuning.noteAt(string, fret);
    final positions = _tuning.positionsOf(note, maxFret: 12);
    setState(() {
      _readout =
          '${note.name()} · ${_math.hz(note).toStringAsFixed(2)} Hz · ${positions.length} positions';
      _markers = [
        for (final p in positions)
          FretMarker(
            string: p.string,
            fret: p.fret,
            label: note.pitchClass.name(),
            emphasis: p.string == string && p.fret == fret ? 1 : 0,
          ),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = context.stageText;
    return GlassPanel(
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.md),
            child: SizedBox(
              height: 168,
              child: Fretboard(
                markers: _markers,
                leftHanded: widget.leftHanded,
                controller: _controller,
                onTap: _onTap,
                semanticLabel: 'Fretboard. $_readout',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xs, Space.md, 0, 0),
            child: Row(
              children: [
                Expanded(child: Text(_readout, style: text.caption)),
                StageButton.glass(
                  label: 'Strum',
                  onPressed: () => unawaited(_controller.strum(_tuning.stringCount)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: Space.xs),
            child: Row(
              children: [
                Expanded(child: Text('Left-handed', style: text.body)),
                Switch(value: widget.leftHanded, onChanged: widget.onLeftHanded),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TuningStates extends StatelessWidget {
  const _TuningStates();

  @override
  Widget build(BuildContext context) => const Wrap(
    spacing: Space.sm,
    runSpacing: Space.sm,
    children: [
      TuningStateBadge(TuningState.flat, cents: -12),
      TuningStateBadge(TuningState.inTune, cents: 1),
      TuningStateBadge(TuningState.sharp, cents: 8),
    ],
  );
}

class _Controls extends StatefulWidget {
  const _Controls();

  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls> {
  String _meter = '4/4';
  double _bpm = 96;

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            StageButton(label: 'Start', icon: Icons.play_arrow_rounded, onPressed: () {}),
            StageButton.glass(label: 'Tap tempo', onPressed: () {}),
            const StageButton.glass(label: 'Disabled', onPressed: null),
          ],
        ),
        const SizedBox(height: Space.lg),
        StageSegmented<String>(
          options: const ['2/4', '3/4', '4/4', '6/8'],
          selected: _meter,
          onChanged: (v) => setState(() => _meter = v),
          labelOf: (v) => v,
        ),
        const SizedBox(height: Space.lg),
        GlassPanel(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_bpm.round().toString(), style: t.readout),
                  const SizedBox(width: Space.sm),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('BPM', style: t.caption),
                  ),
                ],
              ),
              Slider(value: _bpm, min: 30, max: 300, onChanged: (v) => setState(() => _bpm = v)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChordSymbols extends StatelessWidget {
  const _ChordSymbols();

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: Space.xl,
    runSpacing: Space.md,
    crossAxisAlignment: WrapCrossAlignment.end,
    children: [
      for (final s in ['C', 'F#m7', 'Bbmaj7', 'G/B', 'Dsus4', 'E5', 'Ebm'])
        ChordSymbol(Chord.parse(s), size: 44),
    ],
  );
}

class _TypeSamples extends StatelessWidget {
  const _TypeSamples();

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Am7', style: t.chordHero),
        const SizedBox(height: Space.sm),
        Text('Red River Valley', style: t.display),
        Text('Verse 2', style: t.title),
        const SizedBox(height: Space.xs),
        Text('Reference pitch', style: t.heading),
        Text('Strum each string slowly and let it ring.', style: t.body),
        Text('Detection works best with one guitar in a quiet room.', style: t.caption),
        const SizedBox(height: Space.sm),
        Text('CHORUS', style: t.overline),
        const SizedBox(height: Space.sm),
        Text('110.00 Hz', style: t.readout),
      ],
    );
  }
}

class _Palette extends StatelessWidget {
  const _Palette();

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    final swatches = {
      'Text': c.textPrimary,
      'Lamp': c.accent,
      'In tune': c.inTune,
      'Flat': c.flat,
      'Sharp': c.sharp,
      'Ebony': c.fretboardWood,
      'Steel': c.plainString,
      'Nickel': c.woundString,
    };
    return Wrap(
      spacing: Space.lg,
      runSpacing: Space.md,
      children: [
        for (final MapEntry(:key, :value) in swatches.entries)
          Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: value,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.glassBorder),
                ),
              ),
              const SizedBox(height: Space.xs),
              Text(key, style: context.stageText.caption.copyWith(fontSize: TypeScale.micro)),
            ],
          ),
      ],
    );
  }
}
