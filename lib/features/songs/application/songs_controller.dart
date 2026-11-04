import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/storage/local_store.dart';
import 'package:fretlight/features/songs/domain/chordpro.dart';
import 'package:fretlight/features/songs/domain/song_timeline.dart';
import 'package:meta/meta.dart';

/// Starter songs bundled as assets (all public domain; see each file's
/// `{meta: public_domain …}`).
const bundledSongIds = [
  'amazing_grace',
  'auld_lang_syne',
  'clementine',
  'down_in_the_valley',
  'home_on_the_range',
  'michael_row',
  'oh_susanna',
  'red_river_valley',
  'scarborough_fair',
  'shenandoah',
  'swing_low',
  'when_the_saints',
];

@immutable
final class SongEntry {
  const SongEntry({
    required this.id,
    required this.song,
    required this.source,
    required this.bundled,
  });

  final String id;
  final Song song;

  /// The ChordPro text, for editing.
  final String source;
  final bool bundled;
}

/// Per-song choices that should still be there next time.
@immutable
final class SongPrefs {
  const SongPrefs({this.arrangement = const Arrangement(), this.tempo});

  final Arrangement arrangement;

  /// Null = the song's own tempo.
  final int? tempo;
}

/// The bundled starter songs' ChordPro text, by id. A provider so tests can
/// read the files from disk instead of the asset bundle.
final bundledSongSourcesProvider = FutureProvider<Map<String, String>>(
  (ref) async => {
    for (final id in bundledSongIds) id: await rootBundle.loadString('assets/songs/$id.cho'),
  },
);

final songsProvider = AsyncNotifierProvider<SongsController, List<SongEntry>>(SongsController.new);

final class SongsController extends AsyncNotifier<List<SongEntry>> {
  late LocalStore _store;

  @override
  Future<List<SongEntry>> build() async {
    _store = ref.watch(localStoreProvider);
    final sources = await ref.watch(bundledSongSourcesProvider.future);
    final bundled = <SongEntry>[];
    for (final MapEntry(key: id, value: source) in sources.entries) {
      bundled.add(
        SongEntry(id: id, song: ChordProParser.parse(source), source: source, bundled: true),
      );
    }
    bundled.sort((a, b) => a.song.title.compareTo(b.song.title));
    return [..._userEntries(), ...bundled];
  }

  List<SongEntry> _userEntries() => [
    for (final MapEntry(key: id, value: source) in _store.userSongs.entries.toList().reversed)
      SongEntry(id: id, song: ChordProParser.parse(source), source: source, bundled: false),
  ];

  /// Parses without saving: what the import screen previews.
  static Song preview(String source) => ChordProParser.parse(source);

  /// Saves a pasted or imported sheet. Returns the new song's id.
  String add(String source) {
    final id = 'user_${DateTime.now().microsecondsSinceEpoch}';
    _store.putUserSong(id, source);
    _refresh();
    return id;
  }

  void edit(String id, String source) {
    _store.putUserSong(id, source);
    _refresh();
  }

  void delete(String id) {
    _store
      ..deleteUserSong(id)
      ..setSetting(_prefsKey(id), null);
    _refresh();
  }

  void _refresh() {
    final current = state.value;
    if (current == null) return;
    state = AsyncData([..._userEntries(), ...current.where((e) => e.bundled)]);
  }

  SongPrefs prefs(String id, Song song) {
    final raw = _store.setting(_prefsKey(id))?.split(',');
    if (raw == null || raw.length != 3) {
      return SongPrefs(arrangement: Arrangement(capo: song.capo));
    }
    return SongPrefs(
      arrangement: Arrangement(
        transpose: int.tryParse(raw[0]) ?? 0,
        capo: int.tryParse(raw[1]) ?? song.capo,
      ),
      tempo: int.tryParse(raw[2]),
    );
  }

  void savePrefs(String id, SongPrefs p) => _store.setSetting(
    _prefsKey(id),
    '${p.arrangement.transpose},${p.arrangement.capo},${p.tempo ?? ''}',
  );

  static String _prefsKey(String id) => 'song.$id';
}
