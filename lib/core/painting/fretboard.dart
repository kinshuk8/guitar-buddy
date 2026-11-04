import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:fretlight/core/design/motion.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/painting/fretboard_geometry.dart';
import 'package:fretlight/core/painting/fretboard_painter.dart';

/// Lets a parent pluck or strum strings (e.g. when a chord is played).
/// Drives one [Fretboard] or ChordDiagram at a time: the widget drains the
/// queue as it reads it.
final class FretboardController extends ChangeNotifier {
  final List<int> _pending = [];

  void pluck(int string) {
    _pending.add(string);
    notifyListeners();
  }

  /// Plucks strings low to high, [gap] apart, like a down-strum.
  Future<void> strum(int stringCount, {Duration gap = const Duration(milliseconds: 28)}) async {
    for (var s = 0; s < stringCount; s++) {
      pluck(s);
      await Future<void>.delayed(gap);
    }
  }

  /// Plucks requested since the last call. For the widget being driven.
  List<int> drainPlucks() {
    final out = List<int>.of(_pending);
    _pending.clear();
    return out;
  }
}

/// An interactive, custom-painted fretboard.
class Fretboard extends StatefulWidget {
  const Fretboard({
    this.stringCount = 6,
    this.markers = const [],
    this.firstFret = 0,
    this.lastFret = 12,
    this.leftHanded = false,
    this.controller,
    this.onTap,
    this.semanticLabel,
    super.key,
  });

  final int stringCount;
  final List<FretMarker> markers;
  final int firstFret;
  final int lastFret;
  final bool leftHanded;
  final FretboardController? controller;

  /// Called with the string (0 = lowest) and fret under a tap. The tapped
  /// string is plucked either way.
  final void Function(int string, int fret)? onTap;
  final String? semanticLabel;

  @override
  State<Fretboard> createState() => _FretboardState();
}

class _FretboardState extends State<Fretboard> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);

  /// Repaint signal for the strings layer only; no widget rebuilds per frame.
  final _frame = ValueNotifier<int>(0);
  late List<Duration?> _pluckedAt = List.filled(widget.stringCount, null);
  Duration _now = Duration.zero;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerPluck);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = Motion.of(context).reduced;
  }

  @override
  void didUpdateWidget(Fretboard old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onControllerPluck);
      widget.controller?.addListener(_onControllerPluck);
    }
    if (old.stringCount != widget.stringCount) {
      _pluckedAt = List.filled(widget.stringCount, null);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerPluck);
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _onControllerPluck() {
    widget.controller?.drainPlucks().forEach(_pluck);
  }

  void _pluck(int string) {
    if (string < 0 || string >= _pluckedAt.length) return;
    _pluckedAt[string] = _now;
    if (!_ticker.isActive) _ticker.start();
    _frame.value++;
  }

  void _onTick(Duration elapsed) {
    _now = elapsed;
    final anyActive = _pluckedAt.any((t) => t != null && elapsed - t < MotionTokens.stringDecay);
    _frame.value++;
    if (!anyActive) {
      _ticker.stop();
      _now = Duration.zero;
      _pluckedAt = List.filled(widget.stringCount, null);
    }
  }

  List<({double amplitude, double phase})> _vibration() => [
    for (var s = 0; s < widget.stringCount; s++) _stringState(s),
  ];

  ({double amplitude, double phase}) _stringState(int s) {
    final at = _pluckedAt[s];
    if (at == null) return (amplitude: 0, phase: 0);
    final t = (_now - at).inMicroseconds / 1e6;
    final decay = MotionTokens.stringDecay.inMicroseconds / 1e6;
    if (t >= decay) return (amplitude: 0, phase: 0);
    // Exponential decay; heavier strings start wider.
    final amplitude = (3.5 - s * 0.35) * math.exp(-4 * t / decay);
    // Real string frequencies (82-330 Hz) alias into noise at 60 fps, so
    // vibration is drawn at a slow "visual" frequency, lower for bass strings.
    // Under reduced motion the phase is pinned at pi/2: displacement is zero
    // but the amplitude-driven glow still gives feedback.
    final phase = _reduced ? math.pi / 2 : 2 * math.pi * (9 + s * 1.5) * t;
    return (amplitude: amplitude, phase: phase);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.stage;
    return Semantics(
      label: widget.semanticLabel ?? 'Fretboard',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              final hit = FretboardGeometry(
                size: size,
                stringCount: widget.stringCount,
                firstFret: widget.firstFret,
                lastFret: widget.lastFret,
                leftHanded: widget.leftHanded,
              ).hitTest(d.localPosition);
              if (hit == null) return;
              _pluck(hit.string);
              widget.onTap?.call(hit.string, hit.fret);
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    painter: FretboardWoodPainter(
                      colors: colors,
                      stringCount: widget.stringCount,
                      firstFret: widget.firstFret,
                      lastFret: widget.lastFret,
                      leftHanded: widget.leftHanded,
                    ),
                  ),
                ),
                RepaintBoundary(
                  child: CustomPaint(
                    painter: FretboardStringsPainter(
                      colors: colors,
                      stringCount: widget.stringCount,
                      vibration: _vibration,
                      markers: widget.markers,
                      firstFret: widget.firstFret,
                      lastFret: widget.lastFret,
                      leftHanded: widget.leftHanded,
                      repaint: _frame,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
