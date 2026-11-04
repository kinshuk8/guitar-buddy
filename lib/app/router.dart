import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/app/coming_soon.dart';
import 'package:fretlight/app/shell.dart';
import 'package:fretlight/features/chords/presentation/chord_detail_screen.dart';
import 'package:fretlight/features/chords/presentation/chords_screen.dart';
import 'package:fretlight/features/gallery/presentation/gallery_screen.dart';
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
          _branch('/identify', 'Identify', 5, Icons.graphic_eq_rounded),
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
          _branch('/tempo', 'Metronome', 4, Icons.av_timer_rounded),
          _branch('/songs', 'Songs', 6, Icons.queue_music_rounded),
        ],
      ),
      // Developer tool: compiled out of release builds.
      if (kDebugMode) GoRoute(path: '/gallery', builder: (context, state) => const GalleryScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

StatefulShellBranch _branch(String path, String title, int milestone, IconData icon) =>
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: path,
          builder: (context, state) =>
              ComingSoonScreen(title: title, milestone: milestone, icon: icon),
        ),
      ],
    );
