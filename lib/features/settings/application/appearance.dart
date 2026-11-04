import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/storage/local_store.dart';

/// Theme mode and handedness, saved on the device.
@immutable
final class Appearance {
  const Appearance({this.themeMode = ThemeMode.system, this.leftHanded = false});

  final ThemeMode themeMode;
  final bool leftHanded;

  Appearance copyWith({ThemeMode? themeMode, bool? leftHanded}) =>
      Appearance(themeMode: themeMode ?? this.themeMode, leftHanded: leftHanded ?? this.leftHanded);
}

final class AppearanceController extends Notifier<Appearance> {
  static const _themeKey = 'appearance.theme';
  static const _leftKey = 'appearance.leftHanded';

  late LocalStore _store;

  @override
  Appearance build() {
    _store = ref.watch(localStoreProvider);
    return Appearance(
      themeMode: ThemeMode.values.asNameMap()[_store.setting(_themeKey)] ?? ThemeMode.system,
      leftHanded: _store.setting(_leftKey) == 'true',
    );
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _store.setSetting(_themeKey, mode.name);
  }

  void setLeftHanded({required bool value}) {
    state = state.copyWith(leftHanded: value);
    _store.setSetting(_leftKey, value.toString());
  }
}

final appearanceProvider = NotifierProvider<AppearanceController, Appearance>(
  AppearanceController.new,
);
