import 'dart:typed_data';

import 'package:fretlight/core/audio/output/audio_output.dart';
import 'package:fretlight/core/audio/wav.dart';

/// Records what would have played, and renders it so the PCM can be checked.
final class FakeAudioOutput implements AudioOutput {
  final played = <String>[];
  final rendered = <String, WavAudio>{};

  @override
  Future<void> play(String key, Future<Uint8List> Function() render, {String? channel}) async {
    played.add(key);
    rendered[key] ??= decodeWav(await render());
  }

  @override
  Future<void> stopAll() async {}

  @override
  Future<void> dispose() async {}
}
