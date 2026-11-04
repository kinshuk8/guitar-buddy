import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/app/router.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/features/settings/application/appearance.dart';

class FretlightApp extends ConsumerWidget {
  const FretlightApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appearanceProvider.select((a) => a.themeMode));
    return MaterialApp.router(
      title: 'Fretlight',
      debugShowCheckedModeBanner: false,
      theme: StageThemeData.light(),
      darkTheme: StageThemeData.dark(),
      themeMode: themeMode,
      routerConfig: ref.watch(routerProvider),
      // Status bar icons follow the theme on every screen, including the
      // tab screens that have no AppBar to set them.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: child!,
      ),
    );
  }
}
