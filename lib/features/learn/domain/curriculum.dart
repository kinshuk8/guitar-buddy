import 'package:meta/meta.dart';

/// What a lesson trains, for the skill bars on the Learn tab.
enum Skill {
  notes('Notes', 'Strings, frets and note names'),
  chords('Chords', 'Clean shapes'),
  changes('Changes', 'Moving between chords'),
  rhythm('Rhythm', 'Strumming in time'),
  reading('Reading', 'Tab and diagrams'),
  songs('Songs', 'Putting it together');

  Skill(this.label, this.help);

  final String label;
  final String help;
}

/// One thing to do in a lesson. A lesson is one or more of these in a row.
@immutable
sealed class Exercise {
  const Exercise();

  /// Whether it needs the guitar and the microphone (quizzes don't).
  bool get listens => true;
}

/// Play each chord in turn; the app waits until it hears it. Covers single
/// chord drills (`['Em', 'Em', ...]`), changes and progressions.
final class ChordSteps extends Exercise {
  const ChordSteps(this.chords, {this.repeat = 1});

  final List<String> chords;
  final int repeat;

  List<String> get sequence => [for (var i = 0; i < repeat; i++) ...chords];
}

/// One-minute changes: switch between two chords as many times as you can,
/// cleanly, in [seconds]. Stars at [targets] changes per minute.
final class ChangeRace extends Exercise {
  const ChangeRace(this.a, this.b, {required this.targets, this.seconds = 60});

  final String a;
  final String b;
  final int seconds;
  final (int, int, int) targets;

  /// The same key whichever way round the pair is written.
  String get pairKey => ([a, b]..sort()).join('|');
}

/// A starter song in practice mode.
final class SongSteps extends Exercise {
  const SongSteps(this.songId, {this.maxChords});

  final String songId;

  /// Only the first N chords (a verse), for earlier lessons.
  final int? maxChords;
}

/// A place on the neck: string 0 is low E.
@immutable
final class Spot {
  const Spot(this.string, this.fret);

  final int string;
  final int fret;

  @override
  bool operator ==(Object other) => other is Spot && other.string == string && other.fret == fret;

  @override
  int get hashCode => Object.hash(string, fret);

  @override
  String toString() => 'Spot($string, $fret)';
}

/// How a note to find is shown.
enum NotePrompt {
  /// "Play the A string" / "Play G on the low E string".
  name,

  /// As tab: a line of fret numbers on six strings, played left to right.
  tab,
}

/// Find and play notes, heard by pitch. With [tuneCents], each must also be
/// in tune within that many cents (tuning up).
final class NoteSteps extends Exercise {
  const NoteSteps(this.spots, {this.prompt = NotePrompt.name, this.tuneCents, this.title});

  final List<Spot> spots;
  final NotePrompt prompt;
  final double? tuneCents;

  /// A tune's name, shown above a tab line.
  final String? title;
}

/// One stroke of a strum pattern, in beats from the start of the bar.
@immutable
final class Stroke {
  const Stroke(this.beat, {this.down = true});

  final double beat;
  final bool down;
}

/// Strum in time with the beat. Scored by how close each strum lands.
final class RhythmSteps extends Exercise {
  const RhythmSteps({
    required this.chord,
    required this.bpm,
    required this.pattern,
    required this.name,
    this.bars = 4,
    this.beatsPerBar = 4,
    this.windowMs = 90,
  });

  final String chord;
  final int bpm;
  final List<Stroke> pattern;
  final String name;
  final int bars;
  final int beatsPerBar;

  /// How far from the beat a strum may land and still count, either side.
  final int windowMs;

  static const downs = [Stroke(0), Stroke(1), Stroke(2), Stroke(3)];
  static const downUps = [
    Stroke(0),
    Stroke(0.5, down: false),
    Stroke(1),
    Stroke(1.5, down: false),
    Stroke(2),
    Stroke(2.5, down: false),
    Stroke(3),
    Stroke(3.5, down: false),
  ];

