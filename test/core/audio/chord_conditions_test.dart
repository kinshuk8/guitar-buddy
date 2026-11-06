import 'dart:convert';
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
import 'package:fretlight/features/chords/domain/chord_library.dart';
import 'package:fretlight/features/identify/domain/chord_smoother.dart';
import 'package:fretlight/features/learn/domain/curriculum.dart';
import 'package:fretlight/features/practice/domain/practice_session.dart';

const sr = 48000;
const pm = PitchMath();

final library = ChordLibrary.fromJson(
  (jsonDecode(File('assets/chords/guitar.json').readAsStringSync()) as Map).cast<String, Object?>(),
);

/// How a chord reaches the microphone.
final class Condition {
  const Condition(
    this.name, {
    this.gapMs = 22,
    this.up = false,
    this.gainDb = const [0, 0, 0, 0, 0, 0],
    this.jitterDb = 0,
    this.headset = false,
    this.snrDb,
    this.detuneCents = 0,
    this.extreme = false,
  });

  /// Harsher than real use: only "same chord give or take a note" is
  /// required there.
  final bool extreme;

  final String name;

  /// Time between strings as the pick crosses them.
  final int gapMs;
  final bool up;

  /// Per string, low E first: a close mic hears the bass strings louder.
  final List<double> gainDb;

  /// Random per-string level change (uneven picking, a half-muted string).
  final double jitterDb;

  /// A voice headset mic's band: high-pass ~150 Hz, low-pass ~7 kHz.
  final bool headset;
  final double? snrDb;
  final double detuneCents;
}

/// A mic at the soundhole: bass strings up to 9 dB louder than treble
/// (typical), and an extreme 18 dB.
const closeMic = <double>[5, 4, 2, 0, -2, -4];
const bassy = <double>[12, 9, 5, 0, -4, -6];

const conditions = [
  Condition('fast', gapMs: 12),
  Condition('normal'),
  Condition('slow', gapMs: 45),
  Condition('up-strum', gapMs: 15, up: true),
  Condition('headset', gapMs: 30, gainDb: closeMic, headset: true),
  Condition('headset slow', gapMs: 45, gainDb: closeMic, headset: true),
  Condition('very bassy', gapMs: 30, gainDb: bassy, headset: true, extreme: true),
  Condition('v.bassy slow', gapMs: 45, gainDb: bassy, headset: true, extreme: true),
  Condition('uneven', gapMs: 25, jitterDb: 5),
  Condition('far+noise', gapMs: 25, snrDb: 20, detuneCents: 8),
];

Float32List render(List<int?> frets, Condition c, int seed) {
  final rnd = math.Random(seed);
  final out = Float32List((2.2 * sr).round());
  final order = [
    for (var s = 0; s < 6; s++)
      if (frets[s] != null) s,
  ];
  final f = math.pow(2, c.detuneCents / 1200).toDouble();
  for (final (step, s) in (c.up ? order.reversed.toList() : order).indexed) {
    final one = List<double?>.filled(6, null)
      ..[s] = pm.hz(Tuning.standard.noteAt(s, frets[s]!)) * f;
    final pcm = renderStrum(stringHz: one, sampleRate: sr, seconds: 2.2, peak: 0.3);
    final db = c.gainDb[s] + (rnd.nextDouble() * 2 - 1) * c.jitterDb;
    final g = 2 * math.pow(10, db / 20);
    final at = step * c.gapMs * sr ~/ 1000;
    for (var i = 0; i + at < out.length && i < pcm.length; i++) {
      out[i + at] += g * pcm[i];
    }
  }
  var x = out;
  if (c.headset) x = _band(_band(x, 150, high: true), 7000, high: false);
  if (c.snrDb != null) x = TestSignals.withNoise(x, c.snrDb!, seed: seed);
  return x;
}

/// Settled names after the strum's first third (what a player reads).
List<Chord?> readings(Float32List pcm) {
  final det = ChromaChordDetector(sampleRate: sr);
  final tracker = ChordTracker(detector: det);
  final hop = tracker.hopSeconds(sr);
  final sm = ChordSmoother(
    hopSeconds: hop,
    floor: NoiseFloor(marginDb: 10, frameSeconds: hop),
  );
  final out = <Chord?>[];
  for (final e in tracker.push(Float32List.fromList([...Float32List(sr ~/ 2), ...pcm]))) {
    final r = sm.update(e);
    if (r != null && r.settled && !r.fading) out.add(r.chord);
  }
  return out.skip(out.length ~/ 3).toList();
}

