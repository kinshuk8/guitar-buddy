import 'dart:math' as math;
import 'dart:typed_data';

/// The metronome's voices, loudest and highest first, so the downbeat is
/// recognisable by pitch as well as level (it must not rely on volume alone
/// on a phone speaker).
enum ClickVoice {
  strong(hz: 1760, gain: 1, ms: 32),
  medium(hz: 1320, gain: 0.8, ms: 30),
  normal(hz: 990, gain: 0.62, ms: 28),
  subdivision(hz: 1480, gain: 0.26, ms: 16);

  ClickVoice({required this.hz, required this.gain, required this.ms});

  final double hz;
  final double gain;
  final int ms;
}

/// A short wood-block-like click: a sine with a quieter octave above, a
/// 0.4 ms attack (no DC step, so no speaker pop) and a fast exponential
/// decay that is silent well before the next sixteenth at 300 BPM (50 ms).
Float32List renderClick(ClickVoice voice, int sampleRate) {
  final n = voice.ms * sampleRate ~/ 1000;
  final out = Float32List(n);
  final attack = math.max(1, (0.0004 * sampleRate).round());
  final tau = voice.ms / 1000 / 5; // ~-43 dB by the end
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final env = math.min(1, i / attack) * math.exp(-t / tau);
    final phase = 2 * math.pi * voice.hz * t;
    out[i] = voice.gain * env * (0.8 * math.sin(phase) + 0.2 * math.sin(2 * phase));
  }
  return out;
}
