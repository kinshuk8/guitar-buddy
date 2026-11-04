import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/features/songs/domain/chordpro.dart';
import 'package:meta/meta.dart';

/// One chord change in the song's playback order.
@immutable
final class SongEvent {
  const SongEvent({
    required this.section,
    required this.line,
    required this.segment,
    required this.chord,
    required this.chordText,
    required this.startBeat,
    required this.beats,
  });

  final int section;
  final int line;
  final int segment;
  final Chord? chord;
  final String chordText;
  final double startBeat;
  final double beats;

  double get endBeat => startBeat + beats;
}

/// How the song unfolds in time.
///
/// ChordPro has no timing, so this uses the convention most chord sheets
/// follow: **one chord, one bar**. The starter songs are written with a
/// chord at every bar (repeated where it's held). For other sheets it's an
/// approximation the tempo control can make up for.
final class SongTimeline {
  SongTimeline._(this.events, this.beatsPerBar, this._sectionSpans);

  factory SongTimeline.of(Song song) {
    final beatsPerBar = song.time.$1;
    final events = <SongEvent>[];
    final spans = <int, (double, double)>{};
    var beat = 0.0;
    for (final (si, section) in song.sections.indexed) {
      final start = beat;
      for (final (li, line) in section.lines.indexed) {
        for (final (gi, seg) in line.segments.indexed) {
          final text = seg.chordText;
          if (text == null) continue;
          events.add(
            SongEvent(
              section: si,
              line: li,
              segment: gi,
              chord: seg.chord,
              chordText: text,
              startBeat: beat,
              beats: beatsPerBar.toDouble(),
            ),
          );
          beat += beatsPerBar;
        }
      }
      if (beat > start) spans[si] = (start, beat);
    }
    return SongTimeline._(List.unmodifiable(events), beatsPerBar, spans);
  }

  final List<SongEvent> events;
  final int beatsPerBar;
  final Map<int, (double, double)> _sectionSpans;

  double get totalBeats => events.isEmpty ? 0 : events.last.endBeat;

  /// Start and end beat of a section, or null if it has no chords.
  (double, double)? sectionSpan(int section) => _sectionSpans[section];

  /// Index of the event sounding at [beat] (clamped to the song).
  int indexAt(double beat) {
    if (events.isEmpty) return -1;
    var lo = 0;
    var hi = events.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (events[mid].startBeat <= beat) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// The next event with a real chord after [index] (for the "next" diagram),
  /// wrapping within [loop] when looping.
  SongEvent? nextChord(int index, {(double, double)? loop}) {
    for (var i = index + 1; i < events.length; i++) {
      final e = events[i];
      if (loop != null && e.startBeat >= loop.$2) break;
      if (e.chord != null) return e;
    }
    if (loop != null) {
      for (final e in events) {
        if (e.startBeat >= loop.$1 && e.chord != null) return e;
      }
    }
    return null;
  }
}

/// How the player wants to play it: transposed, with a capo.
///
/// The written chords sound as written. Transposing moves the sounding key;
/// a capo changes the shapes you finger (the sounding key stays put).
@immutable
final class Arrangement {
  const Arrangement({this.transpose = 0, this.capo = 0});

  final int transpose;
  final int capo;

  /// The shape to finger for a written chord.
  Chord shape(Chord written) => Transposer.shapeForCapo(written.transpose(transpose), capo);

  /// The key the audience hears.
  Chord? soundingKey(Chord? written) => written?.transpose(transpose);

  /// Spelling for the shapes, following the key you're fingering in.
  Spelling spelling(Chord? writtenKey) {
    final k = writtenKey;
    if (k == null) return Spelling.sharps;
    final shapeKey = shape(k);
    return Spelling.forKey(shapeKey.root, minor: shapeKey.quality == ChordQuality.minor);
  }

  /// A written chord symbol as you'd finger it (unparseable text unchanged).
  String display(String written, Chord? writtenKey) {
    final c = Chord.tryParse(written);
    return c == null ? written : shape(c).symbol(spelling(writtenKey));
  }

  Arrangement copyWith({int? transpose, int? capo}) =>
      Arrangement(transpose: transpose ?? this.transpose, capo: capo ?? this.capo);
}
