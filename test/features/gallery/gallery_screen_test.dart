import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/app/router.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/painting/fretboard.dart';
import 'package:fretlight/features/gallery/presentation/gallery_screen.dart';

import '../../support/test_app.dart';

Widget _host({required ThemeData theme, bool reducedMotion = false}) => TestDevices().wrap(
  MaterialApp(
    theme: theme,
    home: MediaQuery(
      data: MediaQueryData(size: const Size(390, 844), disableAnimations: reducedMotion),
      child: const GalleryScreen(),
    ),
  ),
);

void main() {
  testWidgets('app boots into Learn, in a shell with six tabs', (tester) async {
    await tester.pumpWidget(TestDevices().app());
    await tester.pumpAndSettle();
    // Every tab is labelled for screen readers; only the active one shows text.
    for (final label in ['Learn', 'Tune', 'Identify', 'Chords', 'Tempo', 'Songs']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    expect(find.text('Learn'), findsWidgets);
    // The gallery is a debug-only route (linked from the bottom of Songs).
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    unawaited(container.read(routerProvider).push('/gallery'));
    await tester.pumpAndSettle();
    expect(find.text('Gallery'), findsOneWidget);
  });

  for (final (name, theme) in [
    ('dark', StageThemeData.dark()),
    ('light', StageThemeData.light()),
  ]) {
    testWidgets('gallery renders in $name theme without overflow', (tester) async {
      await tester.pumpWidget(_host(theme: theme));
      await tester.pumpAndSettle();
      // Scroll the whole page to build every section.
      await tester.dragUntilVisible(
        find.text('COLOUR'),
        find.byType(Scrollable).first,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('fretboard tap shows the note and its positions; strum settles', (tester) async {
    await tester.pumpWidget(_host(theme: StageThemeData.dark()));
    await tester.pumpAndSettle();
    final board = find.byType(Fretboard);
    // Centre the board so no part of it is under the frosted app bar.
    await Scrollable.ensureVisible(tester.element(board), alignment: 0.5);
    await tester.pumpAndSettle();
    // Tap near the right end of the top string (high E, ~fret 12 region).
    final rect = tester.getRect(board);
    await tester.tapAt(Offset(rect.right - 5, rect.top + rect.height * 0.08));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('E5 · 659.26 Hz'), findsOneWidget);
    // The vibration ticker must stop by itself (pumpAndSettle would time out otherwise).
    await tester.pumpAndSettle();
  });

  testWidgets('reduced motion is reported and nothing animates forever', (tester) async {
    await tester.pumpWidget(_host(theme: StageThemeData.dark(), reducedMotion: true));
    await tester.pumpAndSettle();
    expect(find.text('Reduced motion on'), findsOneWidget);
  });
}