  /// D, DU, UDU: the strum in half the songs you know.
  static const folk = [
    Stroke(0),
    Stroke(1),
    Stroke(1.5, down: false),
    Stroke(2.5, down: false),
    Stroke(3),
    Stroke(3.5, down: false),
  ];
  static const waltz = [Stroke(0), Stroke(1), Stroke(2)];
}

/// Questions on the screen, no guitar needed.
enum QuizKind {
  /// Which string is lit?
  stringName,

  /// What note is at this string and fret?
  fretNote,

  /// What chord is this diagram?
  chordName,

  /// A fret number on a tab line: what note is it?
  tabNote,
}

final class Quiz extends Exercise {
  const Quiz(this.kinds, {this.questions = 10, this.maxFret = 0, this.chords = const []});

  final Set<QuizKind> kinds;
  final int questions;

  /// Highest fret asked about (0 = open strings only).
  final int maxFret;

  /// Chords for [QuizKind.chordName].
  final List<String> chords;

  @override
  bool get listens => false;
}

@immutable
final class Lesson {
  const Lesson({
    required this.id,
    required this.title,
    required this.about,
    required this.skill,
    required this.steps,
    this.tip,
    this.xp = 20,
  });

  /// Stable: progress is stored against it.
  final String id;
  final String title;

  /// What you'll learn and why, one or two sentences.
  final String about;
  final Skill skill;
  final List<Exercise> steps;

  /// A teacher's hint, shown before you start.
  final String? tip;
  final int xp;

  bool get listens => steps.any((s) => s.listens);

  /// Free practice (a chord drill, a change race) rather than a lesson on
  /// the path: it builds mastery and practice time but earns no stars.
  bool get isDrill => id.startsWith(drillPrefix);

  static const drillPrefix = 'drill:';

  /// Chord symbols the lesson asks for, in order of appearance.
  List<String> get chords {
    final out = <String>[];
    for (final s in steps) {
      final specs = switch (s) {
        ChordSteps(:final chords) => chords,
        ChangeRace(:final a, :final b) => [a, b],
        RhythmSteps(:final chord) => [chord],
        Quiz(:final chords) => chords,
        SongSteps() || NoteSteps() => const <String>[],
      };
      for (final c in specs.map(chordSymbolOf)) {
        if (!out.contains(c)) out.add(c);
      }
    }
    return out;
  }
}

@immutable
final class Unit {
  const Unit(this.title, this.lessons);

  final String title;
  final List<Lesson> lessons;
}

@immutable
final class Stage {
  const Stage({required this.id, required this.title, required this.about, required this.units});

  final String id;
  final String title;
  final String about;
  final List<Unit> units;

  List<Lesson> get lessons => [for (final u in units) ...u.lessons];
}

/// A lesson names a chord by symbol, optionally pinning the shape to show:
/// `G:355433` is G played as a barre at the 3rd fret (frets low E to high
/// E, `x` = muted). The mic only cares about the symbol.
String chordSymbolOf(String spec) => spec.split(':').first;

/// The pinned shape of [spec], if any.
List<int?>? chordFretsOf(String spec) {
  final parts = spec.split(':');
  if (parts.length != 2 || parts[1].length != 6) return null;
  return [
    for (final ch in parts[1].split(''))
      if (ch == 'x') null else int.parse(ch),
  ];
}

/// Open strings, low to high.
const _open = [Spot(0, 0), Spot(1, 0), Spot(2, 0), Spot(3, 0), Spot(4, 0), Spot(5, 0)];

