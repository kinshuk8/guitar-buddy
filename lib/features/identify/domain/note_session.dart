import 'package:fretlight/core/audio/dsp/pitch_tracker.dart';
import 'package:fretlight/core/audio/listening.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:meta/meta.dart';

/// A single note as the identifier shows it.
@immutable
final class NoteReading {
  const NoteReading({
    required this.note,
    required this.hz,
    required this.cents,
    this.fading = false,
  });

  final Note note;
  final double hz;

  /// Offset from equal temperament at the current reference pitch.
  final double cents;

  /// The note has stopped; shown dimmed for a moment.
  final bool fading;
}

/// Steadies pitch frames into a note: clarity and level gates, a short
/// median, and a brief hold after the note stops.
///
/// Unlike the tuner there's no target string: any note is fair game, and
/// the octave matters (A2 vs A3 are different places on the neck).
final class NoteSession {
  NoteSession({
    required this.sampleRate,
    this.math = const PitchMath(),
    this.minClarity = 0.9,
    this.minDb = -55,
    this.hold = const Duration(milliseconds: 800),
    this.floor,
  });

  /// Room-relative level gate; replaces [minDb] when set.
  final NoiseFloor? floor;

  final int sampleRate;
  PitchMath math;
  final double minClarity;
  final double minDb;
  final Duration hold;

  final List<double> _recent = [];
  NoteReading? _reading;
  int? _lastHeardSample;

  NoteReading? get reading => _reading;

  void reset() {
    _recent.clear();
    _reading = null;
    _lastHeardSample = null;
  }

  NoteReading? update(PitchFrame f) {
    final hz = f.hz;
    final loudEnough = floor?.update(f.rmsDb) ?? f.rmsDb >= minDb;
    final ok = hz != null && f.clarity >= minClarity && loudEnough && hz > 60 && hz < 1500;
    if (!ok) {
      final last = _lastHeardSample;
      final r = _reading;
      if (r == null || last == null) return _reading;
      if ((f.endSample - last) / sampleRate * 1e6 > hold.inMicroseconds) {
        reset();
        return null;
      }
      return _reading = NoteReading(note: r.note, hz: r.hz, cents: r.cents, fading: true);
    }
    _lastHeardSample = f.endSample;
    // A jump of more than half a semitone is a new note: start over so
    // the median doesn't drag the old one along.
    if (_recent.isNotEmpty && PitchMath.cents(hz, _recent.last).abs() > 50) _recent.clear();
    _recent.add(hz);
    if (_recent.length > 5) _recent.removeAt(0);
    final sorted = [..._recent]..sort();
    final median = sorted[sorted.length ~/ 2];
    final a = math.analyse(median);
    return _reading = NoteReading(note: a.note, hz: median, cents: a.cents);
  }
}
