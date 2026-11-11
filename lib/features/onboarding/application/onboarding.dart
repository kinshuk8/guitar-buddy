import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/storage/local_store.dart';
import 'package:fretlight/features/learn/application/progress_controller.dart';
import 'package:fretlight/features/learn/domain/curriculum.dart';
import 'package:fretlight/features/settings/application/appearance.dart';

/// How much guitar someone has played, asked once at first launch.
enum Experience {
  beginner('I’m new to guitar', 'Start from the first chord, one step at a time.'),
  returning('I’ve played a little', 'Skip the very first steps and pick up from open chords.'),
  experienced('I play already', 'Everything is open. Go straight to what you need.');

  Experience(this.label, this.detail);

  final String label;
  final String detail;
}

/// Set when a new player finishes the welcome screens: Home opens the
/// guided first session once it is on screen. (Pushing the lesson from the
/// welcome page itself would lose it when that page is replaced.)
final firstSessionPendingProvider = NotifierProvider<FirstSessionPending, bool>(
  FirstSessionPending.new,
);

final class FirstSessionPending extends Notifier<bool> {
  @override
  bool build() => false;

  // A setter would read oddly at the call sites ("pending = true").
  // ignore: use_setters_to_change_properties
  void set({required bool value}) => state = value;
}

/// Whether the welcome screens still need showing.
final onboardingProvider = NotifierProvider<Onboarding, bool>(Onboarding.new);

final class Onboarding extends Notifier<bool> {
  static const doneKey = 'onboarding.done';
  static const levelKey = 'onboarding.level';

  @override
  bool build() {
    final store = ref.watch(localStoreProvider);
    if (store.setting(doneKey) != null) return false;
    // Anyone with saved data came from a version without a welcome: they
    // already know the app, so don't ask.
    return store.isFresh;
  }

  /// Saves the answers and opens the right part of the course. Null answers
  /// (skipped) change nothing.
  void finish({Experience? experience, bool? leftHanded}) {
    final store = ref.read(localStoreProvider)..setSetting(doneKey, 'true');
    if (leftHanded != null) {
      ref.read(appearanceProvider.notifier).setLeftHanded(value: leftHanded);
    }
    if (experience != null) {
      store.setSetting(levelKey, experience.name);
      switch (experience) {
        case Experience.beginner:
          ref.read(firstSessionPendingProvider.notifier).set(value: true);
        case Experience.returning:
          ref.read(progressProvider.notifier).jumpTo(1);
        case Experience.experienced:
          ref.read(progressProvider.notifier).jumpTo(curriculum.length - 1);
      }
    }
    state = false;
  }

  /// The level chosen at first launch, if one was.
  Experience? get experience =>
      Experience.values.asNameMap()[ref.read(localStoreProvider).setting(levelKey)];
}
