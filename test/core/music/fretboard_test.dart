import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/music/music.dart';

void main() {
  group('Tuning', () {
    test('presets have six strings, lowest first', () {
      for (final t in Tuning.presets) {
        expect(t.stringCount, 6, reason: t.name);
        for (var i = 1; i < 6; i++) {
          expect(t.strings[i].midi, greaterThan(t.strings[i - 1].midi), reason: t.name);
        }
      }
      expect(Tuning.dropD.strings.first.name(), 'D2');
      expect(Tuning.halfStepDown.strings.first.name(Spelling.flats), 'Eb2');
    });

    test('nearestString picks the closest open string', () {
      final t = Tuning.standard;
      expect(t.nearestString(40), 0); // E2
      expect(t.nearestString(39.3), 0); // E2, flat
      expect(t.nearestString(44.6), 1); // A2, flat
      expect(t.nearestString(59.4), 4); // B3, sharp
      expect(t.nearestString(64), 5); // E4
    });

    test('positionsOf finds every place to play a note', () {
      final positions = Tuning.standard.positionsOf(Note.parse('E4'), maxFret: 24);
      expect(positions, [
        const FretPosition(0, 24),
        const FretPosition(1, 19),
        const FretPosition(2, 14),
        const FretPosition(3, 9),
        const FretPosition(4, 5),
        const FretPosition(5, 0),
      ]);
      expect(Tuning.standard.positionsOf(Note.parse('E2')), [const FretPosition(0, 0)]);
      expect(Tuning.standard.positionsOf(Note.parse('D2')), isEmpty);
    });
  });

  group('Voicing', () {
    Voicing v(List<int?> frets) => Voicing(frets: frets);

    test('open C plays C E G C E', () {
      final c = v([null, 3, 2, 0, 1, 0]);
      expect(c.notes.map((n) => n.name()).toList(), ['C3', 'E3', 'G3', 'C4', 'E4']);
      expect(c.bass?.name(), 'C3');
      expect(c.baseFret, 1);
    });

    test('baseFret is 1 for open shapes and the lowest fret for higher shapes', () {
      expect(v([null, 0, 2, 2, 2, 0]).baseFret, 1);
      expect(v([null, 3, 5, 5, 5, 3]).baseFret, 3); // C barre at 3
      expect(v([8, 10, 10, 9, 8, 8]).baseFret, 8);
    });

    test('alternate tunings change the notes', () {
      final open = Voicing(frets: const [0, 0, 0, 0, 0, 0], tuning: Tuning.openG);
      expect(ChordNamer.name(open.pitchClasses, bass: open.bass?.pitchClass)?.symbol(), 'G/D');
    });
  });

  group('Voicing.check (chord-data validation)', () {
    Voicing v(List<int?> frets) => Voicing(frets: frets);

    test('accepts correct open chords', () {
      final shapes = {
        'C': [null, 3, 2, 0, 1, 0],
        'A': [null, 0, 2, 2, 2, 0],
        'G': [3, 2, 0, 0, 0, 3],
        'E': [0, 2, 2, 1, 0, 0],
        'D': [null, null, 0, 2, 3, 2],
        'Am': [null, 0, 2, 2, 1, 0],
        'Em': [0, 2, 2, 0, 0, 0],
        'Dm': [null, null, 0, 2, 3, 1],
        'G7': [3, 2, 0, 0, 0, 1],
        'Cmaj7': [null, 3, 2, 0, 0, 0],
        'E5': [0, 2, null, null, null, null],
        'G/B': [null, 2, 0, 0, 0, 3],
      };
      for (final MapEntry(key: symbol, value: frets) in shapes.entries) {
        final result = v(frets).check(Chord.parse(symbol));
        expect(result.isValid, isTrue, reason: '$symbol: ${result.describe()}');
      }
    });

    test('reports a real chords-db error: C#aug shape that plays C# F# B', () {
      // chords-db C#aug: frets [-1,4,4,4,2,2] at baseFret 1.
      final result = v([null, 4, 4, 4, 2, 2]).check(Chord.parse('C#aug'));
      expect(result.isValid, isFalse);
      expect(result.missing.map((p) => p.name()), containsAll(['F', 'A']));
      expect(result.foreign.map((p) => p.name()), containsAll(['F#', 'B']));
    });

    test('reports a missing third and a wrong slash bass', () {
      expect(v([0, 2, 2, null, null, null]).check(Chord.parse('E')).describe(), 'missing G#');
      expect(v([null, 3, 2, 0, 1, 0]).check(Chord.parse('C/E')).wrongBass, isTrue);
    });
  });
}
