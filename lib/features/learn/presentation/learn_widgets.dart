import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/painting/chord_diagram.dart';
import 'package:fretlight/features/chords/application/chord_library_provider.dart';
import 'package:fretlight/features/learn/domain/curriculum.dart';
import 'package:fretlight/features/settings/application/appearance.dart';

/// Three stars, filled up to [stars].
class StarRow extends StatelessWidget {
  const StarRow(this.stars, {this.size = 16, this.of = 3, super.key});

  final int stars;
  final double size;
  final int of;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    return Semantics(
      label: '$stars of $of stars',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < of; i++)
            Icon(
              i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: i < stars ? Palette.lamp : c.textTertiary.withValues(alpha: 0.6),
            ),
        ],
      ),
    );
  }
}

IconData skillIcon(Skill s) => switch (s) {
  Skill.notes => Icons.music_note_rounded,
  Skill.chords => Icons.grid_view_rounded,
  Skill.changes => Icons.swap_horiz_rounded,
  Skill.rhythm => Icons.graphic_eq_rounded,
  Skill.reading => Icons.menu_book_rounded,
  Skill.songs => Icons.queue_music_rounded,
};

/// A thin ring that fills clockwise, with something in the middle.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    required this.value,
    required this.child,
    this.size = 64,
    this.stroke = 5,
    this.color,
    super.key,
  });

  final double value;
  final Widget child;
  final double size;
  final double stroke;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(
          value: value.clamp(0, 1).toDouble(),
          stroke: stroke,
          track: c.glassBorder,
          fill: color ?? c.inTune,
        ),
        child: Center(child: child),
      ),
    );
  }
}

final class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.stroke,
    required this.track,
    required this.fill,
  });

  final double value;
  final double stroke;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, 2 * math.pi, false, paint..color = track);
    if (value > 0) {
      canvas.drawArc(r, -math.pi / 2, 2 * math.pi * value, false, paint..color = fill);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.fill != fill || old.track != track;
}

/// A slim bar for skill levels and XP.
class MeterBar extends StatelessWidget {
  const MeterBar({required this.value, this.color, this.height = 6, super.key});

  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radii.pill),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: c.glassBorder),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0, 1).toDouble(),
              child: ColoredBox(color: color ?? c.inTune),
            ),
          ],
        ),
      ),
    );
  }
}

/// A lesson's chord, drawn: the pinned shape if the lesson gives one,
/// otherwise the library's first.
class LessonChordDiagram extends ConsumerWidget {
  const LessonChordDiagram(this.spec, {this.compact = true, super.key});

  final String spec;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voicing = lessonVoicing(ref, spec);
    if (voicing == null) return const SizedBox.shrink();
    final leftHanded = ref.watch(appearanceProvider.select((a) => a.leftHanded));
    return ChordDiagram(voicing: voicing, compact: compact, leftHanded: leftHanded);
  }
}

Voicing? lessonVoicing(WidgetRef ref, String spec) {
  final frets = chordFretsOf(spec);
  if (frets != null) return Voicing(frets: frets);
  final chord = Chord.parse(chordSymbolOf(spec));
  return ref.watch(chordLibraryProvider).value?.byChord(chord)?.voicings.first;
}

/// Guitar tab: six lines (high E on top), fret numbers in playing order.
/// The note to play now is lit; played ones dim.
class TabStrip extends StatelessWidget {
  const TabStrip({required this.spots, this.current, this.height = 132, super.key});

  final List<Spot> spots;

  /// Index of the note to play now (null: none lit).
  final int? current;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    final t = context.stageText;
    return Semantics(
      label:
          'Tab: ${[for (final s in spots) '${QuizStringNames.of(s.string)} string fret ${s.fret}'].join(', ')}',
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, box) {
            const labelW = 18.0;
            final gap = (height - 12) / 5;
            // Scroll so the current note stays in view on long tunes.
            const step = 34.0;
            final width = math.max(box.maxWidth, labelW + 16 + spots.length * step);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: ScrollController(
                initialScrollOffset: current == null ? 0 : math.max(0, (current! - 3) * step),
              ),
              child: SizedBox(
                width: width,
                height: height,
                child: Stack(
                  children: [
                    for (var line = 0; line < 6; line++) ...[
                      Positioned(
                        left: 0,
                        top: 6 + line * gap - 8,
                        child: SizedBox(
                          width: labelW,
                          child: Text(
                            const ['e', 'B', 'G', 'D', 'A', 'E'][line],
                            style: t.caption.copyWith(
                              color: c.textTertiary,
                              fontSize: TypeScale.micro,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: labelW,
                        right: 0,
                        top: 6 + line * gap,
                        child: Container(height: 1, color: c.textTertiary.withValues(alpha: 0.5)),
                      ),
                    ],
                    for (final (i, s) in spots.indexed)
                      Positioned(
                        left: labelW + 12 + i * step,
                        top: 6 + (5 - s.string) * gap - 11,
                        child: Container(
                          width: 24,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: i == current ? c.primaryFill : c.background,
                            borderRadius: const BorderRadius.all(Radius.circular(6)),
                          ),
                          child: Text(
                            '${s.fret}',
                            style: t.label.copyWith(
                              fontSize: 14,
                              color: i == current
                                  ? c.onPrimary
                                  : current != null && i < current!
                                  ? c.textTertiary
                                  : c.textPrimary,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// String names as players say them.
abstract final class QuizStringNames {
  static String of(int string) => const ['low E', 'A', 'D', 'G', 'B', 'high E'][string];

  /// "the A string, 3rd fret" / "the open D string".
  static String spot(Spot s) => s.fret == 0
      ? 'the open ${of(s.string)} string'
      : 'the ${of(s.string)} string, ${ordinal(s.fret)} fret';

  static String ordinal(int n) {
    final suffix = (n % 100 >= 11 && n % 100 <= 13)
        ? 'th'
        : switch (n % 10) {
            1 => 'st',
            2 => 'nd',
            3 => 'rd',
            _ => 'th',
          };
    return '$n$suffix';
  }
}
