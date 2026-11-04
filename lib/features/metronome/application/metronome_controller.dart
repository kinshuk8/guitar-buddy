import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/audio/output/audio_output.dart';
import 'package:fretlight/core/audio/wav.dart';
import 'package:fretlight/core/storage/local_store.dart';
import 'package:fretlight/features/chords/application/chord_player.dart';
import 'package:fretlight/features/metronome/domain/metronome_settings.dart';
import 'package:fretlight/features/metronome/domain/transport.dart';

@immutable
final class MetronomeState {
  const MetronomeState({required this.settings, this.playing = false});

  final MetronomeSettings settings;
  final bool playing;

  MetronomeState copyWith({MetronomeSettings? settings, bool? playing}) =>
      MetronomeState(settings: settings ?? this.settings, playing: playing ?? this.playing);
}

final metronomeProvider = NotifierProvider<MetronomeController, MetronomeState>(
  MetronomeController.new,
);

/// Runs the click loop on the audio engine.
///
/// No Dart timer is involved in when a click sounds: each tempo or pattern
/// is rendered to a loop and handed to the engine, scheduled on its sample
/// clock. A change lands on the next beat by scheduling the new loop to
/// start, and the old one to stop, at that same engine time.
final class MetronomeController extends Notifier<MetronomeState> {
  static const sampleRate = 48000;

  /// Time to render and load a loop before its first click is due.
  static const _lead = Duration(milliseconds: 150);

  late AudioOutput _out;
  late LocalStore _store;
  final transport = Transport();
  final _tap = TapTempo();

  LoopVoice? _current;
  ({LoopVoice voice, Duration at, int beat})? _pending;
  Future<void> _queue = Future.value();

  @override
  MetronomeState build() {
    _out = ref.watch(audioOutputProvider);
    _store = ref.watch(localStoreProvider);
    ref.onDispose(() => unawaited(_silence()));
    return MetronomeState(settings: _load());
  }

  /// Engine time now, for the beat visual.
  Duration get clock => _out.clock;

  BeatPosition? positionNow() => state.playing ? transport.position(_out.clock) : null;

  Future<void> toggle() => state.playing ? stop() : start();

  Future<void> start() {
    if (state.playing) return Future.value();
    state = state.copyWith(playing: true);
    return _enqueue(() async {
      await _out.warmUp();
      final wav = await _render(state.settings, 0);
      if (!state.playing || !ref.mounted) return;
      final at = _out.clock + const Duration(milliseconds: 60);
      _current = await _out.scheduleLoop(wav, at: at);
      transport
        ..clear()
        ..add(_segment(state.settings, at, 0));
    });
  }

  Future<void> stop() {
    if (!state.playing) return Future.value();
    state = state.copyWith(playing: false);
    return _enqueue(_silence);
  }

  void setBpm(int bpm) => _update(state.settings.copyWith(bpm: bpm));

  void nudge(int delta) => setBpm(state.settings.bpm + delta);

  void setSignature(TimeSignature s) => _update(state.settings.copyWith(signature: s));

  void setSubdivision(Subdivision s) => _update(state.settings.copyWith(subdivision: s));

  void cycleAccent(int beat) {
    final accents = [...state.settings.accents];
    accents[beat] = accents[beat].next;
    _update(state.settings.copyWith(accents: accents));
  }

  /// Tap tempo. [now] is Dart time: taps are human input, and their
  /// timestamps only set a tempo, they never schedule a click.
  void tap(Duration now) {
    final bpm = _tap.tap(now);
    if (bpm != null) setBpm(bpm);
  }

  void _update(MetronomeSettings next) {
    final previous = state.settings;
    if (next == previous) return;
    state = state.copyWith(settings: next);
    _save(next);
    if (state.playing) {
      final meterChanged = next.signature != previous.signature;
      unawaited(_enqueue(() => _reschedule(next, restartBar: meterChanged)));
    }
  }

