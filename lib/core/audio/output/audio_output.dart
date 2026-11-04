import 'dart:typed_data';

/// Plays short rendered sounds (chord strums, plucks; later metronome
/// clicks). Behind an interface so tests and previews need no audio device.
abstract interface class AudioOutput {
  /// Plays the WAV that [render] produces, cached under [key] so a sound
  /// heard once plays instantly the next time.
  ///
  /// A sound on the same [channel] as one still ringing stops it first, the
  /// way a new strum silences the last one; null mixes over everything.
  Future<void> play(String key, Future<Uint8List> Function() render, {String? channel});

  Future<void> stopAll();

  Future<void> dispose();
}
