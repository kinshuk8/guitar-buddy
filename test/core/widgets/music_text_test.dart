import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/widgets/music_text.dart';

void main() {
  group('TuningState.fromCents (in tune within ±3 cents)', () {
    final cases = {
      -50.0: TuningState.flat,
      -3.01: TuningState.flat,
      -3.0: TuningState.inTune,
      0.0: TuningState.inTune,
      3.0: TuningState.inTune,
      3.01: TuningState.sharp,
      40.0: TuningState.sharp,
    };
    for (final MapEntry(key: cents, value: state) in cases.entries) {
      test('$cents -> ${state.name}', () => expect(TuningState.fromCents(cents), state));
    }
  });

  test('every tuning state has a distinct icon and word, not just a colour', () {
    expect(TuningState.values.map((s) => s.icon).toSet(), hasLength(3));
    expect(TuningState.values.map((s) => s.label).toSet(), hasLength(3));
  });

  test('chords are spoken, not spelled', () {
    expect(spokenChord(Chord.parse('F#m7')), 'F sharp minor 7th');
    expect(spokenChord(Chord.parse('Bb')), 'B flat major');
    expect(spokenChord(Chord.parse('G/B')), 'G major over B');
    expect(spokenChord(Chord.parse('Ebm')), 'E flat minor');
  });

  testWidgets('ChordSymbol exposes the spoken label to screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: StageThemeData.dark(),
        home: Scaffold(body: ChordSymbol(Chord.parse('Bbmaj7'))),
      ),
    );
    expect(find.bySemanticsLabel('B flat major 7th'), findsOneWidget);
    handle.dispose();
  });
}
