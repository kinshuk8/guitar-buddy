import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fretlight/core/audio/dsp/fft.dart';
import 'package:fretlight/core/audio/dsp/pitch_detector.dart' show rmsDb;
import 'package:fretlight/core/music/music.dart';
import 'package:meta/meta.dart';

/// One chord hypothesis with its match score (cosine, 0..1).
typedef ChordScore = ({Chord chord, double score});

/// What a [ChordDetector] heard in one window.
@immutable
final class ChordEstimate {
  const ChordEstimate({
    required this.ranked,
    required this.chroma,
    required this.bass,
    required this.rmsDb,
    required this.distinctNotes,
    this.singleNote,
  });

  static const silent = ChordEstimate(
    ranked: [],
    chroma: [],
    bass: null,
    rmsDb: -120,
    distinctNotes: 0,
  );

  /// Every candidate, best first. Empty when too quiet to judge.
  final List<ChordScore> ranked;

  /// Normalised pitch-class energy, C first (length 12, or empty).
  final List<double> chroma;

  /// Lowest strong pitch class, if one stood out.
  final PitchClass? bass;
  final double rmsDb;

  /// Pitch classes with real energy. A chord needs at least 3 (2 for a
  /// power chord); a single note's harmonics shouldn't pass as a chord.
  final int distinctNotes;

  /// Set when the spectrum fits one note's harmonics at least as well as
  /// any chord: a single string, not a chord.
  final PitchClass? singleNote;

  ChordScore? get best => ranked.isEmpty ? null : ranked.first;

  /// The same estimate keeping only the top [n] candidates.
  ChordEstimate trimmed(int n) => ranked.length <= n
      ? this
      : ChordEstimate(
          ranked: ranked.sublist(0, n),
          chroma: chroma,
          bass: bass,
          rmsDb: rmsDb,
          distinctNotes: distinctNotes,
          singleNote: singleNote,
        );
}

/// Names the chord in a window of audio. An interface so v2 (e.g. a small
/// on-device model) can replace the template matcher without touching the UI.
abstract interface class ChordDetector {
  int get windowSize;

  ChordEstimate detect(Float32List window);
}

/// Chroma + template matching, with the bass note as a tie-breaker.
///
/// 1. FFT of a long Hann window (16k samples at 48 kHz: ~3 Hz bins, enough
///    to tell low E from F).
/// 2. Spectral peaks only, each mapped to its pitch class with parabolic
///    frequency refinement; partials more than ~35 cents from a semitone are
///    ignored (inharmonic noise, string buzz). Square-root magnitudes so one
///    loud partial can't dominate.
/// 3. Templates model each chord tone *with its harmonics* (octave, fifth,
///    major third above…), because that is what a guitar string actually
///    puts into the chroma. Cosine similarity ranks the candidates.
/// 4. The bass (lowest strong partial below ~260 Hz) nudges the ranking:
///    the root in the bass helps; a bass outside the chord costs.
final class ChromaChordDetector implements ChordDetector {
  ChromaChordDetector({
    required this.sampleRate,
    int? windowSize,
    this.qualities = ChordQuality.detectable,
    this.silenceDb = -66,
  }) : windowSize = windowSize ?? chordWindow(sampleRate),
       _templates = _buildTemplates(qualities) {
    _fft = Fft(this.windowSize);
    _re = Float64List(this.windowSize);
    _im = Float64List(this.windowSize);
    _hann = Float64List(this.windowSize);
    for (var i = 0; i < this.windowSize; i++) {
      _hann[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (this.windowSize - 1));
    }
  }

  /// ~0.34 s: long enough for low-string resolution, short enough to follow
  /// a chord change.
  static int chordWindow(int sampleRate) => sampleRate > 30000 ? 16384 : 8192;

  final int sampleRate;
  @override
  final int windowSize;
  final List<ChordQuality> qualities;
  final double silenceDb;

  late final Fft _fft;
  late final Float64List _re;
  late final Float64List _im;
  late final Float64List _hann;
  final List<({Chord chord, Float64List t})> _templates;

  static const _minHz = 70.0;
  static const _maxHz = 4200.0;
  static const _bassMaxHz = 260.0;

  /// A peak must be this many times its band's noise level (~12 dB).
  static const _prominence = 4.0;

