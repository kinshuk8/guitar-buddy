<p align="center">
  <img src="docs/logo.png" width="96" height="96" alt="Fretlight app icon: six guitar strings with a glowing amber fret marker">
</p>

<h1 align="center">Fretlight</h1>

<p align="center">
  <strong>A guitar practice companion that listens, keeps time and stays offline.</strong>
</p>

<p align="center">
  <a href="https://github.com/kinshuk8/guitar-buddy/releases"><img src="https://img.shields.io/badge/release-v0.7.0%20pre--release-2f6f62" alt="Release: v0.7.0 pre-release"></a>
  <img src="https://img.shields.io/badge/platform-Android%20%7C%20iOS-3b4a6b" alt="Platforms: Android and iOS">
  <img src="https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white" alt="Built with Flutter 3.47">
  <img src="https://img.shields.io/badge/network-none%20at%20runtime-555" alt="No network access at runtime">
</p>

---

Fretlight brings the everyday tools of guitar practice into one app: a
tuner, a chord library you can hear, a metronome, a note and chord
identifier, and songs you can play along with. Its practice mode listens
through the microphone and waits for you to play each chord before moving
on.

Everything runs on the device. There is no account, no advertising, no
analytics and no network access. The microphone is only open while a
listening screen is visible, and audio is never recorded or stored.

<p align="center">
  <img src="docs/screenshots/tuner.jpg" width="300" alt="Tuner screen reading A2 at 110.4 Hz, 6 cents sharp, with the needle just right of centre and the mic meter showing it hears the string">
</p>

## Screens

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/chord-library.jpg" width="200" alt="Chord library showing the eight essential C chords as diagrams with shape counts"><br><sub>Chord library</sub></td>
    <td align="center"><img src="docs/screenshots/chord-detail.jpg" width="200" alt="C major chord diagram with finger numbers, note names under each string, and Play and Practise buttons"><br><sub>Chord detail</sub></td>
    <td align="center"><img src="docs/screenshots/note-identifier.jpg" width="200" alt="Note identifier showing A2 at 110.0 Hz and every place to play it on a fretboard"><br><sub>Note identifier</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/song-library.jpg" width="200" alt="Song library listing public-domain starter songs such as Amazing Grace and Aura Lee with their keys"><br><sub>Song library</sub></td>
    <td align="center"><img src="docs/screenshots/play-along.jpg" width="200" alt="Amazing Grace play-along with chords above the lyrics, the current and next chord diagrams, bar and tempo sliders"><br><sub>Play-along</sub></td>
    <td align="center"><img src="docs/screenshots/practice-mode.jpg" width="200" alt="Practice mode asking for a G chord with its diagram, the lyric line, the next chords and a Listening indicator"><br><sub>Practice mode</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/arrange-song.jpg" width="200" alt="Arrange sheet with transpose, capo and tempo controls, a guitar-part strum pattern and a click toggle"><br><sub>Arrange a song</sub></td>
    <td align="center"><img src="docs/screenshots/metronome.jpg" width="200" alt="Metronome at 100 BPM in 4/4 with accent dots, a tempo slider, Tap and Start buttons"><br><sub>Metronome</sub></td>
    <td align="center"><img src="docs/screenshots/settings.jpg" width="200" alt="Settings with appearance, left-handed mode, listening sensitivity and a plain-language privacy statement"><br><sub>Settings</sub></td>
  </tr>
</table>

## Features

**Tune quickly and accurately.** Pick a tuning, or let the tuner find the
string you play. It measures the string's fundamental, so a real steel
string reads true rather than a few cents sharp. Standard, drop D, DADGAD,
open G and half-step down are built in, alongside your own tunings and any
A4 reference.

**Learn chords by sight and sound.** Over 3,000 checked voicings, grouped
by root and type and searchable by name ("Am7", "G/B", "minor 7th"). Every
shape plays back as a strum, and you can tap a single string to hear it.
Draw your own shapes on a fretboard grid: the app names them from their
notes.

**Practise chord changes.** Drill one chord, or switch between two, and
the app moves on only when it hears the chord.