  Future<void> _reschedule(MetronomeSettings s, {required bool restartBar}) async {
    final current = _current;
    if (current == null || !state.playing) return;
    var now = _out.clock;
    final pending = _pending;
    ({Duration at, int beat}) target;
    if (pending != null && pending.at > now + const Duration(milliseconds: 30)) {
      // A change is already waiting for its beat: replace it, same beat.
      _out.stopLoopAt(pending.voice, now);
      target = (at: pending.at, beat: pending.beat);
    } else {
      if (pending != null) _current = pending.voice; // it has started
      _pending = null;
      target = transport.nextBeat(now + _lead)!;
    }
    final beat = restartBar ? 0 : target.beat % s.beats;
    final wav = await _render(s, beat);
    if (!state.playing || !ref.mounted) return;

    now = _out.clock;
    if (target.at < now + const Duration(milliseconds: 10)) {
      // Rendering took longer than the lead (a very slow device): take the
      // following beat instead of starting late.
      target = transport.nextBeat(now + const Duration(milliseconds: 20))!;
    }
    final voice = await _out.scheduleLoop(wav, at: target.at);
    _out.stopLoopAt(_current!, target.at);
    _pending = (voice: voice, at: target.at, beat: beat);
    transport.add(_segment(s, target.at, beat));
  }

  Future<void> _silence() async {
    final now = _out.clock;
    if (_current case final v?) _out.stopLoopAt(v, now);
    if (_pending case final p?) _out.stopLoopAt(p.voice, now);
    _current = null;
    _pending = null;
    transport.clear();
  }

  TransportSegment _segment(MetronomeSettings s, Duration at, int beat) => TransportSegment(
    start: at,
    startBeat: beat,
    beats: s.beats,
    beatSeconds: s.beatSeconds(sampleRate),
    perBeat: s.subdivision.perBeat,
  );

  static Future<Uint8List> _render(MetronomeSettings s, int startBeat) =>
      Isolate.run(() => encodeWav16(renderLoop(s, sampleRate, startBeat: startBeat), sampleRate));

  Future<void> _enqueue(Future<void> Function() op) {
    final next = _queue.then((_) => ref.mounted ? op() : null).catchError((
      Object e,
      StackTrace st,
    ) {
      debugPrint('Metronome: $e\n$st');
      if (ref.mounted) state = state.copyWith(playing: false);
    });
    _queue = next;
    return next;
  }

  // Persistence: tempo, meter, subdivision and accents survive a restart.
  static const _bpmKey = 'metronome.bpm';
  static const _sigKey = 'metronome.signature';
  static const _subKey = 'metronome.subdivision';
  static const _accentKey = 'metronome.accents';

  MetronomeSettings _load() {
    final sig = TimeSignature.tryParse(_store.setting(_sigKey) ?? '');
    final signature = TimeSignature.common.contains(sig) ? sig! : const TimeSignature(4, 4);
    final accents = _store
        .setting(_accentKey)
        ?.split(',')
        .map((a) => Accent.values.asNameMap()[a])
        .toList();
    return MetronomeSettings(
      bpm: (int.tryParse(_store.setting(_bpmKey) ?? '') ?? 100).clamp(
        MetronomeSettings.minBpm,
        MetronomeSettings.maxBpm,
      ),
      signature: signature,
      subdivision: Subdivision.values.asNameMap()[_store.setting(_subKey)] ?? Subdivision.none,
      accents: accents != null && accents.length == signature.beats && !accents.contains(null)
          ? accents.cast<Accent>()
          : null,
    );
  }

  void _save(MetronomeSettings s) {
    _store
      ..setSetting(_bpmKey, '${s.bpm}')
      ..setSetting(_sigKey, '${s.signature}')
      ..setSetting(_subKey, s.subdivision.name)
      ..setSetting(_accentKey, s.accents.map((a) => a.name).join(','));
  }
}
