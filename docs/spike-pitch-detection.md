# Spike: pitch detector choice (Milestone 2)

**Decision:** use our own MPM detector (`lib/core/audio/dsp/mpm.dart`) on an
FFT correlogram, with YIN (`yin.dart`) kept as a drop-in alternative behind
the `PitchDetector` interface. Depend on neither `pitch_kit` nor
`khuur_pitch`.

Date: 2026-11-04. Flutter 3.47.8, Dart 3.13.7. Test VM (JIT), 48 kHz.

## Candidates

| Candidate | Version | Licence | Notes from reading the source |
|---|---|---|---|
| pitch_kit | 0.0.3 (2026-10-31) | Apache-2.0 | Direct O(n·τ) YIN on boxed `List<double>`; returns Hz or -1 (no clarity); non-overlapping 8192 frames in its engine (~5 updates/s); detection runs on the main isolate; DSP untested |
| khuur_pitch | 0.1.0 (2026-10-04) | MIT | FFT correlogram YIN, typed lists, overlapping windows, clarity + dBFS + sample-clock timestamps, good tests. Built in one day by one maintainer; window derived from `minHz` (2048 at 44.1/48 kHz) |
| ours YIN | — | — | Same correlogram idea as khuur_pitch (credited), 4096 window |
| ours MPM | — | — | McLeod NSDF with key-maximum cutoff 0.93, 4096 window |

## Method

Every open string (E2–E4) under four conditions: clean plucked tone,
fundamental attenuated 30 dB (worse than a phone mic on low E), 20 dB SNR
white noise, and a Karplus–Strong pluck 9 cents sharp. Signals are fed in
512-sample chunks like a mic stream; frames inside the first 150 ms (the
pluck transient) are skipped. "Gross" = more than 600 cents off (octave
errors). Harness: `test/core/audio/detector_harness.dart`.

The additive tones include string stiffness (B = 5e-5), which genuinely
moves the waveform period ~1.2 cents sharp; every detector reports it, so
that shared baseline is physics, not error. Karplus–Strong rows (exact
pitch) show the detectors' own error: ≤ 0.06 cents for all candidates.

## Results

```
ours YIN 4096     detect 100%  median 1.27¢  p95 2.12¢  gross 0/1080  0.17 ms/frame
ours MPM 4096     detect 100%  median 1.23¢  p95 2.08¢  gross 0/1080  0.17 ms/frame
pitch_kit 4096    detect 100%  median 1.26¢  p95 2.49¢  gross 0/1080  0.38 ms/frame
pitch_kit 8192    detect 100%  median 1.32¢  p95 2.40¢  gross 0/984   0.39 ms/frame
khuur_pitch 2048  detect 100%  median 1.24¢  p95 2.21¢  gross 0/1128
```

Worst single frame under 20 dB noise on low E: ours 3.5¢, khuur_pitch 4.0¢,
pitch_kit 8.9¢.

## Why our own

* Accuracy is a tie on clean signals; ours is best under noise.
* We need a clarity value for gating (pitch_kit has none) and control over
  window size (khuur_pitch fixes it from `minHz`).
* No young single-maintainer dependency in the most critical path.
* 0.17 ms per frame leaves >99% of the 21 ms frame budget free.

## Octave errors

A YIN "octave guard" (prefer the dip at 2τ when it is much deeper) was
built and measured. It never changed a result: periodicity detectors judge
the period of the whole waveform, which stays at f0 even when the
fundamental is 40 dB down. The only way to fool all five detectors was a
non-physical signal with odd harmonics suppressed (genuinely periodic at
2·f0). The guard was removed. Octave correction lives in the tuner instead,
which knows the open strings it expects (`TunerSession`).

## Still to verify on a real guitar

Synthetic signals do not model a real body resonance, room reflections or
the phone's mic processing. Milestone 2 ends with on-device testing of all
six open strings; WAV recordings can be dropped into `test/fixtures/wav/`
(see its README) and are scored by the same harness.
