import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/storage/local_store.dart';
import 'package:fretlight/features/practice/domain/practice_session.dart';

/// How closely lessons and practice want the chord you play to match.
final chordMatchingProvider = NotifierProvider<ChordMatchingController, ChordMatching>(
  ChordMatchingController.new,
);

final class ChordMatchingController extends Notifier<ChordMatching> {
  static const _key = 'listen.chordMatching';

  @override
  ChordMatching build() =>
      ChordMatching.values.asNameMap()[ref.watch(localStoreProvider).setting(_key)] ??
      ChordMatching.normal;

  void set(ChordMatching m) {
    state = m;
    ref.read(localStoreProvider).setSetting(_key, m.name);
  }
}
