import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/music/music.dart';

void main() {
  test('transposes chords, including slash bass', () {
    expect(Transposer.transposeSymbol('G', 2), 'A');
    expect(Transposer.transposeSymbol('Am7', 3), 'Cm7');
    expect(Transposer.transposeSymbol('G/B', 2), 'A/C#');
    expect(Transposer.transposeSymbol('B', 1), 'C');
    expect(Transposer.transposeSymbol('C', -1), 'B');
    expect(Transposer.transposeSymbol('C', 12), 'C');
  });

  test('spelling follows the target key when asked', () {
    final inF = Spelling.forKey(PitchClass.tryParse('F')!);
    expect(Transposer.transposeSymbol('A', 1, spelling: inF), 'Bb');
    final inB = Spelling.forKey(PitchClass.tryParse('B')!);
    expect(Transposer.transposeSymbol('A', 1, spelling: inB), 'A#');
  });

  test('leaves non-chords untouched', () {
    for (final text in ['N.C.', '%', 'x', '']) {
      expect(Transposer.transposeSymbol(text, 5), text);
    }
  });

  test('capo: shapes move down, sound moves up', () {
    final bb = Chord.parse('Bb');
    expect(Transposer.shapeForCapo(bb, 1).symbol(), 'A');
    expect(Transposer.shapeForCapo(bb, 3).symbol(), 'G');
    expect(Transposer.soundingFromShape(Chord.parse('G'), 3).symbol(), 'Bb');
    // Round trip.
    for (var capo = 0; capo < 12; capo++) {
      expect(Transposer.soundingFromShape(Transposer.shapeForCapo(bb, capo), capo), bb);
    }
  });

  test('suggestCapo finds open shapes for a flat-key song', () {
    // Eb Ab Bb Cm with capo 3 -> C F G Am; F is not open, but capo 1 gives
    // D G A Bm (3 open) and capo 3 gives 3 open too; lowest fret wins.
    final song = ['Eb', 'Ab', 'Bb', 'Cm'].map(Chord.parse);
    expect(Transposer.suggestCapo(song), 1);
    // Bb F Gm Eb -> capo 3 -> G D Em C, all open.
    expect(Transposer.suggestCapo(['Bb', 'F', 'Gm', 'Eb'].map(Chord.parse)), 3);
    expect(Transposer.suggestCapo(['G', 'C', 'D'].map(Chord.parse)), 0);
  });
}