  /// Noise level per bin: the 30th-percentile magnitude of its
  /// quarter-octave band.
  static double Function(int) _bandNoise(Float64List mag, int lo, int hi, double binHz) {
    final edges = <int>[lo];
    while (edges.last < hi) {
      edges.add(
        math.min(hi + 1, math.max(edges.last + 4, (edges.last * math.pow(2, 0.25)).ceil())),
      );
    }
    final levels = <double>[];
    for (var i = 0; i + 1 < edges.length; i++) {
      final band = mag.sublist(edges[i], edges[i + 1])..sort();
      levels.add(band[(band.length * 0.3).floor()]);
    }
    return (k) {
      var i = 0;
      while (i + 1 < edges.length - 1 && k >= edges[i + 1]) {
        i++;
      }
      return levels[i];
    };
  }

  @override
  ChordEstimate detect(Float32List window) {
    final level = rmsDb(window);
    if (level < silenceDb) {
      return ChordEstimate(
        ranked: const [],
        chroma: const [],
        bass: null,
        rmsDb: level,
        distinctNotes: 0,
      );
    }
    final n = windowSize;
    for (var i = 0; i < n; i++) {
      _re[i] = window[i] * _hann[i];
      _im[i] = 0;
    }
    _fft.transform(_re, _im);
    final half = n ~/ 2;
    final mag = Float64List(half);
    for (var k = 0; k < half; k++) {
      mag[k] = math.sqrt(_re[k] * _re[k] + _im[k] * _im[k]);
    }

    final binHz = sampleRate / n;
    final lo = (_minHz / binHz).floor().clamp(2, half - 2);
    final hi = (_maxHz / binHz).ceil().clamp(lo + 1, half - 2);
    var peakMax = 0.0;
    for (var k = lo; k <= hi; k++) {
      peakMax = math.max(peakMax, mag[k]);
    }
    if (peakMax == 0) {
      return ChordEstimate(
        ranked: const [],
        chroma: const [],
        bass: null,
        rmsDb: level,
        distinctNotes: 0,
      );
    }
    // Peaks within 40 dB of the strongest one, and clearly above the noise
    // in their part of the spectrum. Room hiss makes thousands of tiny local
    // maxima; counting them smears the chroma flat. The noise level is a
    // low percentile per quarter-octave band: it follows the hiss and
    // ignores the strong partials themselves (a mean would include them and
    // drown a chord's weaker notes).
    final floor = peakMax * 0.01;
    final noise = _bandNoise(mag, lo, hi, binHz);
    final chroma = Float64List(12);
    final low = <({double hz, double m})>[];
    final peaks = <({double hz, double m})>[];
    for (var k = lo; k <= hi; k++) {
      final m = mag[k];
      if (m < floor || m < mag[k - 1] || m < mag[k + 1]) continue;
      if (m < _prominence * noise(k)) continue;
      // Parabolic interpolation on log magnitude: sub-bin frequency.
      final a = math.log(mag[k - 1] + 1e-12);
      final b = math.log(m + 1e-12);
      final c = math.log(mag[k + 1] + 1e-12);
      final denom = a - 2 * b + c;
      final delta = denom == 0 ? 0.0 : (0.5 * (a - c) / denom).clamp(-0.5, 0.5);
      final hz = (k + delta) * binHz;
      final midi = 69 + 12 * math.log(hz / 440) / math.ln2;
      final nearest = midi.round();
      final off = (midi - nearest).abs();
      if (off > 0.35) continue;
      // High partials are mostly harmonics of lower notes, not notes in
      // their own right: they count for less.
      final w = math.sqrt(m) * (1 - (off / 0.35) * (off / 0.35)) / (1 + hz / 2800);
      final pc = nearest % 12;
      chroma[pc] += w;
      if (hz <= _bassMaxHz) low.add((hz: hz, m: m));
      peaks.add((hz: hz, m: m));
    }

    final norm = _l2(chroma);
    if (norm == 0) {
      return ChordEstimate(
        ranked: const [],
        chroma: const [],
        bass: null,
        rmsDb: level,
        distinctNotes: 0,
      );
    }
    for (var i = 0; i < 12; i++) {
      chroma[i] /= norm;
    }
    final maxChroma = chroma.reduce(math.max);
    final distinct = chroma.where((v) => v >= 0.25 * maxChroma).length;

    // Broadband noise spreads evenly over all twelve notes; a chord (even
    // with its harmonics) concentrates in a few.
    final sorted = [...chroma]..sort((a, b) => b.compareTo(a));
    final l1 = chroma.fold<double>(0, (s, v) => s + v);
    if ((sorted[0] + sorted[1] + sorted[2] + sorted[3]) / l1 < 0.5) {
      return ChordEstimate(
        ranked: const [],
        chroma: const [],
        bass: null,
        rmsDb: level,
        distinctNotes: distinct,
      );
    }

    // The bass is the *lowest* reasonably strong partial, not the loudest
    // low one: a low string's 3rd harmonic (a fifth up) is often louder
    // than its fundamental on a phone mic.
    PitchClass? bass;
    if (low.isNotEmpty) {
      final lowMax = low.map((p) => p.m).reduce(math.max);
      for (final p in low) {
        if (p.m >= 0.2 * lowMax) {
          bass = PitchClass((69 + 12 * math.log(p.hz / 440) / math.ln2).round() % 12);
          break;
        }
      }
    }

    final ranked = <ChordScore>[];
    for (final (:chord, :t) in _templates) {
      var dot = 0.0;
      for (var i = 0; i < 12; i++) {
        dot += chroma[i] * t[i];
      }
      if (bass != null) {
        if (bass == chord.root) {
          dot += 0.03;
        } else if (!chord.pitchClasses.contains(bass)) {
          dot -= 0.05;
        }
      }
      // Prefer the simpler name when two fit nearly equally: a bright C
      // puts some energy on B (harmonics of E and G) without being Cmaj7.
      dot -= 0.008 * math.min(chord.quality.complexity, 2);
      // A strong note the chord doesn't contain counts against it. The
      // template already expects some energy on its tones' harmonics, so a
      // real 7th (as in Fmaj7's open E) otherwise hides there.
      final pcs = chord.pitchClasses;
      var unexplained = 0.0;
      for (var i = 0; i < 12; i++) {
        if (!pcs.contains(PitchClass(i))) {
          unexplained += math.max(0, chroma[i] / maxChroma - _unexplainedFrom);
        }
      }
      dot -= _unexplainedWeight * unexplained;
      ranked.add((chord: chord, score: dot));
    }
    ranked.sort((x, y) => y.score.compareTo(x.score));

    // A single string's partials sit at whole multiples of its pitch; a
    // chord has partials at ratios like 1.5 (a fifth) or 1.25 (a third).
    // Note names can't tell them apart (D's harmonics *are* D, F#, A), but
    // these ratios can.
    // The candidate pitch: the lowest strong partial below 1 kHz (the high
    // E string's 330 Hz is above the bass range used for the bass label).
    PitchClass? single;
    final lowish = peaks.where((p) => p.hz <= 1000).toList();
    final lowishMax = lowish.isEmpty ? 0.0 : lowish.map((p) => p.m).reduce(math.max);
    final f0 = lowish.where((p) => p.m >= 0.2 * lowishMax).firstOrNull?.hz;
    if (f0 != null) {
      final strong = peaks.where((p) => p.m >= 0.08 * peakMax).toList();
      var harmonic = 0.0;
      var total = 0.0;
      for (final p in strong) {
        final ratio = p.hz / f0;
        final k = ratio.round();
        final cents = k < 1 ? 1200 : (1200 * math.log(ratio / k) / math.ln2).abs();
        total += p.m;
        if (cents < 25) harmonic += p.m;
      }
      if (total > 0 && harmonic / total >= 0.9) {
        single = PitchClass((69 + 12 * math.log(f0 / 440) / math.ln2).round() % 12);
      }
    }
    return ChordEstimate(
      ranked: ranked,
      chroma: List.unmodifiable(chroma),
      bass: bass,
      rmsDb: level,
      distinctNotes: distinct,
      singleNote: single,
    );
  }

