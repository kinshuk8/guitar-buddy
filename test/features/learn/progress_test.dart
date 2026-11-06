import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/features/learn/domain/curriculum.dart';
import 'package:fretlight/features/learn/domain/games.dart';
import 'package:fretlight/features/learn/domain/progress.dart';

LessonRecord rec(int stars) =>
    LessonRecord(stars: stars, bestScore: stars / 3, attempts: 1, lastPlayed: DateTime(2026));

Progress withStars(Map<String, int> stars, {int jumpedTo = 0}) =>
    Progress(lessons: {for (final e in stars.entries) e.key: rec(e.value)}, jumpedTo: jumpedTo);

void main() {
  test('levels: 50 XP for level 2, then more each level', () {
    expect(Progress.xpForLevel(1), 0);
    expect(Progress.xpForLevel(2), 50);
    expect(Progress.xpForLevel(3), 150);
    const p = Progress(days: {'2026-11-06': DayRecord(seconds: 0, xp: 160)});
    expect(p.level, 3);
    expect(p.levelProgress, closeTo(10 / 150, 1e-9));
  });

  test('lessons open one at a time; units after the previous unit', () {
    final fresh = withStars({});
    expect(fresh.unlocked(lessonById('b.strings')!), isTrue);
    expect(fresh.unlocked(lessonById('b.tune')!), isFalse);
    expect(fresh.unlocked(lessonById('b.em')!), isFalse, reason: 'next unit waits');
    expect(fresh.unlocked(lessonById('i.c')!), isFalse, reason: 'next stage waits');
    expect(fresh.next.id, 'b.strings');

    final some = withStars({'b.strings': 2, 'b.tune': 1});
    expect(some.unlocked(lessonById('b.em')!), isTrue);
    expect(some.unlocked(lessonById('b.am')!), isFalse);
    expect(some.next.id, 'b.em');
  });

  test('finishing a stage opens the next; jumping ahead opens it too', () {
    final beginner = curriculum.first.lessons;
    final done = withStars({for (final l in beginner) l.id: 1});
    expect(done.openStage, 1);
    expect(done.rank, 'Improver');
    expect(done.unlocked(curriculum[1].lessons.first), isTrue);

    final jumped = withStars({}, jumpedTo: 2);
    expect(jumped.unlocked(curriculum[2].lessons.first), isTrue);
    expect(jumped.unlocked(curriculum[2].lessons[1]), isFalse);
    expect(
      jumped.unlocked(curriculum[1].lessons.first),
      isTrue,
      reason: 'earlier stages stay open',
    );
    expect(jumped.unlocked(curriculum[3].lessons.first), isFalse);
  });

  test('skill levels are the share of that skill’s stars', () {
    final rhythm = allLessons.where((l) => l.skill == Skill.rhythm).toList();
    final p = withStars({rhythm.first.id: 3});
    expect(p.skillLevel(Skill.rhythm), closeTo(1 / rhythm.length, 1e-9));
    expect(p.skillLevel(Skill.songs), 0);
  });

  test('streak counts days in a row, today or up to yesterday', () {
    final now = DateTime(2026, 11, 6, 20);
    const p = Progress(
      days: {
        '2026-11-03': DayRecord(seconds: 600, xp: 40),
        '2026-11-04': DayRecord(seconds: 300, xp: 0),
        '2026-11-05': DayRecord(seconds: 10, xp: 20),
      },
    );
    expect(p.streak(now), 3, reason: 'today not played yet: still counts to yesterday');
    expect(p.streak(DateTime(2026, 11, 7)), 0, reason: 'a missed day breaks it');
    expect(p.goalProgress(DateTime(2026, 11, 3)), 1);
    expect(p.goalProgress(DateTime(2026, 11, 4)), 0.5);
  });

  test('stars for a lesson: the steps’ average, none if any step unfinished', () {
    StepOutcome o(int stars) => StepOutcome(score: 0, stars: stars, headline: '');
    expect(lessonStars([o(3), o(2)]), 3);
    expect(lessonStars([o(1), o(2)]), 2);
    expect(lessonStars([o(1), o(1)]), 1);
    expect(lessonStars([o(3), o(0)]), 0);
  });

  test('XP: first clear in full, replays a quarter plus a bonus per new star', () {
    expect(xpFor(base: 20, stars: 1, previousStars: 0), 20);
    expect(xpFor(base: 20, stars: 3, previousStars: 0), 40);
    expect(xpFor(base: 20, stars: 2, previousStars: 2), 8);
    expect(xpFor(base: 20, stars: 3, previousStars: 1), 10 + 20);
    expect(xpFor(base: 20, stars: 0, previousStars: 0), 5);
  });

  test('mastery climbs with clean strums, slower near the top; misses cost', () {
    var m = 0.0;
    m = updatedMastery(m, (clean: 5, missed: 0));
    expect(m, closeTo(100 * (1 - 0.88 * 0.88 * 0.88 * 0.88 * 0.88), 1e-6));
    expect(updatedMastery(m, (clean: 0, missed: 2)), closeTo(m - 12, 1e-6));
    expect(updatedMastery(5, (clean: 0, missed: 9)), 0);
  });

  test('daily workout works the weakest chords you know', () {
    final p = Progress(
      lessons: {'b.em': rec(3), 'b.am': rec(2), 'b.d': rec(1)},
      skills: const {'chord:Em': 90, 'chord:Am': 30, 'chord:D': 10},
    );
    expect(p.chordsToWork(), ['D', 'Am', 'Em']);
    final w = dailyWorkout(p);
    expect((w.steps[0] as ChordSteps).chords, ['D']);
    final race = w.steps[1] as ChangeRace;
    expect((race.a, race.b), ('D', 'Am'));
    expect(race.targets, (10, 18, 26));

    // Day one: no chords known yet, still a workout.
    expect(dailyWorkout(const Progress()).chords, containsAll(['Em', 'Am']));
  });
}
