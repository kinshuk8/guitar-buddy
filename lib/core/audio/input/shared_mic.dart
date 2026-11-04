import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/audio/input/audio_input_source.dart';
import 'package:fretlight/core/audio/input/record_input_source.dart';

/// The microphone. Overridden with a fake in tests.
final audioInputProvider = Provider<AudioInputSource>((ref) {
  final source = RecordInputSource();
  ref.onDispose(() => unawaited(source.dispose()));
  return source;
});

/// One microphone, several listeners (tuner, identifier).
final sharedMicProvider = Provider<SharedMic>((ref) => SharedMic(ref.watch(audioInputProvider)));

/// Shares a single recorder between screens.
///
/// Each screen gets a [MicClient] that looks like its own microphone. The
/// real recorder starts when the first client starts and stops when the
/// last one stops, with every start/stop serialised. Without this, leaving
/// the tuner for the identifier could stop the recorder the identifier had
/// just started, depending on which tab's lifecycle callback ran first.
final class SharedMic {
  SharedMic(this._source);

  final AudioInputSource _source;
  final _active = <MicClient>{};
  StreamController<Uint8List>? _fanout;
  StreamSubscription<Uint8List>? _sub;
  late InputDescription _description;
  late Future<void> _queue = Future.value();

  // A factory for per-screen handles, not a conversion.
  // ignore: use_to_and_as_if_applicable
  MicClient client() => MicClient._(this);

  @visibleForTesting
  int get activeClients => _active.length;

  Future<T> _enqueue<T>(Future<T> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<({InputDescription description, Stream<Uint8List> pcm})> _acquire(MicClient c) =>
      _enqueue(() async {
        var fanout = _fanout;
        if (fanout == null) {
          final started = await _source.start();
          // Synchronous: chunks are forwarded the moment they arrive, with no
          // extra scheduling hop between the recorder and the analysers.
          fanout = _fanout = StreamController<Uint8List>.broadcast(sync: true);
          _description = started.description;
          _sub = started.pcm.listen(fanout.add, onError: fanout.addError);
        }
        _active.add(c);
        return (description: _description, pcm: fanout.stream);
      });

  Future<void> _release(MicClient c) => _enqueue(() async {
    if (!_active.remove(c) || _active.isNotEmpty) return;
    await _sub?.cancel();
    _sub = null;
    await _fanout?.close();
    _fanout = null;
    await _source.stop();
  });
}

/// A screen's view of the shared microphone. [stop] is safe to call even
/// when this client never started.
final class MicClient implements AudioInputSource {
  MicClient._(this._shared);

  final SharedMic _shared;

  @override
  Future<MicPermission> permission() => _shared._source.permission();

  @override
  Future<MicPermission> requestPermission() => _shared._source.requestPermission();

  @override
  Future<void> openSettings() => _shared._source.openSettings();

  @override
  Stream<InputEvent> get events => _shared._source.events;

  @override
  Future<({InputDescription description, Stream<Uint8List> pcm})> start() => _shared._acquire(this);

  @override
  Future<void> stop() => _shared._release(this);

  /// Releases this client only; the recorder belongs to [SharedMic].
  @override
  Future<void> dispose() => stop();
}
