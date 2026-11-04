import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/design/motion.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/widgets/music_text.dart';
import 'package:fretlight/core/widgets/stage_buttons.dart';
import 'package:fretlight/features/tuner/application/tuner_controller.dart';
import 'package:fretlight/features/tuner/domain/tuner_session.dart';
import 'package:fretlight/features/tuner/presentation/tuner_gauge.dart';
import 'package:fretlight/features/tuner/presentation/tuner_sheets.dart';

class TunerScreen extends ConsumerStatefulWidget {
  const TunerScreen({super.key});

  @override
  ConsumerState<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends ConsumerState<TunerScreen> {
  late final AppLifecycleListener _lifecycle;
  ValueListenable<TickerModeData>? _tickerMode;
  bool? _active;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: (_) => _sync());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The tab shell keeps hidden tabs alive with tickers disabled. Following
    // TickerMode means the mic closes the moment you switch tabs, without
    // the tuner having to know anything about the router.
    final notifier = TickerMode.getValuesNotifier(context);
    if (notifier != _tickerMode) {
      _tickerMode?.removeListener(_sync);
      _tickerMode = notifier..addListener(_sync);
    }
    _sync();
  }

  void _sync() {
    final visible = _tickerMode?.value.enabled ?? true;
    final foreground = switch (WidgetsBinding.instance.lifecycleState) {
      AppLifecycleState.resumed || null => true,
      _ => false,
    };
    final active = visible && foreground;
    if (active == _active) return;
    _active = active;
    // Deferred: _sync can run during build (didChangeDependencies).
    scheduleMicrotask(() {
      if (mounted) unawaited(ref.read(tunerProvider.notifier).setActive(active: active));
    });
  }

  @override
  void dispose() {
    _tickerMode?.removeListener(_sync);
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(tunerProvider.select((s) => s.status));
    final text = context.stageText;
    return SafeArea(
      bottom: false,
      child: Padding(
        // Bottom padding clears the floating tab bar.
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 112),
        child: Column(
          children: [
            const _TopBar(),
            Expanded(
              child: switch (status) {
                TunerStatus.needsPermission => _Blocked(
                  title: 'Microphone needed',
                  body:
                      'The tuner listens to your guitar. Nothing is recorded or leaves your phone.',
                  action: 'Allow microphone',
                  onAction: () => ref.read(tunerProvider.notifier).requestPermission(),
                ),
                TunerStatus.permanentlyDenied => _Blocked(
                  title: 'Microphone is off',
                  body: 'Turn on microphone access for Fretlight in Settings to use the tuner.',
                  action: 'Open Settings',
                  onAction: () => ref.read(tunerProvider.notifier).openSettings(),
                ),
                TunerStatus.error => _Blocked(
                  title: 'Couldn’t start the microphone',
                  body: 'Another app may be using it.',
                  action: 'Try again',
                  onAction: () async {
                    final n = ref.read(tunerProvider.notifier);
                    await n.setActive(active: false);
                    await n.setActive(active: true);
                  },
                ),
                _ => const _Live(),
              },
            ),
            if (status == TunerStatus.interrupted)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.md),
                child: Text('Paused while another app uses the microphone', style: text.caption),
              ),
            const _StringRow(),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tuning = ref.watch(tunerProvider.select((s) => s.tuning));
    final a4 = ref.watch(tunerProvider.select((s) => s.a4));
    return Row(
      children: [
        _Pill(
          label: tuning.name,
          semantics: 'Tuning: ${tuning.name}. Change tuning',
          onTap: () => showTuningSheet(context),
          chevron: true,
        ),
        const Spacer(),
        _Pill(
          label: '${a4.round()} Hz',
          semantics: 'Reference pitch ${a4.round()} hertz. Change',
          onTap: () => showReferenceSheet(context),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.semantics,
    required this.onTap,
    this.chevron = false,
  });

  final String label;
  final String semantics;
  final VoidCallback onTap;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm + 2),
            decoration: BoxDecoration(
              color: c.glassFill,
              borderRadius: const BorderRadius.all(Radii.pill),
              border: Border.all(color: c.glassBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: context.stageText.label),
                if (chevron) ...[
                  const SizedBox(width: Space.xs),
                  Icon(Icons.expand_more_rounded, size: 18, color: c.textTertiary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Note, gauge and state: the part that updates ~47 times a second.
class _Live extends ConsumerStatefulWidget {
  const _Live();

  @override
  ConsumerState<_Live> createState() => _LiveState();
}

class _LiveState extends ConsumerState<_Live> {
  TuningState? _lastState;

  @override
  Widget build(BuildContext context) {
    final reading = ref.watch(tunerProvider.select((s) => s.reading));
    final status = ref.watch(tunerProvider.select((s) => s.status));
    final t = context.stageText;
    final state = reading == null ? null : TuningState.fromCents(reading.cents);

    // A light tick when a string arrives in tune: you can tune by feel
    // without looking, and it is one more non-colour cue.
    if (state == TuningState.inTune && _lastState != TuningState.inTune) {
      unawaited(HapticFeedback.lightImpact());
    }
    _lastState = state;

    // Natural height is ~420 pt. Small phones and landscape get a
    // proportionally smaller note and gauge instead of overflowing.
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = (constraints.maxHeight / 470).clamp(0.4, 1.0);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _NoteName(reading: reading, scale: scale),
            const SizedBox(height: Space.xs),
            SizedBox(
              height: 22,
              child: reading == null
                  ? Text(_idleHint(status), style: t.caption)
                  : Text(
                      reading.detected == reading.target
                          ? '${reading.hz.toStringAsFixed(1)} Hz'
                          : 'Tuning to ${_noteLabel(reading.target)} · ${reading.hz.toStringAsFixed(1)} Hz',
                      style: t.caption.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
            ),
            SizedBox(height: Space.xl * scale),
            SizedBox(
              height: 190 * scale,
              width: double.infinity,
              child: TunerGauge(cents: reading?.cents),
            ),
            SizedBox(height: Space.lg * scale),
            SizedBox(
              height: 40,
              child: AnimatedSwitcher(
                duration: Motion.of(context).quick,
                child: state == null
                    ? const SizedBox.shrink()
                    : TuningStateBadge(
                        state,
                        cents: reading!.cents.clamp(-99, 99),
                        key: ValueKey(state),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

String _noteLabel(Note n) => n.name(Spelling.forRoot(n.pitchClass));

String _idleHint(TunerStatus status) => switch (status) {
  TunerStatus.listening => 'Play a single string',
  TunerStatus.starting => 'Starting microphone…',
  _ => ' ',
};

class _NoteName extends StatelessWidget {
  const _NoteName({required this.reading, this.scale = 1});

  final TunerReading? reading;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    final t = context.stageText;
    final r = reading;
    final note = r?.detected;
    final pc = note?.pitchClass;
    // Nothing heard: keep the space (no layout jump) but draw nothing.
    final name = pc == null ? ' ' : pc.name(Spelling.forRoot(pc));
    final color = r == null ? c.textTertiary : c.textPrimary;
    final size = TypeScale.chordHero * scale;
    final big = t.chordHero.copyWith(color: color, fontSize: size);
    return Semantics(
      liveRegion: false,
      label: note == null ? 'No note' : 'Hearing ${spokenNote(note)}',
      excludeSemantics: true,
      child: SizedBox(
        height: size * 1.05,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name[0], style: big),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 18 * scale),
                Text(
                  name.length > 1
                      ? name.substring(1).replaceAll('#', '♯').replaceAll('b', '♭')
                      : ' ',
                  style: big.copyWith(fontSize: size * 0.4),
                ),
                const Spacer(),
                if (note != null)
                  Padding(
                    padding: EdgeInsets.only(bottom: 16 * scale),
                    child: Text('${note.octave}', style: t.title.copyWith(color: c.textTertiary)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "E sharp 2" style spoken note.
String spokenNote(Note n) {
  final name = n.pitchClass.name(Spelling.forRoot(n.pitchClass));
  return '${name.replaceFirst('#', ' sharp').replaceFirst(RegExp(r'b$'), ' flat')} ${n.octave}';
}

class _Blocked extends StatelessWidget {
  const _Blocked({
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
  });

  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_none_rounded, size: 36, color: c.textTertiary),
          const SizedBox(height: Space.md),
          Text(title, style: t.heading, textAlign: TextAlign.center),
          const SizedBox(height: Space.sm),
          Text(body, style: t.bodySecondary, textAlign: TextAlign.center),
          const SizedBox(height: Space.xl),
          StageButton(label: action, onPressed: onAction),
        ],
      ),
    );
  }
}

/// Auto + one button per string. Tap a string to lock to it; tap it again
/// (or Auto) to go back to auto-detect.
class _StringRow extends ConsumerWidget {
  const _StringRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tuning = ref.watch(tunerProvider.select((s) => s.tuning));
    final locked = ref.watch(tunerProvider.select((s) => s.lockedString));
    final heard = ref.watch(tunerProvider.select((s) => s.reading?.stringIndex));
    final inTune = ref.watch(
      tunerProvider.select(
        (s) => s.reading != null && TuningState.fromCents(s.reading!.cents) == TuningState.inTune,
      ),
    );
    final controller = ref.read(tunerProvider.notifier);
    final c = context.stage;
    final t = context.stageText;
    final motion = Motion.of(context);

    Widget chip({
      required String label,
      required String semantics,
      required bool selected,
      required bool lit,
      required VoidCallback onTap,
      double width = 44,
    }) => Semantics(
      button: true,
      selected: selected,
      label: semantics,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          unawaited(HapticFeedback.selectionClick());
          onTap();
        },
        child: SizedBox(
          height: Space.touchTarget,
          width: width,
          child: Center(
            child: AnimatedContainer(
              duration: motion.standard,
              curve: MotionTokens.move,
              height: 44,
              width: width,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? c.primaryFill : (lit ? c.glassFillStrong : c.glassFill),
                borderRadius: const BorderRadius.all(Radii.pill),
                border: Border.all(
                  color: lit && !selected ? (inTune ? c.inTune : c.textSecondary) : c.glassBorder,
                  width: lit && !selected ? 1.5 : 1,
                ),
              ),
              child: Text(
                label,
                style: t.label.copyWith(color: selected ? c.onPrimary : c.textPrimary),
              ),
            ),
          ),
        ),
      ),
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        chip(
          label: 'Auto',
          semantics: 'Auto-detect string',
          selected: locked == null,
          lit: false,
          width: 64,
          onTap: () => controller.lockString(null),
        ),
        for (var i = 0; i < tuning.stringCount; i++)
          chip(
            label: tuning.strings[i].pitchClass.name(
              Spelling.forRoot(tuning.strings[i].pitchClass),
            ),
            semantics: 'String ${tuning.stringCount - i}, ${spokenNote(tuning.strings[i])}',
            selected: locked == i,
            lit: heard == i,
            onTap: () => controller.lockString(locked == i ? null : i),
          ),
      ],
    );
  }
}
