import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/audio/dsp/chord_detector.dart';
import 'package:fretlight/core/audio/dsp/chord_tracker.dart';
import 'package:fretlight/core/audio/synth/strum.dart';
import 'package:fretlight/core/audio/synth/test_signals.dart';
import 'package:fretlight/core/audio/wav.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/features/chords/domain/chord_library.dart';
import 'package:fretlight/features/identify/domain/chord_smoother.dart';

const sr = 48000;
const pm = PitchMath();

final library = ChordLibrary.fromJson(
  (jsonDecode(File('assets/chords/guitar.json').readAsStringSync()) as Map).cast<String, Object?>(),
);

/// Plays a voicing as a strum, the whole guitar [detune] cents off (a guitar
/// tuned by ear), optionally with room noise.
Float32List strum(Voicing v, {double detune = 0, double? snrDb, int seed = 1}) {
  final f = math.pow(2, detune / 1200).toDouble();
  final hz = [
    for (var s = 0; s < 6; s++)
      if (v.frets[s] case final int fret) pm.hz(Tuning.standard.noteAt(s, fret)) * f else null,
  ];
  final pcm = renderStrum(stringHz: hz, sampleRate: sr, seconds: 2.2);
  return snrDb == null ? pcm : TestSignals.withNoise(pcm, snrDb, seed: seed);
}

/// Smoothed readings for every hop of [pcm], with their times.
List<(double, ChordReading?)> run(Float32List pcm) {
  final det = ChromaChordDetector(sampleRate: sr);
  final tracker = ChordTracker(detector: det);
  final smoother = ChordSmoother(hopSeconds: tracker.hopSeconds(sr));
  final out = <(double, ChordReading?)>[];
  var t = det.windowSize / sr;
  for (final e in tracker.push(pcm)) {
    out.add((t, smoother.update(e)));
    t += tracker.hopSeconds(sr);
  }
  return out;
}

/// Share of frames (after the strum has settled, 0.4 s) naming [expected].
({double hit, double notSure, String commonWrong}) score(
  List<(double, ChordReading?)> frames,
  Chord expected,
) {
  final judged = frames.where((f) => f.$1 >= 0.4).toList();
  var hit = 0;
  var unsure = 0;
  final wrong = <String, int>{};
  for (final (_, r) in judged) {
    final c = r?.chord;
    if (c == expected) {
      hit++;
    } else if (c == null) {
      unsure++;
    } else {
      wrong.update(c.symbol(), (n) => n + 1, ifAbsent: () => 1);
    }
  }
  final top = wrong.entries.fold<MapEntry<String, int>?>(
    null,
    (a, b) => a == null || b.value > a.value ? b : a,
  );
  return (
    hit: hit / judged.length,
    notSure: unsure / judged.length,
    commonWrong: top == null ? '' : top.key,
  );
}

