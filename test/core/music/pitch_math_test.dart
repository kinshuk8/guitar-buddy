import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/music/music.dart';

void main() {
  const math = PitchMath();

  group('frequencies of the open strings (A4 = 440)', () {
    // Reference values from the equal-temperament table, to 2 decimals.
    const expected = {
      'E2': 82.41,
      'A2': 110.00,
      'D3': 146.83,
      'G3': 196.00,
      'B3': 246.94,
      'E4': 329.63,
    };
    expected.forEach((name, hz) {
      test(name, () => expect(math.hz(Note.parse(name)), closeTo(hz, 0.005)));
    });
  });

  test('hz and midiFloat are inverses', () {
    for (var midi = 28; midi <= 100; midi++) {
      expect(math.midiFloat(math.hz(Note(midi))), closeTo(midi, 1e-9));
    }
  });

  test('cents: octave = 1200, semitone = 100, sign = sharp positive', () {
    expect(PitchMath.cents(880, 440), closeTo(1200, 1e-9));
    expect(PitchMath.cents(440 * 1.0594630943592953, 440), closeTo(100, 1e-9));
    expect(PitchMath.cents(439, 440), lessThan(0));
    expect(PitchMath.cents(441, 440), closeTo(3.93, 0.01));
  });

  test('analyse finds nearest note and offset, including across the half-way point', () {
    final low = math.analyse(81.5);
    expect(low.note.name(), 'E2');
    expect(low.cents, closeTo(-19.2, 0.1));

    // 49 cents sharp of E2 is still E2; 51 cents sharp is F2 (-49).
    final e2 = math.hz(Note.parse('E2'));
    expect(math.analyse(e2 * 1.0287).note.name(), 'E2');
    expect(math.analyse(e2 * 1.0299).note.name(), 'F2');
  });

  test('reference pitch shifts every note proportionally', () {
    const baroque = PitchMath(a4: 415);
    expect(baroque.hz(Note.parse('A4')), 415);
    expect(baroque.analyse(415).cents, closeTo(0, 1e-9));
    // 440 Hz against A4=432 reads as A4, about 31.8 cents sharp.
    expect(const PitchMath(a4: 432).analyse(440).cents, closeTo(31.77, 0.01));
  });
}
