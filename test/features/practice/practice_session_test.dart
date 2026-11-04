import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/features/identify/domain/chord_smoother.dart';
import 'package:fretlight/features/practice/domain/practice_session.dart';

Chord c(String s) => Chord.parse(s);

ChordReading heard(String chord, int strum, {double confidence = 0.9, bool fading = false}) =>
    ChordReading(chord: c(chord), confidence: confidence, strum: strum, fading: fading);

void main() {
  test('advances when the expected chord is played', () {
    final s = PracticeSession([c('G'), c('C'), c('D')]);
    expect(s.current, c('G'));
    expect(s.hear(heard('G', 1)), Verdict.hit);
    expect(s.current, c('C'));
    expect(s.hear(heard('C', 2)), Verdict.hit);
    expect(s.hear(heard('D', 3)), Verdict.hit);
    expect(s.done, isTrue);
    expect(s.firstTimeRate, 1);
    expect(s.trouble(), isEmpty);
  });

  test('one strum is judged once: a ringing G does not tick off two G bars', () {
    final s = PracticeSession([c('G'), c('G'), c('C')]);
    s
      ..hear(heard('G', 1))
      ..hear(heard('G', 1))
      ..hear(heard('G', 1));
    expect(s.index, 1, reason: 'still waiting for the second G');
    s.hear(heard('G', 2));
    expect(s.index, 2);
  });

  test('wrong chords count once per strum; the summary names the trouble', () {
    final s = PracticeSession([c('G'), c('Em'), c('C')])..hear(heard('G', 1));
    expect(s.hear(heard('G', 2)), Verdict.miss, reason: 'G when Em was asked');
    s.hear(heard('G', 2)); // the same strum still ringing
    expect(s.hear(heard('E', 3)), Verdict.miss, reason: 'major instead of minor');
    s
      ..hear(heard('Em', 4))
      ..skip();
    expect(s.done, isTrue);
    final trouble = s.trouble();
    expect(trouble.first.chord, c('C'), reason: 'skips weigh most');
    expect((trouble[1].chord, trouble[1].misses), (c('Em'), 2));
    expect(s.firstTimeRate, closeTo(1 / 3, 1e-9));
  });

  test('unsure, unsettled and fading readings are not held against you', () {
    final s = PracticeSession([c('Am')]);
    expect(
      s.hear(ChordReading(chord: c('Bb'), confidence: 1, strum: 1, settled: false)),
      isNull,
      reason: 'the attack frame of a strum',
    );
    expect(s.hear(heard('C', 1, confidence: 0.4)), isNull);
    expect(s.hear(heard('Am', 2, fading: true)), isNull);
    expect(s.hear(heard('Am', 3)), Verdict.hit);
  });

  test('judging: close enough vs a different chord', () {
    expect(PracticeSession.judge(c('G7'), c('G')), Verdict.close);
    expect(PracticeSession.judge(c('C'), c('Cmaj7')), Verdict.close);
    expect(PracticeSession.judge(c('Asus2'), c('A5')), Verdict.close);
    expect(PracticeSession.judge(c('G/B'), c('G')), Verdict.hit, reason: 'slash bass ignored');
    expect(PracticeSession.judge(c('A'), c('Am')), Verdict.miss);
    expect(PracticeSession.judge(c('G'), c('Em')), Verdict.miss);
    expect(PracticeSession.judge(c('C'), c('C#')), Verdict.miss);
  });
}
