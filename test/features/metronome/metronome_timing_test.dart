import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/audio/synth/click.dart';
import 'package:fretlight/features/metronome/domain/metronome_settings.dart';
import 'package:fretlight/features/metronome/domain/transport.dart';

/// Click onsets found in audio: the first sample of each burst that rises
/// above a threshold after at least [gap] samples of quiet.
List<int> detectOnsets(Float32List pcm, {double threshold = 0.02, int gap = 200}) {
  final onsets = <int>[];
  var quiet = gap;
  for (var i = 0; i < pcm.length; i++) {
    if (pcm[i].abs() > threshold) {
      if (quiet >= gap) onsets.add(i);
      quiet = 0;
    } else {
      quiet++;
    }
  }
  return onsets;
}

void main() {
  test('a click is short enough for sixteenths at 300 BPM and starts without a pop', () {
    for (final v in ClickVoice.values) {
      final c = renderClick(v, 48000);
      expect(c.length / 48000, lessThan(0.05), reason: v.name);
      expect(c.first.abs(), lessThan(1e-3), reason: '${v.name}: no DC step');
      expect(c.last.abs(), lessThan(0.01 * v.gain), reason: '${v.name}: decayed');
    }
  });

  test('accents: downbeat strong, compound meters grouped, muted beats silent', () {
    expect(const TimeSignature(4, 4).defaultAccents, [
      Accent.strong,
      Accent.normal,
      Accent.normal,
      Accent.normal,
    ]);
    expect(const TimeSignature(6, 8).defaultAccents[3], Accent.medium);
    final s = MetronomeSettings(
      subdivision: Subdivision.eighths,
      accents: const [Accent.strong, Accent.mute, Accent.normal, Accent.normal],
    );
    final events = clickEvents(s, 48000);
    expect(events.where((e) => e.beat == 1), isEmpty, reason: 'muted beat and its subdivision');
    expect(events.first.voice, ClickVoice.strong);
    expect(events.where((e) => e.sub == 1).map((e) => e.voice).toSet(), {ClickVoice.subdivision});
  });

  test('rotated bars keep the beat: starting on beat 3 puts beat 3 first', () {
    final s = MetronomeSettings();
    final e = clickEvents(s, 48000, startBeat: 2);
    expect(e.take(4).map((x) => x.beat), [2, 3, 0, 1]);
    expect(e[2].voice, ClickVoice.strong);
  });

  test('drift over 10 minutes stays far below audibility', () {
    // How the engine plays it: one rendered bar, looped sample-exactly.
    // Onsets are detected in the real rendered audio, then followed through
    // ten minutes of loop repeats and compared with the ideal click times.
    final report = StringBuffer('\n== Metronome drift over 10 minutes ==\n')
      ..writeln('rate   BPM   meter  sub  clicks   worst error   drift at 10 min');
    var worstOverall = 0.0;
    for (final sr in [48000, 44100]) {
      for (final bpm in [30, 47, 60, 97, 120, 133, 187, 251, 300]) {
        for (final (sig, sub) in [
          (const TimeSignature(4, 4), Subdivision.none),
          (const TimeSignature(7, 8), Subdivision.sixteenths),
          (const TimeSignature(3, 4), Subdivision.triplets),
        ]) {
          final s = MetronomeSettings(bpm: bpm, signature: sig, subdivision: sub);
          final bar = renderLoop(s, sr);
          final onsets = detectOnsets(bar);
          final perBar = s.loopBars(sr) * s.beats * s.subdivision.perBeat;
          expect(onsets, hasLength(perBar), reason: '$bpm $sig ${sub.label}: every click found');

          final clickSeconds = 60 / bpm / sub.perBeat;
          final bars = (600 / (bar.length / sr)).ceil();
          var worst = 0.0;
          var last = 0.0;
          var n = 0;
          for (var b = 0; b < bars; b++) {
            for (var i = 0; i < perBar; i++) {
              final actual = (b * bar.length + onsets[i]) / sr;
              if (actual > 600) break;
              // Detection adds a constant onset delay (the click's attack);
              // measure against the first click so only drift remains.
              final ideal = n * clickSeconds + onsets[0] / sr;
              final err = (actual - ideal).abs();
              worst = math.max(worst, err);
              last = actual - ideal;
              n++;
            }
          }
          worstOverall = math.max(worstOverall, worst);
          report.writeln(
            '${sr ~/ 1000}k   ${'$bpm'.padLeft(3)}   ${'$sig'.padRight(5)}  ${'${sub.perBeat}'.padLeft(3)}  '
            '${'$n'.padLeft(6)}   ${(worst * 1000).toStringAsFixed(3).padLeft(7)} ms   '
            '${(last * 1000).toStringAsFixed(3).padLeft(8)} ms',
          );
          // Humans notice ~5-10 ms of timing error between clicks; a whole
          // millisecond after ten minutes is far below that.
          expect(worst, lessThan(0.001), reason: '$sr Hz, $bpm BPM, $sig, ${sub.label}');
        }
      }
    }
    report.writeln('Worst anywhere: ${(worstOverall * 1000).toStringAsFixed(3)} ms');
    // Printed on purpose: the milestone's drift report.
    // ignore: avoid_print
    print(report);
  });

  test('the loop sounds the same streamed: wrap-around clicks land on time', () {
    // Concatenate 20 s of loops (as the engine does) and detect onsets in
    // the continuous signal, catching any click that straddles the seam.
    final s = MetronomeSettings(bpm: 137, subdivision: Subdivision.sixteenths);
    final bar = renderLoop(s, 48000);
    final reps = (20 * 48000 / bar.length).ceil();
    final stream = Float32List(bar.length * reps);
    for (var r = 0; r < reps; r++) {
      stream.setAll(r * bar.length, bar);
    }
    final onsets = detectOnsets(stream);
    const step = 48000 * 60 / 137 / 4;
    // Threshold detection finds quiet subdivision clicks a few samples
    // later than loud downbeats; that is the detector, not the timing.
    for (final (i, o) in onsets.indexed) {
      expect((o - onsets.first - i * step).abs(), lessThan(4), reason: 'click $i');
    }
    expect(onsets.length, reps * s.loopBars(48000) * 16);
  });

  group('transport', () {
    TransportSegment seg(Duration start, {int startBeat = 0, double beat = 0.5}) =>
        TransportSegment(
          start: start,
          startBeat: startBeat,
          beats: 4,
          beatSeconds: beat,
          perBeat: 2,
        );

    test('maps engine time to beat, subdivision and phase', () {
      final t = Transport()..add(seg(const Duration(seconds: 10)));
      expect(t.position(const Duration(seconds: 9)), isNull, reason: 'before the first click');
      expect(t.position(const Duration(seconds: 10))!.beat, 0);
      final p = t.position(const Duration(milliseconds: 11300))!; // 2.6 beats in
      expect((p.beat, p.sub), (2, 1));
      expect(p.phase, closeTo(0.6, 1e-9));
      expect(t.position(const Duration(seconds: 12))!.beat, 0, reason: 'next bar');
    });

    test('a tempo change lands on the next beat and keeps counting the bar', () {
      final t = Transport()..add(seg(Duration.zero));
      final next = t.nextBeat(const Duration(milliseconds: 1600))!; // beat 3.2
      expect(next.at, const Duration(seconds: 2));
      expect(next.beat, 0);
      final mid = t.nextBeat(const Duration(milliseconds: 1100))!;
      expect((mid.at, mid.beat), (const Duration(milliseconds: 1500), 3));

      // Faster tempo from beat 3 at 1.5 s.
      t.add(seg(mid.at, startBeat: 3, beat: 0.25));
      expect(
        t.position(const Duration(milliseconds: 1400))!.beat,
        2,
        reason: 'old tempo until then',
      );
      expect(t.position(const Duration(milliseconds: 1500))!.beat, 3);
      expect(t.position(const Duration(milliseconds: 1750))!.beat, 0);
    });

    test('a newer change replaces one still pending', () {
      final t = Transport()
        ..add(seg(Duration.zero))
        ..add(seg(const Duration(seconds: 2), beat: 0.3))
        ..add(seg(const Duration(seconds: 2), beat: 0.4));
      expect(t.latest!.beatSeconds, 0.4);
      expect(t.position(const Duration(milliseconds: 2450))!.beat, 1);
    });
  });

  group('tap tempo', () {
    Duration ms(int v) => Duration(milliseconds: v);

    test('steady taps give the tempo; one sloppy tap does not swing it', () {
      final tap = TapTempo();
      expect(tap.tap(ms(0)), isNull);
      expect(tap.tap(ms(500)), 120);
      expect(tap.tap(ms(1000)), 120);
      expect(tap.tap(ms(1580)), 120, reason: 'median ignores the late tap');
      expect(tap.tap(ms(2000)), 120);
    });

    test('a long pause starts over', () {
      final tap = TapTempo()
        ..tap(ms(0))
        ..tap(ms(1000));
      expect(tap.tap(ms(5000)), isNull);
      expect(tap.tap(ms(5400)), 150);
    });
  });
}
