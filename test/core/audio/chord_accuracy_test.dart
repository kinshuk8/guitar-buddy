import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/audio/dsp/chord_detector.dart';
import 'package:fretlight/core/audio/dsp/chord_tracker.dart';
import 'package:fretlight/core/audio/listening.dart';
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
List<(double, ChordReading?)> run(Float32List pcm, {Sensitivity? sensitivity}) {
  final det = ChromaChordDetector(sampleRate: sr);
  final tracker = ChordTracker(detector: det);
  final smoother = ChordSmoother(
    hopSeconds: tracker.hopSeconds(sr),
    floor: sensitivity == null
        ? null
        : NoiseFloor(marginDb: sensitivity.marginDb, frameSeconds: tracker.hopSeconds(sr)),
  );
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

  test('a quiet strum across a room still names the chord (room-relative gate)', () {
    // A phone in raw-mic mode a metre or two from the guitar: peaks around
    // -32 dBFS (the old fixed -45 dB RMS gate rejected most of this), over
    // a -62 dB room hiss that the noise floor has to learn first.
    final rnd = math.Random(4);
    final report = StringBuffer('\n== Quiet strums, room noise at -62 dB ==\n');
    var worst = 1.0;
    for (final sym in required) {
      final v = library.bySymbol(sym)!.voicings.first;
      final strummed = strum(v);
      final quiet = Float32List(sr + strummed.length);
      for (var i = 0; i < quiet.length; i++) {
        final s = i >= sr ? strummed[i - sr] * 0.03 : 0.0;
        quiet[i] = s + (rnd.nextDouble() * 2 - 1) * 0.0014;
      }
      final frames = run(quiet, sensitivity: Sensitivity.normal);
      final shifted = [
        for (final (t, r) in frames)
          if (t >= 1.4) (t - 1, r),
      ];
      final s = score(shifted, library.bySymbol(sym)!.chord);
      worst = math.min(worst, s.hit);
      report.writeln('${sym.padRight(4)} ${(s.hit * 100).toStringAsFixed(0)}%');
    }
    // Printed on purpose: part of the accuracy report.
    // ignore: avoid_print
    print(report);
    expect(worst, greaterThan(0.85));
  });

  test('the room-relative gate ignores the room itself', () {
    final rnd = math.Random(5);
    final hiss = Float32List.fromList([
      for (var i = 0; i < sr * 4; i++) (rnd.nextDouble() * 2 - 1) * 0.0014,
    ]);
    for (final s in Sensitivity.values) {
      expect(run(hiss, sensitivity: s).where((f) => f.$2 != null), isEmpty, reason: s.name);
    }
  });

  group('strum counting', () {
    final open8 = ['C', 'G', 'D', 'A', 'E', 'Am', 'Em', 'Dm'];

    test('one strum is one onset, however long it takes to build up', () {
      for (final c in open8) {
        final v = library.bySymbol(c)!.voicings.first;
        final pcm = Float32List.fromList([...Float32List(sr ~/ 2), ...strum(v)]);
        final strums = {for (final (_, r) in run(pcm, sensitivity: Sensitivity.normal)) ?r?.strum};
        expect(strums, {1}, reason: c);
      }
    });

    test('a new strum over a still-ringing chord counts, and is named', () {
      final g = strum(library.bySymbol('G')!.voicings.first);
      final c = strum(library.bySymbol('C')!.voicings.first);
      // C strummed 1.2 s into G, while G still rings (no silence between).
      final at = (1.2 * sr).round();
      final pcm = Float32List(at + c.length)..setAll(0, g);
      for (var i = 0; i < c.length; i++) {
        pcm[at + i] += c[i];
      }
      final frames = run(pcm, sensitivity: Sensitivity.normal);
      expect(frames.last.$2?.strum, 2);
      expect(frames.last.$2?.chord?.symbol(), 'C');
    });
  });
}
