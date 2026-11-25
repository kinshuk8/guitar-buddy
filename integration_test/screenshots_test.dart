import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/app/app.dart';
import 'package:fretlight/core/audio/synth/strum.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/storage/local_store.dart';
import 'package:fretlight/features/learn/domain/curriculum.dart';
import 'package:fretlight/features/learn/domain/progress.dart';
import 'package:fretlight/features/tuner/application/tuner_controller.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/fake_audio_input.dart';

/// Walks the app for the README's screenshots. It prints `SHOT <name>` and
/// holds still while a script outside takes the simulator's screenshot:
///   flutter test integration_test/screenshots_test.dart -d DEVICE
/// (see tool/screenshots.sh). Progress is a demo player's, two weeks in;
/// the microphone is fed the app's own synthesised guitar, so listening
/// screens show what they show when you play.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  const pm = PitchMath();
  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  final now = DateTime.now();
  final done = allLessons.take(14).toList();
  final store = LocalStore.memory(
    settings: {
      'onboarding.done': 'true',
      'songs.recent': 'amazing_grace|aura_lee|clementine',
    },
    lessons: {
      for (final (i, l) in done.indexed)
        l.id: StoredLesson(
          stars: i % 4 == 2 ? 2 : 3,
          bestScore: i % 4 == 2 ? 0.8 : 0.95,
          attempts: 1 + i % 3,
          lastPlayed: now.subtract(Duration(days: 13 - i)),
        ),
    },
    days: {
      for (var d = 0; d < 14; d++)
        if (d != 7)
          dayKey(now.subtract(Duration(days: d))): StoredDay(
            seconds: d == 0 ? 7 * 60 : (9 + d % 5) * 60,
            xp: 40 + 7 * (d % 4),
          ),
    },
    skills: {
      'chord:Em': 92,
      'chord:Am': 84,
      'chord:D': 71,
      'chord:G': 63,
      'chord:C': 38,
      'chord:A': 22,
      'chord:E': 15,
      'race:Am|Em': 31,
      'race:D|G': 24,
      'race:C|G': 17,
    },
  );
  final mic = FakeAudioInputSource();

  /// Plays [pcm] into the fake mic at real speed.
  Future<void> play(Float32List pcm) async {
    const block = 4800; // 100 ms
    for (var i = 0; i < pcm.length; i += block) {
      mic.feed(Float32List.sublistView(pcm, i, (i + block).clamp(0, pcm.length)));
      await wait(100);
    }
  }

  Float32List strum(List<int?> frets, {double seconds = 2.2}) => renderStrum(
    stringHz: [
      for (var s = 0; s < 6; s++)
        if (frets[s] case final int f) pm.hz(Tuning.standard.noteAt(s, f)) else null,
    ],
    sampleRate: 48000,
    seconds: seconds,
    peak: 0.4,
  );

  Future<void> shot(String name, {int hold = 2500, int settle = 600}) async {
    await wait(settle);
    debugPrint('SHOT $name');
    await wait(hold);
  }

  testWidgets('screenshots', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          audioInputProvider.overrideWithValue(mic),
        ],
        child: const FretlightApp(),
      ),
    );
    await wait(2500);

    void go(String location) =>
        GoRouter.of(tester.element(find.byType(Navigator).first)).go(location);
    Future<void> tap(Finder f, {int settle = 900}) async {
      await tester.tap(f.first);
      await tester.pump();
      await wait(settle);
    }

    Future<void> closeAll() async {
      tester.state<NavigatorState>(find.byType(Navigator).first).popUntil((r) => r.isFirst);
      await wait(800);
    }

    await shot('home');

    go('/practice');
    await shot('practice');
    go('/practice/lessons');
    await shot('lessons');
    go('/practice/progress');
    await shot('progress');
    go('/practice/changes');
    await shot('changes');

    // A chord drill, listening: E, strummed, and counted.
    go('/practice');
    await wait(900);
    await tap(find.bySemanticsLabel(RegExp('^E major, ')));
    await tap(find.text('Start'), settle: 1500);
    await play(strum([0, 2, 2, 1, 0, 0]));
    await play(strum([0, 2, 2, 1, 0, 0], seconds: 1.2));
    await shot('chord-drill');
    await closeAll();

    go('/songs');
    await shot('songs');
    go('/songs/play?id=amazing_grace');
    await wait(1500);
    await tap(find.bySemanticsLabel('Play'), settle: 5000);
    await shot('play-along');
    await tap(find.bySemanticsLabel('Pause'));
    await tap(find.text('Practise'), settle: 1500);
    await play(strum([3, 2, 0, 0, 0, 3], seconds: 1.4));
    await shot('song-practice');
    await closeAll();

    go('/tools');
    await shot('tools');

    // Listening screens first learn the room: a moment of quiet, then play.
    final quiet = Float32List(48000 * 2);
    go('/tuner');
    await wait(800);
    await play(quiet);
    final listen = play(
      renderStrum(
        stringHz: [null, pm.hz(Tuning.standard.noteAt(1, 0)) * 1.004, null, null, null, null],
        sampleRate: 48000,
        seconds: 5,
        peak: 0.4,
      ),
    );
    await shot('tuner', settle: 1400, hold: 1500);
    await listen;
    await closeAll();

    go('/tools/identify');
    await wait(800);
    await play(quiet);
    final chord = play(strum([null, 3, 2, 0, 1, 0], seconds: 3)).then((_) => play(quiet));
    await shot('identify', settle: 750, hold: 1500);
    await chord;

    go('/tools/chords');
    await shot('chord-library');
    go('/tools/chords/chord?s=C');
    await shot('chord-detail');

    go('/tools/metronome');
    await wait(900);
    await tap(find.text('Start'), settle: 1200);
    await shot('metronome');
    await tap(find.text('Stop'));

    go('/settings');
    await shot('settings');
    await closeAll();

    binding.reportData = {'done': true};
    await tester.pumpWidget(const SizedBox());
  });
}
