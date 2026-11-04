import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/audio/output/audio_output.dart';
import 'package:fretlight/core/audio/output/soloud_output.dart';
import 'package:fretlight/core/audio/synth/strum.dart';
import 'package:fretlight/core/audio/wav.dart';
import 'package:fretlight/core/music/music.dart';

/// The speaker. Overridden with a fake in tests.
final audioOutputProvider = Provider<AudioOutput>((ref) {
  final out = SoLoudOutput();
  ref.onDispose(() => unawaited(out.dispose()));
  return out;
});

final chordPlayerProvider = Provider<ChordPlayer>(
  (ref) => ChordPlayer(ref.watch(audioOutputProvider)),
);

/// Sounds voicings with Karplus–Strong synthesis: no samples, so no
/// recordings to license, and every chord is exactly in tune.
final class ChordPlayer {
  ChordPlayer(this._out);

  static const sampleRate = 48000;
  static const _pitch = PitchMath();
  final AudioOutput _out;

  /// Down-strum, low string to high, like a pick across the strings.
  Future<void> strum(Voicing voicing, {Tuning? tuning}) {
    final t = tuning ?? Tuning.standard;
    final hz = [
      for (var s = 0; s < voicing.frets.length; s++)
        if (voicing.frets[s] case final int f) _pitch.hz(t.noteAt(s, f)) else null,
    ];
    return _play('strum:${t.id}:${voicing.frets.join(',')}', hz, channel: 'strum');
  }

  /// One string of the voicing (a tap on the diagram).
  Future<void> pluck(Voicing voicing, int string, {Tuning? tuning}) {
    final fret = voicing.frets[string];
    if (fret == null) return Future.value();
    final t = tuning ?? Tuning.standard;
    final hz = List<double?>.filled(voicing.frets.length, null);
    hz[string] = _pitch.hz(t.noteAt(string, fret));
    return _play('pluck:${t.id}:$string:$fret', hz, seconds: 1.8);
  }

  Future<void> _play(String key, List<double?> hz, {String? channel, double seconds = 2.6}) async {
    try {
      await _out.play(
        key,
        // ~10 ms of DSP per strum: run it off the UI isolate anyway so a
        // tap never costs a frame.
        () => Isolate.run<Uint8List>(
          () => encodeWav16(
            renderStrum(stringHz: hz, sampleRate: sampleRate, seconds: seconds),
            sampleRate,
          ),
        ),
        channel: channel,
      );
    } on Object catch (e, st) {
      // Sound is a nicety here; never let it break the screen.
      debugPrint('ChordPlayer: $e\n$st');
    }
  }
}
