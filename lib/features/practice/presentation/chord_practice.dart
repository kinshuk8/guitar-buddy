import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/widgets/glass.dart';
import 'package:fretlight/core/widgets/glass_controls.dart';
import 'package:fretlight/core/widgets/music_text.dart';
import 'package:fretlight/core/widgets/screen_header.dart';
import 'package:fretlight/core/widgets/stage_buttons.dart';
import 'package:fretlight/features/learn/application/progress_controller.dart';
import 'package:fretlight/features/learn/domain/curriculum.dart';
import 'package:fretlight/features/learn/domain/progress.dart';
import 'package:fretlight/features/learn/presentation/learn_screen.dart';
import 'package:fretlight/features/learn/presentation/learn_widgets.dart';
import 'package:fretlight/features/tuner/presentation/tuner_button.dart';
import 'package:go_router/go_router.dart';

/// Every chord symbol the course teaches, in teaching order.
final List<String> practiceChords = [
  for (final g in chordsByStage)
    for (final spec in g.specs) chordSymbolOf(spec),
];

/// One chord to drill: its name inside a ring showing how well you know it.
class ChordPracticeTile extends ConsumerWidget {
  const ChordPracticeTile({required this.symbol, super.key});

  final String symbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mastery = ref.watch(progressProvider.select((p) => p.mastery(symbol)));
    final c = context.stage;
    return Semantics(
      container: true,
      button: true,
      label: '${spokenChord(Chord.parse(symbol))}, ${mastery.round()} percent. Drill it',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openLesson(context, ref, chordDrill(symbol)),
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              ProgressRing(
                value: mastery / 100,
                size: 60,
                stroke: 4,
                child: ChordSymbol(Chord.parse(symbol), size: 20),
              ),
              const SizedBox(height: Space.xs),
              Text(
                mastery == 0 ? 'New' : '${mastery.round()}%',
                style: context.stageText.caption.copyWith(
                  color: c.textTertiary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every chord the course teaches, by stage. Tap one to drill it.
class ChordsPracticeScreen extends StatelessWidget {
  const ChordsPracticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 132),
        children: [
          ScreenHeader(
            title: 'Chords',
            subtitle: 'Tap a chord to drill it',
            onBack: () => context.pop(),
            actions: const [TunerButton()],
          ),
          const SizedBox(height: Space.md),
          Text(
            'Five clean strums each time. The ring fills as you get it right first time, '
            'and drops a little when you miss.',
            style: t.caption.copyWith(color: c.textTertiary),
          ),
          for (final g in chordsByStage)
            if (g.specs.isNotEmpty) ...[
              SectionLabel(g.stage.title),
              Wrap(
                spacing: Space.md,
                runSpacing: Space.lg,
                children: [
                  for (final spec in g.specs) ChordPracticeTile(symbol: chordSymbolOf(spec)),
                ],
              ),
            ],
        ],
      ),
    );
  }
}

/// Pick two chords and practise the change: untimed, or a one-minute race.
class ChangesScreen extends ConsumerStatefulWidget {
  const ChangesScreen({super.key});

  @override
  ConsumerState<ChangesScreen> createState() => _ChangesScreenState();
}

