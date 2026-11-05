import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/features/chords/domain/chord_library.dart';
import 'package:fretlight/features/songs/domain/chordpro.dart';
import 'package:fretlight/features/songs/domain/song_timeline.dart';

void main() {
  group('ChordPro parser', () {
    test('metadata directives, long and short forms', () {
      final s = ChordProParser.parse('''
{t: My Song}
{st: A subtitle}
{artist: Someone}
{key: Am}
{tempo: 92}
{time: 3/4}
{capo: 2}
{meta: public_domain Written 1850}
''');
      expect(s.title, 'My Song');
      expect(s.subtitle, 'A subtitle');
      expect(s.artists, ['Someone']);
      expect(s.key, Chord.parse('Am'));
      expect((s.tempo, s.time, s.capo), (92, (3, 4), 2));
      expect(s.meta['public_domain'], ['Written 1850']);
      expect(s.warnings, isEmpty);
    });

    test('inline chords split the lyric at each chord', () {
      final s = ChordProParser.parse('[G]Amazing [G7]grace, how sweet the [C]sound');
      final segs = s.sections.single.lines.single.segments;
      expect(segs.map((x) => x.chordText), ['G', 'G7', 'C']);
      expect(segs.map((x) => x.text), ['Amazing ', 'grace, how sweet the ', 'sound']);
      expect(s.sections.single.lines.single.lyrics, 'Amazing grace, how sweet the sound');
    });

    test('a lyric before the first chord and a chord at the end of a line', () {
      final segs = ChordProParser.parse('A[G]mazing grace[D]')
          .sections
          .single
          .lines
          .single
          .segments;
      expect(segs.map((x) => (x.chordText, x.text)), [
        (null, 'A'),
        ('G', 'mazing grace'),
        ('D', ''),
      ]);
    });

    test('sections with labels, and {chorus} repeats the last chorus', () {
      final s = ChordProParser.parse('''
{start_of_verse: Verse 1}
[C]One
{end_of_verse}
{soc}
[F]Chorus line
{eoc}
{chorus}
''');
      expect(s.sections.map((x) => (x.kind, x.displayLabel, x.repeat)), [
        (SectionKind.verse, 'Verse 1', false),
        (SectionKind.chorus, 'Chorus', false),
        (SectionKind.chorus, 'Chorus', true),
      ]);
      expect(s.sections.last.lines.single.lyrics, 'Chorus line');
    });

    test('blank lines separate paragraphs outside environments', () {
      final s = ChordProParser.parse('[C]First\n[G]line\n\n[Am]Second');
      expect(s.sections, hasLength(2));
    });

    test('comments, N.C. and unknown things are kept or warned, never fatal', () {
      final s = ChordProParser.parse('''
# a file comment
{c: Slowly}
[N.C.]Spoken [Xyz]word
{new_page}
{x_custom: whatever}
''');
      final lines = s.sections.single.lines;
      expect(lines.first.comment, 'Slowly');
      expect(lines.last.segments.first.chordText, 'N.C.');
      expect(lines.last.segments.first.chord, isNull);
      expect(s.warnings, hasLength(2));
      expect(s.warnings.first, contains('Xyz'));
      expect(s.warnings.last, contains('new_page'));
    });

    test('Windows line endings and missing title', () {
      final s = ChordProParser.parse('[C]Hello\r\n[G]World\r\n');
      expect(s.title, 'Untitled');
      expect(s.sections.single.lines, hasLength(2));
    });
  });

  group('timeline', () {
    final song = ChordProParser.parse('''
{time: 3/4}
{sov}
[G]One [C]two
[D]Three
{eov}
{soc}
[G]Four
{eoc}
''');
    final t = SongTimeline.of(song);

    test('one bar per chord, in order', () {
      expect(t.events.map((e) => e.chordText), ['G', 'C', 'D', 'G']);
      expect(t.events.map((e) => e.startBeat), [0, 3, 6, 9]);
      expect(t.totalBeats, 12);
    });

    test('position lookup and section spans', () {
      expect(t.indexAt(0), 0);
      expect(t.indexAt(4.5), 1);
      expect(t.indexAt(100), 3);
      expect(t.sectionSpan(0), (0.0, 9.0));
      expect(t.sectionSpan(1), (9.0, 12.0));
    });

    test('next chord, wrapping inside a loop', () {
      expect(t.nextChord(1)!.chordText, 'D');
      expect(t.nextChord(3), isNull);
      expect(t.nextChord(2, loop: (0, 9))!.chordText, 'G', reason: 'back to the start of the loop');
    });
  });

  group('arrangement', () {
    test('capo changes shapes, not the sounding key', () {
      const a = Arrangement(capo: 2);
      expect(a.shape(Chord.parse('A')).symbol(), 'G');
      expect(a.soundingKey(Chord.parse('A'))!.symbol(), 'A');
    });

    test('transpose changes the sounding key and the shapes', () {
      const a = Arrangement(transpose: 2);
      expect(a.shape(Chord.parse('G')).symbol(), 'A');
      expect(a.soundingKey(Chord.parse('G'))!.symbol(), 'A');
    });

    test('spelling follows the key you finger in', () {
      // Song in G transposed to F: shapes spelled with flats (Bb, not A#).
      const a = Arrangement(transpose: -2);
      expect(a.display('C', Chord.parse('G')), 'Bb');
      expect(a.display('N.C.', Chord.parse('G')), 'N.C.');
    });
  });

  group('starter songs', () {
    final library = ChordLibrary.fromJson(
      (jsonDecode(File('assets/chords/guitar.json').readAsStringSync()) as Map)
          .cast<String, Object?>(),
    );
    final files = Directory('assets/songs').listSync().whereType<File>().toList();

    test('there are 10 to 15 of them', () {
      expect(files.length, inInclusiveRange(10, 15));
    });

    for (final f in files) {
      final name = f.uri.pathSegments.last;
      test('$name parses cleanly, is public domain, and every chord has a shape', () {
        final song = ChordProParser.parse(f.readAsStringSync());
        expect(song.warnings, isEmpty, reason: song.warnings.join('\n'));
        expect(song.title, isNot('Untitled'));
        expect(song.meta['public_domain'], isNotEmpty, reason: 'records its public-domain basis');
        expect(
          song.meta['source'],
          isNotEmpty,
          reason: 'names the pre-1929 publication its words follow',
        );
        expect(song.key, isNotNull);
        expect(song.tempo, isNotNull);
        for (final c in song.chords) {
          expect(library.byChord(c), isNotNull, reason: '${c.symbol()} in the chord library');
        }
        expect(SongTimeline.of(song).events, isNotEmpty);
      });
    }
  });
}
