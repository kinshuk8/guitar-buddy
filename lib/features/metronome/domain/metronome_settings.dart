import 'dart:typed_data';

import 'package:fretlight/core/audio/synth/click.dart';
import 'package:meta/meta.dart';

/// How a beat sounds. Tapping a beat in the UI cycles through these.
enum Accent {
  strong,
  medium,
  normal,
  mute;

  Accent get next => values[(index + 1) % values.length];

  ClickVoice? get voice => switch (this) {
    strong => ClickVoice.strong,
    medium => ClickVoice.medium,
    normal => ClickVoice.normal,
    mute => null,
  };
}

/// Clicks per beat.
enum Subdivision {
  none(1, 'None'),
  eighths(2, '8ths'),
  triplets(3, 'Triplets'),
  sixteenths(4, '16ths');

  Subdivision(this.perBeat, this.label);

  final int perBeat;
  final String label;
}

@immutable
final class TimeSignature {
  const TimeSignature(this.beats, this.unit);

  /// Clicks per bar. The BPM counts these (in 6/8, eighth notes).
  final int beats;
  final int unit;

  static const common = [
    TimeSignature(2, 4),
    TimeSignature(3, 4),
    TimeSignature(4, 4),
    TimeSignature(5, 4),
    TimeSignature(6, 8),
    TimeSignature(7, 8),
    TimeSignature(12, 8),
  ];

  /// Downbeat strong; in compound and odd meters the start of each group
  /// gets a medium accent (6/8 = 3+3, 7/8 = 2+2+3, 12/8 = 3+3+3+3).
  List<Accent> get defaultAccents {
    final groupStarts = switch ((beats, unit)) {
      (6, 8) => {3},
      (7, 8) => {2, 4},
      (12, 8) => {3, 6, 9},
      _ => <int>{},
    };
    return [
      for (var i = 0; i < beats; i++)
        if (i == 0)
          Accent.strong
        else if (groupStarts.contains(i))
          Accent.medium
        else
          Accent.normal,
    ];
  }

  static TimeSignature? tryParse(String s) {
    final parts = s.split('/');
    if (parts.length != 2) return null;
    final b = int.tryParse(parts[0]);
    final u = int.tryParse(parts[1]);
    return b == null || u == null ? null : TimeSignature(b, u);
  }

  @override
  String toString() => '$beats/$unit';

  @override
  bool operator ==(Object other) =>
      other is TimeSignature && other.beats == beats && other.unit == unit;

  @override
  int get hashCode => Object.hash(beats, unit);
}

@immutable
final class MetronomeSettings {
  MetronomeSettings({
    this.bpm = 100,
    this.signature = const TimeSignature(4, 4),
    this.subdivision = Subdivision.none,
    List<Accent>? accents,
  }) : accents = List.unmodifiable(accents ?? signature.defaultAccents) {
    if (this.accents.length != signature.beats) {
      throw ArgumentError('accents must have one entry per beat');
    }
  }

  static const minBpm = 30;
  static const maxBpm = 300;

  final int bpm;
  final TimeSignature signature;
  final Subdivision subdivision;
  final List<Accent> accents;

  int get beats => signature.beats;

  MetronomeSettings copyWith({
    int? bpm,
    TimeSignature? signature,
    Subdivision? subdivision,
    List<Accent>? accents,
  }) {
    final sig = signature ?? this.signature;
    return MetronomeSettings(
      bpm: (bpm ?? this.bpm).clamp(minBpm, maxBpm),
      signature: sig,
      subdivision: subdivision ?? this.subdivision,
      // A new meter gets its own default accents.
      accents: accents ?? (sig == this.signature ? this.accents : null),
    );
  }

