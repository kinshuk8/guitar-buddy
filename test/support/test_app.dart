import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:fretlight/app/app.dart';
import 'package:fretlight/core/storage/local_store.dart';
import 'package:fretlight/features/chords/application/chord_library_provider.dart';
import 'package:fretlight/features/chords/application/chord_player.dart';
import 'package:fretlight/features/chords/domain/chord_library.dart';
import 'package:fretlight/features/progressions/data/progression_pack.dart';
import 'package:fretlight/features/songs/application/songs_controller.dart';
import 'package:fretlight/features/tuner/application/tuner_controller.dart';

import 'fake_audio_input.dart';
import 'fake_audio_output.dart';

/// Fakes for every device the app touches: mic, speaker, and storage.
final class TestDevices {
  TestDevices({FakeAudioInputSource? mic, LocalStore? store, this.library})
    : mic = mic ?? FakeAudioInputSource(),
      store = store ?? LocalStore.memory();

  /// Preloaded library. Without it the app reads the asset through
  /// rootBundle, whose cache only works for the first test in a file.
  final ChordLibrary? library;

  final FakeAudioInputSource mic;
  final FakeAudioOutput speaker = FakeAudioOutput();
  final LocalStore store;

  List<Override> get overrides => [
    audioInputProvider.overrideWithValue(mic),
    audioOutputProvider.overrideWithValue(speaker),
    localStoreProvider.overrideWithValue(store),
    if (library case final lib?) chordLibraryProvider.overrideWith((ref) async => lib),
    // Read from disk: rootBundle's cache only works for a file's first test.
    progressionPackProvider.overrideWith(
      (ref) async => ProgressionPack.openFile(ProgressionPack.asset),
    ),
    bundledSongSourcesProvider.overrideWith(
      (ref) async => {
        for (final id in bundledSongIds) id: File('assets/songs/$id.cho').readAsStringSync(),
      },
    ),
  ];

  Widget app() => ProviderScope(overrides: overrides, child: const FretlightApp());

  Widget wrap(Widget child) => ProviderScope(overrides: overrides, child: child);
}
