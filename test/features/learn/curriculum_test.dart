import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/features/chords/domain/chord_library.dart';
import 'package:fretlight/features/learn/domain/curriculum.dart';
import 'package:fretlight/features/songs/application/songs_controller.dart';

void main() {
  final library = ChordLibrary.fromJson(
    (jsonDecode(File('assets/chords/guitar.json').readAsStringSync()) as Map)
        .cast<String, Object?>(),
  );

  test('four stages, Beginner to Mastery, every lesson id unique', () {
    expect(curriculum.map((s) => s.title), ['Beginner', 'Improver', 'Adept', 'Mastery']);
    final ids = allLessons.map((l) => l.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(allLessons.length, greaterThan(40));
    expect(lessonById('b.em')!.title, 'E minor');
  });

  test('every skill is taught in every stage but the last at least once', () {
    for (final stage in curriculum.take(3)) {
      final skills = stage.lessons.map((l) => l.skill).toSet();
      expect(
        skills,
        containsAll([Skill.chords, Skill.changes, Skill.rhythm, Skill.songs]),
        reason: stage.title,
      );
    }
  });

  test('every chord a lesson asks for is in the library; pinned shapes play that chord', () {
    for (final lesson in allLessons) {
      final specs = [
        for (final s in lesson.steps)
          ...switch (s) {
            ChordSteps(:final chords) => chords,
            ChangeRace(:final a, :final b) => [a, b],
            RhythmSteps(:final chord) => [chord],
            Quiz(:final chords) => chords,
            _ => const <String>[],
          },
      ];
      for (final spec in specs) {
        final chord = Chord.parse(chordSymbolOf(spec));
        expect(library.byChord(chord), isNotNull, reason: '${lesson.id}: $spec');
        final frets = chordFretsOf(spec);
        if (spec.contains(':')) {
          expect(frets, isNotNull, reason: spec);
          expect(
            Voicing(frets: frets!).check(chord).isValid,
            isTrue,
            reason: '${lesson.id}: $spec',
          );
        }
      }
    }
  });

  test('song lessons use bundled songs', () {
    for (final l in allLessons) {
      for (final s in l.steps.whereType<SongSteps>()) {
        expect(bundledSongIds, contains(s.songId), reason: l.id);
      }
    }
  });

  test('note spots are on the neck; strum patterns fit their bar', () {
    for (final l in allLessons) {
      for (final s in l.steps) {
        if (s is NoteSteps) {
          for (final p in s.spots) {
            expect(p.string, inInclusiveRange(0, 5), reason: l.id);
            expect(p.fret, inInclusiveRange(0, 12), reason: l.id);
          }
        }
        if (s is RhythmSteps) {
          for (final st in s.pattern) {
            expect(st.beat, lessThan(s.beatsPerBar), reason: l.id);
          }
        }
      }
    }
  });

  test('the tab melodies are the tunes they claim', () {
    String tune(String id) => [
      for (final p in (lessonById(id)!.steps.single as NoteSteps).spots)
        Tuning.standard.noteAt(p.string, p.fret).pitchClass.name(),
    ].join(' ');
    expect(tune('a.ode'), 'B B C D D C B A G G A B B A A');
    expect(tune('a.twinkle'), 'C C G G A A G F F E E D D C');
  });

  test('a lesson lists its chords once each, by symbol', () {
    expect(lessonById('b.em-am')!.chords, ['Em', 'Am']);
    expect(lessonById('m.e-shape')!.chords, ['F', 'G', 'A', 'Bb']);
  });
}
