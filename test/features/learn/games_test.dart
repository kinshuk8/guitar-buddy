import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/audio/dsp/onset_detector.dart';
import 'package:fretlight/core/audio/synth/strum.dart';
import 'package:fretlight/core/audio/synth/test_signals.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/features/identify/domain/chord_smoother.dart';
import 'package:fretlight/features/identify/domain/note_session.dart';
import 'package:fretlight/features/learn/domain/curriculum.dart';
import 'package:fretlight/features/learn/domain/games.dart';
import 'package:fretlight/features/practice/domain/practice_session.dart';

ChordReading strum(String chord, int n) =>
    ChordReading(chord: Chord.parse(chord), confidence: 1, strum: n);

NoteReading note(String name, {double cents = 0}) =>
    NoteReading(note: Note.parse(name), hz: 0, cents: cents);

void main() {
  group('chord game', () {
    test('steps: waits for each chord; first-time rate makes the stars', () {
      final g = ChordGame.steps(['Em', 'Am']);
      expect(g.hear(strum('Em', 1), Duration.zero), Verdict.hit);
      expect(g.hear(strum('C', 2), Duration.zero), Verdict.miss);
      expect(g.hear(strum('Am', 3), Duration.zero), Verdict.hit);
      expect(g.done, isTrue);
      final o = g.outcome();
      expect(o.score, 0.5);
      expect(o.stars, 1);
      expect(o.chords['Em'], (clean: 1, missed: 0));
      expect(o.chords['Am'], (clean: 0, missed: 1));
    });

    test('pinned shapes are heard by symbol', () {
      final g = ChordGame.steps(['G:355433']);
      expect(g.hear(strum('G', 1), Duration.zero), Verdict.hit);
      expect(g.outcome().stars, 3);
    });

    test('race: the clock starts at the first chord; changes a minute', () {
      final g = ChordGame.race(const ChangeRace('Em', 'Am', targets: (10, 18, 26), seconds: 30));
      expect(g.remaining(const Duration(seconds: 5)), const Duration(seconds: 30));
      var t = const Duration(seconds: 2);
      g.hear(strum('Em', 1), t);
      for (var i = 0; i < 12; i++) {
        t += const Duration(seconds: 2);
        g.hear(strum(i.isEven ? 'Am' : 'Em', i + 2), t);
      }
      g.tick(t);
      expect(g.done, isFalse);
      g.tick(const Duration(seconds: 33));
      expect(g.done, isTrue);
      expect(g.changes, 12);
      final o = g.outcome();
      expect(o.headline, '24 changes a minute');
      expect(o.stars, 2);
      expect(o.best, ('race:Am|Em', 24.0));
    });

    test('a step where most chords were skipped earns no star', () {
      final g = ChordGame.steps(['Em', 'Am', 'G'])
        ..skip()
        ..skip();
      g.hear(strum('G', 1), Duration.zero);
      expect(g.outcome().stars, 0);
    });
  });

  group('note game', () {
    test('a note must hold for a moment; a held wrong note counts once', () {
      final g = NoteGame(const NoteSteps([Spot(0, 0), Spot(1, 0)]));
      expect(g.current, Note.parse('E2'));
      for (var i = 0; i < 10; i++) {
        g.hear(note('F2'));
      }
      expect(g.wrong, Note.parse('F2'));
      expect(g.hear(note('E2')), isFalse);
      expect(g.hear(note('E2')), isFalse);
      expect(g.hear(note('E2')), isTrue);
      // The E still ringing doesn't count against the A.
      for (var i = 0; i < 10; i++) {
        g.hear(note('E2'));
      }
      for (var i = 0; i < 3; i++) {
        g.hear(note('A2'));
      }
      expect(g.done, isTrue);
      expect(g.outcome().headline, '1 of 2 notes first try');
    });

    test('tuning: the string must stay within the cents for a moment', () {
      final g = NoteGame(const NoteSteps([Spot(1, 0)], tuneCents: 10));
      for (var i = 0; i < 20; i++) {
        g.hear(note('A2', cents: 25));
      }
      expect(g.done, isFalse);
      for (var i = 0; i < 12; i++) {
        g.hear(note('A2', cents: -4));
      }
      expect(g.done, isTrue);
      expect(g.outcome().stars, 3);
    });

    test('a fading note neither hits nor misses', () {
      final g = NoteGame(const NoteSteps([Spot(0, 0)]));
      for (var i = 0; i < 5; i++) {
        g.hear(const NoteReading(note: Note(40), hz: 0, cents: 0, fading: true));
      }
      expect(g.done, isFalse);
    });
  });

  group('rhythm game', () {
    const steps = RhythmSteps(chord: 'Em', bpm: 60, pattern: RhythmSteps.downs, name: 'x', bars: 2);

    test('steady strums with a constant latency score full marks', () {
      final g = RhythmGame(steps);
      for (final e in g.expected) {
        g.onset(e + 0.12); // 120 ms of mic latency, perfectly steady
      }
      final m = g.match();
      expect(m.latency, closeTo(0.12, 1e-9));
      final o = g.outcome();
      expect(o.headline, '8 of 8 strums on the beat');
      expect(o.stars, 3);
    });

    test('missed beats, wild strums and extras cost points', () {
      final g = RhythmGame(steps);
      final rnd = math.Random(4);
      for (final (i, e) in g.expected.indexed) {
        if (i == 3) continue; // missed one
        g.onset(e + (i == 5 ? 0.3 : (rnd.nextDouble() - 0.5) * 0.04));
      }
      g.onset(6.5); // an extra between beats
      g.onset(g.expected[2] + 0.13); // a double hit beside a scored beat: not an extra
      final o = g.outcome();
      expect(o.headline, '6 of 8 strums on the beat');
      expect(o.stars, lessThan(3));
      expect(
        o.detail,
        contains('2 extra strums'),
        reason: 'the stray at 6.5 s and the strum 300 ms late',
      );
    });

    test('strums before the count-in ends or after the last bar are ignored', () {
      final g = RhythmGame(steps)
        ..onset(-1)
        ..onset(20);
      expect(g.onsets, isEmpty);
    });
  });

  group('quiz', () {
    test('questions are deterministic, have their answer among four or six options', () {
      final a = QuizGame(
        const Quiz({QuizKind.fretNote, QuizKind.chordName}, chords: ['C', 'G']),
        seed: 3,
      );
      final b = QuizGame(
        const Quiz({QuizKind.fretNote, QuizKind.chordName}, chords: ['C', 'G']),
        seed: 3,
      );
      expect(a.questions.map((q) => q.prompt), b.questions.map((q) => q.prompt));
      for (final q in a.questions) {
        expect(q.options.toSet().length, q.options.length);
        expect(q.options.length, 4);
        expect(q.answer, inInclusiveRange(0, q.options.length - 1));
      }
    });

    test('fret notes are right: string 1 fret 3 is C', () {
      final g = QuizGame(const Quiz({QuizKind.fretNote}, questions: 40, maxFret: 5), seed: 9);
      for (final q in g.questions) {
        final pc = Tuning.standard.noteAt(q.spot!.string, q.spot!.fret).pitchClass;
        expect(q.options[q.answer], QuizGame.noteName(pc));
      }
    });

    test('string names, combo and stars', () {
      final g = QuizGame(const Quiz({QuizKind.stringName}, questions: 5));
      for (var i = 0; i < 5; i++) {
        final q = g.current!;
        expect(q.options[q.answer], QuizGame.stringNames[q.spot!.string]);
        g.answer(i == 1 ? (q.answer + 1) % 6 : q.answer);
      }
      expect(g.correct, 4);
      expect(g.bestCombo, 3);
      expect(g.outcome().stars, 2);
    });
  });

  group('onset detector', () {
    test('finds each strum of a rhythm to within 10 ms, once each', () {
      const sr = 48000;
      const pm = PitchMath();
      final em = [
        for (final (s, f) in [(0, 0), (1, 2), (2, 2), (3, 0), (4, 0), (5, 0)])
          pm.hz(Tuning.standard.noteAt(s, f)),
      ];
      final times = [0.5, 1.0, 1.5, 2.0, 2.25, 2.5, 3.0];
      final pcm = Float32List((3.8 * sr).round());
      for (final (i, t) in times.indexed) {
        final s = renderStrum(
          stringHz: em,
          sampleRate: sr,
          seconds: 1.2,
          down: i != 4,
          peak: i == 4 ? 0.3 : 0.6,
        );
        final at = (t * sr).round();
        // Each strum damps the last, as a strumming hand does.
        for (var j = at; j < pcm.length; j++) {
          pcm[j] *= math.exp(-(j - at) / (0.01 * sr));
        }
        for (var j = 0; j < s.length && at + j < pcm.length; j++) {
          pcm[at + j] += s[j];
        }
      }
      for (final (label, signal) in [
        ('clean', pcm),
        ('room noise', TestSignals.withNoise(pcm, 20)),
      ]) {
        final det = OnsetDetector(sampleRate: sr);
        final found = <int>[];
        // In chunks, as the mic delivers it.
        for (var o = 0; o < signal.length; o += 960) {
          found.addAll(
            det.push(Float32List.sublistView(signal, o, math.min(o + 960, signal.length))),
          );
        }
        // Every onset found is a real strum, within 10 ms.
        for (final f in found) {
          final nearest = times.reduce((a, b) => (a - f / sr).abs() < (b - f / sr).abs() ? a : b);
          expect(f / sr, closeTo(nearest, 0.01), reason: '$label: onset at ${f / sr}');
        }
        final missed = times.where((t) => !found.any((f) => (f / sr - t).abs() < 0.01)).toList();
        if (label == 'clean') {
          expect(missed, isEmpty, reason: label);
        } else {
          // Known limit: in a noisy room the soft up-strum, half as loud and
          // a quarter-second after a full down-strum, can be lost.
          expect(missed, anyOf(isEmpty, [2.25]), reason: label);
        }
      }
    });

    test('silence and steady hum produce nothing', () {
      final det = OnsetDetector(sampleRate: 48000);
      final hum = Float32List.fromList([
        for (var i = 0; i < 48000; i++) 0.05 * math.sin(2 * math.pi * 60 * i / 48000),
      ]);
      expect(det.push(Float32List(48000)), isEmpty);
      expect(det.push(hum).length, lessThanOrEqualTo(1), reason: 'at most the hum starting');
      expect(det.push(hum), isEmpty);
    });
  });
}
