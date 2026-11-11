import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/app/app.dart';
import 'package:fretlight/app/shell.dart';
import 'package:fretlight/core/storage/local_store.dart';
import 'package:integration_test/integration_test.dart';

/// Frame times while using the app on a device: build (UI thread) and
/// raster (GPU thread) for each scenario. Run with:
///   flutter test integration_test -d DEVICE
/// Debug builds run unoptimised code, so their times are an upper bound.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  final frames = <FrameTiming>[];
  void collect(List<FrameTiming> t) => frames.addAll(t);

  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  Finder tab(String label) =>
      find.descendant(of: find.byType(StageNavBar), matching: find.bySemanticsLabel(label));

  Future<void> tap(WidgetTester tester, Finder f, {int settleMs = 700}) async {
    if (f.evaluate().isEmpty) {
      // Below the fold: scroll the page (the first vertical list) to it.
      final page = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      );
      await tester.scrollUntilVisible(f, 300, scrollable: page.first);
    }
    await tester.ensureVisible(f.first);
    await tester.tap(f.first);
    await tester.pump();
    await wait(settleMs);
  }

  Future<void> fling(WidgetTester tester, Finder list, {int times = 3}) async {
    for (var i = 0; i < times; i++) {
      await tester.fling(list.first, const Offset(0, -900), 2500);
      await tester.pump();
      await wait(900);
    }
    for (var i = 0; i < times; i++) {
      await tester.fling(list.first, const Offset(0, 900), 2500);
      await tester.pump();
      await wait(900);
    }
  }

  final report = <String, String>{};

  Future<void> measure(String name, Future<void> Function() body) async {
    await wait(300);
    frames.clear();
    await body();
    await wait(300);
    if (frames.isEmpty) {
      report[name] = 'no frames';
      return;
    }
    List<double> ms(Duration Function(FrameTiming) f) =>
        frames.map((t) => f(t).inMicroseconds / 1000).toList()..sort();
    String q(List<double> v, double p) => v[((v.length - 1) * p).round()].toStringAsFixed(1);
    final build = ms((t) => t.buildDuration);
    final raster = ms((t) => t.rasterDuration);
    final slow = frames
        .where(
          (t) => t.buildDuration.inMicroseconds > 16667 || t.rasterDuration.inMicroseconds > 16667,
        )
        .length;
    report[name] =
        '${frames.length} frames · build p50 ${q(build, .5)} p90 ${q(build, .9)} p99 ${q(build, .99)} '
        'max ${q(build, 1)} ms · raster p50 ${q(raster, .5)} p90 ${q(raster, .9)} p99 ${q(raster, .99)} '
        'max ${q(raster, 1)} ms · over 16.7 ms: $slow';
  }

  testWidgets('frame times across the app', (tester) async {
    SchedulerBinding.instance.addTimingsCallback(collect);
    final store = LocalStore.memory(settings: {'onboarding.done': 'true'});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localStoreProvider.overrideWithValue(store)],
        child: const FretlightApp(),
      ),
    );
    await wait(1500);

    // Twice: the first pass includes compiling each screen's code for the
    // first time (debug builds compile as they go); the second is what
    // using the app feels like.
    for (final pass in ['first', 'again']) {
      await measure('$pass · tabs: switching all four', () async {
        for (final t in [
          'Practice',
          'Songs',
          'Tools',
          'Home',
          'Practice',
          'Songs',
          'Tools',
          'Home',
        ]) {
          await tap(tester, tab(t), settleMs: 500);
        }
      });
      await measure('$pass · home: scroll', () => fling(tester, find.byType(Scrollable), times: 1));
      await measure('$pass · practice → lessons: open and fling the 55-lesson list', () async {
        await tap(tester, tab('Practice'));
        await tap(tester, find.bySemanticsLabel(RegExp(r'^Lessons\.')));
        await fling(tester, find.byType(Scrollable));
        await tap(tester, find.bySemanticsLabel('Back'));
      });
      await measure('$pass · practice → chords: open and fling', () async {
        await tap(tester, find.bySemanticsLabel(RegExp(r'^Chords\.')));
        await fling(tester, find.byType(Scrollable), times: 2);
        await tap(tester, find.bySemanticsLabel('Back'));
      });
      await measure('$pass · practice → changes: pick chords', () async {
        await tap(tester, find.bySemanticsLabel(RegExp(r'^Changes\.')));
        await tap(tester, find.bySemanticsLabel('Am').first, settleMs: 300);
        await tap(tester, find.bySemanticsLabel('D').last, settleMs: 300);
        await tap(tester, find.bySemanticsLabel('Back'));
      });
      await measure('$pass · lesson: open, intro, close', () async {
        await tap(tester, tab('Home'));
        await tap(tester, find.bySemanticsLabel(RegExp('^Up next: ')), settleMs: 1000);
        await tap(tester, find.bySemanticsLabel('Close lesson'), settleMs: 1000);
      });
      await measure('$pass · songs: fling the list', () async {
        await tap(tester, tab('Songs'));
        await fling(tester, find.byType(Scrollable), times: 2);
      });
      await measure('$pass · play-along: open, play 6 s, pause', () async {
        await tap(tester, find.bySemanticsLabel(RegExp('^Amazing Grace, ')), settleMs: 1500);
        await tap(tester, find.bySemanticsLabel('Play'), settleMs: 6000);
        await tap(tester, find.bySemanticsLabel('Pause'), settleMs: 500);
        await tap(tester, find.bySemanticsLabel('Back'));
      });
      await measure('$pass · tools → chord library: fling, change root, open a chord', () async {
        await tap(tester, tab('Tools'));
        await tap(tester, find.bySemanticsLabel(RegExp(r'^Chord library\.')), settleMs: 1500);
        await fling(tester, find.byType(Scrollable), times: 2);
        await tap(tester, find.bySemanticsLabel('Root D'), settleMs: 600);
        await tap(tester, find.bySemanticsLabel(RegExp(r'^D major, \d+ shapes?$')), settleMs: 800);
        await tap(tester, find.text('Play'), settleMs: 2500);
        await tap(tester, find.bySemanticsLabel('Back'));
        // The list is scrolled away from its header: the tab goes back to Tools.
        await tap(tester, tab('Tools'));
      });
      await measure('$pass · tuner: open, listen 4 s, close', () async {
        await tap(tester, find.bySemanticsLabel(RegExp(r'^Tuner\.')), settleMs: 4000);
        await tap(tester, find.bySemanticsLabel('Back'));
      });
      await measure('$pass · metronome: run 4 s at 160 BPM', () async {
        await tap(tester, find.bySemanticsLabel(RegExp(r'^Metronome\.')));
        for (var i = 0; i < 6; i++) {
          await tap(tester, find.bySemanticsLabel('Faster'), settleMs: 50);
        }
        await tap(tester, find.text('Start'), settleMs: 4000);
        await tap(tester, find.text('Stop'), settleMs: 300);
        await tap(tester, find.bySemanticsLabel('Back'));
      });
    }

    SchedulerBinding.instance.removeTimingsCallback(collect);
    binding.reportData = {'frames': report};
    for (final MapEntry(:key, :value) in report.entries) {
      debugPrint('FRAMES $key: $value');
    }
    // Leave nothing running.
    await tester.pumpWidget(const SizedBox());
    expect(report, isNotEmpty);
    expect(PlatformDispatcher.instance, isNotNull);
  });
}