  /// Pitch-class steps of the first six harmonics: 1, 2 (octave), 3 (octave
  /// + fifth), 4, 5 (two octaves + major third), 6. Weights fall off like a
  /// plucked string's partials.
  /// Above this share of the strongest note, a note outside the chord costs
  /// [_unexplainedWeight] per unit.
  static const _unexplainedFrom = 0.35;
  static const _unexplainedWeight = 0.15;

  static const _harmonics = [(0, 1.0), (0, 0.7), (7, 0.6), (0, 0.45), (4, 0.4), (7, 0.3)];

  static List<({Chord chord, Float64List t})> _buildTemplates(List<ChordQuality> qualities) {
    final out = <({Chord chord, Float64List t})>[];
    for (var r = 0; r < 12; r++) {
      final root = PitchClass(r);
      for (final q in qualities) {
        final t = Float64List(12);
        // Required tones only: the template asks for what defines the
        // chord. An optional 5th that's present still adds to the score.
        for (final interval in q.allowed) {
          for (final (step, w) in _harmonics) {
            t[(r + interval + step) % 12] += w * (q.required.contains(interval) ? 1 : 0.7);
          }
        }
        final n = _l2(t);
        for (var i = 0; i < 12; i++) {
          t[i] /= n;
        }
        out.add((chord: Chord(root, q), t: t));
      }
    }
    return out;
  }

  static double _l2(Float64List v) {
    var s = 0.0;
    for (final x in v) {
      s += x * x;
    }
    return math.sqrt(s);
  }
}
