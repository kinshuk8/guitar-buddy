import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:fretlight/core/audio/output/audio_output.dart';
import 'package:fretlight/core/audio/session/app_audio_session.dart';

/// [AudioOutput] on SoLoud (miniaudio): low latency on both platforms and
/// sample-accurate scheduling, which the metronome will rely on.
///
/// SoLoud is told not to manage the iOS audio session (it ships with
/// `sessionCategory = none`), so [AppAudioSession] stays the only owner.
final class SoLoudOutput implements AudioOutput {
  SoLoudOutput({this.cacheSize = 24});

  final int cacheSize;
  final SoLoud _soloud = SoLoud.instance;
  Future<void>? _init;

  /// Loaded sounds, least recently used first.
  final _cache = <String, AudioSource>{}; // Dart maps keep insertion order
  final _channels = <String, SoundHandle>{};

  Future<void> _ensureInit() => _init ??= () async {
    await AppAudioSession.ensurePlayback();
    if (!_soloud.isInitialized) await _soloud.init(sampleRate: 48000, channels: Channels.mono);
  }();

  @override
  Future<void> play(String key, Future<Uint8List> Function() render, {String? channel}) async {
    await _ensureInit();
    // The mic may have deactivated the session since; re-activating is cheap.
    await AppAudioSession.ensurePlayback();
    var source = _cache.remove(key);
    if (source == null) {
      source = await _soloud.loadMem(key, await render());
      while (_cache.length >= cacheSize) {
        final oldest = _cache.keys.first;
        unawaited(_soloud.disposeSource(_cache.remove(oldest)!));
      }
    }
    _cache[key] = source; // most recently used last
    if (channel != null) {
      final previous = _channels[channel];
      if (previous != null && _soloud.getIsValidVoiceHandle(previous)) {
        // A 30 ms fade instead of a hard stop: no click.
        _soloud.fadeVolume(previous, 0, const Duration(milliseconds: 30));
        _soloud.scheduleStop(previous, const Duration(milliseconds: 30));
      }
    }
    final handle = _soloud.play(source);
    if (channel != null) _channels[channel] = handle;
  }

  @override
  Future<void> stopAll() async {
    if (!_soloud.isInitialized) return;
    for (final h in _channels.values) {
      if (_soloud.getIsValidVoiceHandle(h)) await _soloud.stop(h);
    }
    _channels.clear();
  }

  @override
  Future<void> dispose() async {
    if (!_soloud.isInitialized) return;
    try {
      await stopAll();
      await _soloud.disposeAllSources();
    } on Object catch (e) {
      debugPrint('SoLoudOutput.dispose: $e');
    }
    _cache.clear();
  }
}
