import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/app/router.dart';
import 'package:fretlight/app/shell.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/storage/app_database.dart';
import 'package:fretlight/core/storage/local_store.dart';
import 'package:fretlight/features/chords/domain/chord_library.dart';
import 'package:fretlight/features/learn/application/progress_controller.dart';
import 'package:fretlight/features/settings/application/appearance.dart';
import 'package:fretlight/features/tuner/presentation/tuner_screen.dart';

import '../support/test_app.dart';

final library = ChordLibrary.fromJson(
  (jsonDecode(File('assets/chords/guitar.json').readAsStringSync()) as Map).cast<String, Object?>(),
);

Future<TestDevices> launch(WidgetTester tester, {LocalStore? store, bool onboarded = true}) async {
  tester.view.physicalSize = const Size(1206, 2622); // iPhone 17 at 3x
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final devices = TestDevices(library: library, store: store, onboarded: onboarded);
  await tester.pumpWidget(devices.app());
  await tester.pumpAndSettle();
  return devices;
}

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Navigator).first));

String location(WidgetTester tester) =>
    containerOf(tester).read(routerProvider).state.uri.toString();

/// Taps [finder] (scrolling it clear of the tab bar first) and settles.
Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

/// A tab in the bottom bar (the page title can carry the same name).
Finder tab(String label) =>
    find.descendant(of: find.byType(StageNavBar), matching: find.bySemanticsLabel(label));

/// A screen the test expects to have arrived on.
Finder heading(String title) => find.bySemanticsLabel(title);

