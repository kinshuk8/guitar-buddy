import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/audio/listening.dart';
import 'package:fretlight/core/storage/local_store.dart';

final sensitivityProvider = NotifierProvider<SensitivityController, Sensitivity>(
  SensitivityController.new,
);

final class SensitivityController extends Notifier<Sensitivity> {
  static const _key = 'listen.sensitivity';

  @override
  Sensitivity build() =>
      Sensitivity.values.asNameMap()[ref.watch(localStoreProvider).setting(_key)] ??
      Sensitivity.normal;

  void set(Sensitivity s) {
    state = s;
    ref.read(localStoreProvider).setSetting(_key, s.name);
  }
}
