import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';

/// The microphone's current level and the level that counts as playing.
@immutable
final class MicLevel {
  const MicLevel(this.db, this.gateDb);

  final double db;
  final double gateDb;

  bool get hearing => db >= gateDb;
}

/// Whichever screen is listening reports here; the meter shows it. Only one
/// screen listens at a time, so one value is enough.
final micLevelProvider = NotifierProvider<MicLevelController, MicLevel?>(MicLevelController.new);

final class MicLevelController extends Notifier<MicLevel?> {
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  MicLevel? build() => null;

  /// Throttled to ~15 updates a second: plenty for a meter, cheap for the UI.
  void report(double db, double gateDb) {
    final now = DateTime.now();
    if (now.difference(_last) < const Duration(milliseconds: 66)) return;
    _last = now;
    state = MicLevel(db, gateDb);
  }

  void clear() => state = null;
}

/// A quiet meter: how loud the mic hears you, against the line where the
/// app starts paying attention. Answers "is it even hearing me?".
class MicLevelMeter extends ConsumerWidget {
  const MicLevelMeter({super.key});

  static const _minDb = -75.0;
  static const _maxDb = -15.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = ref.watch(micLevelProvider);
    final c = context.stage;
    final t = context.stageText;
    if (level == null) return const SizedBox(height: 18);
    double frac(double db) => ((db - _minDb) / (_maxDb - _minDb)).clamp(0.0, 1.0);
    final hearing = level.hearing;
    return Semantics(
      label: hearing ? 'Microphone hears you' : 'Microphone is waiting for sound',
      liveRegion: false,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hearing ? Icons.mic_rounded : Icons.mic_none_rounded,
            size: 14,
            color: hearing ? c.textSecondary : c.textTertiary,
          ),
          const SizedBox(width: Space.xs + 2),
          SizedBox(
            width: 90,
            height: 6,
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: c.glassFill,
                      borderRadius: const BorderRadius.all(Radii.pill),
                      border: Border.all(color: c.glassBorder, width: 0.5),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 80),
                    width: box.maxWidth * frac(level.db),
                    decoration: BoxDecoration(
                      color: hearing ? c.textSecondary : c.textTertiary.withValues(alpha: 0.6),
                      borderRadius: const BorderRadius.all(Radii.pill),
                    ),
                  ),
                  // The line sound has to cross to count.
                  Positioned(
                    left: box.maxWidth * frac(level.gateDb) - 0.5,
                    top: -2,
                    bottom: -2,
                    child: Container(width: 1, color: c.textPrimary.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: Space.xs + 2),
          Text(
            hearing ? 'Hearing you' : 'Waiting for sound',
            style: t.caption.copyWith(color: c.textTertiary, fontSize: TypeScale.micro),
          ),
        ],
      ),
    );
  }
}
