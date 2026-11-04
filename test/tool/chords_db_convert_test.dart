import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/music/music.dart';

import '../../tool/chords_db/convert_lib.dart';

Map<String, Object?> pos(
  List<int> frets,
  List<int> fingers,
  int baseFret,
  List<int> midi, {
  List<int> barres = const [],
}) => {'frets': frets, 'fingers': fingers, 'baseFret': baseFret, 'barres': barres, 'midi': midi};

Map<String, Object?> db(Map<String, List<Map<String, Object?>>> chords) => {
  'main': {'strings': 6, 'fretsOnChord': 4},
  'tunings': {
    'standard': ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
  },
  'chords': chords,
};

void main() {
  test('suffixes: plain, slash, and minor-slash', () {
    expect(parseSuffix('m7b5')!.quality, ChordQuality.halfDim7);
    expect(parseSuffix('/E')!.bass, PitchClass.tryParse('E'));
    final mSlash = parseSuffix('m/B')!;
    expect((mSlash.quality, mSlash.bass), (ChordQuality.minor, PitchClass.tryParse('B')));
    expect(parseSuffix('m9/Bb')!.quality, ChordQuality.minor9);
    expect(parseSuffix('nonsense'), isNull);
    expect(parseKey('Fsharp'), PitchClass.tryParse('F#'));
  });

  test('relative frets become absolute; barre span comes from the fingers', () {
    // chords-db's C major barre at the 3rd fret: x 1 3 3 3 1, baseFret 3.
    final r = convertPosition(
      pos([-1, 1, 3, 3, 3, 1], [0, 1, 2, 3, 4, 1], 3, [48, 55, 60, 64, 67], barres: [1]),
    );
    expect(r.problem, isNull);
    final v = r.voicing!;
    expect(v.frets, [null, 3, 5, 5, 5, 3]);
    expect(v.barres.single.fret, 3);
    expect((v.barres.single.lowString, v.barres.single.highString), (1, 5));
    expect(v.fingers, [null, 1, 2, 3, 4, 1]);
  });

  test('a fret/MIDI disagreement is rejected', () {
    final r = convertPosition(
      pos([-1, 3, 2, 0, 1, 0], [0, 3, 2, 0, 1, 0], 1, [48, 52, 55, 60, 65]),
    );
    expect(r.voicing, isNull);
    expect(r.problem, contains('MIDI'));
  });

  test('an open string under a barre is rejected', () {
    // Barre at fret 2 across strings 1–5 with the G string open.
    final r = convertPosition(
      pos([-1, 2, 2, 0, 2, 2], [0, 1, 1, 0, 1, 1], 1, [47, 52, 55, 61, 66], barres: [2]),
    );
    expect(r.problem, contains('below the barre'));
  });

  test('wrong notes are reported, duplicates merged, sus becomes sus4', () {
    final result = convert(
      db({
        'C': [
          {
            'key': 'C',
            'suffix': 'major',
            'positions': [
              pos([-1, 3, 2, 0, 1, 0], [0, 3, 2, 0, 1, 0], 1, [48, 52, 55, 60, 64]),
              // Labelled C but plays C Eb G: wrong third.
              pos([-1, 3, 1, 0, 1, -1], [0, 3, 1, 0, 2, 0], 1, [48, 51, 55, 60]),
            ],
          },
          {
            'key': 'C',
            'suffix': 'sus',
            'positions': [
              pos([-1, 3, 3, 0, 1, 1], [0, 3, 4, 0, 1, 1], 1, [48, 53, 55, 60, 65]),
            ],
          },
          {
            'key': 'C',
            'suffix': 'sus4',
            'positions': [
              pos([-1, 3, 3, 0, 1, 1], [0, 3, 4, 0, 1, 1], 1, [48, 53, 55, 60, 65]),
            ],
          },
        ],
      }),
    );
    expect(result.sourcePositions, 4);
    expect(result.keptVoicings, 2);
    expect(result.mergedDuplicates, 1);
    expect(result.issues.single.message, contains('missing E'));
    expect(result.chords.map((c) => c.symbol), ['C', 'Csus4']);
  });
}