/// The path from first chord to fluent player. Ordered the way teachers
/// tend to: a few easy shapes and changes first, rhythm alongside, a song
/// as soon as two chords allow one; reading and the fretboard once your
/// hands know the basics; barre chords once changes are quick.
///
/// Songs are the bundled public-domain starters.
const curriculum = <Stage>[
  Stage(
    id: 'beginner',
    title: 'Beginner',
    about: 'Your first chords, your first changes, your first song.',
    units: [
      Unit('Meet your guitar', [
        Lesson(
          id: 'b.strings',
          title: 'The six strings',
          about: 'Strings are named E A D G B E, from the thickest to the thinnest.',
          tip: 'Eddie Ate Dynamite, Good Bye Eddie.',
          skill: Skill.notes,
          steps: [
            Quiz({QuizKind.stringName}, questions: 8),
            NoteSteps(_open),
          ],
        ),
        Lesson(
          id: 'b.tune',
          title: 'Tune up',
          about: 'Every practice starts in tune. Play each string until it is within 10 cents.',
          tip: 'Tune up to the note: if you are sharp, go below it and come back up.',
          skill: Skill.notes,
          steps: [NoteSteps(_open, tuneCents: 10)],
        ),
      ]),
      Unit('First chords', [
        Lesson(
          id: 'b.em',
          title: 'E minor',
          about: 'Two fingers, all six strings. The easiest full chord on the guitar.',
          tip: 'Fingertips just behind the fret, thumb behind the neck.',
          skill: Skill.chords,
          steps: [
            ChordSteps(['Em'], repeat: 5),
          ],
        ),
        Lesson(
          id: 'b.am',
          title: 'A minor',
          about: 'Same shape as E minor, one string over, plus a finger on the B string.',
          tip: 'Leave the low E string out: start your strum on the A string.',
          skill: Skill.chords,
          steps: [
            ChordSteps(['Am'], repeat: 5),
          ],
        ),
        Lesson(
          id: 'b.em-am',
          title: 'Em to Am',
          about: 'Your first change. Move your fingers together, as one shape.',
          tip: 'Slow and clean beats fast and messy.',
          skill: Skill.changes,
          steps: [
            ChordSteps(['Em', 'Am'], repeat: 4),
            ChangeRace('Em', 'Am', targets: (10, 18, 26)),
          ],
        ),
        Lesson(
          id: 'b.chord-quiz',
          title: 'Read a chord diagram',
          about: 'Strings run top to bottom, frets left to right on the page: learn to read the boxes.',
          skill: Skill.reading,
          steps: [
            Quiz({QuizKind.chordName}, chords: ['Em', 'Am', 'E', 'A', 'D', 'G']),
          ],
        ),
      ]),
      Unit('Strum', [
        Lesson(
          id: 'b.downs',
          title: 'Down strums on the beat',
          about: 'One strum per beat, steady as a clock. Rhythm matters more than any chord.',
          tip: 'Move from the elbow and keep your wrist loose.',
          skill: Skill.rhythm,
          steps: [
            RhythmSteps(chord: 'Em', bpm: 60, pattern: RhythmSteps.downs, name: 'Four downs'),
          ],
        ),
        Lesson(
          id: 'b.downs-am',
          title: 'Strum and change',
          about: 'Keep the beat going while you switch chords.',
          skill: Skill.rhythm,
          steps: [
            RhythmSteps(chord: 'Am', bpm: 60, pattern: RhythmSteps.downs, name: 'Four downs'),
            ChordSteps(['Em', 'Am', 'Em', 'Am'], repeat: 2),
          ],
        ),
      ]),
      Unit('D and G', [
        Lesson(
          id: 'b.d',
          title: 'D major',
          about: 'A bright little triangle on the top three strings.',
          tip: 'Strum from the D string down: four strings only.',
          skill: Skill.chords,
          steps: [
            ChordSteps(['D'], repeat: 5),
          ],
        ),
        Lesson(
          id: 'b.g',
          title: 'G major',
          about: 'The big, full chord of folk and country.',
          tip: 'Reach the low E string with your middle finger and let the open strings ring.',
          skill: Skill.chords,
          steps: [
            ChordSteps(['G'], repeat: 5),
          ],
        ),
        Lesson(
          id: 'b.g-d',
          title: 'G to D',
          about: 'Two chords that carry hundreds of songs.',
          skill: Skill.changes,
          steps: [
            ChordSteps(['G', 'D'], repeat: 4),
            ChangeRace('G', 'D', targets: (10, 18, 26)),
          ],
        ),
        Lesson(
          id: 'b.clementine',
          title: 'First song: Clementine',
          about: 'Only G and D. Play through the first verse, chord by chord.',
          skill: Skill.songs,
          xp: 40,
          steps: [SongSteps('clementine', maxChords: 16)],
        ),
      ]),
    ],
  ),
  Stage(
    id: 'improver',
    title: 'Improver',
    about: 'All the open chords, a real strum pattern, and the notes under your fingers.',
    units: [
      Unit('More open chords', [
        Lesson(
          id: 'i.a-e',
          title: 'A and E',
          about: 'A packs three fingers into one fret; E is A minor’s shape moved over.',
          skill: Skill.chords,
          steps: [
            ChordSteps(['A'], repeat: 3),
            ChordSteps(['E'], repeat: 3),
            ChordSteps(['A', 'D', 'E'], repeat: 2),
          ],
        ),
        Lesson(
          id: 'i.c',
          title: 'C major',
          about: 'The stretch chord: three fingers over three frets.',
          tip: 'Arch your fingers so the open G and E strings ring.',
          skill: Skill.chords,
          steps: [
            ChordSteps(['C'], repeat: 5),
          ],
        ),
        Lesson(
          id: 'i.c-g',
          title: 'C to G',
          about: 'The change most beginners find hardest. One minute at a time.',
          skill: Skill.changes,
          steps: [
            ChordSteps(['C', 'G'], repeat: 4),
            ChangeRace('C', 'G', targets: (12, 20, 30)),
          ],
        ),
        Lesson(
          id: 'i.dm',
          title: 'D minor',
          about: 'D with one finger moved: hear how one note turns major to minor.',
          skill: Skill.chords,
          steps: [
            ChordSteps(['D', 'Dm'], repeat: 3),
          ],
        ),
        Lesson(
          id: 'i.a-d',
          title: 'A to D',
          about: 'Keep your first finger’s neighbourhood: a short, quick move.',
          skill: Skill.changes,
          steps: [ChangeRace('A', 'D', targets: (14, 22, 32))],
        ),
        Lesson(
          id: 'i.open-quiz',
          title: 'Name that chord',
          about: 'All your open chords, at a glance.',
          skill: Skill.reading,
          steps: [
            Quiz(
              {QuizKind.chordName},
              questions: 12,
              chords: ['C', 'G', 'D', 'A', 'E', 'Am', 'Em', 'Dm'],
            ),
          ],
        ),
      ]),
      Unit('Strum patterns', [
        Lesson(
          id: 'i.down-up',
          title: 'Down and up',
          about: 'Eighth notes: down on the beat, up in between. Your hand never stops.',
          tip: 'Keep the hand moving even when it misses the strings.',
          skill: Skill.rhythm,
          steps: [
            RhythmSteps(chord: 'G', bpm: 60, pattern: RhythmSteps.downUps, name: 'D U D U D U D U'),
          ],
        ),
        Lesson(
          id: 'i.folk',
          title: 'The folk strum',
          about: 'D, DU, UDU: skip the down on beat 3 and the strum starts to swing.',
          skill: Skill.rhythm,
          steps: [
            RhythmSteps(chord: 'C', bpm: 66, pattern: RhythmSteps.folk, name: 'D  D U  U D U'),
          ],
        ),
        Lesson(
          id: 'i.waltz',
          title: 'Three-four time',
          about: 'Three beats to the bar: the strum of Amazing Grace and Clementine.',
          skill: Skill.rhythm,
          steps: [
            RhythmSteps(
              chord: 'D',
              bpm: 80,
              pattern: RhythmSteps.waltz,
              name: 'ONE two three',
              beatsPerBar: 3,
            ),
          ],
        ),
      ]),
      Unit('Notes on the neck', [
        Lesson(
          id: 'i.low-e',
          title: 'Notes on the low E string',
          about: 'E, F, G, A, B, C: the notes behind every root on the sixth string.',
          tip: 'There’s no sharp between B and C or between E and F.',
          skill: Skill.notes,
          steps: [
            Quiz({QuizKind.fretNote}, maxFret: 5),
            NoteSteps([Spot(0, 0), Spot(0, 1), Spot(0, 3), Spot(0, 5)]),
          ],
        ),
        Lesson(
          id: 'i.a-string',
          title: 'Notes on the A string',
          about: 'The roots of A, B, C and D chords.',
          skill: Skill.notes,
          steps: [
            NoteSteps([Spot(1, 0), Spot(1, 2), Spot(1, 3), Spot(1, 5)]),
          ],
        ),
        Lesson(
          id: 'i.tab',
          title: 'Reading tab',
          about: 'Six lines are the six strings, high E on top; a number is the fret to play.',
          skill: Skill.reading,
          steps: [
            Quiz({QuizKind.tabNote}, maxFret: 3),
            NoteSteps(
              [Spot(3, 0), Spot(3, 2), Spot(4, 0), Spot(4, 1), Spot(4, 0), Spot(3, 2), Spot(3, 0)],
              prompt: NotePrompt.tab,
              title: 'Up and back',
            ),
          ],
        ),
      ]),
      Unit('Songs', [
        Lesson(
          id: 'i.swing-low',
          title: 'Swing Low, Sweet Chariot',
          about: 'A, D and G, at a gentle tempo.',
          skill: Skill.songs,
          xp: 40,
          steps: [SongSteps('swing_low')],
        ),
        Lesson(
          id: 'i.oh-susanna',
          title: 'Oh! Susanna',
          about: 'C, D and G: your first song with C.',
          skill: Skill.songs,
          xp: 40,
          steps: [SongSteps('oh_susanna')],
        ),
        Lesson(
          id: 'i.scarborough',
          title: 'Scarborough Fair',
          about: 'A minor-key ballad: Am, C, D and G.',
          skill: Skill.songs,
          xp: 40,
          steps: [SongSteps('scarborough_fair')],
        ),
      ]),
    ],
  ),
  Stage(
    id: 'adept',
    title: 'Adept',
    about: 'Your first barre chord, sevenths, faster changes and melodies from tab.',
    units: [
      Unit('The F chord', [
        Lesson(
          id: 'a.fmaj7',
          title: 'Easy F (Fmaj7)',
          about: 'The F shape without the barre: a stepping stone.',
          skill: Skill.chords,
          steps: [
            ChordSteps(['Fmaj7'], repeat: 4),
          ],
        ),
        Lesson(
          id: 'a.f',
          title: 'F major',
          about: 'One finger flat across all six strings. Everyone struggles with it; everyone gets it.',
          tip: 'Roll your first finger slightly onto its bony side, and pull back with your arm, not your thumb.',
          skill: Skill.chords,
          xp: 30,
          steps: [
            ChordSteps(['F'], repeat: 5),
          ],
        ),
        Lesson(
          id: 'a.c-f',
          title: 'C to F',
          about: 'The change that unlocks songs in C.',
          skill: Skill.changes,
          steps: [
            ChordSteps(['C', 'F'], repeat: 3),
            ChangeRace('C', 'F', targets: (10, 18, 26)),
          ],
        ),
      ]),
      Unit('Sevenths and colours', [
        Lesson(
          id: 'a.sevenths',
          title: 'Seventh chords',
          about: 'G7, D7, A7 and E7: the chords that pull you home.',
          skill: Skill.chords,
          steps: [
            ChordSteps(['G7', 'C', 'D7', 'G', 'A7', 'D', 'E7', 'A']),
          ],
        ),
        Lesson(
          id: 'a.sus',
          title: 'Sus chords',
          about: 'Lift a finger or add one: Dsus2, Dsus4 and Asus4 add movement to plain chords.',
          skill: Skill.chords,
          steps: [
            ChordSteps(['D', 'Dsus4', 'D', 'Dsus2', 'A', 'Asus4', 'A']),
          ],
        ),
        Lesson(
          id: 'a.bm',
          title: 'B minor',
          about: 'A barre from the second fret: the A minor shape moved up.',
          skill: Skill.chords,
          xp: 30,
          steps: [
            ChordSteps(['Bm:x24432'], repeat: 4),
            ChordSteps(['G', 'D', 'Bm:x24432', 'A'], repeat: 2),
          ],
        ),
      ]),
      Unit('Faster changes', [
        Lesson(
          id: 'a.g-c-race',
          title: 'G to C, faster',
          about: 'Aim for one change every two seconds.',
          skill: Skill.changes,
          steps: [ChangeRace('G', 'C', targets: (20, 30, 40))],
        ),
        Lesson(
          id: 'a.am-f-race',
          title: 'Am to F',
          about: 'Your first finger stays on the B string’s first fret: use it as a pivot.',
          skill: Skill.changes,
          steps: [ChangeRace('Am', 'F', targets: (14, 22, 30))],
        ),
        Lesson(
          id: 'a.pop',
          title: 'The four-chord loop',
          about: 'C, G, Am, F: the progression behind countless songs.',
          skill: Skill.changes,
          steps: [
            ChordSteps(['C', 'G', 'Am', 'F'], repeat: 4),
          ],
        ),
        Lesson(
          id: 'a.syncopation',
          title: 'Folk strum, faster',
          about: 'The folk strum at a real song tempo, with a change every bar.',
          skill: Skill.rhythm,
          steps: [
            RhythmSteps(
              chord: 'G',
              bpm: 90,
              pattern: RhythmSteps.folk,
              name: 'D  D U  U D U',
              windowMs: 70,
            ),
          ],
        ),
      ]),
      Unit('Melodies from tab', [
        Lesson(
          id: 'a.ode',
          title: 'Ode to Joy',
          about: 'Beethoven’s melody (public domain) on the B and G strings.',
          skill: Skill.reading,
          xp: 30,
          steps: [
            NoteSteps(
              [
                Spot(4, 0), Spot(4, 0), Spot(4, 1), Spot(4, 3), //
                Spot(4, 3), Spot(4, 1), Spot(4, 0), Spot(3, 2),
                Spot(3, 0), Spot(3, 0), Spot(3, 2), Spot(4, 0),
                Spot(4, 0), Spot(3, 2), Spot(3, 2),
              ],
              prompt: NotePrompt.tab,
              title: 'Ode to Joy',
            ),
          ],
        ),
        Lesson(
          id: 'a.twinkle',
          title: 'Twinkle, Twinkle',
          about: 'A traditional melody across three strings.',
          skill: Skill.reading,
          xp: 30,
          steps: [
            NoteSteps(
              [
                Spot(1, 3), Spot(1, 3), Spot(3, 0), Spot(3, 0), //
                Spot(3, 2), Spot(3, 2), Spot(3, 0),
                Spot(2, 3), Spot(2, 3), Spot(2, 2), Spot(2, 2),
                Spot(2, 0), Spot(2, 0), Spot(1, 3),
              ],
              prompt: NotePrompt.tab,
              title: 'Twinkle, Twinkle, Little Star',
            ),
          ],
        ),
      ]),
      Unit('Songs', [
        Lesson(
          id: 'a.amazing-grace',
          title: 'Amazing Grace',
          about: 'G, G7, C and D in three-four time.',
          skill: Skill.songs,
          xp: 40,
          steps: [SongSteps('amazing_grace')],
        ),
        Lesson(
          id: 'a.michael',
          title: 'Michael, Row the Boat Ashore',
          about: 'With F and D minor: the barre chord in a song.',
          skill: Skill.songs,
          xp: 40,
          steps: [SongSteps('michael_row')],
        ),
        Lesson(
          id: 'a.aura-lee',
          title: 'Aura Lee',
          about: 'Sevenths, F and A minor in one lovely tune.',
          skill: Skill.songs,
          xp: 50,
          steps: [SongSteps('aura_lee')],
        ),
      ]),
    ],
  ),
  Stage(
    id: 'mastery',
    title: 'Mastery',
    about: 'Barre shapes anywhere on the neck, every note, every key, at speed.',
    units: [
      Unit('Barre chords anywhere', [
        Lesson(
          id: 'm.e-shape',
          title: 'E-shape barre chords',
          about: 'The F shape slides up the neck: G at the 3rd fret, A at the 5th, Bb at the 6th.',
          skill: Skill.chords,
          xp: 40,
          steps: [
            ChordSteps(['F:133211', 'G:355433', 'A:577655', 'Bb:688766']),
          ],
        ),
        Lesson(
          id: 'm.a-shape',
          title: 'A-shape barre chords',
          about: 'The Bm shape slides too: Cm at the 3rd fret, C#m at the 4th, Dm at the 5th.',
          skill: Skill.chords,
          xp: 40,
          steps: [
            ChordSteps(['Bm:x24432', 'Cm:x35543', 'C#m:x46654', 'Dm:x57765']),
          ],
        ),
        Lesson(
          id: 'm.barre-race',
          title: 'F to Bb',
          about: 'Two barre chords, one minute.',
          skill: Skill.changes,
          steps: [ChangeRace('F', 'Bb', targets: (16, 24, 34))],
        ),
      ]),
      Unit('Every key', [
        Lesson(
          id: 'm.key-g',
          title: 'I–IV–V in G and D',
          about: 'The three chords of a key. Learn their positions and any song follows.',
          skill: Skill.changes,
          steps: [
            ChordSteps(['G', 'C', 'D', 'G', 'D', 'G', 'A', 'D'], repeat: 2),
          ],
        ),
        Lesson(
          id: 'm.key-a',
          title: 'I–IV–V in A, E and C',
          about: 'Same pattern, three more keys.',
          skill: Skill.changes,
          steps: [
            ChordSteps(['A', 'D', 'E', 'A', 'E', 'A', 'B7', 'E', 'C', 'F', 'G', 'C']),
          ],
        ),
        Lesson(
          id: 'm.minor-keys',
          title: 'Minor keys',
          about: 'i–iv–v and the borrowed major V: Am, Dm, E and Em, Am, B7.',
          skill: Skill.changes,
          steps: [
            ChordSteps(['Am', 'Dm', 'E', 'Am', 'Em', 'Am', 'B7', 'Em']),
          ],
        ),
      ]),
      Unit('The whole neck', [
        Lesson(
          id: 'm.all-strings',
          title: 'Notes on every string',
          about: 'Any note, any string, up to the 7th fret.',
          skill: Skill.notes,
          xp: 40,
          steps: [
            Quiz({QuizKind.fretNote}, questions: 15, maxFret: 7),
            NoteSteps([Spot(2, 5), Spot(3, 4), Spot(4, 3), Spot(5, 7), Spot(0, 7), Spot(1, 7)]),
          ],
        ),
        Lesson(
          id: 'm.octaves',
          title: 'Octave shapes',
          about: 'The same note two strings up and two frets over: find any note twice.',
          skill: Skill.notes,
          steps: [
            NoteSteps([Spot(0, 3), Spot(2, 5), Spot(1, 3), Spot(3, 5), Spot(0, 5), Spot(2, 7)]),
          ],
        ),
      ]),
      Unit('Speed and flow', [
        Lesson(
          id: 'm.speed-g-c',
          title: 'G to C at speed',
          about: 'Forty changes a minute: a change every beat and a half at 60 BPM.',
          skill: Skill.changes,
          xp: 40,
          steps: [ChangeRace('G', 'C', targets: (30, 40, 50))],
        ),
        Lesson(
          id: 'm.speed-am-f',
          title: 'Am to F at speed',
          about: 'Barre changes without the pause.',
          skill: Skill.changes,
          xp: 40,
          steps: [ChangeRace('Am', 'F', targets: (24, 32, 42))],
        ),
        Lesson(
          id: 'm.fast-strum',
          title: 'Sixteenth feel',
          about: 'Down-up eighths at a lively 100 BPM, tight to the beat.',
          skill: Skill.rhythm,
          xp: 40,
          steps: [
            RhythmSteps(
              chord: 'Em',
              bpm: 100,
              pattern: RhythmSteps.downUps,
              name: 'D U D U D U D U',
              windowMs: 50,
            ),
          ],
        ),
        Lesson(
          id: 'm.jingle',
          title: 'Jingle Bells',
          about: 'Five chords at 120 BPM: the full song, no stops.',
          skill: Skill.songs,
          xp: 60,
          steps: [SongSteps('jingle_bells')],
        ),
        Lesson(
          id: 'm.dreamer',
          title: 'Beautiful Dreamer',
          about: 'Sevenths and F in a flowing waltz.',
          skill: Skill.songs,
          xp: 60,
          steps: [SongSteps('beautiful_dreamer')],
        ),
      ]),
    ],
  ),
];

