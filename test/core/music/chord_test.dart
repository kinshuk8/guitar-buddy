import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/music/music.dart';

void main() {
  group('Chord.tryParse', () {
    final cases = {
      'C': 'C',
      'Am': 'Am',
      'Amin': 'Am', // Chordonomicon spelling
      'A-': 'Am',
      'F#m7': 'F#m7',
      'Bbmaj7': 'Bbmaj7',
      'CM7': 'Cmaj7',
      'CΔ7': 'Cmaj7',
      'Dsus': 'Dsus4',
      'Asus2': 'Asus2',
      'E5': 'E5',
      'Bm7b5': 'Bm7b5',
      'Bø': 'Bm7b5',
      'C6/9': 'C69',
      'G/B': 'G/B',
      'A/Cs': 'A/C#', // Chordonomicon sharp
      'D/D': 'D', // bass equal to root collapses
      'Ebm': 'Ebm',
      'Csus4': 'Csus4', // 's' of "sus" is not a sharp
      'Cs': 'C#',
      'Cs5': 'C#5',
      'Gadd9': 'Gadd9',
    };
    for (final MapEntry(key: input, value: symbol) in cases.entries) {
      test('$input -> $symbol', () => expect(Chord.parse(input).symbol(), symbol));
    }

    test('rejects nonsense', () {
      for (final bad in ['', 'N.C.', 'H7', 'Cxyz', 'C/Q', '%']) {
        expect(Chord.tryParse(bad), isNull, reason: bad);
      }
    });
  });

  test('pitch classes include formula and slash bass', () {
    expect(Chord.parse('C').pitchClasses.map((p) => p.value).toSet(), {0, 4, 7});
    expect(Chord.parse('Am7').pitchClasses.map((p) => p.value).toSet(), {9, 0, 4, 7});
    expect(Chord.parse('C/B').pitchClasses.map((p) => p.value).toSet(), {0, 4, 7, 11});
  });

  test('equality is structural', () {
    expect(Chord.parse('A#m'), Chord.parse('Bbm'));
    expect(Chord.parse('G/B').hashCode, Chord.parse('G/B').hashCode);
    expect(Chord.parse('G'), isNot(Chord.parse('G/B')));
  });
}
