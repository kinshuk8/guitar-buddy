# Fretlight

A free, offline guitar practice app for Android and iOS: tuner, chord
library, metronome and note/chord identifier; song play-along in progress.

No account, no ads, no analytics, no network access at runtime. The
microphone is only open while a listening screen is visible, and audio is
never saved.

## Status

| Milestone | | |
|---|---|---|
| 1 | Design system, music theory core | done |
| 2 | Tuner | done |
| 3 | Chord library with synthesised playback | done |
| 4 | Metronome | done |
| 5 | Live note and chord identifier | done |
| 6 | Song play-along (ChordPro) | next |
| 7 | Practice mode, progression pack, polish | |

## Building

Flutter 3.47 or newer.

```bash
flutter pub get
flutter run
```

## Tests

```bash
flutter analyze
flutter test
```

The detector tests print accuracy reports, and the metronome test prints
a 10-minute drift report ([docs/metronome-timing.md](docs/metronome-timing.md)), and the
chord test prints the identifier's accuracy ([docs/accuracy-report-m5.md](docs/accuracy-report-m5.md)). To score the tuner against real
recordings, drop WAV files into `test/fixtures/wav/` (see the README there).

## Regenerating things

Generated code (the Drift database) is committed. After changing
`lib/core/storage/app_database.dart`:

```bash
dart run build_runner build
```

The chord library asset is built from
[chords-db](https://github.com/tombatossals/chords-db) on a developer machine:

```bash
git clone https://github.com/tombatossals/chords-db /tmp/chords-db
dart run tool/chords_db/convert.dart /tmp/chords-db
```

This rewrites `assets/chords/guitar.json` and `docs/chord-data-report.md`,
which lists every voicing that failed validation and why.

## Layout

```
lib/
  app/        shell, routing
  core/       design system, music theory, audio (DSP, synth, I/O), storage
  features/   tuner, chords, settings…  (domain / application / presentation)
tool/         offline data converters (never shipped)
docs/         spike results, accuracy and data reports
```

## Licences

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for every package,
font and dataset.
