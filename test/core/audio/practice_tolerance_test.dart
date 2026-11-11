import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/audio/dsp/chord_detector.dart';
import 'package:fretlight/core/audio/dsp/chord_tracker.dart';
import 'package:fretlight/core/audio/listening.dart';
import 'package:fretlight/core/audio/synth/strum.dart';
import 'package:fretlight/core/audio/synth/test_signals.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/features/identify/domain/chord_smoother.dart';
import 'package:fretlight/features/learn/domain/curriculum.dart';
import 'package:fretlight/features/practice/domain/practice_session.dart';

import 'chord_conditions_test.dart' show Condition, chordsToTest, closeMic, library;

const sr = 48000;
const pm = PitchMath();

/// Barre shapes beyond the course: the ones players reach for up the neck.
const barres = {
  'A:577655': 'A, E shape at 5',
  'G:355433': 'G, E shape at 3',
  'C:x35553': 'C, A shape at 3',
  'D:x57775': 'D, A shape at 5',
  'Am:577555': 'Am, E shape at 5',
  'Gm:355333': 'Gm, E shape at 3',
  'Cm:x35543': 'Cm, A shape at 3',
  'F#m:244222': 'F#m, E shape at 2',
  'Bb:x13331': 'Bb, A shape at 1',
  'B:x24442': 'B, A shape at 2',
};

/// How each strum reached the mic.
final class Case {
  const Case(
    this.name,
    this.condition, {
    this.voice = GuitarVoice.steel,
    this.weakThird = 0,
    this.detune = 0,
  });

  final String name;
  final Condition condition;
  final GuitarVoice voice;

  /// dB taken off the string carrying the chord's third (a half-fretted or
  /// muted string: the Em-heard-as-E5 case).
  final double weakThird;

  /// Random per-string tuning error, in cents (a guitar slightly out).
  final double detune;
}

final cases = <Case>[
  for (final v in GuitarVoice.all) ...[
    Case('${v.name} · normal', const Condition('normal'), voice: v),
    Case('${v.name} · slow', const Condition('slow', gapMs: 45), voice: v),
    Case(
      '${v.name} · headset',
      const Condition('headset', gapMs: 30, gainDb: closeMic, headset: true),
      voice: v,
    ),
    Case('${v.name} · uneven', const Condition('uneven', gapMs: 25, jitterDb: 5), voice: v),
    Case('${v.name} · far+noise', const Condition('far', gapMs: 25, snrDb: 20), voice: v),
  ],
  const Case('weak third −12 dB', Condition('normal'), weakThird: 12),
  const Case(
    'weak third, headset',
    Condition('h', gapMs: 30, gainDb: closeMic, headset: true),
    weakThird: 12,
  ),
  const Case('muted third −30 dB', Condition('normal'), weakThird: 30),
  const Case('out of tune ±12¢', Condition('normal'), detune: 12),
  const Case('out of tune, nylon', Condition('normal'), voice: GuitarVoice.nylon, detune: 12),
];

Float32List render(List<int?> frets, Chord chord, Case k, int seed) {
  final c = k.condition;
  final rnd = math.Random(seed);
  final out = Float32List((2.2 * sr).round());
  final order = [
    for (var s = 0; s < 6; s++)
      if (frets[s] != null) s,
  ];
  // The highest string sounding the third: the one a sloppy finger mutes.
  final third = chord.root.transpose(
    chord.quality.required.firstWhere((i) => i == 3 || i == 4, orElse: () => -1),
  );
  final hasThird = chord.quality.required.any((i) => i == 3 || i == 4);
  int? thirdString;
  for (final s in order) {
    if (hasThird && Tuning.standard.noteAt(s, frets[s]!).pitchClass == third) thirdString = s;
  }
  for (final (step, s) in (c.up ? order.reversed.toList() : order).indexed) {
    final cents = (rnd.nextDouble() * 2 - 1) * k.detune;
    final one = List<double?>.filled(6, null)
      ..[s] = pm.hz(Tuning.standard.noteAt(s, frets[s]!)) * math.pow(2, cents / 1200);
    final pcm = renderStrum(stringHz: one, sampleRate: sr, seconds: 2.2, peak: 0.3, voice: k.voice);
    var db = c.gainDb[s] + (rnd.nextDouble() * 2 - 1) * c.jitterDb;
    if (s == thirdString) db -= k.weakThird;
    final g = 2 * math.pow(10, db / 20);
    final at = step * c.gapMs * sr ~/ 1000;
    for (var i = 0; i + at < out.length && i < pcm.length; i++) {
      out[i + at] += g * pcm[i];
    }
  }
  var x = out;
  if (c.headset) x = band(band(x, 150, high: true), 7000, high: false);
  if (c.snrDb != null) x = TestSignals.withNoise(x, c.snrDb!, seed: seed);
  return x;
}