  /// Bars in the rendered loop.
  ///
  /// A loop must be a whole number of samples, and one bar rarely is
  /// (120 BPM 4/4 at 44.1 kHz is exactly 88,200; 97 BPM is 109,113.4…).
  /// The rounding would repeat every bar as a tiny steady tempo error, so
  /// we loop the number of bars (up to ~20 s of audio) whose total length
  /// lands closest to a whole sample.
  int loopBars(int sampleRate) {
    final ideal = beats * 60 * sampleRate / bpm;
    var best = 1;
    var bestError = double.infinity;
    for (var m = 1; m <= 16 && (m == 1 || m * ideal <= 20 * sampleRate); m++) {
      final error = (m * ideal - (m * ideal).round()).abs() / m;
      if (error < bestError - 1e-12) {
        best = m;
        bestError = error;
      }
    }
    return best;
  }

  /// Samples in the loop. Rounded once, here: every click position derives
  /// from this, so the only timing error is this rounding spread over
  /// [loopBars] bars.
  int loopSamples(int sampleRate) => (loopBars(sampleRate) * beats * 60 * sampleRate / bpm).round();

  /// The loop's exact beat length, in seconds, for the transport.
  double beatSeconds(int sampleRate) =>
      loopSamples(sampleRate) / (loopBars(sampleRate) * beats) / sampleRate;

  @override
  bool operator ==(Object other) =>
      other is MetronomeSettings &&
      other.bpm == bpm &&
      other.signature == signature &&
      other.subdivision == subdivision &&
      _listEquals(other.accents, accents);

  @override
  int get hashCode => Object.hash(bpm, signature, subdivision, Object.hashAll(accents));
}

/// One click in a rendered bar.
typedef ClickEvent = ({int sample, int beat, int sub, ClickVoice voice});

/// Every click in the loop, starting from beat [startBeat] (rotated, so a
/// tempo change can take over mid-bar without jumping to beat 1).
List<ClickEvent> clickEvents(MetronomeSettings s, int sampleRate, {int startBeat = 0}) {
  final total = s.loopSamples(sampleRate);
  final per = s.subdivision.perBeat;
  final n = s.loopBars(sampleRate) * s.beats * per;
  return [
    for (var j = 0; j < n; j++)
      if (_voiceFor(s, (startBeat + j ~/ per) % s.beats, j % per) case final voice?)
        (
          // Positions from the bar length, not by adding a rounded beat:
          // rounding errors cannot accumulate within the bar.
          sample: (j * total / n).round(),
          beat: (startBeat + j ~/ per) % s.beats,
          sub: j % per,
          voice: voice,
        ),
  ];
}

ClickVoice? _voiceFor(MetronomeSettings s, int beat, int sub) {
  if (sub == 0) return s.accents[beat].voice;
  // Subdivisions of a muted beat stay silent too: muting is for gaps.
  return s.accents[beat] == Accent.mute ? null : ClickVoice.subdivision;
}

/// Renders the click loop. Looped by the audio engine, this *is* the
/// metronome: timing lives in sample positions, not in Dart timers.
Float32List renderLoop(MetronomeSettings s, int sampleRate, {int startBeat = 0}) {
  final out = Float32List(s.loopSamples(sampleRate));
  final cache = <ClickVoice, Float32List>{};
  for (final e in clickEvents(s, sampleRate, startBeat: startBeat)) {
    final click = cache[e.voice] ??= renderClick(e.voice, sampleRate);
    for (var i = 0; i < click.length; i++) {
      // A click near the end of the bar wraps to the start, as it would
      // when the loop repeats.
      final at = (e.sample + i) % out.length;
      out[at] += click[i];
    }
  }
  return out;
}

/// Italian tempo marking: a quiet caption, not a control.
String tempoMarking(int bpm) => switch (bpm) {
  < 60 => 'Largo',
  < 66 => 'Larghetto',
  < 76 => 'Adagio',
  < 108 => 'Andante',
  < 120 => 'Moderato',
  < 156 => 'Allegro',
  < 176 => 'Vivace',
  < 200 => 'Presto',
  _ => 'Prestissimo',
};

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
