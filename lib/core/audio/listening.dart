/// Listening gates. Pure Dart: no Flutter, safe in isolates and tools.
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';

/// How eagerly the app treats sound as playing.
///
/// Fixed thresholds don't survive real rooms and phones: in raw-mic mode
/// (iOS measurement mode, Android UNPROCESSED) a guitar a metre away can
/// read 20 dB quieter than the same guitar close up, and a fan or fridge
/// sets a floor that varies by room. So gates are relative to the room's
/// own noise floor (see [NoiseFloor]); this only sets how far above it.
enum Sensitivity {
  /// Noisy room: needs clearly louder playing, ignores more background.
  low(marginDb: 15, tunerClarity: 0.9, noteClarity: 0.9),
  normal(marginDb: 10, tunerClarity: 0.85, noteClarity: 0.86),

  /// Quiet room, soft playing or the phone further away.
  high(marginDb: 6, tunerClarity: 0.8, noteClarity: 0.82);

  Sensitivity({required this.marginDb, required this.tunerClarity, required this.noteClarity});

  /// How far above the room's noise floor sound must be to count.
  final double marginDb;

  /// Pitch clarity (0..1) a frame needs. Real strings with buzz and room
  /// echo rarely reach the 0.9+ a synthesised string does.
  final double tunerClarity;
  final double noteClarity;

  String get label => switch (this) {
    low => 'Low',
    normal => 'Normal',
    high => 'High',
  };

  String get help => switch (this) {
    low => 'For noisy rooms. Play a little louder.',
    normal => 'For most rooms.',
    high => 'For quiet rooms, soft playing or the phone further away.',
  };
}

/// Tracks the room's background level from the frames themselves: drops
/// instantly to any quieter frame, creeps up slowly otherwise. Between
/// notes it settles on the true floor; during long playing it can't climb
/// fast enough to mistake the guitar for the room.
@immutable
final class NoiseFloorReading {
  const NoiseFloorReading(this.floorDb, this.gateDb);

  final double floorDb;

  /// Level a frame must reach to count as playing.
  final double gateDb;
}

final class NoiseFloor {
  NoiseFloor({
    required this.marginDb,
    required this.frameSeconds,
    this.riseDbPerSecond = 3,
    this.ceilingDb = -38,
    this.absoluteMinDb = -72,
    this.startDb = -60,
  }) : _floor = startDb;

  final double marginDb;
  final double frameSeconds;

  /// How fast the floor may rise when the room gets louder.
  final double riseDbPerSecond;

  /// The floor never rises above this: anything louder is playing, not
  /// background, however long it lasts.
  final double ceilingDb;

  /// Gate never below this: digital silence isn't a reason to trigger on
  /// a mouse click.
  final double absoluteMinDb;
  final double startDb;

  double _floor;

  double get floorDb => _floor;
  double get gateDb => math.max(_floor + marginDb, absoluteMinDb);

  /// Below this is digital silence (a mic still opening, a muted input),
  /// not a room: learning it as the floor would make the next seconds
  /// wildly over-sensitive.
  static const _digitalSilenceDb = -90.0;
  bool _seeded = false;

  /// Feeds one frame's level; returns whether it counts as playing.
  bool update(double levelDb) {
    if (levelDb < _digitalSilenceDb) return false;
    if (!_seeded) {
      // The first real frame is the best guess at the room (people rarely
      // play the instant a screen opens); cap it in case they do.
      _floor = math.min(levelDb, ceilingDb);
      _seeded = true;
    }
    final playing = levelDb >= gateDb;
    if (levelDb < _floor) {
      _floor = math.max(levelDb, -100);
    } else {
      _floor = math.min(_floor + riseDbPerSecond * frameSeconds, math.min(levelDb, ceilingDb));
    }
    return playing;
  }

  void reset() {
    _floor = startDb;
    _seeded = false;
  }

  NoiseFloorReading get reading => NoiseFloorReading(_floor, gateDb);
}
