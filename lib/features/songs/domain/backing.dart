import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fretlight/core/audio/synth/click.dart';
import 'package:fretlight/core/audio/synth/strum.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:meta/meta.dart';

/// How the guitar part is strummed.
enum StrumPattern {
  /// One strum at the start of each bar: hear the changes, play over them.
  bar('One per bar'),

  /// A down-strum on every beat.
  beats('Every beat'),

  /// Down, down-up, up-down-up (4/4) or down, down-up, down-up (3/4).
  folk('Folk');

  StrumPattern(this.label);

  final String label;

  /// Strokes within one bar: (beat offset, down?, gain).
  List<(double, bool, double)> strokes(int beatsPerBar) => switch (this) {
    bar => [(0, true, 1)],
    beats => [for (var b = 0; b < beatsPerBar; b++) (b.toDouble(), true, b == 0 ? 1.0 : 0.8)],
    folk when beatsPerBar == 3 => [
      (0, true, 1),
      (1, true, 0.75),
      (1.5, false, 0.55),
      (2, true, 0.75),
      (2.5, false, 0.55),
    ],
    folk => [
      (0, true, 1),
      (1, true, 0.75),
      (1.5, false, 0.55),
      (2.5, false, 0.55),
      (3, true, 0.75),
      (3.5, false, 0.55),
    ],
  };
}

/// One chord change to play: when, for how long, and which shape.
@immutable
final class BackingEvent {
  const BackingEvent({required this.startBeat, required this.beats, required this.frets});

  final double startBeat;
  final double beats;

  /// Shape as sounding frets (standard tuning), lowest string first; null
  /// for N.C. or a chord with no shape (that bar is silent).
  final List<int?>? frets;
}

/// Renders the guitar part of a song, from [fromBeat] to [toBeat].
///
/// Pure and deterministic, so it runs in an isolate and can be tested.
/// Each distinct strum is synthesised once and then placed at every
/// stroke; a new stroke damps the one before over a few milliseconds, the
/// way a strumming hand does, so chords don't smear into each other.
Float32List renderBacking({
  required List<BackingEvent> events,
  required int beatsPerBar,
  required double bpm,
  required int sampleRate,
  required double fromBeat,
  required double toBeat,
  StrumPattern pattern = StrumPattern.bar,
  bool click = false,
  double tailSeconds = 1.5,
}) {
  final beatSamples = 60 / bpm * sampleRate;
  final length = ((toBeat - fromBeat) * beatSamples).round();
  final out = Float32List(length + (tailSeconds * sampleRate).round());
  const pm = PitchMath();
  final cache = <String, Float32List>{};

  Float32List strumFor(List<int?> frets, {required bool down}) {
    final key = '${frets.join(',')}|$down';
    return cache[key] ??= () {
      // Up-strokes catch the top strings only, and are brighter and shorter.
      final hz = [
        for (var s = 0; s < frets.length; s++)
          if (frets[s] case final int f when down || s >= 2)
            pm.hz(Tuning.standard.noteAt(s, f))
          else
            null,
      ];
      return renderStrum(
        stringHz: hz,
        sampleRate: sampleRate,
        down: down,
        seconds: 2.4,
        gap: Duration(milliseconds: down ? 18 : 12),
        peak: 0.7,
      );
    }();
  }

  // Every stroke in time order, then each one plays until the next.
  // A null-frets stroke is a damp: N.C. means the strings stop.
  final strokes = <(double beat, List<int?>? frets, bool down, double gain)>[];
  for (final e in events) {
    final frets = e.frets;
    if (frets == null) {
      if (e.startBeat >= fromBeat && e.startBeat < toBeat) {
        strokes.add((e.startBeat, null, true, 0));
      }
      continue;
    }
    final bars = (e.beats / beatsPerBar).ceil();
    for (var bar = 0; bar < bars; bar++) {
      for (final (offset, down, gain) in pattern.strokes(beatsPerBar)) {
        final beat = e.startBeat + bar * beatsPerBar + offset;
        if (beat >= e.startBeat + e.beats) continue;
        if (beat + 1e-9 < fromBeat || beat >= toBeat) continue;
        strokes.add((beat, frets, down, gain));
      }
    }
  }
  strokes.sort((a, b) => a.$1.compareTo(b.$1));

  final damp = (0.012 * sampleRate).round();
  for (final (i, (beat, frets, down, gain)) in strokes.indexed) {
    final start = ((beat - fromBeat) * beatSamples).round();
    final end = i + 1 < strokes.length
        ? ((strokes[i + 1].$1 - fromBeat) * beatSamples).round() + damp
        : out.length;
    if (frets == null) continue; // The damp itself makes no sound.
    final pcm = strumFor(frets, down: down);
    final n = math.min(pcm.length, math.min(end, out.length) - start);
    for (var j = 0; j < n; j++) {
      // Fade out over the damp window as the next stroke lands.
      final fromEnd = (start + j) - (end - damp);
      final env = fromEnd <= 0 ? 1.0 : 1 - fromEnd / damp;
      out[start + j] += pcm[j] * gain * env;
    }
  }

  if (click) {
    final strong = renderClick(ClickVoice.strong, sampleRate);
    final normal = renderClick(ClickVoice.normal, sampleRate);
    for (var beat = fromBeat.ceil(); beat < toBeat; beat++) {
      final c = beat % beatsPerBar == 0 ? strong : normal;
      final start = ((beat - fromBeat) * beatSamples).round();
      for (var j = 0; j < c.length && start + j < out.length; j++) {
        out[start + j] += c[j] * 0.35;
      }
    }
  }

  var peak = 0.0;
  for (final v in out) {
    if (v.abs() > peak) peak = v.abs();
  }
  if (peak > 0.95) {
    final g = 0.95 / peak;
    for (var i = 0; i < out.length; i++) {
      out[i] *= g;
    }
  }
  return out;
}