void main() {
  group('every primary feature is at most two taps from launch', () {
    // (feature, taps, what proves you arrived)
    // Built inside each test: semantics finders need a running tester.
    List<(String, List<Finder>, Finder)> routes() => [
      ('Tuner', [find.bySemanticsLabel('Open the tuner')], find.byType(TunerScreen)),
      ('Practice', [tab('Practice')], find.text('Ways to practise'.toUpperCase())),
      ('Songs', [tab('Songs')], find.text('Amazing Grace')),
      ('Tools', [tab('Tools')], find.text('Chord library')),
      ('Next lesson', [find.bySemanticsLabel(RegExp('^Up next: '))], find.text('Start')),
      ('Daily workout', [find.text('Daily chord workout')], find.text('Start')),
      ('Metronome', [find.bySemanticsLabel('Metronome')], find.text('BPM · Andante')),
      ('Identify', [find.bySemanticsLabel('Identify')], find.text('Note')),
      ('Settings', [find.bySemanticsLabel('Settings')], find.text('Left-handed')),
      (
        'Lessons',
        [tab('Practice'), find.bySemanticsLabel(RegExp(r'^Lessons\.'))],
        find.text('Beginner'),
      ),
      (
        'Drill a chord',
        [tab('Practice'), find.bySemanticsLabel(RegExp('^E minor, '))],
        find.text('Em drill'),
      ),
      (
        'Changes',
        [tab('Practice'), find.bySemanticsLabel(RegExp(r'^Changes\.'))],
        find.text('One-minute race'),
      ),
      (
        'All chords',
        [tab('Practice'), find.bySemanticsLabel(RegExp(r'^Chords\.'))],
        find.text('Tap a chord to drill it'),
      ),
      (
        'Progressions',
        [tab('Practice'), find.bySemanticsLabel(RegExp(r'^Progressions\.'))],
        find.textContaining('loops songs use most'),
      ),
      (
        'Progress',
        [tab('Practice'), find.bySemanticsLabel(RegExp(r'^Your progress\.'))],
        find.text('SKILLS'),
      ),
      (
        'Chord library',
        [tab('Tools'), find.bySemanticsLabel(RegExp(r'^Chord library\.'))],
        find.text('Search, e.g. Am7 or G/B'),
      ),
      (
        'Open a song',
        [tab('Songs'), find.bySemanticsLabel(RegExp('^Amazing Grace, '))],
        find.text('Key and capo'),
      ),
      ('Add a song', [tab('Songs'), find.text('Add a song')], find.text('Import file')),
    ];
    const names = [
      'Tuner',
      'Practice',
      'Songs',
      'Tools',
      'Next lesson',
      'Daily workout',
      'Metronome',
      'Identify',
      'Settings',
      'Lessons',
      'Progressions',
      'Progress',
      'Drill a chord',
      'Changes',
      'All chords',
      'Chord library',
      'Open a song',
      'Add a song',
    ];
    for (final name in names) {
      testWidgets(name, (tester) async {
        final (_, taps, arrived) = routes().firstWhere((r) => r.$1 == name);
        await launch(tester);
        expect(taps.length, lessThanOrEqualTo(2));
        for (final t in taps) {
          await tap(tester, t);
        }
        expect(arrived, findsWidgets, reason: name);
        // Leave the screen so its mic or audio stops before the test ends.
        await tester.pumpWidget(const SizedBox());
      });
    }
  });

  testWidgets('the tab bar always names all four tabs, in the same places', (tester) async {
    await launch(tester);
    Offset where(String label) => tester.getCenter(tab(label));
    final before = {
      for (final l in ['Home', 'Practice', 'Songs', 'Tools']) l: where(l),
    };
    for (final tab in ['Practice', 'Songs', 'Tools', 'Home']) {
      await tap(tester, find.bySemanticsLabel(tab));
      for (final l in before.keys) {
        expect(find.text(l), findsWidgets, reason: '$l shows its name on the $tab tab');
        expect(where(l), before[l], reason: '$l stays put on the $tab tab');
      }
    }
  });

  group('the tuner is one tap from every screen, and Back returns to it', () {
    for (final path in [
      '/home',
      '/practice',
      '/practice/lessons',
      '/practice/progressions',
      '/practice/progress',
      '/practice/chords',
      '/practice/changes',
      '/songs',
      '/songs/play?id=amazing_grace',
      '/tools/metronome',
      '/tools/identify',
      '/tools/chords',
      '/tools/chords/chord?s=Am',
      '/settings',
    ]) {
      testWidgets(path, (tester) async {
        await launch(tester);
        goTo(tester, path);
        await tester.pumpAndSettle();
        await tap(tester, find.bySemanticsLabel('Open the tuner'));
        expect(find.byType(TunerScreen), findsOneWidget);
        await tap(tester, find.bySemanticsLabel('Back'));
        expect(find.byType(TunerScreen), findsNothing);
        expect(location(tester), path);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('during a lesson', (tester) async {
      await launch(tester);
      await tap(tester, find.bySemanticsLabel(RegExp('^Up next: ')));
      await tap(tester, find.bySemanticsLabel('Open the tuner'));
      expect(find.byType(TunerScreen), findsOneWidget);
      await tap(tester, find.bySemanticsLabel('Back'));
      expect(find.text('Start'), findsOneWidget, reason: 'back on the lesson, not the tabs');
    });
  });

  testWidgets('Back on a screen inside a tab returns to that tab’s first screen', (tester) async {
    await launch(tester);
    for (final (name, row, home) in [
      ('Practice', RegExp(r'^Lessons\.'), 'Ways to practise'.toUpperCase()),
      ('Tools', RegExp(r'^Metronome\.'), 'Chord library'),
      // The list keeps its scroll position, so the button at the top may be
      // scrolled away; the song you came from is still there.
      ('Songs', RegExp('^Amazing Grace, '), 'Amazing Grace'),
    ]) {
      await tap(tester, tab(name));
      await tap(tester, find.bySemanticsLabel(row));
      expect(find.bySemanticsLabel('Back'), findsOneWidget, reason: name);
      await tap(tester, find.bySemanticsLabel('Back'));
      expect(location(tester), '/${name.toLowerCase()}', reason: name);
      expect(find.text(home), findsWidgets, reason: name);
    }
  });

  testWidgets('tapping the current tab again goes back to its first screen', (tester) async {
    await launch(tester);
    await tap(tester, tab('Tools'));
    await tap(tester, find.bySemanticsLabel(RegExp(r'^Chord library\.')));
    expect(location(tester), '/tools/chords');
    await tap(tester, tab('Tools'));
    expect(location(tester), '/tools');
  });

  testWidgets('switching tabs keeps each tab where you left it', (tester) async {
    await launch(tester);
    await tap(tester, tab('Practice'));
    await tap(tester, find.bySemanticsLabel(RegExp(r'^Progressions\.')));
    await tap(tester, tab('Songs'));
    await tap(tester, tab('Practice'));
    expect(location(tester), '/practice/progressions');
  });

  testWidgets('links from 0.9 and earlier still land on the right screen', (tester) async {
    await launch(tester);
    for (final (old, now) in [
      ('/learn', '/practice/lessons'),
      ('/tempo', '/tools/metronome'),
      ('/identify', '/tools/identify'),
      ('/chords', '/tools/chords'),
      ('/chords/chord?s=Am', '/tools/chords/chord?s=Am'),
    ]) {
      goTo(tester, old);
      await tester.pumpAndSettle();
      expect(location(tester), now, reason: old);
    }
    goTo(tester, '/tune');
    await tester.pumpAndSettle();
    expect(find.byType(TunerScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving a lesson mid-game asks first; Keep playing stays', (tester) async {
    await launch(tester);
    await tap(tester, find.bySemanticsLabel(RegExp('^Up next: ')));
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Close lesson'));
    await tester.pumpAndSettle();
    expect(find.text('Leave this lesson?'), findsOneWidget);
    await tester.tap(find.text('Keep playing'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Part 1 of'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close lesson'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave lesson'));
    await tester.pumpAndSettle();
    expect(find.text('Ways to practise'.toUpperCase()), findsNothing);
    expect(find.text('Quick tools'.toUpperCase()), findsOneWidget, reason: 'back on Home');
    await tester.pump();
    expect(
      containerOf(tester).read(progressProvider).minutesOn(DateTime.now()),
      greaterThanOrEqualTo(0),
      reason: 'the half-played lesson’s time is saved without an error',
    );
  });

  testWidgets('empty states offer a next step', (tester) async {
    await launch(tester);
    // Home with no songs opened yet.
    await tap(tester, find.text('Pick a first song'));
    expect(location(tester), '/songs');
    // Favourites with none saved.
    goTo(tester, '/tools/chords');
    await tester.pumpAndSettle();
    await tap(tester, find.bySemanticsLabel('Favourites only'));
    await tap(tester, find.text('Browse all chords'));
    expect(find.text('No favourites yet', findRichText: true), findsNothing);
  });

  testWidgets('a song you open shows on Home and opens in one tap', (tester) async {
    final devices = await launch(tester);
    await tap(tester, tab('Songs'));
    await tap(tester, find.bySemanticsLabel(RegExp('^Aura Lee, ')));
    expect(devices.store.setting('songs.recent'), 'aura_lee');
    await tap(tester, tab('Home'));
    await tap(tester, find.bySemanticsLabel('Open Aura Lee'));
    expect(location(tester), '/songs/play?id=aura_lee');
  });

  group('first launch', () {
    testWidgets('asks two questions; Skip goes straight to Home and changes nothing', (
      tester,
    ) async {
      final devices = await launch(tester, onboarded: false);
      expect(find.text('Welcome to Fretlight'), findsOneWidget);
      expect(find.text('1 OF 2'), findsOneWidget);
      await tap(tester, find.bySemanticsLabel('Skip the questions'));
      expect(location(tester), '/home');
      expect(devices.store.setting('onboarding.done'), 'true');
      expect(devices.store.setting('appearance.leftHanded'), isNull);
      expect(containerOf(tester).read(progressProvider).openStage, 0);
    });

    testWidgets('a new left-handed player gets mirrored diagrams and a guided first session', (
      tester,
    ) async {
      final devices = await launch(tester, onboarded: false);
      await tap(tester, find.bySemanticsLabel(RegExp('^I’m new to guitar')));
      expect(find.text('Which hand do you strum with?'), findsOneWidget);
      await tap(tester, find.bySemanticsLabel(RegExp('^Left hand')));
      expect(containerOf(tester).read(appearanceProvider).leftHanded, isTrue);
      expect(devices.store.setting('onboarding.level'), 'beginner');
      // Tune, first chord, first change.
      expect(find.text('Your first session'), findsWidgets);
      expect(find.textContaining('Tune each string'), findsOneWidget);
      expect(find.textContaining('Play a chord'), findsOneWidget);
      expect(find.textContaining('Change chords'), findsOneWidget);
      await tap(tester, find.bySemanticsLabel('Close lesson'));
      expect(location(tester), '/home');
    });

    testWidgets('an experienced player has every stage open', (tester) async {
      await launch(tester, onboarded: false);
      await tap(tester, find.bySemanticsLabel(RegExp('^I play already')));
      await tap(tester, find.bySemanticsLabel(RegExp('^Right hand')));
      expect(location(tester), '/home');
      expect(find.text('Your first session'), findsNothing);
      expect(containerOf(tester).read(progressProvider).openStage, 3);
    });

    testWidgets('a returning player starts at Improver', (tester) async {
      await launch(tester, onboarded: false);
      await tap(tester, find.bySemanticsLabel(RegExp('^I’ve played a little')));
      await tap(tester, find.bySemanticsLabel(RegExp('^Right hand')));
      expect(containerOf(tester).read(progressProvider).openStage, greaterThanOrEqualTo(1));
    });

    testWidgets('Back on the second question returns to the first', (tester) async {
      await launch(tester, onboarded: false);
      await tap(tester, find.bySemanticsLabel(RegExp('^I play already')));
      await tap(tester, find.bySemanticsLabel('Back'));
      expect(find.text('Welcome to Fretlight'), findsOneWidget);
    });
  });

  // A database written the way 0.9.1 wrote it, then reopened, as an app
  // update would. Set up and closed in real time: SQLite work started under
  // the widget tester's fake clock never finishes.
  late AppDatabase db;
  late LocalStore upgraded;
  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    (await LocalStore.open(db))
      ..setSetting('appearance.leftHanded', 'true')
      ..setSetting('metronome.bpm', '92')
      ..setFavorite('Am7', favorite: true)
      ..setCustomTunings([
        Tuning.fromNames('custom_1', 'Open D', const [
          'D2',
          'A2',
          'D3',
          'F#3',
          'A3',
          'D4',
        ], isCustom: true),
      ])
      ..putUserSong('mine', '{title: My song}\n[G]Hello')
      ..putLesson(
        'b.strings',
        StoredLesson(stars: 3, bestScore: 1, attempts: 2, lastPlayed: DateTime(2026, 11)),
      )
      ..putSkill('chord:Em', 55);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    upgraded = await LocalStore.open(db);
  });
  tearDownAll(() => db.close());

  testWidgets('upgrading from 0.9: a saved database opens on Home, with everything kept', (
    tester,
  ) async {
    final devices = await launch(tester, store: upgraded, onboarded: false);
    expect(find.text('Welcome to Fretlight'), findsNothing, reason: 'not asked again');
    expect(location(tester), '/home');
    final s = devices.store;
    expect(s.setting('appearance.leftHanded'), 'true');
    expect(s.setting('metronome.bpm'), '92');
    expect(s.favorites, {'Am7'});
    expect(s.customTunings.single.name, 'Open D');
    expect(s.userSongs.keys, ['mine']);
    expect(s.lessons['b.strings']!.stars, 3);
    expect(s.skills['chord:Em'], 55);
    expect(containerOf(tester).read(progressProvider).totalStars, 3);
    await tap(tester, tab('Songs'));
    expect(find.text('My song'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