/// Every lesson in path order.
final List<Lesson> allLessons = [for (final s in curriculum) ...s.lessons];

/// A new player's first sitting, offered once after the welcome screens:
/// tune up, one chord, one change. Not part of the path, so it never
/// locks or unlocks anything.
const firstSession = Lesson(
  id: 'first-session',
  title: 'Your first session',
  about: 'Tune up, play your first chord, then change to a second one. About five minutes.',
  tip: 'Press with your fingertips, just behind the fret, and let every string ring.',
  skill: Skill.chords,
  xp: 30,
  steps: [
    NoteSteps(_open, tuneCents: 10),
    ChordSteps(['Em'], repeat: 4),
    ChordSteps(['Em', 'Am'], repeat: 3),
  ],
);

Lesson? lessonById(String id) => allLessons.where((l) => l.id == id).firstOrNull;

Stage stageOf(Lesson lesson) => curriculum.firstWhere((s) => s.lessons.contains(lesson));

/// Every chord the course teaches, as it first appears (a spec such as
/// `G` or `Bm:x24432`), grouped by the stage that introduces it.
final List<({Stage stage, List<String> specs})> chordsByStage = () {
  final seen = <String>{};
  return [
    for (final stage in curriculum)
      (
        stage: stage,
        specs: [
          for (final lesson in stage.lessons)
            for (final step in lesson.steps)
              for (final spec in switch (step) {
                ChordSteps(:final chords) => chords,
                ChangeRace(:final a, :final b) => [a, b],
                RhythmSteps(:final chord) => [chord],
                _ => const <String>[],
              })
                if (seen.add(chordSymbolOf(spec))) spec,
        ],
      ),
  ];
}();

