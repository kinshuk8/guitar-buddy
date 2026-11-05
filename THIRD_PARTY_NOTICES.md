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
| file_picker | 13.3.2 | MIT | Importing ChordPro files |
| wakelock_plus | 1.8.2 | BSD-3-Clause | Keeping the screen on during play-along |
| sqlite3 (direct) | 3.8.0 | MIT | Reading the progression pack |

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
| [Chordonomicon](https://huggingface.co/datasets/ailsntua/Chordonomicon) (Kantarelis et al., 2024, arXiv:2410.22046), file `chordonomicon_v2.csv` at commit `2ad317c` | **CC BY-NC 4.0** | Bundled as an optional pack at `assets/packs/chordonomicon/` | Reduced by `tool/chordonomicon/build_pack.dart` to aggregate counts for the 300 most common repeating 3–4 chord loops (songs using each, top genres, decades). No per-song rows, song or artist identifiers, Spotify IDs, dates or lyrics are included. Attribution in `ATTRIBUTION.txt`, in the app (Songs → Progressions, Settings) and on the licence page. **Non-commercial:** remove the pack before any paid or ad-supported release. |

## Starter songs

Twelve songs in `assets/songs/`. Every one was published before 1900, so all
are public domain in the US (published before 1929) and in life+70 countries
(every author died before 1955). Each file records its public-domain basis
(`{meta: public_domain …}`) and the publication its words follow
(`{meta: source …}`). Chord arrangements are original to Fretlight.

Choices made to stay clear of later copyrighted versions:
- *Oh! Susanna*: only the 1848 verses without period slurs.
- *Scarborough Fair*: Kidson's 1891 wording, not the 1966 Simon & Garfunkel
  arrangement.
- *Michael, Row the Boat Ashore*: only the refrain and verse printed in 1867,
  none of the 1950s folk-revival verses.
- *Home on the Range*: Lomax's 1910 text.
- Four earlier candidates were dropped because their familiar words couldn't
  be traced to a dated pre-1929 printing: *Red River Valley* (popular words
  from 1920s recordings), *Down in the Valley* (familiar words match a 1927
  recording), *When the Saints Go Marching In* (no dated print source), and
  *Shenandoah* (the popular verses differ from the 1882 printing).

| Song | Words from |
|---|---|
| Amazing Grace | John Newton, *Olney Hymns*, 1779 |
| Auld Lang Syne | Robert Burns, *The Scots Musical Museum*, 1796 |
| Aura Lee | W. W. Fosdick / G. R. Poulton, 1861 |
| Beautiful Dreamer | Stephen Foster, 1864 |
| Home on the Range | J. A. Lomax, *Cowboy Songs*, 1910 |
| Jingle Bells | James Lord Pierpont, 1857/1859 |
| Michael, Row the Boat Ashore | *Slave Songs of the United States*, 1867 |
| Oh My Darling, Clementine | Percy Montrose, 1884 |
| Oh! Susanna | Stephen Foster, 1848 |
| Scarborough Fair | Frank Kidson, *Traditional Tunes*, 1891 |
| Simple Gifts | Joseph Brackett, 1848 |
| Swing Low, Sweet Chariot | Fisk Jubilee Singers, *Jubilee Songs*, 1872 |
