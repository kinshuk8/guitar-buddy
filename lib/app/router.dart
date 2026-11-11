import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/app/shell.dart';
import 'package:fretlight/features/chords/presentation/chord_detail_screen.dart';
import 'package:fretlight/features/chords/presentation/chords_screen.dart';
import 'package:fretlight/features/gallery/presentation/gallery_screen.dart';
import 'package:fretlight/features/home/presentation/home_screen.dart';
import 'package:fretlight/features/identify/presentation/identify_screen.dart';
import 'package:fretlight/features/learn/presentation/learn_screen.dart';
import 'package:fretlight/features/metronome/presentation/metronome_screen.dart';
import 'package:fretlight/features/onboarding/application/onboarding.dart';
import 'package:fretlight/features/onboarding/presentation/welcome_screen.dart';
import 'package:fretlight/features/practice/presentation/chord_practice.dart';
import 'package:fretlight/features/practice/presentation/practice_hub_screen.dart';
import 'package:fretlight/features/practice/presentation/practice_screen.dart';
import 'package:fretlight/features/progressions/presentation/progressions_screen.dart';
import 'package:fretlight/features/settings/presentation/settings_screen.dart';
import 'package:fretlight/features/songs/presentation/play_along_screen.dart';
import 'package:fretlight/features/songs/presentation/songs_screen.dart';
import 'package:fretlight/features/tools/presentation/tools_screen.dart';
import 'package:fretlight/features/tuner/presentation/tuner_screen.dart';
import 'package:go_router/go_router.dart';

/// Where the six tabs of 0.9 and earlier live now. Old paths keep working.
const legacyRoutes = {
  '/learn': '/practice/lessons',
  '/tune': '/tuner',
  '/identify': '/tools/identify',
  '/chords': '/tools/chords',
  '/chords/chord': '/tools/chords/chord',
  '/tempo': '/tools/metronome',
};

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/home',
    redirect: (context, state) {
      final path = state.uri.path;
      // First launch: two quick questions before anything else.
      if (ref.read(onboardingProvider)) return path == '/welcome' ? null : '/welcome';
      if (path == '/welcome') return '/home';
      if (legacyRoutes[path] case final moved?) {
        return state.uri.replace(path: moved).toString();
      }
      return null;
    },
    routes: [
      // One branch per tab; IndexedStack keeps each tab's place (the lesson
      // list's scroll position, the song you had open) while you visit
      // another.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => StageShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/home', builder: (context, state) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/practice',
                builder: (context, state) => const PracticeHubScreen(),
                routes: [
                  GoRoute(path: 'lessons', builder: (context, state) => const LessonsScreen()),
                  GoRoute(
                    path: 'chords',
                    builder: (context, state) => const ChordsPracticeScreen(),
                  ),
                  GoRoute(path: 'changes', builder: (context, state) => const ChangesScreen()),
                  GoRoute(
                    path: 'progressions',
                    builder: (context, state) => const ProgressionsScreen(),
                  ),
                  GoRoute(path: 'progress', builder: (context, state) => const ProgressScreen()),
                ],
              ),
            ],
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
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tools',
                builder: (context, state) => const ToolsScreen(),
                routes: [
                  GoRoute(path: 'metronome', builder: (context, state) => const MetronomeScreen()),
                  GoRoute(path: 'identify', builder: (context, state) => const IdentifyScreen()),
                  GoRoute(
                    path: 'chords',
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
            ],
          ),
        ],
      ),
      // Full-attention screens sit above the tabs: one task, then Back.
      GoRoute(path: '/drill', builder: (context, state) => const PracticeScreen()),
      GoRoute(path: '/tuner', builder: (context, state) => const TunerScreen()),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
      GoRoute(path: '/welcome', builder: (context, state) => const WelcomeScreen()),
      // Developer tool: compiled out of release builds.
      if (kDebugMode) GoRoute(path: '/gallery', builder: (context, state) => const GalleryScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
