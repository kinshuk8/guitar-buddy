import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/music/music.dart';

void main() {
  group('PitchClass', () {
    test('normalises into 0..11, including negatives', () {
      expect(PitchClass(12).value, 0);
      expect(PitchClass(-1).value, 11);
      expect(PitchClass(25).value, 1);
    });

    test('parses names with ASCII, unicode and Chordonomicon accidentals', () {
      expect(PitchClass.tryParse('C')?.value, 0);
      expect(PitchClass.tryParse('F#')?.value, 6);
      expect(PitchClass.tryParse('Bb')?.value, 10);
      expect(PitchClass.tryParse('E♭')?.value, 3);
      expect(PitchClass.tryParse('G♯')?.value, 8);
      expect(PitchClass.tryParse('Cs')?.value, 1);
      expect(PitchClass.tryParse('B#')?.value, 0);
      expect(PitchClass.tryParse('Cb')?.value, 11);
      expect(PitchClass.tryParse('Dbb')?.value, 0);
    });

    test('rejects non-notes', () {
      for (final bad in ['', 'H', 'X#', 'C#m', 'c4']) {
        expect(PitchClass.tryParse(bad), isNull, reason: bad);
      }
    });

    test('spells sharps and flats', () {
      expect(PitchClass(10).name(), 'A#');
      expect(PitchClass(10).name(Spelling.flats), 'Bb');
    });

    test('interval is ascending and wraps', () {
      expect(PitchClass(9).intervalTo(PitchClass(0)), 3); // A up to C
      expect(PitchClass(0).intervalTo(PitchClass(9)), 9);
    });
  });

  group('Spelling', () {
    test('chart roots: C C# D Eb E F F# G Ab A Bb B', () {
      final names = [
        for (var i = 0; i < 12; i++) PitchClass(i).name(Spelling.forRoot(PitchClass(i))),
      ];
      expect(names, ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B']);
    });

    test('keys follow the key signature', () {
      expect(Spelling.forKey(PitchClass(5)), Spelling.flats); // F
      expect(Spelling.forKey(PitchClass(11)), Spelling.sharps); // B
      expect(Spelling.forKey(PitchClass(2), minor: true), Spelling.flats); // Dm ~ F
      expect(Spelling.forKey(PitchClass(4), minor: true), Spelling.sharps); // Em ~ G
    });
  });

  group('Note', () {
    test('scientific pitch notation round-trips', () {
      expect(Note.parse('A4').midi, 69);
      expect(Note.parse('C4').midi, 60);
      expect(Note.parse('E2').midi, 40);
      expect(Note.parse('C-1').midi, 0);
      expect(const Note(40).name(), 'E2');
      expect(const Note(70).name(Spelling.flats), 'Bb4');
    });

    test('enharmonics across the octave boundary keep the right octave', () {
      expect(Note.parse('Cb4').midi, Note.parse('B3').midi);
      expect(Note.parse('B#3').midi, Note.parse('C4').midi);
    });

    test('rejects malformed input', () {
      expect(Note.tryParse('E'), isNull);
      expect(Note.tryParse('E2x'), isNull);
      expect(() => Note.parse('Q3'), throwsFormatException);
    });
  });
}
