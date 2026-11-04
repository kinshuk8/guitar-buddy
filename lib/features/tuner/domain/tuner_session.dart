import 'dart:math' as math;

import 'package:fretlight/core/audio/dsp/pitch_tracker.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:meta/meta.dart';

/// What the tuner shows for the string being tuned.
@immutable
final class TunerReading {
  const TunerReading({
    required this.hz,
    required this.detected,
    required this.stringIndex,
    required this.target,
    required this.cents,
  });

  /// Smoothed frequency actually heard (after octave folding).
  final double hz;

  /// Nearest equal-tempered note to [hz].
  final Note detected;

  /// String being tuned (0 = lowest).
  final int stringIndex;

  /// That string's open note in the current tuning.
  final Note target;

  /// Cents from [target]; negative = flat. Not clamped.
  final double cents;
}

/// Turns raw [PitchFrame]s into a steady [TunerReading].
///
/// Pure logic, driven by the audio's own sample clock, so it is fully
/// testable offline and immune to UI timing.
final class TunerSession {
  TunerSession({
    required this._tuning,
    required this.sampleRate,
    int? lockedString,
    this._math = const PitchMath(),
    this.minClarity = 0.88,
    this.minLevelDb = -55,
    this.holdSeconds = 0.8,
  }) : _locked = lockedString;

  final int sampleRate;
  final double minClarity;
  final double minLevelDb;

  /// How long the last reading stays up after the note fades, so the
  /// needle doesn't vanish between plucks.
  final double holdSeconds;

  Tuning _tuning;
  int? _locked;
  PitchMath _math;

  /// Recent pitches as fractional MIDI numbers; median-filtered.
  final List<double> _recent = [];
  static const _window = 5;

  /// Consecutive frames disagreeing with the median by a big interval.
  int _jumpCount = 0;
  double? _jumpMidi;

  int? _string;
  int? _candidateString;
  int _candidateCount = 0;

  int _lastVoicedSample = -1 << 40;
  TunerReading? _reading;

  TunerReading? get reading => _reading;

  Tuning get tuning => _tuning;

  set tuning(Tuning value) {
    _tuning = value;
    _clear();
  }

  int? get lockedString => _locked;

  /// Locks to one string (manual mode), or null for auto-detect.
  set lockedString(int? value) {
    _locked = value;
    _string = value;
    _clear();
  }

  PitchMath get pitchMath => _math;

  set pitchMath(PitchMath value) {
    _math = value;
    _clear();
  }

  void _clear() {
    _recent.clear();
    _jumpCount = 0;
    _reading = null;
    _candidateString = null;
    _candidateCount = 0;
    if (_locked == null) _string = null;
  }

  /// Feeds one analysis frame; returns the current reading (or null).
  TunerReading? update(PitchFrame frame) {
    final hz = frame.hz;
    final voiced = hz != null && frame.clarity >= minClarity && frame.rmsDb >= minLevelDb;
    if (!voiced) {
      if (frame.endSample - _lastVoicedSample > holdSeconds * sampleRate) {
        _recent.clear();
        _reading = null;
      }
      return _reading;
    }
    _lastVoicedSample = frame.endSample;

    final midi = _fold(_math.midiFloat(hz));
    if (_recent.isNotEmpty) {
      final current = _median();
      if ((midi - current).abs() > 0.8) {
        // A single outlier (pluck noise, a stray octave) is ignored; two in
        // a row agreeing with each other means a new note: start over fast.
        if (_jumpCount > 0 && _jumpMidi != null && (midi - _jumpMidi!).abs() < 0.5) {
          _recent.clear();
          _jumpCount = 0;
        } else {
          _jumpCount++;
          _jumpMidi = midi;
          return _reading;
        }
      } else {
        _jumpCount = 0;
      }
    }
    _recent.add(midi);
    if (_recent.length > _window) _recent.removeAt(0);

    final smoothed = _median();
    final string = _chooseString(smoothed);
    final target = _tuning.strings[string];
    final smoothedHz = _math.a4 * math.pow(2, (smoothed - 69) / 12).toDouble();
    return _reading = TunerReading(
      hz: smoothedHz,
      detected: Note(smoothed.round()),
      stringIndex: string,
      target: target,
      cents: (smoothed - target.midi) * 100,
    );
  }

  /// Octave folding.
  ///
  /// Locked to a string, any octave of its note is folded onto it: that is
  /// what makes 12th-fret harmonics work and absorbs stray octave errors.
  /// In auto mode only a reading well outside the open-string range (more
  /// than a fourth below the lowest or above the highest string) is folded,
  /// and only if an octave shift lands near a string. Anything between the
  /// strings is left alone: a string a few semitones off is normal when
  /// restringing, and folding it would light up the wrong string.
  double _fold(double midi) {
    final locked = _locked;
    if (locked != null) {
      final target = _tuning.strings[locked].midi.toDouble();
      var m = midi;
      while (m - target > 6) {
        m -= 12;
      }
      while (target - m > 6) {
        m += 12;
      }
      return m;
    }
    final lowest = _tuning.strings.first.midi;
    final highest = _tuning.strings.last.midi;
    if (midi >= lowest - 5 && midi <= highest + 5) return midi;
    for (final shift in const [-12.0, 12.0]) {
      if (_distanceToNearestString(midi + shift) < 0.5) return midi + shift;
    }
    return midi;
  }

  double _distanceToNearestString(double midi) =>
      _tuning.strings.map((n) => (n.midi - midi).abs()).reduce(math.min);

  int _chooseString(double midi) {
    final locked = _locked;
    if (locked != null) return locked;
    final nearest = _tuning.nearestString(midi);
    final current = _string;
    if (current == null || nearest == current) {
      _string = nearest;
      _candidateCount = 0;
      return nearest;
    }
    // Hysteresis: a note between two strings must favour the new one for a
    // few frames before the highlighted string jumps.
    if (_candidateString == nearest) {
      _candidateCount++;
    } else {
      _candidateString = nearest;
      _candidateCount = 1;
    }
    if (_candidateCount >= 3) {
      _string = nearest;
      _candidateCount = 0;
    }
    return _string!;
  }

  double _median() {
    final sorted = List<double>.of(_recent)..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  }
}
