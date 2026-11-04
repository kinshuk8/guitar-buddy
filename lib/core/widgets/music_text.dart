import 'package:flutter/material.dart';
import 'package:fretlight/core/design/motion.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/music/music.dart';

/// Renders a chord symbol the way chord charts do: big root, true ♯/♭
/// glyphs raised, and a smaller quality suffix. Screen readers get the
/// spoken form ("F sharp minor 7th") instead of "F hash m 7".
class ChordSymbol extends StatelessWidget {
  const ChordSymbol(
    this.chord, {
    this.size = TypeScale.chordLarge,
    this.color,
    this.spelling,
    super.key,
  });

  final Chord chord;
  final double size;
  final Color? color;
  final Spelling? spelling;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    final ink = color ?? c.textPrimary;
    TextStyle weighted(double fontSize, int weight) =>
        StageText.style(fontSize, weight: weight, color: ink, tracking: -0.04, height: 1);
    final base = weighted(size, 600);
    final s = spelling ?? Spelling.forRoot(chord.root);
    final root = chord.root.name(s);
    final bass = chord.bass;

    List<InlineSpan> note(String name, double scale) => [
      TextSpan(
        text: name[0],
        style: base.copyWith(fontSize: size * scale),
      ),
      if (name.length > 1)
        WidgetSpan(
          // Align baselines, then lift: top-alignment depends on font
          // metrics and dropped the glyph below the baseline with fallback fonts.
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          // A fixed narrow slot: the ♯/♭ glyphs have wide advances that left
          // a visible gap before the suffix ("B♭  maj7").
          child: SizedBox(
            width: size * scale * 0.3,
            height: size * scale * 0.7,
            child: OverflowBox(
              maxWidth: double.infinity,
              alignment: Alignment.centerLeft,
              child: Transform.translate(
                offset: Offset(0, -size * scale * 0.36),
                child: Text(
                  name.substring(1).replaceAll('#', '♯').replaceAll('b', '♭'),
                  style: weighted(size * scale * 0.5, 500),
                ),
              ),
            ),
          ),
        ),
    ];

    return Semantics(
      label: spokenChord(chord, s),
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: [
            ...note(root, 1),
            if (chord.quality.suffix.isNotEmpty)
              TextSpan(text: chord.quality.suffix, style: weighted(size * 0.48, 500)),
            if (bass != null) ...[
              TextSpan(text: '/', style: weighted(size * 0.6, 300)),
              ...note(bass.name(s), 0.6),
            ],
          ],
        ),
        maxLines: 1,
        softWrap: false,
      ),
    );
  }
}

/// "F sharp minor 7th", "G over B".
String spokenChord(Chord chord, [Spelling? spelling]) {
  final s = spelling ?? Spelling.forRoot(chord.root);
  String spokenNote(PitchClass p) =>
      p.name(s).replaceFirst('#', ' sharp').replaceFirst(RegExp(r'b$'), ' flat');
  final quality = chord.quality == ChordQuality.major ? 'major' : chord.quality.label;
  final bass = chord.bass;
  return '${spokenNote(chord.root)} $quality${bass == null ? '' : ' over ${spokenNote(bass)}'}';
}

/// Tuning state. Communicated by icon + word + colour, never colour alone.
enum TuningState {
  flat('Flat', Icons.south_rounded, 'tune up'),
  inTune('In tune', Icons.check_rounded, 'in tune'),
  sharp('Sharp', Icons.north_rounded, 'tune down');

  TuningState(this.label, this.icon, this.hint);

  final String label;
  final IconData icon;

  /// Spoken hint for screen readers ("tune up").
  final String hint;

  /// Within ±3 cents counts as in tune.
  static const double inTuneCents = 3;

  static TuningState fromCents(double cents) {
    if (cents.abs() <= inTuneCents) return inTune;
    return cents < 0 ? flat : sharp;
  }

  Color color(StageColors c) => switch (this) {
    flat => c.flat,
    inTune => c.inTune,
    sharp => c.sharp,
  };
}

class TuningStateBadge extends StatelessWidget {
  const TuningStateBadge(this.state, {this.cents, super.key});

  final TuningState state;
  final double? cents;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    final color = state.color(c);
    final centsText = cents == null
        ? ''
        : ' ${cents! >= 0 ? '+' : '−'}${cents!.abs().toStringAsFixed(0)}¢';
    return Semantics(
      liveRegion: true,
      label:
          '${state.label}${cents == null ? '' : ', ${cents!.abs().toStringAsFixed(0)} cents'}, ${state.hint}',
      excludeSemantics: true,
      // Quiet glass pill; only the icon and word carry the state colour, and
      // the in-tune state adds a ring so it differs by shape too.
      child: AnimatedContainer(
        duration: Motion.of(context).standard,
        padding: const EdgeInsets.symmetric(horizontal: Space.md + 2, vertical: Space.sm),
        decoration: BoxDecoration(
          color: c.glassFill,
          borderRadius: const BorderRadius.all(Radii.pill),
          border: Border.all(
            color: state == TuningState.inTune ? color.withValues(alpha: 0.6) : c.glassBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(state.icon, color: color, size: 18),
            const SizedBox(width: Space.xs + 2),
            Text(state.label, style: context.stageText.label.copyWith(color: color)),
            if (centsText.isNotEmpty)
              Text(centsText, style: context.stageText.label.copyWith(color: c.textSecondary)),
          ],
        ),
      ),
    );
  }
}