/// Every chord the lessons teach (with their pinned shapes), plus common
/// ones from the library.
/// Chord specs the lessons ask for: these must be named reliably.
final Set<String> taught = {};

List<(String, List<int?>)> chordsToTest() {
  final out = <String, List<int?>>{};
  for (final l in allLessons) {
    for (final s in l.steps) {
      final specs = switch (s) {
        ChordSteps(:final chords) => chords,
        ChangeRace(:final a, :final b) => [a, b],
        RhythmSteps(:final chord) => [chord],
        _ => const <String>[],
      };
      for (final spec in specs) {
        final frets =
            chordFretsOf(spec) ??
            library.byChord(Chord.parse(chordSymbolOf(spec)))!.voicings.first.frets;
        out[spec] = frets;
        taught.add(spec);
      }
    }
  }
  for (final sym in [
    'E7',
    'A7',
    'D7',
    'B7',
    'C7',
    'Am7',
    'Em7',
    'Dm7',
    'Cmaj7',
    'Gmaj7',
    'Asus2',
    'Asus4',
    'Esus4',
    'F#m',
    'Bb',
  ]) {
    out.putIfAbsent(sym, () => library.bySymbol(sym)!.voicings.first.frets);
  }
  return [for (final e in out.entries) (e.key, e.value)];
}

void main() {
  test('every chord taught is named right under real-world playing and mic conditions', () {
    final rows = chordsToTest();
    final buf = StringBuffer('\n== Chords under real-world conditions ==\n')
      ..writeln(
        'Share of settled readings (after the first third of the ring) naming the chord exactly;',
      )
      ..writeln(
        '[c] = the rest were the same chord give or take a note (E5 for Em: practice counts these).\n',
      )
      ..write('chord           ')
      ..writeln(conditions.map((c) => c.name.padLeft(13)).join());
    final worst = <String, double>{};
    final failures = <String>[];
    final broken = <String>[];
    for (final (spec, frets) in rows) {
      final target = Chord.parse(chordSymbolOf(spec));
      buf.write(spec.padRight(16));
      for (final (ci, c) in conditions.indexed) {
        final names = readings(render(frets, c, ci * 31 + spec.hashCode));
        final exact = names.isEmpty
            ? 0.0
            : names.where((n) => n != null && _same(n, target)).length / names.length;
        final close = names.isEmpty
            ? 0.0
            : names
                      .where((n) => n != null && PracticeSession.judge(target, n) != Verdict.miss)
                      .length /
                  names.length;
        final wrong = <String, int>{};
        for (final n in names) {
          if (n == null || _same(n, target)) continue;
          wrong.update(n.symbol(), (v) => v + 1, ifAbsent: () => 1);
        }
        final top = wrong.entries.fold<MapEntry<String, int>?>(
          null,
          (b, e) => b == null || e.value > b.value ? e : b,
        );
        final cell =
            '${(exact * 100).round()}%${close > exact + 0.05 ? 'c' : ''}${exact < 0.9 && top != null ? ' ${top.key}' : ''}';
        buf.write(cell.padLeft(13));
        worst[c.name] = math.min(worst[c.name] ?? 1, exact);
        if (exact < 0.9) {
          failures.add('$spec/${c.name}: ${(exact * 100).round()}% (${top?.key ?? 'unsure'})');
        }
        if (taught.contains(spec)) {
          // Realistic conditions: the exact name. An extreme mic: at least
          // the same chord give or take a note (what practice accepts).
          final ok = c.extreme ? close : exact;
          if (ok < 0.9) {
            broken.add('$spec/${c.name}: ${(ok * 100).round()}% (${top?.key ?? 'unsure'})');
          }
        }
      }
      buf.writeln();
    }
    buf
      ..writeln(
        '\n${rows.length} chords × ${conditions.length} conditions; under 90%: ${failures.length}',
      )
      ..writeln(failures.join('\n'));
    // Printed on purpose: the real-world accuracy report.
    // ignore: avoid_print
    print(buf);
    expect(broken, isEmpty, reason: 'chords the lessons teach must be named reliably');
  });
}

bool _same(Chord a, Chord b) => a.root == b.root && a.quality == b.quality;

/// A 2nd-order (RBJ) high- or low-pass, Q 0.707.
Float32List _band(Float32List x, double hz, {required bool high}) {
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