/// The teaching spec for [symbol] (`Bm` → `Bm:x24432`), or the symbol
/// itself for a chord the course doesn't teach.
String chordSpecFor(String symbol) {
  for (final g in chordsByStage) {
    for (final spec in g.specs) {
      if (chordSymbolOf(spec) == symbol) return spec;
    }
  }
  return symbol;
}

/// Five clean strums of one chord: a free drill.
Lesson chordDrill(String symbol) => Lesson(
  id: '${Lesson.drillPrefix}chord:$symbol',
  title: '$symbol drill',
  about: 'Five clean strums. Lift your hand off between strums so each one is a fresh shape.',
  tip: 'Every string should ring. If one buzzes or is muted, press closer to the fret.',
  skill: Skill.chords,
  xp: 10,
  steps: [
    ChordSteps([chordSpecFor(symbol)], repeat: 5),
  ],
);

/// Back and forth between two chords, untimed: it waits for each one.
Lesson changeDrill(String a, String b) => Lesson(
  id: '${Lesson.drillPrefix}change:$a|$b',
  title: '$a to $b',
  about: 'Switch between $a and $b, four times each way. Take your time; it waits for you.',
  tip: 'Look for a finger that stays put or slides between the two shapes, and move it first.',
  skill: Skill.changes,
  xp: 10,
  steps: [
    ChordSteps([chordSpecFor(a), chordSpecFor(b)], repeat: 4),
  ],
);
