import 'dart:typed_data';

/// A looping sound scheduled on the engine clock.
final class LoopVoice {
  LoopVoice(this.id);

  /// Implementation-defined (a SoLoud handle, or a fake's counter).
  final Object? id;
}

/// Plays rendered sounds: one-shots (chord strums, plucks) and loops
/// scheduled on the engine clock (the metronome). Behind an interface so
/// tests and previews need no audio device.
abstract interface class AudioOutput {
  /// Plays the WAV that [render] produces, cached under [key] so a sound
  /// heard once plays instantly the next time.
  ///
  /// A sound on the same [channel] as one still ringing stops it first, the
  /// way a new strum silences the last one; null mixes over everything.
  Future<void> play(String key, Future<Uint8List> Function() render, {String? channel});

  Future<void> stopAll();

  /// Starts the engine (if needed) so [clock] is live.
  Future<void> warmUp();

  /// The audio engine's clock: the timeline every scheduled loop is pinned
  /// to. It advances with the samples actually mixed, not with Dart time.
  /// Synchronous and cheap: the beat visual reads it every frame.
  Duration get clock;

  /// Starts looping [wav] at engine time [at], sample-accurately. Loops are
  /// gapless: the engine wraps from the last sample to the first.
  Future<LoopVoice> scheduleLoop(Uint8List wav, {required Duration at});

  /// Plays [wav] once, starting at engine time [at] (a song's backing).
  Future<LoopVoice> scheduleOnce(Uint8List wav, {required Duration at});

  /// Stops [voice] at engine time [at] (sample-accurate), or cancels it if
  /// it hasn't started by then. A time in the past stops it now.
  void stopLoopAt(LoopVoice voice, Duration at);

  Future<void> dispose();
}
