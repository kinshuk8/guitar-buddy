import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/features/progressions/data/progression_pack.dart';

import '../../tool/chordonomicon/build_pack_lib.dart';

void main() {
  group('builder', () {
    test('tokens: min/s spellings, slash and extended chords dropped', () {
      expect(parseToken('Amin'), Chord.parse('Am'));
      expect(parseToken('Fs7'), Chord.parse('F#7'));
      expect(parseToken('Csmin7'), Chord.parse('C#m7'));
      expect(parseToken('A/Cs'), isNull);
      expect(parseToken('G13'), isNull, reason: 'not checkable by ear in v1');
    });

    test('sections, including songs with no section tags', () {
      String show(String s) => sections(s).map((x) => '${x.$1}: ${x.$2.join(' ')}').join(' | ');
      expect(show('<verse_1> C G <chorus_1> F'), 'verse: C G | chorus: F');
      expect(show('Amin C F'), 'song: Amin C F');
    });

    test('loops: repeated 3-4 chord cycles only', () {
      List<String>? loop(String s) => loopOf(s.split(' '))?.map((c) => c.symbol()).toList();
      expect(loop('G D Emin C G D Emin C G'), ['G', 'D', 'Em', 'C']);
      expect(loop('F C G F C G'), ['F', 'C', 'G']);
      expect(loop('G G D D C C G G D D C C'), ['G', 'D', 'C'], reason: 'held chords merged');
      expect(loop('G D Emin C'), isNull, reason: 'must repeat');
      expect(loop('C G Amin F C G F Amin'), isNull, reason: 'not a loop');
      expect(loop('G C G C G C'), isNull, reason: 'two-chord vamps are not kept');
    });

    test('one key-free name per progression, spelled the way musicians write it', () {
      final inG = loopOf('G D Emin C G D Emin C'.split(' '))!;
      final inA = loopOf('A E Fsmin D A E Fsmin D'.split(' '))!;
      expect(patternKey(inG), patternKey(inA));
      expect(patternKey(inG), 'C G Am F');
      expect(spellInKey([Chord.parse('C'), Chord.parse('A#'), Chord.parse('F')]), ['C', 'Bb', 'F']);
      expect(spellInKey([Chord.parse('Cm'), Chord.parse('G#')]), ['Cm', 'Ab']);
    });

    test('CSV lines with quoted fields', () {
      expect(parseCsvLine('1,"a, b",\'x\' \'y\',,z'), ['1', 'a, b', "'x' 'y'", '', 'z']);
    });
  });

  group('the shipped pack', () {
    final pack = ProgressionPack.openFile('assets/packs/chordonomicon/progressions.sqlite');

    test('has attribution and the CC BY-NC licence', () {
      expect(pack.info['licence'], contains('CC BY-NC 4.0'));
      expect(pack.info['citation'], contains('arXiv:2410.22046'));
      expect(pack.info['changes'], contains('no per-song data'));
    });

    test('every progression is a playable, checkable loop with aggregate stats only', () {
      expect(pack.items.length, greaterThan(100));
      for (final p in pack.items) {
        expect(p.chords.length, inInclusiveRange(3, 4), reason: p.symbols.join(' '));
        for (final c in p.chords) {
          expect(ChordQuality.detectable, contains(c.quality), reason: p.symbols.join(' '));
          expect(c.bass, isNull);
        }
        expect(p.songs, greaterThanOrEqualTo(25));
      }
      // Most used first.
      expect(pack.items.first.songs, greaterThanOrEqualTo(pack.items.last.songs));
    });

    test('carries no per-song columns', () {
      expect(pack.columns, isNot(contains('artist_id')));
      expect(pack.columns, isNot(contains('spotify_song_id')));
      expect(pack.columns, isNot(contains('release_date')));
    });
  });
}
