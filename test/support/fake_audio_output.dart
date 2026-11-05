import 'dart:typed_data';

import 'package:fretlight/core/audio/output/audio_output.dart';
import 'package:fretlight/core/audio/wav.dart';

/// A loop the fake was asked to schedule.
final class FakeLoop {
  FakeLoop(this.voice, this.audio, this.start, {this.looping = true});

  final bool looping;

  final LoopVoice voice;
  final WavAudio audio;
  final Duration start;
  Duration? stop;

  bool soundingAt(Duration t) => start <= t && (stop == null || t < stop!);
}

/// Records what would have played, renders it so the PCM can be checked,
/// and keeps an engine clock that tests move by hand.
final class FakeAudioOutput implements AudioOutput {
  final played = <String>[];
  final rendered = <String, WavAudio>{};
  final loops = <FakeLoop>[];

  /// The fake engine clock. Advance it to simulate audio playing.
  Duration now = const Duration(seconds: 1);

  List<FakeLoop> soundingAt(Duration t) => [
    for (final l in loops)
      if (l.soundingAt(t)) l,
  ];

  @override
  Future<void> play(String key, Future<Uint8List> Function() render, {String? channel}) async {
    played.add(key);
    rendered[key] ??= decodeWav(await render());
  }

  @override
  Future<void> warmUp() async {}

  @override
  Duration get clock => now;

  @override
  Future<LoopVoice> scheduleLoop(Uint8List wav, {required Duration at}) async {
    final v = LoopVoice(loops.length);
    loops.add(FakeLoop(v, decodeWav(wav), at));
    return v;
  }

  @override
  Future<LoopVoice> scheduleOnce(Uint8List wav, {required Duration at}) async {
    final v = LoopVoice(loops.length);
    loops.add(FakeLoop(v, decodeWav(wav), at, looping: false));
    return v;
  }

  @override
  void stopLoopAt(LoopVoice voice, Duration at) {
    final l = loops.firstWhere((l) => identical(l.voice, voice));
    l.stop = l.stop == null || at < l.stop! ? at : l.stop;
  }

  @override
  Future<void> stopAll() async {
    for (final l in loops) {
      if (l.stop == null || l.stop! > now) l.stop = now;
    }
  }

  @override
  Future<void> dispose() async {}
}
