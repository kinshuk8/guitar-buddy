# Metronome timing (Milestone 4)

## How clicks are timed

No Dart timer decides when a click sounds.

1. The current tempo, meter, accents and subdivision are rendered to a
   **loop of PCM audio** with every click at an exact sample position
   (`renderLoop` in `lib/features/metronome/domain/metronome_settings.dart`).
2. The loop is handed to the audio engine (SoLoud / miniaudio), which repeats
   it gaplessly. Timing is now the audio hardware's sample clock.
3. A change (tempo, accent, subdivision, meter) renders a new loop and
   schedules it on the **engine clock** to start on the next beat, and the
   old loop to stop at the same sample (`playScheduled` / `stopScheduled`).
   No beat is dropped or doubled. Quick successive changes replace the one
   still waiting.
4. The beat lights read the same engine clock each frame, so the light
   follows the sound.

One subtlety: a loop must be a whole number of samples, and one bar usually
isn't (97 BPM in 4/4 at 48 kHz is 118,762.9 samples). Rounding once per bar
would be a tiny constant tempo error, so the loop holds the number of bars
(up to ~20 s) whose total length lands closest to a whole sample.

## Measured drift

`test/features/metronome/metronome_timing_test.dart` renders real loop audio,
finds each click's onset in the waveform, follows the loop for **10
minutes**, and compares every click with its ideal time. It runs 54 cases:
48 and 44.1 kHz; 30, 47, 60, 97, 120, 133, 187, 251 and 300 BPM; 4/4
quarters, 7/8 sixteenths and 3/4 triplets.

| | |
|---|---|
| Worst error at any click over 10 minutes | **0.39 ms** (44.1 kHz, 97 BPM, 3/4 triplets) |
| Typical | 0.02–0.2 ms |
| Audible threshold for timing error | roughly 5–10 ms |

That figure includes the onset detector's own jitter (about ±1 sample
between loud and quiet clicks), so the true error is lower.

A second test mixes down what the speaker would play across a tempo change
mid-bar (150 → 120 BPM) and checks every click time: the change lands exactly
on the beat boundary, within 0.5 ms.

## Not measured here

- **Output latency** (the phone's audio buffer, typically 10–40 ms) delays
  everything equally, so it doesn't affect steadiness. The beat light may lead
  the sound by that amount.
- **Device clock accuracy**: phone audio clocks are typically within
  ±50 ppm, which is 30 ms over 10 minutes against a wall clock. That error is
  steady and the same for every click, so you hear a tempo that is 0.005% off,
  not drift.
