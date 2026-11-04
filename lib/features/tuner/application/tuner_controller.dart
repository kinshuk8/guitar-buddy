import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/audio/engine/dsp_worker.dart';
import 'package:fretlight/core/audio/input/audio_input_source.dart';
import 'package:fretlight/core/audio/input/record_input_source.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/features/tuner/domain/tuner_session.dart';

enum TunerStatus {
  /// Not visible or app in background; mic closed.
  idle,

  /// Mic permission not granted yet (the prompt can still be shown).
  needsPermission,

  /// Denied for good; only Settings can fix it.
  permanentlyDenied,
  starting,
  listening,

  /// A call or another app has the mic.
  interrupted,
  error,
}

@immutable
final class TunerState {
  const TunerState({
    required this.tuning,
    this.status = TunerStatus.idle,
    this.reading,
    this.customTunings = const [],
    this.lockedString,
    this.a4 = PitchMath.defaultA4,
    this.input,
  });

  final TunerStatus status;
  final TunerReading? reading;
  final Tuning tuning;
  final List<Tuning> customTunings;

  /// Manual string selection; null = auto-detect.
  final int? lockedString;
  final double a4;
  final InputDescription? input;

  List<Tuning> get allTunings => [...Tuning.presets, ...customTunings];

  TunerState copyWith({
    TunerStatus? status,
    TunerReading? Function()? reading,
    Tuning? tuning,
    List<Tuning>? customTunings,
    int? Function()? lockedString,
    double? a4,
    InputDescription? input,
  }) => TunerState(
    status: status ?? this.status,
    reading: reading != null ? reading() : this.reading,
    tuning: tuning ?? this.tuning,
    customTunings: customTunings ?? this.customTunings,
    lockedString: lockedString != null ? lockedString() : this.lockedString,
    a4: a4 ?? this.a4,
    input: input ?? this.input,
  );
}

/// The microphone. Overridden with a fake in tests.
final audioInputProvider = Provider<AudioInputSource>((ref) {
  final source = RecordInputSource();
  ref.onDispose(() => unawaited(source.dispose()));
  return source;
});

final tunerProvider = NotifierProvider<TunerController, TunerState>(TunerController.new);

final class TunerController extends Notifier<TunerState> {
  late AudioInputSource _input;
  DspWorker? _worker;
  StreamSubscription<Uint8List>? _pcm;
  StreamSubscription<Object>? _frames;
  StreamSubscription<InputEvent>? _events;
  TunerSession? _session;

  /// Whether the screen wants the mic (visible and app in foreground).
  bool _wanted = false;
  bool _interrupted = false;
  bool _askedThisSession = false;

  /// Start/stop are serialised: quick tab switches queue up instead of
  /// racing two `record` sessions.
  Future<void> _queue = Future.value();

  @override
  TunerState build() {
    _input = ref.watch(audioInputProvider);
    _events = _input.events.listen(_onInputEvent);
    ref.onDispose(() {
      unawaited(_events?.cancel());
      unawaited(_stopCapture());
      _worker?.dispose();
    });
    return TunerState(tuning: Tuning.standard);
  }

  /// Called by the tuner screen when it becomes visible/hidden or the app
  /// moves between foreground and background.
  Future<void> setActive({required bool active}) {
    _wanted = active;
    return _enqueue(_reconcile);
  }

  Future<void> requestPermission() => _enqueue(() async {
    final p = await _input.requestPermission();
    if (!ref.mounted) return;
    _applyPermission(p);
    await _reconcile();
  });

  Future<void> openSettings() => _input.openSettings();

  void selectTuning(Tuning tuning) {
    state = state.copyWith(tuning: tuning, lockedString: () => null, reading: () => null);
    _session?.tuning = tuning;
    _session?.lockedString = null;
  }

  void saveCustomTuning(Tuning tuning) {
    final others = state.customTunings.where((t) => t.id != tuning.id);
    state = state.copyWith(customTunings: [...others, tuning]);
    selectTuning(tuning);
  }

