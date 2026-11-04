import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Theme mode and handedness. In memory for now; persisted via Drift once
/// the database lands in Milestone 3.
@immutable
final class Appearance {
  const Appearance({this.themeMode = ThemeMode.system, this.leftHanded = false});

  final ThemeMode themeMode;
  final bool leftHanded;

  Appearance copyWith({ThemeMode? themeMode, bool? leftHanded}) =>
      Appearance(themeMode: themeMode ?? this.themeMode, leftHanded: leftHanded ?? this.leftHanded);
}

final class AppearanceController extends Notifier<Appearance> {
  @override
  Appearance build() => const Appearance();

  void setThemeMode(ThemeMode mode) => state = state.copyWith(themeMode: mode);

  void setLeftHanded({required bool value}) => state = state.copyWith(leftHanded: value);
}

final appearanceProvider = NotifierProvider<AppearanceController, Appearance>(
  AppearanceController.new,
);
