# Third-party notices

Fretlight bundles no third-party audio or images; chord sounds are synthesised on the device. This file lists
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
| flutter_soloud | 5.2.2 | MIT; bundles SoLoud (zlib/libpng) and miniaudio (public domain / MIT-0) | Low-latency playback of synthesised chords |
| drift | 2.35.3 | MIT | SQLite database (settings, favourites, custom tunings) |
| drift_flutter | 0.3.1 | MIT | Opens the on-device database |
| sqlite3 | 3.8.0 | MIT (bindings); SQLite itself is public domain | SQLite engine, built by its build hook |
| path_provider | 2.1.6 | BSD-3-Clause | Locates the app-private database directory |

## Fonts

| Font | Licence | Source | Notes |
|---|---|---|---|
| Inter (variable, wght + opsz) | SIL Open Font License 1.1, © 2020 The Inter Project Authors | github.com/google/fonts `ofl/inter` | Licence text bundled at `assets/fonts/Inter-OFL.txt` and registered with `LicenseRegistry` |

## Development-only packages (not shipped)

| Package | Version | Licence |
|---|---|---|
| flutter_test (SDK) | — | BSD-3-Clause |
| very_good_analysis | 11.0.0 | MIT |
| drift_dev | 2.35.2 | MIT |
| build_runner | 2.17.1 | BSD-3-Clause |

## Design credits

| Work | Licence | What we used |
|---|---|---|
| khuur_pitch 0.1.0 (Tseku210) | MIT | The idea of computing YIN/MPM from one FFT correlogram (`lib/core/audio/dsp/correlogram.dart`). Reimplemented; no code copied. |
| YIN (de Cheveigné & Kawahara, 2002), MPM (McLeod & Wyvill, 2005), Karplus–Strong with all-pass tuning (Jaffe & Smith, 1983) | Published algorithms | Implemented from the papers |

## Datasets

| Dataset | Licence | Status | Notes |
|---|---|---|---|
| [tombatossals/chords-db](https://github.com/tombatossals/chords-db) (guitar), commit `df06fa7` | MIT, © 2016 David Rubert | Bundled at `assets/chords/guitar.json` | Converted by `tool/chords_db/convert.dart`; every voicing checked against its chord formula and the source's own MIDI notes. 116 of 3,283 failed and are left out, listed in `docs/chord-data-report.md`. Licence text bundled at `assets/chords/chords-db-LICENSE.txt` and registered with `LicenseRegistry` |
| Chordonomicon (ailsntua/Chordonomicon) | CC BY-NC 4.0 | Planned (milestone 7) | Separate removable pack; chord progressions only, no artist or Spotify IDs |

## Original content

Starter songs (Milestone 6) are public-domain works; each file records its
public-domain basis in its metadata. Chord arrangements are original.
