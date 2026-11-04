import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';

enum MicPermission {
  granted,

  /// Not asked yet, or denied but the OS will ask again.
  denied,

  /// The OS will not show the prompt again; the user must use Settings.
  permanentlyDenied,
}

/// Something the input wants the app to know while capturing.
sealed class InputEvent {
  const InputEvent();
}

/// A phone call, Siri, an alarm or another app took the microphone.
final class InterruptionBegan extends InputEvent {
  const InterruptionBegan();
}

/// The interruption is over; capture may resume.
final class InterruptionEnded extends InputEvent {
  const InterruptionEnded();
}

/// How the microphone is configured, shown honestly in the UI.
@immutable
final class InputDescription {
  const InputDescription({required this.sampleRate, required this.raw, required this.label});

  final int sampleRate;

  /// True when the OS promised unprocessed audio (no AGC/noise suppression).
  final bool raw;
  final String label;
}

/// Microphone capture as a stream of 16-bit little-endian mono PCM chunks.
///
/// PCM16 bytes rather than floats: that is what the platforms deliver, it is
/// half the size to move to the DSP isolate, and the isolate does the
/// conversion off the UI thread.
abstract interface class AudioInputSource {
  Future<MicPermission> permission();

  /// Shows the OS prompt if it can still be shown.
  Future<MicPermission> requestPermission();

  /// Opens the system settings page for this app.
  Future<void> openSettings();

  /// Starts capture. The stream ends when [stop] is called.
  Future<({InputDescription description, Stream<Uint8List> pcm})> start();

  Future<void> stop();

  /// Interruptions and similar events, independent of the PCM stream.
  Stream<InputEvent> get events;

  Future<void> dispose();
}