void main() {
  const required = ['C', 'A', 'G', 'E', 'D', 'Am', 'Em', 'Dm'];
  const extras = [
    'F',
    'Bm',
    'A7',
    'E7',
    'D7',
    'G7',
    'B7',
    'Cmaj7',
    'Am7',
    'Em7',
    'Dsus4',
    'Asus2',
    'Fmaj7',
  ];

  test('accuracy report: common chords, strummed (synthesised)', () {
    final report = StringBuffer('\n== Chord identifier accuracy (synthesised strums) ==\n')
      ..writeln('Frames after 0.4 s naming the right chord; 4 takes per chord:')
      ..writeln('in tune and ±12 cents, each clean and with 25 dB SNR room noise.\n')
      ..writeln('chord    shape               correct   not sure   most common miss');
    var requiredWorst = 1.0;
    for (final sym in [...required, ...extras]) {
      final entry = library.bySymbol(sym)!;
      final v = entry.voicings.first;
      var hit = 0.0;
      var unsure = 0.0;
      final misses = <String>{};
      var takes = 0;
      for (final detune in [0.0, -12.0, 12.0]) {
        for (final snr in [null, 25.0]) {
          if (detune != 0 && snr == null) continue; // 4 takes: (0,clean) (0,noisy) (±12,noisy)
          final s = score(run(strum(v, detune: detune, snrDb: snr, seed: takes + 3)), entry.chord);
          hit += s.hit;
          unsure += s.notSure;
          if (s.commonWrong.isNotEmpty) misses.add(s.commonWrong);
          takes++;
        }
      }
      hit /= takes;
      unsure /= takes;
      if (required.contains(sym)) requiredWorst = math.min(requiredWorst, hit);
      report.writeln(
        '${sym.padRight(8)} ${v.frets.map((f) => f ?? 'x').join(' ').padRight(18)}  '
        '${(hit * 100).toStringAsFixed(0).padLeft(5)}%    ${(unsure * 100).toStringAsFixed(0).padLeft(5)}%   '
        '${misses.join(', ')}',
      );
    }
    // Printed on purpose: the milestone's accuracy report.
    // ignore: avoid_print
    print(report);
    // Definition of done: the eight open chords are reliable when clearly strummed.
    expect(requiredWorst, greaterThan(0.9));
  });

  test('a single string reads as a note, never as a confident chord', () {
    for (final (i, note) in Tuning.standard.strings.indexed) {
      final hz = List<double?>.filled(6, null)..[i] = pm.hz(note);
      final frames = run(renderStrum(stringHz: hz, sampleRate: sr, seconds: 1.5));
      final settled = frames.where((f) => f.$1 >= 0.4 && f.$2 != null).map((f) => f.$2!).toList();
      final asNote = settled.where((r) => r.singleNote == note.pitchClass).length;
      expect(asNote / settled.length, greaterThan(0.8), reason: note.name());
    }
  });

  test('steady background sound never gets a chord name', () {
    // A room with a hum and a radio: tonal, chord-like, but no strum.
    // About -38 dBFS: clearly audible on a phone mic, well under a strum.
    final hum = TestSignals.mix([
      for (final n in ['G2', 'B3', 'D4', 'F4'])
        TestSignals.sine(hz: pm.hz(Note.parse(n)), sampleRate: sr, seconds: 4),
    ], amplitude: 0.03);
    expect(run(hum).where((f) => f.$2?.chord != null), isEmpty);
  });

  test('silence shows nothing; noise is never a confident chord', () {
    expect(run(Float32List(sr)).every((f) => f.$2 == null), isTrue);
    // Broadband room noise at -20 dBFS: loud enough to pass the level gate.
    final rnd = math.Random(9);
    final noise = Float32List.fromList([
      for (var i = 0; i < sr * 2; i++) (rnd.nextDouble() * 2 - 1) * 0.17,
    ]);
    final confident = run(noise).where((f) => (f.$2?.confidence ?? 0) > 0.6);
    expect(confident, isEmpty);
  });

  test('a chord change is followed within a few frames, without flicker', () {
    final c = strum(library.bySymbol('C')!.voicings.first);
    final g = strum(library.bySymbol('G')!.voicings.first);
    final both = Float32List(c.length + g.length)
      ..setAll(0, c)
      ..setAll(c.length, g);
    final frames = run(both);
    final labels = [
      for (final (t, r) in frames)
        if (t > 0.4) r?.chord?.symbol(),
    ];
    // Collapse runs: the sequence should be C … G, nothing in between.
    final runs = <String?>[];
    for (final l in labels) {
      if (runs.isEmpty || runs.last != l) runs.add(l);
    }
    expect(runs.whereType<String>().toList(), ['C', 'G']);
    final switchAt = frames.firstWhere((f) => f.$1 > 2.2 && f.$2?.chord?.symbol() == 'G').$1;
    expect(switchAt - 2.2, lessThan(0.7), reason: 'G recognised soon after it is strummed');
  });

  // Real recordings: test/fixtures/wav/chord_<Symbol>_<anything>.wav
  final dir = Directory('test/fixtures/wav');
  final files = dir.existsSync()
      ? dir
            .listSync()
            .whereType<File>()
            .where((f) => f.uri.pathSegments.last.startsWith('chord_'))
            .toList()
      : <File>[];
  test('recorded chords (${files.length} fixtures)', () {
    final report = StringBuffer('\n== Chord identifier on recordings ==\n');
    for (final f in files) {
      final name = f.uri.pathSegments.last;
      // `Cs` = C#: `#` is awkward in file names, and Chord.tryParse reads both.
      final chord = Chord.tryParse(name.split('_')[1]);
      if (chord == null) continue;
      final wav = decodeWav(f.readAsBytesSync());
      expect(wav.sampleRate, sr, reason: '$name: record at 48 kHz');
      final s = score(run(wav.samples), chord);
      report.writeln(
        '$name  correct ${(s.hit * 100).toStringAsFixed(0)}%  not sure ${(s.notSure * 100).toStringAsFixed(0)}%  ${s.commonWrong}',
      );
    }
    // Printed on purpose: the real-guitar chord report.
    // ignore: avoid_print
    print(report);
  }, skip: files.isEmpty ? 'No chord recordings in test/fixtures/wav yet' : false);
}
