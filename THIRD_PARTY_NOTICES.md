# Third-party notices

Fretlight bundles no third-party audio or images. This file lists
every direct dependency and dataset, and is updated in the same change that
adds one. The full transitive licence texts will be shown in-app from
Flutter's `LicenseRegistry` (a Licences page arrives with Settings), which is
generated from the packages actually compiled in.

## Runtime packages

| Package | Version | Licence | Use |
|---|---|---|---|
| Flutter SDK | 3.47.8 | BSD-3-Clause | UI framework |
| flutter_riverpod | 3.4.3 | MIT | State management |
| go_router | 18.1.2 | BSD-3-Clause | Navigation |
| meta | 1.19.0 | BSD-3-Clause | `@immutable` annotations in the pure-Dart core |
| record | 7.1.2 | BSD-3-Clause | Microphone capture (PCM stream) |
| audio_session | 0.2.4 | MIT | iOS/Android audio session (measurement mode, interruptions) |
| permission_handler | 13.0.2 | MIT | Microphone permission state and Settings link |

## Fonts

| Font | Licence | Source | Notes |
|---|---|---|---|
| Inter (variable, wght + opsz) | SIL Open Font License 1.1, © 2020 The Inter Project Authors | github.com/google/fonts `ofl/inter` | Licence text bundled at `assets/fonts/Inter-OFL.txt` and registered with `LicenseRegistry` |

## Development-only packages (not shipped)

| Package | Version | Licence |
|---|---|---|
| flutter_test (SDK) | — | BSD-3-Clause |
| very_good_analysis | 11.0.0 | MIT |

## Design credits

| Work | Licence | What we used |
|---|---|---|
| khuur_pitch 0.1.0 (Tseku210) | MIT | The idea of computing YIN/MPM from one FFT correlogram (`lib/core/audio/dsp/correlogram.dart`). Reimplemented; no code copied. |
| YIN (de Cheveigné & Kawahara, 2002), MPM (McLeod & Wyvill, 2005), Karplus–Strong with all-pass tuning (Jaffe & Smith, 1983) | Published algorithms | Implemented from the papers |

## Datasets

None bundled yet. Planned, each recorded here when added:

| Dataset | Licence | Milestone | Notes |
|---|---|---|---|
| tombatossals/chords-db (guitar) | MIT, © 2016 David Rubert | 3 | Converted and validated by `tool/`; invalid voicings dropped or flagged |
| Chordonomicon (ailsntua/Chordonomicon) | CC BY-NC 4.0 | 7 | Separate removable pack; chord progressions only, no artist or Spotify IDs |

## Original content

Starter songs (Milestone 6) are public-domain works; each file records its
public-domain basis in its metadata. Chord arrangements are original.
