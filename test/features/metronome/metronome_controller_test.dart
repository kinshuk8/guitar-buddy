import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/storage/local_store.dart';
import 'package:fretlight/features/chords/application/chord_player.dart';
import 'package:fretlight/features/metronome/application/metronome_controller.dart';
import 'package:fretlight/features/metronome/domain/metronome_settings.dart';

import '../../support/fake_audio_output.dart';
import 'metronome_timing_test.dart' show detectOnsets;

const sr = 48000;

int samplesOf(Duration d) => (d.inMicroseconds * sr / 1e6).round();

/// What the speaker would play from [from] to [to]: every scheduled loop,
/// started and stopped at its engine times and wrapped sample-exactly.
Float32List mixdown(FakeAudioOutput out, Duration from, Duration to) {
  final n = samplesOf(to - from);
  final mix = Float32List(n);
  for (final l in out.loops) {
    final start = samplesOf(l.start - from);
    final stop = l.stop == null ? n : samplesOf(l.stop! - from);
    final pcm = l.audio.samples;
    for (var i = start < 0 ? 0 : start; i < n && i < stop; i++) {
      mix[i] += pcm[(i - start) % pcm.length];
    }
  }
  return mix;
}

void main() {
  late FakeAudioOutput out;
  late LocalStore store;
  late ProviderContainer c;

  setUp(() {
    out = FakeAudioOutput();
    store = LocalStore.memory();
    c = ProviderContainer(
      overrides: [
        audioOutputProvider.overrideWithValue(out),
        localStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(c.dispose);
  });

  MetronomeController ctl() => c.read(metronomeProvider.notifier);

  test('start schedules one loop just ahead on the engine clock', () async {
    ctl().setBpm(120);
    await ctl().start();
    expect(out.loops, hasLength(1));
    final loop = out.loops.single;
    expect(loop.start, out.now + const Duration(milliseconds: 60));
    expect(loop.audio.sampleRate, sr);
    expect(c.read(metronomeProvider).playing, isTrue);

    out.now = loop.start + const Duration(milliseconds: 1250); // 2.5 beats in
    final p = ctl().positionNow()!;
    expect(p.beat, 2);
    expect(p.phase, closeTo(0.5, 1e-6));
  });

  test('a tempo change mid-bar lands on the next beat: no gap, no double click', () async {
    ctl().setBpm(150);
    await ctl().start();
    final start = out.loops.single.start;
    out.now = start + const Duration(milliseconds: 1100); // during beat 3
    ctl().setBpm(120);
    await pumpQueue();

    expect(out.loops, hasLength(2));
    final first = out.loops[0];
    final second = out.loops[1];
    // Next boundary at least the render lead (150 ms) ahead of 1.1 s, at
    // 150 BPM (0.4 s beats): 1.6 s = beat 4 (index 0 of the next bar).
    expect(first.stop, second.start);
    expect(second.start, start + const Duration(milliseconds: 1600));

    final audio = mixdown(out, start, start + const Duration(seconds: 4));
    final onsets = detectOnsets(audio);
    final times = [for (final o in onsets) o / sr];
    // 150 BPM until 1.6 s, then 120 BPM: clicks at 0, .4, .8, 1.2, 1.6, 2.1, 2.6…
    final expected = [0.0, 0.4, 0.8, 1.2, 1.6, 2.1, 2.6, 3.1, 3.6];
    expect(times, hasLength(expected.length));
    for (final (i, t) in times.indexed) {
      expect(t, closeTo(expected[i], 0.0005), reason: 'click $i');
    }
  });

  test('rapid changes replace the one still waiting, at the same beat', () async {
    ctl().setBpm(100);
    await ctl().start();
    final start = out.loops.single.start;
    out.now = start + const Duration(milliseconds: 100);
    ctl()
      ..setBpm(101)
      ..setBpm(102)
      ..setBpm(103);
    await pumpQueue();
    final sounding = [
      for (final l in out.loops)
        if (l.stop == null || l.stop! > l.start) l,
    ];
    // The original, then only the latest change; the cancelled ones never sound.
    expect(sounding, hasLength(2));
    expect(sounding.last.audio.samples.length, MetronomeSettings(bpm: 103).loopSamples(sr));
    expect(sounding.first.stop, sounding.last.start);
  });

  test('a new meter restarts the count on the next beat', () async {
    await ctl().start();
    out.now = out.loops.single.start + const Duration(milliseconds: 700);
    ctl().setSignature(const TimeSignature(3, 4));
    await pumpQueue();
    final at = out.loops.last.start;
    expect(ctl().transport.position(at)!.beat, 0);
  });

  test('stop silences now and clears the beat', () async {
    await ctl().start();
    out.now = out.loops.single.start + const Duration(seconds: 3);
    await ctl().stop();
    expect(out.loops.single.stop, out.now);
    expect(ctl().positionNow(), isNull);
  });

  test('accent taps cycle strong → medium → normal → mute', () {
    ctl().cycleAccent(1);
    expect(c.read(metronomeProvider).settings.accents[1], Accent.mute);
    ctl().cycleAccent(1);
    expect(c.read(metronomeProvider).settings.accents[1], Accent.strong);
  });

  test('settings survive a restart; tempo is clamped to 30–300', () {
    ctl()
      ..setBpm(400)
      ..setSignature(const TimeSignature(6, 8))
      ..setSubdivision(Subdivision.triplets);
    expect(c.read(metronomeProvider).settings.bpm, 300);
    final again = ProviderContainer(
      overrides: [
        audioOutputProvider.overrideWithValue(out),
        localStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(again.dispose);
    final s = again.read(metronomeProvider).settings;
    expect((s.bpm, '${s.signature}', s.subdivision), (300, '6/8', Subdivision.triplets));
    expect(s.accents[3], Accent.medium);
  });

  test('tap tempo sets the BPM', () {
    for (final ms in [0, 600, 1200, 1800]) {
      ctl().tap(Duration(milliseconds: ms));
    }
    expect(c.read(metronomeProvider).settings.bpm, 100);
  });
}

/// Lets the controller's queued render (in an isolate) finish.
Future<void> pumpQueue() => Future<void>.delayed(const Duration(milliseconds: 400));
