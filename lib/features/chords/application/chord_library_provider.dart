import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/storage/local_store.dart';
import 'package:fretlight/features/chords/domain/chord_library.dart';

/// The bundled library (~260 KB of JSON, 3,000+ voicings), parsed off the
/// UI isolate so opening the Chords tab never drops a frame.
final chordLibraryProvider = FutureProvider<ChordLibrary>((ref) async {
  final json = await rootBundle.loadString('assets/chords/guitar.json');
  return await Isolate.run(
    () => ChordLibrary.fromJson((jsonDecode(json) as Map).cast<String, Object?>()),
  );
});

/// Starred chord symbols, newest last.
final favoritesProvider = NotifierProvider<FavoritesController, Set<String>>(
  FavoritesController.new,
);

final class FavoritesController extends Notifier<Set<String>> {
  late LocalStore _store;

  @override
  Set<String> build() {
    _store = ref.watch(localStoreProvider);
    return _store.favorites;
  }

  void toggle(String symbol) {
    final on = !state.contains(symbol);
    _store.setFavorite(symbol, favorite: on);
    state = _store.favorites;
  }
}

/// Root last browsed, so returning to the tab lands where you were.
final browseRootProvider = NotifierProvider<BrowseRootController, int>(BrowseRootController.new);

final class BrowseRootController extends Notifier<int> {
  static const _key = 'chords.root';

  @override
  int build() => int.tryParse(ref.watch(localStoreProvider).setting(_key) ?? '') ?? 0;

  void select(int pitchClass) {
    state = pitchClass;
    ref.read(localStoreProvider).setSetting(_key, '$pitchClass');
  }
}
