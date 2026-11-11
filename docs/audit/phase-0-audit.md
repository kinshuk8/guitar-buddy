# Fretlight navigation audit (Phase 0)

Baseline: `main` at `0a655de` (version 0.9.1+10). Branch: `restructure-navigation`. No code changed.

## 1. Baseline

| Check | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | 420 passed, 2 skipped (both wait for real recordings in `test/fixtures/wav`), 0 failed, 42 test files |
| Line coverage | 81.3% (7,527 of 9,255 lines, generated code included) |
| Lowest coverage | `record_input_source`, `soloud_output`, `app_audio_session` 0% (device plugins); `app_database` 21%; `tuner_sheets` 33% |
| Screenshots | 27 in `docs/audit/baseline/`, iPhone 17 simulator, dark theme |
| Drift schema | Version 4 |

### Stored user data (must survive the restructure)

| Table | Holds |
|---|---|
| `Settings` (key/value) | `appearance.theme`, `appearance.leftHanded`, `listen.sensitivity`, `tuner.tuning`, tuner A4, `identify.mode`, `chords.root`, `metronome.bpm/signature/subdivision/accents`, `songs.sound/pattern/click/keepAwake`, `song.<id>` (transpose, capo, tempo per song), `learn.goalMinutes`, `learn.jumpedTo` |
| `FavoriteChords` | Favourite chord symbols |
| `CustomTunings` | User tunings |
| `UserSongs` | ChordPro source of added songs |
| `CustomChords` | User-drawn chord shapes |
| `LessonRecords` | Stars, best score, attempts, last played, per lesson |
| `PracticeDays` | Seconds practised and XP per day (streak, daily goal) |
| `SkillRecords` | Chord mastery, skill levels, personal bests |

## 2. Screen map today

Launch lands on **Learn**. Six bottom tabs; only the selected tab shows its name.

| # | Screen | Reached by | Taps from launch |
|---|---|---|---|
| 1 | Learn (level, today, up next, skills, chord mastery, 55-lesson path) | launch | 0 |
| 2 | Lesson intro → lesson game → result | Learn → Up next / a lesson | 1 (playing: 2) |
| 3 | Daily chord workout | Learn → button | 1 (playing: 2) |
| 4 | Daily goal sheet | Learn → Change goal | 1 |
| 5 | Jump to a later stage | Learn → scroll → "I can already play this" → confirm | 2 + scrolling |
| 6 | Tuner | Tune tab | 1 |
| 7 | Tuning sheet | Tuner → tuning chip | 2 |
| 8 | Custom tuning editor | Tuner → chip → New custom tuning | 3 |
| 9 | Reference pitch (A4) sheet | Tuner → "440 Hz" chip | 2 |
| 10 | Settings | Tuner → gear icon (only entry point) | 2 |
| 11 | Left-handed, theme, sensitivity | Settings | 3 |
| 12 | Reset learning progress | Settings → button → confirm | 4 |
| 13 | Licences | Settings → Licences | 3 |
| 14 | Identify: note | Identify tab | 1 |
| 15 | Identify: chord | Identify tab → Chord | 2 (1 if last used) |
| 16 | Chord library | Chords tab | 1 |
| 17 | Chord detail (shapes, hear it) | Chords → chord | 2 |
| 18 | Practise one chord | Chords → chord → Practise → "Just X, 5 times" | 4 |
| 19 | Practise a change between two chords | Chords → chord → Practise → second chord | 4 |
| 20 | Draw your own chord | Chords → "+" icon | 2 |
| 21 | Favourites filter | Chords → heart icon | 2 |
| 22 | Metronome | Tempo tab | 1 (running: 2) |
| 23 | Time signature / subdivision sheets | Tempo → chip | 2 |
| 24 | Song list | Songs tab | 1 |
| 25 | Play-along | Songs → song | 2 (playing: 3) |
| 26 | Practise a song (waits for each chord) | Songs → song → ear icon | 3 |
| 27 | Arrange sheet (transpose, capo, tempo, strum, click, screen on) | Songs → song → sliders icon | 3 |
| 28 | Edit / delete own song | Songs → song → sliders icon → Edit / Delete | 4 |
| 29 | Add a song | Songs → "+" icon | 2 |
| 30 | Import ChordPro file | Songs → "+" → Import file | 3 |
| 31 | Progressions | Songs → Progressions | 2 |
| 32 | Practise a progression | Songs → Progressions → row → Practise | 4 |
| 33 | Practice screen (shared by 18, 19, 26, 32) | see above | 3–4 |
| 34 | Widget gallery (debug builds only) | Songs → bottom of list | 2 |

