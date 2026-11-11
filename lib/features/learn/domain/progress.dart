import 'dart:math' as math;

import 'package:fretlight/features/learn/domain/curriculum.dart';
import 'package:fretlight/features/learn/domain/games.dart';
import 'package:meta/meta.dart';

/// The best a lesson has gone, and how often it's been played.
@immutable
final class LessonRecord {
  const LessonRecord({
    required this.stars,
    required this.bestScore,
    required this.attempts,
    required this.lastPlayed,
  });

  final int stars;
  final double bestScore;
  final int attempts;
  final DateTime lastPlayed;
}

/// One calendar day of practice.
@immutable
final class DayRecord {
  const DayRecord({required this.seconds, required this.xp});

  final int seconds;
  final int xp;
}

/// A day as `yyyy-mm-dd` in local time: the key practice days are stored by.
String dayKey(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

/// The player's progress, computed from stored records. Immutable; the
/// controller builds a new one after each lesson.
@immutable
final class Progress {
  const Progress({
    this.lessons = const {},
    this.days = const {},
    this.skills = const {},
    this.jumpedTo = 0,
    this.dailyGoalMinutes = 10,
  });

  final Map<String, LessonRecord> lessons;
  final Map<String, DayRecord> days;

  /// `chord:G` → mastery 0..100; `race:C|G` → best changes a minute;
  /// `rhythm:…` → best rhythm score.
  final Map<String, double> skills;

  /// Stage index the player chose to start from (skipping earlier ones).
  final int jumpedTo;
  final int dailyGoalMinutes;

  // XP and levels -----------------------------------------------------------

  int get xp => days.values.fold(0, (s, d) => s + d.xp);

  /// XP needed to reach [level] (level 1 at 0, 2 at 50, 3 at 150, ...).
  static int xpForLevel(int level) => 25 * level * (level - 1);

  int get level {
    var l = 1;
    while (xp >= xpForLevel(l + 1)) {
      l++;
    }
    return l;
  }

  /// Progress through the current level, 0..1.
  double get levelProgress {
    final from = xpForLevel(level);
    final to = xpForLevel(level + 1);
    return (xp - from) / (to - from);
  }

  // Stars and unlocking -----------------------------------------------------

  int starsOf(String lessonId) => lessons[lessonId]?.stars ?? 0;

  int get totalStars => lessons.values.fold(0, (s, r) => s + r.stars);

  bool completed(Lesson l) => starsOf(l.id) > 0;

  bool stageComplete(Stage s) => s.lessons.every(completed);

  /// The furthest stage open: everything up to the first unfinished stage,
  /// or further if the player jumped ahead.
  int get openStage {
    var i = 0;
    while (i < curriculum.length - 1 && stageComplete(curriculum[i])) {
      i++;
    }
    return math.max(i, jumpedTo);
  }

  /// A lesson is open when its stage is open and the lesson before it in
  /// its unit is done; a unit opens when the unit before it is done. In a
  /// stage reached by jumping, the same rule runs from that stage's start.
  bool unlocked(Lesson lesson) {
    final stageIndex = curriculum.indexWhere((s) => s.lessons.contains(lesson));
    if (stageIndex > openStage) return false;
    final stage = curriculum[stageIndex];
    for (final (ui, unit) in stage.units.indexed) {
      final li = unit.lessons.indexOf(lesson);
      if (li < 0) continue;
      if (li > 0) return completed(unit.lessons[li - 1]);
      if (ui == 0) return true;
      return stage.units[ui - 1].lessons.every(completed);
    }
    return false;
  }

  /// The lesson to suggest: the first open one not yet done, else the
  /// open lesson with the fewest stars.
  Lesson get next {
    final open = allLessons.where(unlocked).toList();
    return open.where((l) => !completed(l)).firstOrNull ??
        (open..sort((a, b) => starsOf(a.id).compareTo(starsOf(b.id)))).first;
  }

  /// Share of the stars available for [skill] across the whole path.
  double skillLevel(Skill skill) {
    final ls = allLessons.where((l) => l.skill == skill).toList();
    if (ls.isEmpty) return 0;
    return ls.fold(0, (s, l) => s + starsOf(l.id)) / (3 * ls.length);
  }

  /// Rank from the stages finished: Beginner until the first is done.
  String get rank {
    var done = 0;
    while (done < curriculum.length && stageComplete(curriculum[done])) {
      done++;
    }
    return switch (done) {
      0 => 'Beginner',
      1 => 'Improver',
      2 => 'Adept',
      3 => 'Master in training',
      _ => 'Master',
    };
  }

  // Chords --------------------------------------------------------------------

  double mastery(String chord) => skills['chord:$chord'] ?? 0;

  double? best(String key) => skills[key];

  /// Chords met in finished lessons (or the first lesson's, at the start),
  /// weakest first.
  List<String> chordsToWork() {
    final known = <String>[];
    for (final l in allLessons.where(completed)) {
      for (final c in l.chords) {
        if (!known.contains(c)) known.add(c);
      }
    }
    if (known.length < 2) {
      for (final c in ['Em', 'Am']) {
        if (!known.contains(c)) known.add(c);
      }
    }
    return known..sort((a, b) => mastery(a).compareTo(mastery(b)));
  }

  // Days ------------------------------------------------------------------------

  /// Days in a row with practice, ending today (or yesterday, if today's
  /// practice hasn't happened yet).
  int streak(DateTime now) {
    bool practised(DateTime d) {
      final r = days[dayKey(d)];
      return r != null && (r.xp > 0 || r.seconds >= 60);
    }

    var d = DateTime(now.year, now.month, now.day);
    if (!practised(d)) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (practised(d)) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  int minutesOn(DateTime day) => ((days[dayKey(day)]?.seconds ?? 0) / 60).floor();

  /// Today's practice against the daily goal, 0..1.
  double goalProgress(DateTime now) => (minutesOn(now) / dailyGoalMinutes).clamp(0, 1).toDouble();
}

/// What finishing a lesson earns.
@immutable
final class Award {
  const Award({
    required this.xp,
    required this.stars,
    required this.previousStars,
    required this.newBests,
  });

  final int xp;
  final int stars;
  final int previousStars;

  /// Personal bests beaten: key, old value (null if first), new value.
  final List<(String, double?, double)> newBests;

  bool get firstClear => previousStars == 0 && stars > 0;
}

/// Lesson stars from its steps: the average, at least one if every step
/// was finished, none if any wasn't.
int lessonStars(List<StepOutcome> steps) {
  if (steps.isEmpty || steps.any((s) => s.stars == 0)) return 0;
  final mean = steps.fold(0, (s, o) => s + o.stars) / steps.length;
  return mean.round().clamp(1, 3);
}

/// XP for a finished lesson. A first clear pays in full; replays pay a
/// quarter, plus half the base for each new star, so practice always
/// earns something but beating your best earns more.
int xpFor({required int base, required int stars, required int previousStars}) {
  const factor = [0.0, 1.0, 1.5, 2.0];
  if (stars == 0) return 5; // showing up counts
  if (previousStars == 0) return (base * factor[stars]).round();
  final replay = base * 0.25 * factor[stars];
  final newStars = math.max(0, stars - previousStars);
  return (replay + base * 0.5 * newStars).round();
}

/// Chord mastery after a step: clean strums push it towards 100 (less as it
/// gets there), wrong tries and skips pull it down.
double updatedMastery(double current, ({int clean, int missed}) result) {
  var v = current;
  for (var i = 0; i < result.clean; i++) {
    v += (100 - v) * 0.12;
  }
  v -= 6 * math.min(result.missed, 4);
  return v.clamp(0, 100).toDouble();
}

/// Bronze, silver and gold targets for a one-minute race between [a] and
/// [b], set by how well you know them.
(int, int, int) raceTargets(Progress p, String a, String b) {
  final avg = (p.mastery(a) + p.mastery(b)) / 2;
  return avg < 40
      ? (10, 18, 26)
      : avg < 75
      ? (16, 24, 34)
      : (24, 34, 44);
}

/// A one-minute race between two chords: as many clean changes as you can.
Lesson raceDrill(Progress p, String a, String b) => Lesson(
  id: '${Lesson.drillPrefix}race:$a|$b',
  title: '$a and $b race',
  about: 'One minute. Change between $a and $b as many times as you can, cleanly.',
  tip: 'Speed comes from not lifting your fingers further than you need to.',
  skill: Skill.changes,
  xp: 15,
  steps: [ChangeRace(chordSpecFor(a), chordSpecFor(b), targets: raceTargets(p, a, b))],
);

/// Today's chord workout: the chords you know, weakest first. A drill on
/// the weakest, a one-minute race between the two weakest, and a run
/// through the weakest four.
Lesson dailyWorkout(Progress p) {
  final chords = p.chordsToWork();
  final a = chords[0];
  final b = chords[1];
  final four = chords.take(4).toList();
  final targets = raceTargets(p, a, b);
  return Lesson(
    id: 'workout',
    title: 'Daily chord workout',
    about: 'Built from your weakest chords: $a and $b need the most work.',
    tip: 'A few minutes every day beats an hour once a week.',
    skill: Skill.changes,
    xp: 30,
    steps: [
      ChordSteps([a], repeat: 4),
      ChangeRace(a, b, targets: targets),
      ChordSteps(four, repeat: 2),
    ],
  );
}
