import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/audio/dsp/chord_detector.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/features/chords/domain/chord_library.dart';
import 'package:fretlight/features/practice/domain/practice_session.dart';
import 'package:fretlight/features/songs/domain/backing.dart';

const sr = 48000;

/// Strum onsets: where 10 ms energy jumps well above the frame before,
/// even while the last chord still rings.
List<int> strumOnsets(Float32List pcm, {double rise = 4}) {
  const frame = 480;
  final out = <int>[];
  var prev = 1e-9;
  var cooldown = 0;
  for (var i = 0; i + frame <= pcm.length; i += frame) {
    var e = 0.0;
    for (var j = i; j < i + frame; j++) {
      e += pcm[j] * pcm[j];
    }
    e /= frame;
    if (cooldown > 0) {
      cooldown--;
    } else if (e > 1e-6 && e > prev * rise) {
      out.add(i);
      cooldown = 10;
    }
    prev = e;
  }
  return out;
}

final library = ChordLibrary.fromJson(
  (jsonDecode(File('assets/chords/guitar.json').readAsStringSync()) as Map).cast<String, Object?>(),
);

List<BackingEvent> bars(List<String> chords, {int beatsPerBar = 4}) => [
  for (final (i, c) in chords.indexed)
    BackingEvent(
      startBeat: (i * beatsPerBar).toDouble(),
      beats: beatsPerBar.toDouble(),
      frets: library.bySymbol(c)!.voicings.first.frets,
    ),
];

void main() {
  test('one strum per bar lands exactly on each bar line', () {
    final pcm = renderBacking(
      events: bars(['G', 'C', 'D', 'G']),
      beatsPerBar: 4,
      bpm: 120,
      sampleRate: sr,
      fromBeat: 0,
      toBeat: 16,
    );
    final onsets = strumOnsets(pcm);
    expect(onsets, hasLength(4));
    for (final (i, o) in onsets.indexed) {
      // 120 BPM, 4 beats: a bar every 2 s.
      expect(o / sr, closeTo(i * 2.0, 0.02), reason: 'bar ${i + 1}');
    }
  });

  test('each bar sounds like its chord (checked by the identifier)', () {
    final det = ChromaChordDetector(sampleRate: sr);
    final chords = ['C', 'Am', 'F', 'G'];
    final pcm = renderBacking(
      events: bars(chords),
      beatsPerBar: 4,
      bpm: 100,
      sampleRate: sr,
      fromBeat: 0,
      toBeat: 16,
      pattern: StrumPattern.folk,
    );
    for (final (i, symbol) in chords.indexed) {
      // Mid-bar, well after the change.
      final start = ((i * 4 + 1.2) * 60 / 100 * sr).round();
      final e = det.detect(Float32List.sublistView(pcm, start, start + det.windowSize));
      // The chord, give or take a note the identifier may add (C/Cmaj7).
      final heard = e.best!.chord;
      expect(
        PracticeSession.judge(Chord.parse(symbol), heard),
        isNot(Verdict.miss),
        reason: '$symbol heard as ${heard.symbol()}',
      );
    }
  });

  test('patterns: strokes per bar for 4/4 and 3/4', () {
    expect(StrumPattern.bar.strokes(4), hasLength(1));
    expect(StrumPattern.beats.strokes(3), hasLength(3));
    expect(StrumPattern.folk.strokes(4).map((s) => s.$1), [0, 1, 1.5, 2.5, 3, 3.5]);
    expect(
      StrumPattern.folk.strokes(3).where((s) => !s.$2),
      hasLength(2),
      reason: 'two up-strokes',
    );
  });

  test('rendering from mid-song starts on time; silent bars stay silent', () {
    final events = [
      ...bars(['G', 'C']),
      const BackingEvent(startBeat: 8, beats: 4, frets: null), // N.C.
      BackingEvent(startBeat: 12, beats: 4, frets: library.bySymbol('D')!.voicings.first.frets),
    ];
    final pcm = renderBacking(
      events: events,
      beatsPerBar: 4,
      bpm: 120,
      sampleRate: sr,
      fromBeat: 4,
      toBeat: 16,
    );
    final onsets = strumOnsets(pcm);
    // C at 0 s (beat 4), nothing at beat 8, D at beat 12 = 4 s.
    expect(onsets.map((o) => (o / sr).toStringAsFixed(1)), ['0.0', '4.0']);
    // The N.C. bar (2-4 s) is damped, not ringing.
    var tail = 0.0;
    for (var i = (2.2 * sr).round(); i < (3.9 * sr).round(); i++) {
      tail = tail < pcm[i].abs() ? pcm[i].abs() : tail;
    }
    expect(tail, lessThan(0.01));
  });

  test('a click track marks every beat', () {
    final pcm = renderBacking(
      events: const [],
      beatsPerBar: 4,
      bpm: 120,
      sampleRate: sr,
      fromBeat: 0,
      toBeat: 4,
      click: true,
    );
    expect(strumOnsets(pcm), hasLength(4));
  });
}