/// What practice did with one strum: accepted it, called it wrong, or
/// didn't judge it at all (you'd have to strum again).
enum Outcome { counted, wrong, unheard }

Outcome judge(Float32List pcm, Chord target, {ChordMatching matching = ChordMatching.normal}) {
  final det = ChromaChordDetector(sampleRate: sr);
  final tracker = ChordTracker(detector: det);
  final hop = tracker.hopSeconds(sr);
  final sm = ChordSmoother(
    hopSeconds: hop,
    floor: NoiseFloor(marginDb: 10, frameSeconds: hop),
  );
  final session = PracticeSession([target], matching: matching);
  for (final e in tracker.push(Float32List.fromList([...Float32List(sr ~/ 2), ...pcm]))) {
    final r = sm.update(e);
    if (r == null) continue;
    final v = session.hear(r);
    if (v == null) continue;
    return v == Verdict.miss ? Outcome.wrong : Outcome.counted;
  }
  return Outcome.unheard;
}

/// Every chord to try: the course's, then the barre shapes.
List<(String, List<int?>)> allChords() => [
  for (final (spec, frets) in chordsToTest())
    if (taughtSpecs.contains(spec)) (spec, frets),
  for (final spec in barres.keys) (spec, chordFretsOf(spec)!),
];

final Set<String> taughtSpecs = {for (final g in chordsByStage) ...g.specs};