  void deleteCustomTuning(Tuning tuning) {
    state = state.copyWith(
      customTunings: state.customTunings.where((t) => t.id != tuning.id).toList(),
    );
    if (state.tuning.id == tuning.id) selectTuning(Tuning.standard);
  }

  /// Locks the tuner to one string, or back to auto with null.
  void lockString(int? index) {
    state = state.copyWith(lockedString: () => index, reading: () => null);
    _session?.lockedString = index;
  }

  void setA4(double hz) {
    final clamped = hz.clamp(PitchMath.minA4, PitchMath.maxA4);
    state = state.copyWith(a4: clamped, reading: () => null);
    _session?.pitchMath = PitchMath(a4: clamped);
  }

  /// Every queued step re-checks `ref.mounted`: the provider can be
  /// disposed while a start (permission prompt, isolate spawn) is pending.
  Future<void> _enqueue(Future<void> Function() op) {
    final next = _queue.then((_) => ref.mounted ? op() : null).catchError((
      Object e,
      StackTrace st,
    ) {
      debugPrint('Tuner: $e\n$st');
      if (ref.mounted) state = state.copyWith(status: TunerStatus.error);
    });
    _queue = next;
    return next;
  }

  void _applyPermission(MicPermission p) {
    state = state.copyWith(
      status: switch (p) {
        MicPermission.granted => state.status,
        MicPermission.denied => TunerStatus.needsPermission,
        MicPermission.permanentlyDenied => TunerStatus.permanentlyDenied,
      },
    );
  }

  Future<void> _reconcile() async {
    final running = _pcm != null;
    if (!_wanted || _interrupted) {
      if (running) await _stopCapture();
      if (!ref.mounted) return;
      state = state.copyWith(
        status: _interrupted ? TunerStatus.interrupted : _idleStatus(),
        reading: () => null,
      );
      return;
    }
    if (running) return;

    var permission = await _input.permission();
    if (permission == MicPermission.denied && !_askedThisSession) {
      // Ask in context, once per launch: the user just opened the tuner.
      _askedThisSession = true;
      permission = await _input.requestPermission();
    }
    if (!ref.mounted) return;
    if (permission != MicPermission.granted) {
      _applyPermission(permission);
      return;
    }
    await _startCapture();
  }

  /// Keep a permission problem visible while idle instead of hiding it.
  TunerStatus _idleStatus() => switch (state.status) {
    TunerStatus.needsPermission || TunerStatus.permanentlyDenied => state.status,
    _ => TunerStatus.idle,
  };

  Future<void> _startCapture() async {
    state = state.copyWith(status: TunerStatus.starting);
    final started = await _input.start();
    final rate = started.description.sampleRate;
    final worker = _worker ??= await DspWorker.spawn(sampleRate: rate);
    if (!ref.mounted) {
      worker.dispose();
      await _input.stop();
      return;
    }
    worker.reset();
    final session = _session = TunerSession(
      tuning: state.tuning,
      sampleRate: rate,
      lockedString: state.lockedString,
      math: PitchMath(a4: state.a4),
    );
    _frames = worker.frames.listen((frame) {
      final before = session.reading;
      final after = session.update(frame);
      if (!identical(before, after)) state = state.copyWith(reading: () => after);
    });
    _pcm = started.pcm.listen(worker.push);
    state = state.copyWith(status: TunerStatus.listening, input: started.description);
  }

  Future<void> _stopCapture() async {
    await _pcm?.cancel();
    _pcm = null;
    await _frames?.cancel();
    _frames = null;
    _session = null;
    await _input.stop();
  }

  void _onInputEvent(InputEvent e) {
    switch (e) {
      case InterruptionBegan():
        _interrupted = true;
      case InterruptionEnded():
        _interrupted = false;
    }
    unawaited(_enqueue(_reconcile));
  }
}
