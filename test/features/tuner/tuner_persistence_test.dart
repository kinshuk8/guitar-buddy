import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/storage/local_store.dart';
import 'package:fretlight/features/tuner/application/tuner_controller.dart';

import '../../support/fake_audio_input.dart';

ProviderContainer containerWith(LocalStore store) {
  final c = ProviderContainer(
    overrides: [
      audioInputProvider.overrideWithValue(FakeAudioInputSource()),
      localStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('tuning, reference pitch and custom tunings come back after a restart', () {
    final store = LocalStore.memory();
    final first = containerWith(store);
    final open = Tuning.fromNames('custom_1', 'Open D', const [
      'D2',
      'A2',
      'D3',
      'F#3',
      'A3',
      'D4',
    ], isCustom: true);
    first.read(tunerProvider.notifier)
      ..setA4(432)
      ..saveCustomTuning(open);

    final second = containerWith(store).read(tunerProvider);
    expect(second.a4, 432);
    expect(second.tuning.id, 'custom_1');
    expect(second.customTunings.single.name, 'Open D');
  });

  test('a saved value out of range is clamped; an unknown tuning falls back', () {
    final store = LocalStore.memory(settings: {'tuner.a4': '9000', 'tuner.tuning': 'gone'});
    final s = containerWith(store).read(tunerProvider);
    expect(s.a4, PitchMath.maxA4);
    expect(s.tuning.id, 'standard');
  });
}
