import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/app/shell.dart';
import 'package:fretlight/features/chords/presentation/chord_detail_screen.dart';
import 'package:fretlight/features/chords/presentation/chords_screen.dart';
import 'package:fretlight/features/gallery/presentation/gallery_screen.dart';
import 'package:fretlight/features/identify/presentation/identify_screen.dart';
import 'package:fretlight/features/metronome/presentation/metronome_screen.dart';
import 'package:fretlight/features/songs/presentation/play_along_screen.dart';
import 'package:fretlight/features/songs/presentation/songs_screen.dart';
import 'package:fretlight/features/tuner/presentation/tuner_screen.dart';
import 'package:go_router/go_router.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/tune',
    routes: [
      // One branch per tab; IndexedStack keeps each tab's state (e.g. a
      // running metronome) alive while you switch to another tab.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => StageShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/tune', builder: (context, state) => const TunerScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/identify', builder: (context, state) => const IdentifyScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/chords',
                builder: (context, state) => const ChordsScreen(),
                routes: [
                  // Symbol as a query parameter: `C#` and `G/B` stay intact.
                  GoRoute(
                    path: 'chord',
                    builder: (context, state) =>
                        ChordDetailScreen(symbol: state.uri.queryParameters['s'] ?? ''),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/tempo', builder: (context, state) => const MetronomeScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/songs',
                builder: (context, state) => const SongsScreen(),
                routes: [
                  GoRoute(
                    path: 'play',
                    builder: (context, state) =>
                        PlayAlongScreen(id: state.uri.queryParameters['id'] ?? ''),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      // Developer tool: compiled out of release builds.
      if (kDebugMode) GoRoute(path: '/gallery', builder: (context, state) => const GalleryScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
