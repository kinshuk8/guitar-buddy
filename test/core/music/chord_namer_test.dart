import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/music/music.dart';

Set<PitchClass> pcs(String names) => {for (final n in names.split(' ')) PitchClass.tryParse(n)!};
PitchClass pc(String name) => PitchClass.tryParse(name)!;

void main() {
  group('names common chords from their notes', () {
    final cases = {
      ('C E G', 'C'): 'C',
      ('A C E', 'A'): 'Am',
      ('G B D F', 'G'): 'G7',
      ('C E G B', 'C'): 'Cmaj7',
      ('D F A C', 'D'): 'Dm7',
      ('D E A', 'D'): 'Dsus2',
      ('D G A', 'D'): 'Dsus4',
      ('E B', 'E'): 'E5',
      ('B D F A', 'B'): 'Bm7b5',
      ('C E', 'C'): 'C', // fifth omitted
    };
    for (final MapEntry(key: input, value: expected) in cases.entries) {
      final (notes, bass) = input;
      test('$notes (bass $bass) -> $expected', () {
        expect(ChordNamer.name(pcs(notes), bass: pc(bass))?.symbol(), expected);
      });
    }
  });

  test('the bass note disambiguates identical pitch-class sets', () {
    final set = pcs('C E G A');
    expect(ChordNamer.name(set, bass: pc('C'))?.symbol(), 'C6');
    expect(ChordNamer.name(set, bass: pc('A'))?.symbol(), 'Am7');
  });

  test('sus2 and sus4 on related roots resolve by bass', () {
    // D E A: Dsus2 with D bass, Asus4 with A bass.
    expect(ChordNamer.name(pcs('D E A'), bass: pc('A'))?.symbol(), 'Asus4');
  });

  test('inversions are named as slash chords', () {
    expect(ChordNamer.name(pcs('G B D'), bass: pc('B'))?.symbol(), 'G/B');
    expect(ChordNamer.name(pcs('C E G'), bass: pc('G'))?.symbol(), 'C/G');
  });

  test('a non-chord bass becomes an added-bass slash chord', () {
    expect(ChordNamer.name(pcs('C E G B'), bass: pc('B'))?.symbol(), 'Cmaj7/B');
    expect(ChordNamer.name(pcs('A C E G'), bass: pc('G'))?.symbol(), 'Am7/G');
  });

  test('returns nothing for a single note or a cluster', () {
    expect(ChordNamer.name(pcs('C')), isNull);
    expect(ChordNamer.name(pcs('C C# D')), isNull);
  });

  test('can restrict to detectable qualities', () {
    final list = ChordNamer.candidates(
      pcs('C E G A'),
      bass: pc('C'),
      qualities: ChordQuality.detectable,
    );
    // C6 is not detectable in v1; the best detectable reading is Am7/C.
    expect(list.first.chord.symbol(), 'Am7/C');
  });

  test('every detectable chord on every root names itself back', () {
    for (var root = 0; root < 12; root++) {
      for (final q in ChordQuality.detectable) {
        final chord = Chord(PitchClass(root), q);
        final named = ChordNamer.name(chord.pitchClasses, bass: chord.root);
        expect(named, chord, reason: chord.symbol());
      }
    }
  });
}