void main() {
  // The full matrix (5 guitars × 5 ways of playing + weak and muted thirds +
  // out-of-tune, on every taught chord and ten barre shapes) takes about two
  // minutes: run it with REPORT=1. By default a cross-section runs, with the
  // same limits.
  final full = Platform.environment['REPORT'] != null;
  final playCases = full
      ? cases
      : [cases[0], cases[11], cases[17], cases[23], cases[25], cases[26]];
  final mixCases = full
      ? [cases[0], cases[2], cases[7], cases[13], cases[25], cases[27]]
      : [cases[0], cases[7], cases[13]];
  bool clean(Case k) => k.weakThird == 0;

  test('practice counts the chord you play, on many guitars and in many ways', () {
    final chords = allChords();
    final report = StringBuffer('\n== Practice: is the chord you play counted? ==\n');
    final counted = {for (final m in ChordMatching.values) m: 0};
    final cleanCounted = {for (final m in ChordMatching.values) m: 0};
    var cleanTotal = 0;
    final misses = {for (final m in ChordMatching.values) m: <String>[]};
    for (final k in playCases) {
      final ki = cases.indexOf(k);
      final row = {for (final m in ChordMatching.values) m: 0};
      for (final (spec, frets) in chords) {
        final target = Chord.parse(chordSymbolOf(spec));
        final pcm = render(frets, target, k, ki * 97 + spec.hashCode);
        if (clean(k)) cleanTotal++;
        for (final m in ChordMatching.values) {
          final o = judge(pcm, target, matching: m);
          expect(o, isNot(Outcome.unheard), reason: '$spec [${k.name}] ${m.name}: never judged');
          if (o == Outcome.counted) {
            row[m] = row[m]! + 1;
            counted[m] = counted[m]! + 1;
            if (clean(k)) cleanCounted[m] = cleanCounted[m]! + 1;
          } else {
            misses[m]!.add('$spec [${k.name}]');
          }
        }
      }
      report
        ..write(k.name.padRight(26))
        ..writeln(
          ChordMatching.values
              .map((m) => '${m.name}: ${row[m]}/${chords.length}'.padRight(20))
              .join(),
        );
    }
    for (final m in ChordMatching.values) {
      report.writeln(
        '\n${m.name}: ${counted[m]} counted; not counted: ${misses[m]!.take(30).join(', ')}',
      );
    }

    // Wrong chords played: how often each setting lets one through.
    final wrongly = {for (final m in ChordMatching.values) m: <String>[]};
    final wronglyClear = {for (final m in ChordMatching.values) m: 0};
    var mixTotal = 0;
    var mixClear = 0;
    for (final k in mixCases) {
      final ki = cases.indexOf(k);
      for (final (want, played) in confusions) {
        final frets =
            chordFretsOf(chordSpecFor(played)) ?? library.bySymbol(played)!.voicings.first.frets;
        final pcm = render(
          frets,
          Chord.parse(played),
          k,
          ki * 13 + want.hashCode + played.hashCode,
        );
        mixTotal++;
        if (clean(k)) mixClear++;
        for (final m in ChordMatching.values) {
          if (judge(pcm, Chord.parse(want), matching: m) == Outcome.counted) {
            wrongly[m]!.add('asked $want, played $played [${k.name}]');
            if (clean(k)) wronglyClear[m] = wronglyClear[m]! + 1;
          }
        }
      }
    }
    report.writeln('\n== Wrong chord played: wrongly counted (of $mixTotal) ==');
    for (final m in ChordMatching.values) {
      report.writeln('${m.name}: ${wrongly[m]!.length}');
      for (final w in wrongly[m]!) {
        report.writeln('  $w');
      }
    }
    if (full) {
      // A report, on request.
      // ignore: avoid_print
      print(report);
    }

    const n = ChordMatching.normal;
    const f = ChordMatching.forgiving;
    // The right chord, cleanly played on any of these guitars: counted.
    expect(cleanCounted[n]! / cleanTotal, greaterThanOrEqualTo(0.99), reason: '$report');
    // Forgiving never counts fewer than normal, and normal no fewer than exact.
    expect(counted[f], greaterThanOrEqualTo(counted[n]!), reason: '$report');
    expect(counted[n], greaterThanOrEqualTo(counted[ChordMatching.exact]!), reason: '$report');
    // A different chord, with its third clearly ringing, is almost never
    // passed: at most one in 25 on forgiving, one in 50 on normal.
    expect(wronglyClear[n]! / mixClear, lessThanOrEqualTo(0.02), reason: '$report');
    expect(wronglyClear[f]! / mixClear, lessThanOrEqualTo(0.04), reason: '$report');
  }, timeout: const Timeout(Duration(minutes: 20)));

  test('the third decides: D asked, Dm played is not counted however it is named', () {
    // Dm's notes include D and A: "D5", which is D give or take a note. The
    // notes heard settle it: an F where F# belongs.
    final c = List<double>.filled(12, 0)
      ..[2] =
          1 // D
      ..[5] =
          0.8 // F
      ..[9] = 0.9; // A
    final e = PracticeSession.evidence(Chord.parse('D'), c);
    expect(e.thirdClash, greaterThan(ChordMatching.normal.maxClash));
    final own = PracticeSession.evidence(Chord.parse('Dm'), c);
    expect(own.thirdClash, lessThan(0));
    expect(own.outside, lessThan(0.05));
  });
}

/// Chords people confuse, as (asked for, actually played).
const confusions = [
  ('Em', 'E'),
  ('E', 'Em'),
  ('Am', 'A'),
  ('A', 'Am'),
  ('D', 'Dm'),
  ('Dm', 'D'),
  ('C', 'Am'),
  ('Am', 'C'),
  ('G', 'Em'),
  ('Em', 'G'),
  ('C', 'G'),
  ('G', 'C'),
  ('A', 'D'),
  ('D', 'A'),
  ('E', 'A'),
  ('A', 'E'),
  ('F', 'Dm'),
  ('Dm', 'F'),
  ('C', 'F'),
  ('F', 'C'),
  ('Em', 'Am'),
  ('Am', 'Em'),
  ('G', 'D'),
  ('D', 'G'),
  ('E7', 'Em'),
  ('Am7', 'A7'),
];

Float32List band(Float32List x, double hz, {required bool high}) {
  final w = 2 * math.pi * hz / sr;
  final alpha = math.sin(w) / (2 * 0.707);
  final c = math.cos(w);
  final a0 = 1 + alpha;
  final b0 = (high ? (1 + c) / 2 : (1 - c) / 2) / a0;
  final b1 = (high ? -(1 + c) : (1 - c)) / a0;
  final b2 = b0;
  final a1 = -2 * c / a0;
  final a2 = (1 - alpha) / a0;
  final y = Float32List(x.length);
  var x1 = 0.0;
  var x2 = 0.0;
  var y1 = 0.0;
  var y2 = 0.0;
  for (var i = 0; i < x.length; i++) {
    final v = b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1;
    x1 = x[i];
    y2 = y1;
    y1 = v;
    y[i] = v;
  }
  return y;
}
