# Recorded fixtures

Drop short WAV recordings of single notes here and run `flutter test
test/core/audio/wav_fixture_test.dart`. Each file is scored by the same
harness as the synthesized signals and printed as an accuracy report.

* **Name:** `<NOTE>_<anything>.wav`, the expected note first in scientific
  pitch notation: `E2_open_iphone.wav`, `A2_open_pixel_room.wav`,
  `G3_12th_harmonic.wav`.
* **Format:** PCM 16/24/32-bit or float 32-bit, mono or stereo, 44.1 or 48 kHz.
* **Content:** one pluck, let ring for 2–4 seconds. The first 0.3 s (attack)
  is not scored.
* **Licence:** only add recordings you made yourself; they are committed to
  an open-source repository.

## Chords

Strummed chords for the identifier go here too, scored by
`test/core/audio/chord_accuracy_test.dart`:

* **Name:** `chord_<Symbol>_<anything>.wav`, e.g. `chord_Am_open_iphone.wav`,
  `chord_Fs_barre_room.wav` (`s` for sharp, since `#` is awkward in file names).
* **Format:** 48 kHz (the phone's capture rate).
* **Content:** one clear strum, let ring for 2–3 seconds.

Each test is skipped while it has no matching files.