## 3. Problems found

**No clear home for practising chords (the app's main job)**
1. Free chord practice has no screen of its own. It is reached three different ways (chord detail sheet, progression sheet, an ear icon in play-along), each 3–4 taps deep.
2. Two practice systems that don't talk to each other: lessons record stars, XP, streak and chord mastery; the Practice screen records nothing (`practice_controller.dart` never writes progress). Ten minutes of free chord practice doesn't count toward the daily goal.
3. One-minute change races exist only inside fixed lessons. You can't race a pair you choose.
4. Progressions are practice loops but live under Songs.

**Tab bar**
5. Six tabs, five of them icon-only at any time. The Tune icon (sliders) is the same icon as "Arrange" in play-along; Identify is a waveform; Chords is a generic grid.
6. Tab positions move when the selection changes (the selected tab is twice as wide), so the same tab is in a different place depending on where you are. My own first tap on Tune missed for this reason.
7. Labels are musician shorthand: "Tune", "Tempo", "Identify". A beginner looks for "Tuner" and "Metronome".

**Buried or hidden**
8. Settings is reachable only from a gear icon on the Tuner. Left-handed mode, the first thing a left-handed beginner needs, is 3 taps deep behind a tab they may not open.
9. Edit and Delete for your own song are inside the "Arrange" sheet.
10. "I can already play this: start here" is far down the Learn scroll; an experienced user lands on "The six strings".
11. Icon-only actions with no visible label: "+" on Chords (draw a chord), heart on Chords (filter), "+" on Songs, ear and sliders in play-along.

**Screens doing too many jobs**
12. Learn is one long scroll holding level, daily goal, workout, next lesson, six skill bars, chord mastery, personal bests and all 55 lessons.
13. Arrange mixes song key/capo/tempo, backing-track options, a screen-on switch and song edit/delete. Tempo appears twice in play-along (dock slider and Arrange).
14. Chord detail is reference (shapes), audio (play) and the only doorway to chord practice.

**Inconsistent back behaviour and chrome**
15. Three mechanisms: go_router pages with a back chevron, lessons pushed on the root navigator with an "X", and sheets. Lessons and Practice hide the tab bar; chord detail and play-along keep it.
16. Closing a lesson mid-game with "X" leaves at once with no confirmation.
17. An iOS edge-swipe back did not close Settings in my one attempt (not yet confirmed as a bug; needs a test in Phase 1).
18. Tuner, Identify and Tempo have no screen title; Learn, Chords and Songs do.
19. Licences opens Flutter's stock page: different look, and "Licenses" where the app says "Licences".
20. On chord detail the hint line under the buttons is hidden behind the tab bar.

**First run and dead ends**
21. No onboarding: experience level and handedness are never asked; the mic permission prompt appears wherever you first land.
22. Empty states without a next step: "Tap the heart on a chord to keep it here", "No chord matches…", "This song is no longer here", "No chord … in the library".

**What already works and should be kept**
- Tuner is 1 tap. Tab state survives switching (a running metronome keeps going).
- Each listening screen explains the mic and has a recovery action.
- Sheets are consistent and dismiss the same way.

## 4. Proposed structure

Four tabs, always labelled, fixed width: **Home · Practice · Songs · Tools**. A labelled **Tuner** button sits in the header of every screen (tabs, lessons, practice, play-along) and opens the tuner on top of where you are; Back returns you to the same spot.

```
Home
├─ Continue: next lesson, or the song / drill you last had open
├─ Today: daily goal ring, streak, "Daily chord workout"
├─ Quick tools: Tuner · Metronome · Identify
├─ Recent songs (empty state: "Pick a first song")
└─ Settings (labelled button in the header)

Practice
├─ Lessons        the four-stage path (Beginner → Mastery), "Start at a later stage" at the top
├─ Chords         one tile per chord with its mastery ring; tap = drill that chord
├─ Changes        pick two chords: untimed switch, or one-minute race; your bests
├─ Progressions   common loops (moved from Songs)
└─ Progress       level, XP, stars, six skills, chord mastery, bests

Songs
├─ Your songs / Starter songs
├─ Add a song     write, paste, or import a ChordPro file (labelled button)
└─ Song → Play along · Practise (waits for you) · Key & capo · Edit · Delete

Tools
├─ Tuner          Advanced: tunings, custom tuning, A4 reference, raw frequency
├─ Metronome      Advanced: subdivisions, accents
├─ Identify       note or chord
├─ Chord library  search, favourites, "Draw your own"; Advanced: all shapes
└─ Settings

Onboarding (first launch, skippable): experience level, handedness, then Home.
New players are taken to: tune → first chord → first change.
```

### Where I'd challenge the brief

- **Lessons need a home.** The proposed tabs don't mention the 55-lesson course, which is the largest feature. I've put it first inside Practice rather than adding a fifth tab; free chord practice sits beside it and both feed the same progress.
- **Tools is 2 taps, the tuner must be 1.** So the tuner gets a global header button instead of relying on the Tools tab, and Home carries a quick-tools row so Metronome and Identify stay 1 tap from launch.
- **Free practice should count.** Chord and change drills started from Practice should add to minutes, streak and chord mastery. This uses the existing tables; no schema change is needed for it.
- **Schema stays at v4** unless Phase 2 needs something new (for example, recently opened songs can be a `Settings` key). Onboarding answers are `Settings` keys too. Existing users skip onboarding and keep everything.

### Taps from launch, before and after

| Feature | Before | After |
|---|---|---|
| Continue next lesson | 1 | 1 |
| Daily chord workout | 1 | 1 |
| Tuner | 1 (from tabs only) | 1 (from every screen) |
| Change tuning | 2 | 2 |
| A4 reference | 2 | 3 (under Advanced, by design) |
| Custom tuning | 3 | 3 |
| Metronome | 1 | 1 from Home, 2 elsewhere |
| Identify note or chord | 1–2 | 1 from Home, 2 elsewhere |
| Chord library | 1 | 2 |
| Practise one chord | 4 | 2 |
| Practise a change between two chords | 4 | 3 |
| One-minute race, any pair | not possible | 3 |
| Practise a progression | 4 | 3 |
| Lesson list | 0 + long scroll | 2 |
| Progress and stats | 0 + scroll | 2 (summary on Home: 0) |
| Song list | 1 | 1 |
| Open a song | 2 | 2 (recent song from Home: 1) |
| Practise a song | 3 (icon only) | 3 (labelled) |
| Key, capo | 3 (icon only) | 3 (labelled) |
| Edit / delete own song | 4 | 3 |
| Add a song | 2 (icon only) | 2 (labelled) |
| Draw your own chord | 2 (icon only) | 3 (labelled) |
| Settings | 2 (via Tuner only) | 1 from Home, 2 elsewhere |
| Left-handed mode | 3 | 2, and asked at first launch |

Every primary feature is at most 2 taps. The items at 3 are either advanced options or a choice inside a feature (which pair, which song).

## 5. Risk to existing tests

About 20 of the 42 test files refer to routes, tab names or screen text that will move (`test/support/test_app.dart`, the learn flow tests, and each screen's widget test). Plan: keep old route paths working as redirects, update tests alongside each move, and add navigation tests (tap counts, tuner from every screen, back behaviour, data survives upgrade from a v4 database) before changing screens.