class _ChangesScreenState extends ConsumerState<ChangesScreen> {
  String? _a;
  String? _b;

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(progressProvider);
    final t = context.stageText;
    final c = context.stage;
    // Until you choose, the two that need it most.
    final weakest = p.chordsToWork();
    final a = _a ?? weakest[0];
    final b = _b ?? weakest[1];
    final same = a == b;
    final races = [
      for (final MapEntry(:key, :value) in p.skills.entries)
        if (key.startsWith('race:'))
          (pair: key.substring(5).split('|').map(chordSymbolOf).toList(), best: value),
    ]..sort((x, y) => y.best.compareTo(x.best));
    final best = p.best('race:${([chordSpecFor(a), chordSpecFor(b)]..sort()).join('|')}');

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 132),
        children: [
          ScreenHeader(
            title: 'Changes',
            subtitle: 'Practise the switch',
            onBack: () => context.pop(),
            actions: const [TunerButton()],
          ),
          const SectionLabel('First chord'),
          _Picker(selected: a, onPick: (s) => setState(() => _a = s)),
          const SectionLabel('Second chord'),
          _Picker(selected: b, onPick: (s) => setState(() => _b = s)),
          const SizedBox(height: Space.xl),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ChordSymbol(Chord.parse(a), size: 32),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.md),
                      child: Icon(Icons.swap_horiz_rounded, color: c.textTertiary),
                    ),
                    ChordSymbol(Chord.parse(b), size: 32),
                  ],
                ),
                const SizedBox(height: Space.xs),
                Text(
                  same
                      ? 'Pick two different chords.'
                      : best == null
                      ? 'No race between these yet.'
                      : 'Your best: ${best.round()} changes a minute.',
                  style: t.caption.copyWith(color: c.textTertiary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Space.lg),
                StageButton(
                  label: 'Switch between them',
                  icon: Icons.swap_horiz_rounded,
                  expand: true,
                  onPressed: same ? null : () => openLesson(context, ref, changeDrill(a, b)),
                ),
                const SizedBox(height: Space.sm),
                StageButton.glass(
                  label: 'One-minute race',
                  icon: Icons.timer_outlined,
                  expand: true,
                  onPressed: same ? null : () => openLesson(context, ref, raceDrill(p, a, b)),
                ),
              ],
            ),
          ),
          const SectionLabel('Your best races'),
          if (races.isEmpty)
            Text(
              'Race a pair to set your first best. A good target to start: 20 a minute.',
              style: t.bodySecondary,
            )
          else
            for (final r in races.take(8))
              Semantics(
                container: true,
                button: true,
                label: '${r.pair.join(' and ')}: ${r.best.round()} a minute. Choose this pair',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() {
                    _a = r.pair.first;
                    _b = r.pair.last;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.sm),
                    child: Row(
                      children: [
                        Expanded(child: Text(r.pair.join(' ↔ '), style: t.body)),
                        Text(
                          '${r.best.round()} a minute',
                          style: t.label.copyWith(
                            color: c.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// A row of every chord, the chosen one scrolled into view.
class _Picker extends StatefulWidget {
  const _Picker({required this.selected, required this.onPick});

  final String selected;
  final ValueChanged<String> onPick;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  final GlobalKey _selectedKey = GlobalKey();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Bring the chosen chord into view within this row only (the page
    // itself stays where it is).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pill = _selectedKey.currentContext?.findRenderObject() as RenderBox?;
      final row = context.findRenderObject() as RenderBox?;
      if (!mounted || pill == null || row == null || !_scroll.hasClients) return;
      final x = pill.localToGlobal(Offset.zero).dx - row.localToGlobal(Offset.zero).dx;
      final target = x + _scroll.offset - (row.size.width - pill.size.width) / 2;
      _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: _scroll,
    scrollDirection: Axis.horizontal,
    clipBehavior: Clip.none,
    child: Row(
      children: [
        for (final s in practiceChords) ...[
          GlassPill(
            key: s == widget.selected ? _selectedKey : null,
            label: s,
            semantics: s,
            selected: s == widget.selected,
            onTap: () => widget.onPick(s),
          ),
          const SizedBox(width: Space.sm),
        ],
      ],
    ),
  );
}

/// Practice tab strip: your chords, weakest first, each a tap from a drill.
class YourChordsStrip extends ConsumerWidget {
  const YourChordsStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chords = ref.watch(progressProvider.select((p) => p.chordsToWork()));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // Runs on into the margin: a row that's cut off reads as scrollable.
      clipBehavior: Clip.none,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in chords.take(8)) ...[
            ChordPracticeTile(symbol: s),
            const SizedBox(width: Space.sm),
          ],
        ],
      ),
    );
  }
}
