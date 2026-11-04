import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/features/chords/domain/chord_library.dart';

void main() {
  // The real bundled asset: these tests are the shipped data's validation.
  final library = ChordLibrary.fromJson(
    (jsonDecode(File('assets/chords/guitar.json').readAsStringSync()) as Map)
        .cast<String, Object?>(),
  );

  test('every bundled voicing plays exactly its chord', () {
    var count = 0;
    for (final e in library.entries) {
      expect(e.voicings, isNotEmpty, reason: e.symbol);
      for (final (i, v) in e.voicings.indexed) {
        final check = v.check(e.chord);
        expect(check.isValid, isTrue, reason: '${e.symbol} #${i + 1}: ${check.describe()}');
        count++;
      }
    }
    expect(count, greaterThan(3000));
  });

  test(
    'every voicing is playable: 6 strings, fits a 4-fret hand span, barres on fretted strings',
    () {
      for (final e in library.entries) {
        for (final v in e.voicings) {
          expect(v.frets.length, 6);
          final fretted = v.frets.whereType<int>().where((f) => f > 0);
          if (fretted.isNotEmpty) {
            final span =
                fretted.reduce((a, b) => a > b ? a : b) - fretted.reduce((a, b) => a < b ? a : b);
            expect(span, lessThanOrEqualTo(4), reason: e.symbol);
          }
          for (final b in v.barres) {
            expect(v.frets[b.lowString], b.fret, reason: '${e.symbol} barre start');
            expect(v.frets[b.highString], b.fret, reason: '${e.symbol} barre end');
          }
        }
      }
    },
  );

  test('the open chords a beginner needs are there, open shape first', () {
    const expected = {
      'C': [null, 3, 2, 0, 1, 0],
      'G': [3, 2, 0, 0, 0, 3],
      'D': [null, null, 0, 2, 3, 2],
      'A': [null, 0, 2, 2, 2, 0],
      'E': [0, 2, 2, 1, 0, 0],
      'Am': [null, 0, 2, 2, 1, 0],
      'Em': [0, 2, 2, 0, 0, 0],
      'Dm': [null, null, 0, 2, 3, 1],
    };
    for (final MapEntry(:key, :value) in expected.entries) {
      expect(library.bySymbol(key)!.voicings.first.frets, value, reason: key);
    }
  });

  test('twelve roots, C first, in guitar spelling', () {
    expect(library.roots, ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B']);
  });

  test('browse groups a root: essentials first, slash chords last', () {
    final groups = library.browse(PitchClass.c);
    expect(groups.keys.first, QualityGroup.essentials);
    expect(groups.keys.last, QualityGroup.slash);
    expect(groups[QualityGroup.essentials]!.map((e) => e.symbol).take(3), ['C', 'Cm', 'C7']);
    expect(groups[QualityGroup.slash]!.every((e) => e.isSlash), isTrue);
  });

  group('search', () {
    List<String> top(String q, [int n = 3]) =>
        library.search(q).take(n).map((e) => e.symbol).toList();

    test('exact symbols, any case for the root', () {
      expect(top('am7', 1), ['Am7']);
      expect(top('Bbmaj7', 1), ['Bbmaj7']);
      expect(top('f#', 1), ['F#']);
    });

    test('enharmonic spellings find the library chord', () {
      expect(top('Db', 1), ['C#']);
      expect(top('A#m', 1), ['Bbm']);
    });

    test('a partial suffix lists that family; m does not drift into maj', () {
      final am = library.search('Am').map((e) => e.symbol).toList();
      expect(am.first, 'Am');
      expect(am, containsAll(['Am7', 'Am6', 'Am9']));
      expect(am.indexOf('Amaj7'), anyOf(-1, greaterThan(am.indexOf('Am9'))));
    });

    test('slash chords and descriptions', () {
      expect(top('G/B', 1), ['G/B']);
      expect(library.search('minor 7th').first.chord.quality, ChordQuality.minor7);
    });

    test('nonsense finds nothing', () {
      expect(library.search('zzz'), isEmpty);
      expect(library.search('   '), isEmpty);
    });
  });
}
