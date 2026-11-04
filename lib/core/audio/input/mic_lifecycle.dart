import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fretlight/core/audio/input/audio_input_source.dart';

enum MicStatus {
  /// Not visible or app in background; mic closed.
  idle,

  /// Permission not granted yet (the prompt can still be shown).
  needsPermission,

  /// Denied for good; only Settings can fix it.
  permanentlyDenied,
  starting,
  listening,

  /// A call or another app has the mic.
  interrupted,
  error,
}

/// The permission / start / stop / interruption logic every listening
/// screen needs, independent of what it does with the audio.
///
/// Every transition runs through one queue, so quick tab switches line up
/// instead of racing. [isAlive] is checked after every await: the owner
/// can be disposed while a permission prompt or start is pending.
final class MicLifecycle {
  MicLifecycle({
    required this.input,
    required this.onStatus,
    required this.onStart,
    required this.onStop,
    required this.isAlive,
  }) {
    _events = input.events.listen((e) {
      _interrupted = e is InterruptionBegan;
      unawaited(_enqueue(_reconcile));
    });
  }

  final AudioInputSource input;
  final void Function(MicStatus) onStatus;

  /// Called with the live stream once the mic is open.
  final Future<void> Function(InputDescription description, Stream<Uint8List> pcm) onStart;
  final Future<void> Function() onStop;
  final bool Function() isAlive;

  late final StreamSubscription<InputEvent> _events;
  MicStatus _status = MicStatus.idle;
  bool _wanted = false;
  bool _interrupted = false;
  bool _asked = false;
  bool _running = false;
  Future<void> _queue = Future.value();

  MicStatus get status => _status;

  Future<void> setActive({required bool active}) {
    _wanted = active;
    return _enqueue(_reconcile);
  }

  Future<void> requestPermission() => _enqueue(() async {
    final p = await input.requestPermission();
    if (!isAlive()) return;
    _applyPermission(p);
    await _reconcile();
  });

  Future<void> openSettings() => input.openSettings();

  /// Stops and starts again (the "Try again" button).
  Future<void> restart() async {
    await setActive(active: false);
    await setActive(active: true);
  }

  Future<void> dispose() async {
    await _events.cancel();
    if (_running) {
      _running = false;
      await onStop();
      await input.stop();
    }
  }

  void _set(MicStatus s) {
    _status = s;
    if (isAlive()) onStatus(s);
  }

  Future<void> _enqueue(Future<void> Function() op) {
    final next = _queue.then((_) => isAlive() ? op() : null).catchError((Object e, StackTrace st) {
      debugPrint('Mic: $e\n$st');
      _set(MicStatus.error);
    });
    _queue = next;
    return next;
  }

  void _applyPermission(MicPermission p) => _set(switch (p) {
    MicPermission.granted => _status,
    MicPermission.denied => MicStatus.needsPermission,
    MicPermission.permanentlyDenied => MicStatus.permanentlyDenied,
  });

  Future<void> _reconcile() async {
    if (!_wanted || _interrupted) {
      if (_running) {
        _running = false;
        await onStop();
        await input.stop();
      }
      if (!isAlive()) return;
      _set(
        _interrupted
            ? MicStatus.interrupted
            : switch (_status) {
                MicStatus.needsPermission || MicStatus.permanentlyDenied => _status,
                _ => MicStatus.idle,
              },
      );
      return;
    }
    if (_running) return;
    var permission = await input.permission();
    if (permission == MicPermission.denied && !_asked) {
      // Ask in context, once per launch: the user just opened this screen.
      _asked = true;
      permission = await input.requestPermission();
    }
    if (!isAlive()) return;
    if (permission != MicPermission.granted) {
      _applyPermission(permission);
      return;
    }
    _set(MicStatus.starting);
    final started = await input.start();
    if (!isAlive()) {
      await input.stop();
      return;
    }
    _running = true;
    await onStart(started.description, started.pcm);
    _set(MicStatus.listening);
  }
}
