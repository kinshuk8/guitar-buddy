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

The test is skipped while this folder has no `.wav` files.