**Play along with songs.** Twelve public-domain starter songs, plus any
song you paste or import in [ChordPro](https://www.chordpro.org) format.
Press play to hear the guitar part at the song's tempo, slow it down, jump
to any bar, loop a section, transpose, or set a capo. The app suggests the
capo position that gives the easiest shapes.

**Practice mode that waits for you.** It shows the chord to play, listens,
and advances when you play it. Afterwards it lists the changes that
slowed you down.

**Identify what you hear.** Play a note to see its name and every place
it sits on the neck, or strum a chord to see its name.

**Keep time.** A sample-accurate metronome with time signatures,
subdivisions, per-beat accents and tap tempo.

**Works in real rooms.** Listening screens learn the room's background
level, so a fan or a quiet TV doesn't register as playing. A level meter
shows when the app hears you, and a sensitivity setting adjusts for
louder or quieter spaces.

**Built for everyone.** Light and dark themes, a left-handed mode, and
screen-reader labels throughout.

## Download

Android builds are published on the
[Releases page](https://github.com/kinshuk8/guitar-buddy/releases).

1. Open the latest release and download the APK for your device. The
   `universal` APK works on any phone; the `arm64-v8a` build is smaller
   and suits most current phones.
2. Open the file on your phone and allow installation from your browser or
   file manager when Android asks.
3. Grant microphone access the first time you open the tuner.

Requires Android 7.0 (API 24) or later. Current releases are pre-releases
for testing. They are not signed with a release key, so they will not
update in place over a future Play Store install. iOS (15.0 or later)
builds from source; no App Store build is published yet.

## How it works

| Layer | Technology |
|---|---|
| UI | Flutter 3.47, Dart 3.13, custom glass design system |
| State and navigation | Riverpod 3, go_router |
| Storage | Drift (SQLite): settings, favourites, tunings, songs and chords |
| Audio input | `record` (PCM stream), `audio_session` |
| Audio output | `flutter_soloud`, scheduled on the audio engine's clock |
| Analysis | Pure-Dart DSP in a background isolate |

Analysis runs in a background isolate so the interface never waits on
it:

- **Pitch:** the McLeod Pitch Method finds the pitch, and a
  Blackman–Harris spectral measurement refines it onto the fundamental.
- **Chords:** a 16k-point FFT builds a chroma profile, which is matched
  against chord templates that model each note's harmonics, with
  bass-note and strum-onset tracking.
- **Guitar sound:** the playback is synthesised on the device: a
  Karplus–Strong string tuned to a hundredth of a cent, with a
  pick-position excitation and an acoustic body filter.

Accuracy is measured in the test suite, not estimated. See
[docs/accuracy-report-m5.md](docs/accuracy-report-m5.md),
[docs/accuracy-report-m2.md](docs/accuracy-report-m2.md) and
[docs/metronome-timing.md](docs/metronome-timing.md).

```
lib/
  app/        shell and routing
  core/       design system, music theory, audio (DSP, synth, I/O), storage
  features/   tuner, identify, chords, metronome, songs, practice, settings
              each split into domain / application / presentation
tool/         offline data converters and the icon renderer (never shipped)
docs/         design spikes, accuracy and data reports, screenshots
```

## Development

**Requirements:** Flutter 3.47 or later (Dart 3.13), Xcode for iOS, and
the Android SDK with JDK 17 for Android.

```bash
flutter pub get
flutter run
```

**Environment variables:** none. The app has no backend, API keys or
runtime configuration.

**Tests:**

```bash
flutter analyze
flutter test
```

The detector, tuner and metronome tests print their accuracy and drift
reports. To score the tuner against your own recordings, add WAV files to
`test/fixtures/wav/` (see the [README](test/fixtures/wav/README.md) there).

**Generated code and data:**

- **Drift database:** the generated code is committed. After editing
  `lib/core/storage/app_database.dart`, run
  `dart run build_runner build`.
- **Chord library:** `assets/chords/guitar.json` is converted from
  [chords-db](https://github.com/tombatossals/chords-db) with
  `dart run tool/chords_db/convert.dart <path-to-chords-db>`. The voicings
  it rejects are listed in
  [docs/chord-data-report.md](docs/chord-data-report.md).
- **Progression pack:** `assets/packs/chordonomicon/` holds 300 common
  chord loops aggregated from
  [Chordonomicon](https://huggingface.co/datasets/ailsntua/Chordonomicon)
  (CC BY-NC 4.0). Rebuild it with
  `dart run tool/chordonomicon/build_pack.dart <chordonomicon_v2.csv>`. To
  ship without it, delete the folder and its line in `pubspec.yaml`.
- **App icon:** the icon is drawn in code. Run
  `flutter test tool/icon/render_icon_test.dart`, then
  `tool/icon/install_icons.sh`.

**Songs:** the player assumes one chord per bar, because ChordPro has no
timing. Every bundled song was published before 1900 and cites its source
in a `{meta: source}` line, which the test suite checks.

## Roadmap

- Release-signed Android builds and a Google Play listing
- An App Store build for iOS
- Validation against real guitar recordings across more phones and rooms
- A final open-source licence for the code

## Contributing

Issues and pull requests are welcome. Before opening a pull request, run
`flutter analyze` and `flutter test`; both must pass. Keep the app
offline: no new dependency may make network calls at runtime. Any bundled
song must be in the public domain and cite its source.

## License

No open-source licence has been chosen yet, so the code is not currently
licensed for reuse. The bundled fonts, chord data, progression data and
packages each carry their own licences, listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The progression data is
CC BY-NC 4.0, which allows non-commercial use only.
