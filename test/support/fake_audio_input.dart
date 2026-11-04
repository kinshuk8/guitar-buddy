import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fretlight/core/audio/engine/dsp_worker.dart';
import 'package:fretlight/core/audio/input/audio_input_source.dart';

/// Scriptable microphone for widget tests.
final class FakeAudioInputSource implements AudioInputSource {
  FakeAudioInputSource({
    this.current = MicPermission.granted,
    this.afterRequest = MicPermission.granted,
  });

  MicPermission current;
  MicPermission afterRequest;
  int requests = 0;
  int starts = 0;
  int stops = 0;
  bool settingsOpened = false;
  StreamController<Uint8List>? _pcm;
  final _events = StreamController<InputEvent>.broadcast();

  bool get isCapturing => _pcm != null;

  @override
  Future<MicPermission> permission() async => current;

  @override
  Future<MicPermission> requestPermission() async {
    requests++;
    return current = afterRequest;
  }

  @override
  Future<void> openSettings() async => settingsOpened = true;

  @override
  Future<({InputDescription description, Stream<Uint8List> pcm})> start() async {
    starts++;
    final c = _pcm = StreamController<Uint8List>();
    return (
      description: const InputDescription(sampleRate: 48000, raw: true, label: 'Fake mic'),
      pcm: c.stream,
    );
  }

  @override
  Future<void> stop() async {
    if (_pcm == null) return;
    stops++;
    await _pcm?.close();
    _pcm = null;
  }

  /// Feeds float samples as 20 ms PCM16 chunks, like a real mic.
  void feed(Float32List samples) {
    final c = _pcm;
    if (c == null) return;
    for (var i = 0; i < samples.length; i += 960) {
      c.add(floatToPcm16(Float32List.sublistView(samples, i, math.min(i + 960, samples.length))));
    }
  }

  void interrupt({required bool began}) =>
      _events.add(began ? const InterruptionBegan() : const InterruptionEnded());

  @override
  Stream<InputEvent> get events => _events.stream;

  @override
  Future<void> dispose() async {
    await stop();
    await _events.close();
  }
}
