import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/audio/dsp/mpm.dart';
import 'package:fretlight/core/audio/dsp/pitch_detector.dart';
import 'package:fretlight/core/audio/synth/karplus_strong.dart';
import 'package:fretlight/core/audio/wav.dart';
import 'package:fretlight/core/music/music.dart';

import 'detector_harness.dart';

/// Real recordings: `test/fixtures/wav/<NOTE>_<anything>.wav`, e.g.
/// `E2_open_acoustic_iphone.wav`. See the README in that folder.
void main() {
  test('WAV encode/decode round-trips', () {
    final s = KarplusStrong(sampleRate: 44100).pluck(hz: 110, seconds: 0.2);
    final back = decodeWav(encodeWav16(s, 44100));
    expect(back.sampleRate, 44100);
    expect(back.samples.length, s.length);
    for (var i = 0; i < s.length; i += 97) {
      expect(back.samples[i], closeTo(s[i], 1 / 16000));
    }
  });

  final dir = Directory('test/fixtures/wav');
  final files = dir.existsSync()
      ? (dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.wav'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];

  test('recorded open strings (${files.length} fixtures)', () {
    const pm = PitchMath();
    final rows = <DetectorScore>[];
    for (final f in files) {
      final name = f.uri.pathSegments.last;
      final note = Note.tryParse(name.split('_').first);
      if (note == null) continue;
      final wav = decodeWav(f.readAsBytesSync());
      final g = analysisGeometry(wav.sampleRate);
      rows.add(
        evaluate(
          name,
          MpmDetector(sampleRate: wav.sampleRate, windowSize: g.window),
          wav.samples,
          expectedHz: pm.hz(note),
          sampleRate: wav.sampleRate,
          skipSeconds: 0.3,
        ),
      );
    }
    // Printed on purpose: this is the real-guitar accuracy report.
    // ignore: avoid_print
    print(formatReport('MPM on recorded fixtures', rows));
    for (final r in rows) {
      // Recordings of a guitar tuned by ear won't be at 0 cents; the hard
      // requirement is no octave errors and a steady reading.
      expect(r.grossErrors, 0, reason: r.label);
      expect(r.detectionRate, greaterThan(0.7), reason: r.label);
    }
  }, skip: files.isEmpty ? 'No recordings in test/fixtures/wav yet' : false);
}
