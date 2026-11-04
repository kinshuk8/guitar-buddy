import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:fretlight/core/audio/dsp/chord_detector.dart';
import 'package:fretlight/core/audio/dsp/chord_tracker.dart';
import 'package:fretlight/core/audio/dsp/mpm.dart';
import 'package:fretlight/core/audio/dsp/pitch_detector.dart';
import 'package:fretlight/core/audio/dsp/pitch_tracker.dart';
import 'package:fretlight/core/audio/dsp/yin.dart';

enum DetectorKind { mpm, yin }

/// Runs pitch tracking (and, for the identifier, chord detection) in a
/// background isolate so the UI thread only handles small result messages.
///
/// PCM goes in as [TransferableTypedData]: the bytes are moved to the
/// isolate rather than copied. Results come back as [PitchFrame]s.
final class DspWorker {
  DspWorker._(this._isolate, this._toWorker, this._fromWorker, this.frames, this.chordFrames);

  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _fromWorker;

  /// Analysis frames, in order.
  final Stream<PitchFrame> frames;

  /// Chord estimates (~12 per second), only when spawned with `chords`.
  final Stream<ChordEstimate> chordFrames;

  static Future<DspWorker> spawn({
    required int sampleRate,
    DetectorKind kind = DetectorKind.mpm,
    bool chords = false,
  }) async {
    final fromWorker = ReceivePort();
    final isolate = await Isolate.spawn(_main, (
      fromWorker.sendPort,
      sampleRate,
      kind,
      chords,
    ), debugName: 'fretlight-dsp');
    final messages = fromWorker.asBroadcastStream();
    final toWorker = await messages.first as SendPort;
    final frames = messages
        .where((m) => m is List<PitchFrame>)
        .expand((m) => m as List<PitchFrame>);
    final chordFrames = messages
        .where((m) => m is List<ChordEstimate>)
        .expand((m) => m as List<ChordEstimate>);
    return DspWorker._(
      isolate,
      toWorker,
      fromWorker,
      frames.asBroadcastStream(),
      chordFrames.asBroadcastStream(),
    );
  }

  /// Sends a chunk of PCM16 little-endian mono samples.
  void push(Uint8List pcm16) => _toWorker.send(TransferableTypedData.fromList([pcm16]));

  /// Forgets buffered audio (e.g. after an interruption) without respawning.
  void reset() => _toWorker.send(#reset);

  void dispose() {
    _toWorker.send(null);
    _fromWorker.close();
    _isolate.kill();
  }

  static void _main((SendPort, int, DetectorKind, bool) args) {
    final (out, sampleRate, kind, withChords) = args;
    final inbox = ReceivePort();
    out.send(inbox.sendPort);

    final g = analysisGeometry(sampleRate);
    final detector = switch (kind) {
      DetectorKind.mpm => MpmDetector(sampleRate: sampleRate, windowSize: g.window),
      DetectorKind.yin => YinDetector(sampleRate: sampleRate, windowSize: g.window),
    };
    final tracker = PitchTracker(detector: detector, hop: g.hop);
    final chordTracker = withChords
        ? ChordTracker(detector: ChromaChordDetector(sampleRate: sampleRate))
        : null;
    var floats = Float32List(0);

    inbox.listen((message) {
      if (message == null) {
        inbox.close();
        return;
      }
      if (message == #reset) {
        tracker.reset();
        chordTracker?.reset();
        return;
      }
      final bytes = (message as TransferableTypedData).materialize();
      final count = bytes.lengthInBytes ~/ 2;
      if (floats.length != count) floats = Float32List(count);
      final data = bytes.asByteData();
      for (var i = 0; i < count; i++) {
        floats[i] = data.getInt16(i * 2, Endian.little) / 32768;
      }
      final frames = tracker.push(floats);
      if (frames.isNotEmpty) out.send(frames);
      if (chordTracker != null) {
        final estimates = chordTracker.push(floats);
        // The top candidates are all the smoother needs; keeps messages small.
        if (estimates.isNotEmpty) out.send([for (final e in estimates) e.trimmed(24)]);
      }
    });
  }
}

/// Converts float samples to PCM16 little-endian bytes (tests and fakes).
Uint8List floatToPcm16(Float32List samples) {
  final bytes = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    bytes.setInt16(i * 2, v, Endian.little);
  }
  return bytes.buffer.asUint8List();
}
