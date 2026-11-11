import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/design/motion.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/widgets/glass.dart';
import 'package:fretlight/core/widgets/glass_controls.dart';
import 'package:fretlight/core/widgets/screen_header.dart';
import 'package:fretlight/core/widgets/stage_buttons.dart';
import 'package:fretlight/features/metronome/application/metronome_controller.dart';
import 'package:fretlight/features/metronome/domain/metronome_settings.dart';
import 'package:fretlight/features/metronome/domain/transport.dart';
import 'package:fretlight/features/tuner/presentation/tuner_button.dart';
import 'package:go_router/go_router.dart';

/// Tempo, beats, start. Meter and subdivision live in two quiet pills.
///
/// The metronome keeps running when you switch tabs (practise chords to
/// it), and stops when the app goes to the background.
class MetronomeScreen extends ConsumerStatefulWidget {
  const MetronomeScreen({super.key});

  @override
  ConsumerState<MetronomeScreen> createState() => _MetronomeScreenState();
}

class _MetronomeScreenState extends ConsumerState<MetronomeScreen> {
  late final AppLifecycleListener _lifecycle;
  late final MetronomeController _controller;
  final _tapClock = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    _controller = ref.read(metronomeProvider.notifier);
    _lifecycle = AppLifecycleListener(
      onHide: () => unawaited(ref.read(metronomeProvider.notifier).stop()),
    );
  }

  @override
  void dispose() {
    // Leaving the screen stops the click: nothing keeps ticking out of sight.
    unawaited(_controller.stop());
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(metronomeProvider);
    final controller = ref.read(metronomeProvider.notifier);
    final s = state.settings;
    final text = context.stageText;
    final c = context.stage;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 112),
        child: Column(
          children: [
            ScreenHeader(
              title: 'Metronome',
              onBack: () => context.pop(),
              actions: const [TunerButton()],
            ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                GlassPill(
                  label: '${s.signature}',
                  semantics: 'Time signature ${s.signature}. Change',
                  chevron: true,
                  onTap: () => _showMeterSheet(context),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: GlassPill(
                      label: 'Advanced',
                      semantics: 'Advanced. Subdivision: ${s.subdivision.label}. Change',
                      chevron: true,
                      onTap: () => _showSubdivisionSheet(context),
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(flex: 3),
            _BeatRow(settings: s, playing: state.playing),
            const SizedBox(height: Space.sm),
            Text(
              'Tap a beat to change its accent',
              style: text.caption.copyWith(color: c.textTertiary, fontSize: TypeScale.micro),
            ),
            const Spacer(flex: 2),
            _Tempo(bpm: s.bpm, onNudge: controller.nudge),
            const SizedBox(height: Space.lg),
            _BpmSlider(bpm: s.bpm, onChanged: controller.setBpm),
            const Spacer(flex: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                StageButton.glass(
                  label: 'Tap',
                  icon: Icons.touch_app_rounded,
                  onPressed: () {
                    unawaited(HapticFeedback.lightImpact());
                    controller.tap(_tapClock.elapsed);
                  },
                ),
                const SizedBox(width: Space.md),
                StageButton(
                  label: state.playing ? 'Stop' : 'Start',
                  icon: state.playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  onPressed: () {
                    unawaited(HapticFeedback.mediumImpact());
                    unawaited(controller.toggle());
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMeterSheet(BuildContext context) => showGlassSheet<void>(
    context,
    builder: (context) => _ChoiceSheet<TimeSignature>(
      title: 'Time signature',
      options: TimeSignature.common,
      selected: (ref) => ref.watch(metronomeProvider.select((s) => s.settings.signature)),
      label: (s) => '$s',
      onSelect: (ref, s) => ref.read(metronomeProvider.notifier).setSignature(s),
      footnote: 'In x/8 meters the tempo counts eighth notes.',
    ),
  );

  Future<void> _showSubdivisionSheet(BuildContext context) => showGlassSheet<void>(
    context,
    builder: (context) => _ChoiceSheet<Subdivision>(
      title: 'Advanced: subdivision',
      options: Subdivision.values,
      selected: (ref) => ref.watch(metronomeProvider.select((s) => s.settings.subdivision)),
      label: (s) => s.label,
      onSelect: (ref, s) => ref.read(metronomeProvider.notifier).setSubdivision(s),
    ),
  );
}

/// The beats of the bar. While playing, the one sounding lights up; the
/// timing comes from the audio engine's clock, read each frame.
class _BeatRow extends ConsumerStatefulWidget {
  const _BeatRow({required this.settings, required this.playing});

  final MetronomeSettings settings;
  final bool playing;

  @override
  ConsumerState<_BeatRow> createState() => _BeatRowState();
}

class _BeatRowState extends ConsumerState<_BeatRow> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => _frame.value = _position());
  final _frame = ValueNotifier<BeatPosition?>(null);

  BeatPosition? _position() => ref.read(metronomeProvider.notifier).positionNow();

  @override
  void didUpdateWidget(_BeatRow old) {
    super.didUpdateWidget(old);
    _syncTicker();
  }

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  void _syncTicker() {
    if (widget.playing && !_ticker.isActive) {
      _ticker.start();
    } else if (!widget.playing && _ticker.isActive) {
      _ticker.stop();
      _frame.value = null;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final c = context.stage;
    final reduced = Motion.of(context).reduced;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Up to 12 beats (12/8) in one row on a narrow phone.
        final slot = math.min(56, constraints.maxWidth / s.beats).toDouble();
        return ValueListenableBuilder<BeatPosition?>(
          valueListenable: _frame,
          builder: (context, pos, _) => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < s.beats; i++)
                _BeatDot(
                  size: slot,
                  index: i,
                  accent: s.accents[i],
                  // A flash that fades over the first half of the beat.
                  lit: pos != null && pos.beat == i ? math.max(0, 1 - pos.phase * 2) : 0,
                  current: pos != null && pos.beat == i,
                  reduced: reduced,
                  colors: c,
                  onTap: () {
                    unawaited(HapticFeedback.selectionClick());
                    ref.read(metronomeProvider.notifier).cycleAccent(i);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BeatDot extends StatelessWidget {
  const _BeatDot({
    required this.size,
    required this.index,
    required this.accent,
    required this.lit,
    required this.current,
    required this.reduced,
    required this.colors,
    required this.onTap,
  });

  final double size;
  final int index;
  final Accent accent;

  /// 0..1 flash intensity.
  final double lit;
  final bool current;
  final bool reduced;
  final StageColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    // Size says the accent (not just colour): strong, medium, normal, mute.
    final base = switch (accent) {
      Accent.strong => 0.62,
      Accent.medium => 0.5,
      Accent.normal => 0.38,
      Accent.mute => 0.38,
    };
    final flash = reduced ? (current ? 1.0 : 0.0) : lit;
    final d = size * base * (1 + 0.18 * flash);
    final muted = accent == Accent.mute;
    final fill = muted
        ? Colors.transparent
        : Color.lerp(
            accent == Accent.normal ? c.textTertiary : c.textSecondary,
            c.accent,
            current ? math.max(flash, 0.55) : 0,
          )!;
    return Semantics(
      button: true,
      label:
          'Beat ${index + 1}, ${accent.name}${accent == Accent.mute ? 'd' : ' accent'}. Tap to change',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: math.max(size, 48),
          child: Center(
            child: Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
                border: muted ? Border.all(color: c.textTertiary, width: 1.5) : null,
                boxShadow: current && flash > 0 && !muted
                    ? [BoxShadow(color: c.accent.withValues(alpha: 0.45 * flash), blurRadius: 18)]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tempo extends StatelessWidget {
  const _Tempo({required this.bpm, required this.onNudge});

  final int bpm;
  final ValueChanged<int> onNudge;

  @override
  Widget build(BuildContext context) {
    final text = context.stageText;
    final c = context.stage;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GlassIconButton(icon: Icons.remove_rounded, semantics: 'Slower', onTap: () => onNudge(-1)),
        Expanded(
          child: Semantics(
            label: '$bpm beats per minute, ${tempoMarking(bpm)}',
            liveRegion: true,
            excludeSemantics: true,
            child: Column(
              children: [
                Text(
                  '$bpm',
                  style: text.readout.copyWith(fontSize: 88, fontWeight: FontWeight.w300),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  'BPM · ${tempoMarking(bpm)}',
                  style: text.caption.copyWith(color: c.textTertiary),
                ),
              ],
            ),
          ),
        ),
        GlassIconButton(icon: Icons.add_rounded, semantics: 'Faster', onTap: () => onNudge(1)),
      ],
    );
  }
}

class _BpmSlider extends StatelessWidget {
  const _BpmSlider({required this.bpm, required this.onChanged});

  final int bpm;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: c.textSecondary,
        inactiveTrackColor: c.glassBorder,
        thumbColor: c.primaryFill,
        overlayColor: c.glassFill,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
        showValueIndicator: ShowValueIndicator.never,
      ),
      child: Slider(
        value: bpm.toDouble(),
        min: MetronomeSettings.minBpm.toDouble(),
        max: MetronomeSettings.maxBpm.toDouble(),
        divisions: MetronomeSettings.maxBpm - MetronomeSettings.minBpm,
        semanticFormatterCallback: (v) => '${v.round()} BPM',
        onChanged: (v) {
          if (v.round() != bpm) {
            unawaited(HapticFeedback.selectionClick());
            onChanged(v.round());
          }
        },
      ),
    );
  }
}

/// A short list of choices as glass pills.
class _ChoiceSheet<T> extends ConsumerWidget {
  const _ChoiceSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.label,
    required this.onSelect,
    this.footnote,
  });

  final String title;
  final List<T> options;
  final T Function(WidgetRef ref) selected;
  final String Function(T) label;
  final void Function(WidgetRef ref, T) onSelect;
  final String? footnote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = selected(ref);
    final text = context.stageText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(title, style: text.title)),
          const SizedBox(height: Space.lg),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final o in options)
                GlassPill(
                  label: label(o),
                  semantics: label(o),
                  selected: o == current,
                  onTap: () {
                    onSelect(ref, o);
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
          if (footnote case final f?) ...[
            const SizedBox(height: Space.lg),
            Text(f, style: text.caption.copyWith(color: context.stage.textTertiary)),
          ],
        ],
      ),
    );
  }
}
