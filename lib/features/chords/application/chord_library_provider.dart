import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/storage/local_store.dart';
import 'package:fretlight/features/chords/domain/chord_library.dart';

/// The bundled library (~260 KB of JSON, 3,000+ voicings), parsed off the
/// UI isolate so opening the Chords tab never drops a frame.
final bundledChordLibraryProvider = FutureProvider<ChordLibrary>((ref) async {
  final json = await rootBundle.loadString('assets/chords/guitar.json');
  return await Isolate.run(
    () => ChordLibrary.fromJson((jsonDecode(json) as Map).cast<String, Object?>()),
  );
});

/// The library as the app uses it: bundled shapes plus the user's own.
final chordLibraryProvider = FutureProvider<ChordLibrary>((ref) async {
  final base = await ref.watch(bundledChordLibraryProvider.future);
  final custom = ref.watch(customChordsProvider);
  return base.withCustom({
    for (final MapEntry(:key, :value) in custom.entries)
      key: (name: value.name, frets: value.frets),
  });
});

/// The user's chord shapes, saved on the phone.
final customChordsProvider = NotifierProvider<CustomChordsController, Map<String, CustomChordData>>(
  CustomChordsController.new,
);

final class CustomChordsController extends Notifier<Map<String, CustomChordData>> {
  late LocalStore _store;

  @override
  Map<String, CustomChordData> build() {
    _store = ref.watch(localStoreProvider);
    return _store.customChords;
  }

  /// Saves a shape (new, or replacing [id]). Returns its id.
  String save(String name, List<int?> frets, {String? id}) {
    final key = id ?? 'chord_${DateTime.now().microsecondsSinceEpoch}';
    _store.putCustomChord(key, CustomChordData(name: name.trim(), frets: frets));
    state = _store.customChords;
    return key;
  }

  void delete(String id) {
    _store.deleteCustomChord(id);
    state = _store.customChords;
  }
}

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
