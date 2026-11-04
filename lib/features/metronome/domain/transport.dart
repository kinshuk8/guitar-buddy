import 'package:meta/meta.dart';

/// One stretch of steady clicking: a bar loop that started at [start]
/// (on the audio engine's clock) on beat [startBeat].
@immutable
final class TransportSegment {
  const TransportSegment({
    required this.start,
    required this.startBeat,
    required this.beats,
    required this.beatSeconds,
    required this.perBeat,
  });

  final Duration start;
  final int startBeat;
  final int beats;
  final double beatSeconds;
  final int perBeat;

  Duration get beatLength => Duration(microseconds: (beatSeconds * 1e6).round());
}

/// Where the music is at a moment.
typedef BeatPosition = ({int beat, int sub, double phase});

/// Maps audio-engine time to beats.
///
/// The UI asks "which beat is sounding now?" every frame by reading the
/// engine clock, so the light follows the audio rather than a timer that
/// could drift away from it. A tempo change appends a segment that begins
/// at a future beat boundary; until then the old one still applies.
final class Transport {
  final List<TransportSegment> _segments = [];

  bool get isRunning => _segments.isNotEmpty;

  TransportSegment? get latest => _segments.isEmpty ? null : _segments.last;

  void clear() => _segments.clear();

  void add(TransportSegment s) {
    // Anything scheduled at or after the new start never happened.
    _segments
      ..removeWhere((e) => e.start >= s.start)
      ..add(s);
    // Only the segment in force and the next one matter.
    while (_segments.length > 2) {
      _segments.removeAt(0);
    }
  }

  TransportSegment? _at(Duration t) {
    TransportSegment? found;
    for (final s in _segments) {
      if (s.start <= t) found = s;
    }
    return found;
  }

  /// Null before the first click.
  BeatPosition? position(Duration t) {
    final s = _at(t);
    if (s == null) return null;
    final beatsElapsed = (t - s.start).inMicroseconds / 1e6 / s.beatSeconds;
    final whole = beatsElapsed.floor();
    final frac = beatsElapsed - whole;
    return (
      beat: (s.startBeat + whole) % s.beats,
      sub: (frac * s.perBeat).floor().clamp(0, s.perBeat - 1),
      phase: frac,
    );
  }

  /// The first beat boundary at or after [t] in the segment in force then,
  /// and which beat of the bar it is. Changes take effect here.
  ({Duration at, int beat})? nextBeat(Duration t) {
    final s = _at(t) ?? latest;
    if (s == null) return null;
    final elapsed = (t - s.start).inMicroseconds / 1e6;
    final k = elapsed <= 0 ? 0 : (elapsed / s.beatSeconds).ceil();
    return (
      at: s.start + Duration(microseconds: (k * s.beatSeconds * 1e6).round()),
      beat: (s.startBeat + k) % s.beats,
    );
  }
}

/// Tap tempo: the median of the recent intervals, so one late tap doesn't
/// swing the result. A pause longer than [reset] starts over.
final class TapTempo {
  TapTempo({this.reset = const Duration(seconds: 2), this.window = 6});

  final Duration reset;
  final int window;
  final List<Duration> _taps = [];

  /// Records a tap at [now]; returns the tempo once there are two taps.
  int? tap(Duration now) {
    if (_taps.isNotEmpty && now - _taps.last > reset) _taps.clear();
    _taps.add(now);
    while (_taps.length > window + 1) {
      _taps.removeAt(0);
    }
    if (_taps.length < 2) return null;
    final intervals = [
      for (var i = 1; i < _taps.length; i++) (_taps[i] - _taps[i - 1]).inMicroseconds,
    ]..sort();
    final mid = intervals.length ~/ 2;
    final median = intervals.length.isOdd
        ? intervals[mid].toDouble()
        : (intervals[mid - 1] + intervals[mid]) / 2;
    return (60e6 / median).round();
  }

  int get count => _taps.length;
}
