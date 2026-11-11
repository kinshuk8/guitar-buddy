import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/storage/local_store.dart';
import 'package:fretlight/features/learn/domain/curriculum.dart';
import 'package:fretlight/features/learn/domain/games.dart';
import 'package:fretlight/features/learn/domain/progress.dart';

/// The current time, as a provider so tests can fix "today".
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final progressProvider = NotifierProvider<ProgressController, Progress>(ProgressController.new);

/// Owns Learn progress: reads it from the store, records lessons, and
/// works out what each one earned.
final class ProgressController extends Notifier<Progress> {
  static const _jumpKey = 'learn.jumpedTo';
  static const _goalKey = 'learn.goalMinutes';
  static const goals = [5, 10, 15, 20, 30];

  late LocalStore _store;

  @override
  Progress build() {
    _store = ref.watch(localStoreProvider);
    return _load();
  }

  Progress _load() => Progress(
    lessons: {
      for (final MapEntry(:key, :value) in _store.lessons.entries)
        key: LessonRecord(
          stars: value.stars,
          bestScore: value.bestScore,
          attempts: value.attempts,
          lastPlayed: value.lastPlayed,
        ),
    },
    days: {
      for (final MapEntry(:key, :value) in _store.days.entries)
        key: DayRecord(seconds: value.seconds, xp: value.xp),
    },
    skills: _store.skills,
    jumpedTo: int.tryParse(_store.setting(_jumpKey) ?? '') ?? 0,
    dailyGoalMinutes: int.tryParse(_store.setting(_goalKey) ?? '') ?? 10,
  );

  /// Adds practice time (and XP) to today.
  ///
  /// Can arrive a moment after a lesson closes (see LessonController.leave);
  /// if the app is shutting down by then, there's nothing to save into.
  void addPractice({Duration time = Duration.zero, int xp = 0}) {
    if (!ref.mounted || (time <= Duration.zero && xp == 0)) return;
    final key = dayKey(ref.read(nowProvider)());
    final day = _store.days[key] ?? const StoredDay(seconds: 0, xp: 0);
    _store.putDay(key, StoredDay(seconds: day.seconds + time.inSeconds, xp: day.xp + xp));
    state = _load();
  }

  /// Records a finished lesson (or workout) and returns what it earned.
  /// [time] is the practice time it took, added to today.
  Award record(Lesson lesson, List<StepOutcome> outcomes, {Duration time = Duration.zero}) {
    final now = ref.read(nowProvider)();
    final stars = lessonStars(outcomes);
    final score = outcomes.isEmpty
        ? 0.0
        : outcomes.map((o) => o.score).reduce((a, b) => a + b) / outcomes.length;
    final previous = _store.lessons[lesson.id];
    final previousStars = previous?.stars ?? 0;
    final xp = xpFor(base: lesson.xp, stars: stars, previousStars: previousStars);

    // Drills build mastery and time, not stars: no lesson record.
    if (!lesson.isDrill) {
      _store.putLesson(
        lesson.id,
        StoredLesson(
          stars: math.max(stars, previousStars),
          bestScore: math.max(score, previous?.bestScore ?? 0),
          attempts: (previous?.attempts ?? 0) + 1,
          lastPlayed: now,
        ),
      );
    }

    // Chord mastery, from every strum judged.
    final perChord = <String, ({int clean, int missed})>{};
    for (final o in outcomes) {
      for (final MapEntry(:key, :value) in o.chords.entries) {
        final prev = perChord[key] ?? (clean: 0, missed: 0);
        perChord[key] = (clean: prev.clean + value.clean, missed: prev.missed + value.missed);
      }
    }
    for (final MapEntry(:key, :value) in perChord.entries) {
      final k = 'chord:$key';
      _store.putSkill(k, updatedMastery(_store.skills[k] ?? 0, value));
    }

    // Personal bests.
    final bests = <(String, double?, double)>[];
    for (final o in outcomes) {
      final b = o.best;
      if (b == null) continue;
      final (key, value) = b;
      final old = _store.skills[key];
      if (old == null || value > old) {
        _store.putSkill(key, value);
        if (value > 0) bests.add((key, old, value));
      }
    }

    final dk = dayKey(now);
    final day = _store.days[dk] ?? const StoredDay(seconds: 0, xp: 0);
    _store.putDay(dk, StoredDay(seconds: day.seconds + time.inSeconds, xp: day.xp + xp));

    state = _load();
    return Award(xp: xp, stars: stars, previousStars: previousStars, newBests: bests);
  }

  /// Records a free practice run (a progression, a song, a chord from the
  /// library): chord mastery from every chord played, and XP for the
  /// chords played cleanly. Its time is added separately, as it's played.
  void recordFree(Map<String, ({int clean, int missed})> chords) {
    if (!ref.mounted || chords.isEmpty) return;
    for (final MapEntry(:key, :value) in chords.entries) {
      final k = 'chord:$key';
      _store.putSkill(k, updatedMastery(_store.skills[k] ?? 0, value));
    }
    final clean = chords.values.fold(0, (s, v) => s + v.clean);
    addPractice(xp: math.min(30, 5 + clean));
  }

  /// Opens a later stage without finishing the ones before.
  void jumpTo(int stage) {
    _store.setSetting(_jumpKey, '$stage');
    state = _load();
  }

  void setDailyGoal(int minutes) {
    _store.setSetting(_goalKey, '$minutes');
    state = _load();
  }

  void reset() {
    _store
      ..clearLearning()
      ..setSetting(_jumpKey, null);
    state = _load();
  }
}
