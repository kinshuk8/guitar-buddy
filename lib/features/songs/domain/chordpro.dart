import 'package:fretlight/core/music/music.dart';
import 'package:meta/meta.dart';

/// A song parsed from ChordPro (https://www.chordpro.org).
///
/// Supported: `{title}` `{subtitle}` `{artist}` `{key}` `{tempo}` `{time}`
/// `{capo}` `{comment}` `{meta: name value}` and their short forms;
/// verse / chorus / bridge environments (with optional labels); `{chorus}`
/// to repeat the last chorus; inline `[chords]`; `#` comment lines.
/// Anything else is kept as a warning, never a failure: a sheet that
/// imports with an unknown directive should still be playable.
@immutable
final class Song {
  const Song({
    required this.title,
    required this.sections,
    this.subtitle,
    this.artists = const [],
    this.key,
    this.tempo,
    this.time = const (4, 4),
    this.capo = 0,
    this.meta = const {},
    this.warnings = const [],
  });

  final String title;
  final String? subtitle;
  final List<String> artists;
  final Chord? key;
  final int? tempo;
  final (int, int) time;
  final int capo;
  final Map<String, List<String>> meta;
  final List<SongSection> sections;

  /// Things the parser skipped or couldn't read, for the import screen.
  final List<String> warnings;

  /// Every chord in the song, in order of first appearance.
  List<Chord> get chords {
    final seen = <Chord>[];
    for (final s in sections) {
      for (final l in s.lines) {
        for (final seg in l.segments) {
          if (seg.chord case final c? when !seen.contains(c)) seen.add(c);
        }
      }
    }
    return seen;
  }
}

enum SectionKind { verse, chorus, bridge, intro, outro, other }

@immutable
final class SongSection {
  const SongSection({required this.kind, required this.lines, this.label, this.repeat = false});

  final SectionKind kind;

  /// The heading shown (`Verse 2`, `Chorus`), if any.
  final String? label;
  final List<SongLine> lines;

  /// A `{chorus}` reference: the same chorus again.
  final bool repeat;

  String get displayLabel =>
      label ??
      switch (kind) {
        SectionKind.verse => 'Verse',
        SectionKind.chorus => 'Chorus',
        SectionKind.bridge => 'Bridge',
        SectionKind.intro => 'Intro',
        SectionKind.outro => 'Outro',
        SectionKind.other => '',
      };
}

/// One line of the sheet: lyric text with chords placed on syllables, or a
/// comment (`{c: Slowly}`), or a blank.
@immutable
final class SongLine {
  const SongLine(this.segments, {this.comment});

  const SongLine.comment(String text) : segments = const [], comment = text;

  /// Lyric split at each chord. The first segment may have no chord.
  final List<LineSegment> segments;
  final String? comment;

  bool get hasChords => segments.any((s) => s.chord != null || s.chordText != null);
  bool get isBlank =>
      comment == null && segments.every((s) => s.text.trim().isEmpty && s.chordText == null);
  String get lyrics => segments.map((s) => s.text).join();
}

@immutable
final class LineSegment {
  const LineSegment({required this.text, this.chordText, this.chord});

  /// The chord as written (`G7`, `N.C.`), shown even if it can't be parsed.
  final String? chordText;

  /// Parsed chord, or null for `N.C.`, `%` and the like.
  final Chord? chord;
  final String text;
}

final class ChordProParser {
  static final _directive = RegExp(r'^\{\s*([A-Za-z_][\w-]*)\s*(?::\s*(.*?))?\s*\}\s*$');
  static final _chordRun = RegExp(r'\[([^\]]*)\]');

  static Song parse(String source) {
    final warnings = <String>[];
    String? title;
    String? subtitle;
    final artists = <String>[];
    Chord? key;
    int? tempo;
    var time = (4, 4);
    var capo = 0;
    final meta = <String, List<String>>{};
    final sections = <SongSection>[];
    SongSection? lastChorus;

    var kind = SectionKind.other;
    String? label;
    var lines = <SongLine>[];
    var inEnv = false;

    void flush() {
      // Trim blank lines at the edges of a section.
      while (lines.isNotEmpty && lines.first.isBlank) {
        lines.removeAt(0);
      }
      while (lines.isNotEmpty && lines.last.isBlank) {
        lines.removeLast();
      }
      if (lines.isNotEmpty) {
        final s = SongSection(kind: kind, label: label, lines: List.unmodifiable(lines));
        sections.add(s);
        if (kind == SectionKind.chorus) lastChorus = s;
      }
      lines = [];
      kind = SectionKind.other;
      label = null;
    }

    void begin(SectionKind k, String? l) {
      flush();
      kind = k;
      label = (l == null || l.isEmpty) ? null : l;
      inEnv = true;
    }

    final rows = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    for (final (i, raw) in rows.indexed) {
      final line = raw.trimRight();
      if (line.trimLeft().startsWith('#')) continue;
      final d = _directive.firstMatch(line.trim());
      if (d != null) {
        final name = d.group(1)!.toLowerCase();
        final value = d.group(2)?.trim() ?? '';
        switch (name) {
          case 'title' || 't':
            title = value;
          case 'subtitle' || 'st':
            subtitle = value;
          case 'artist' || 'composer' || 'lyricist':
            if (value.isNotEmpty) artists.add(value);
          case 'key':
            key = Chord.tryParse(value);
            if (key == null) warnings.add('Line ${i + 1}: key “$value” not understood');
          case 'tempo':
            tempo = int.tryParse(value.split(RegExp(r'\s')).first);
            if (tempo == null) warnings.add('Line ${i + 1}: tempo “$value” not understood');
          case 'time':
            final parts = value.split('/');
            final b = parts.length == 2 ? int.tryParse(parts[0]) : null;
            final u = parts.length == 2 ? int.tryParse(parts[1]) : null;
            if (b != null && u != null && b > 0) {
              time = (b, u);
            } else {
              warnings.add('Line ${i + 1}: time “$value” not understood');
            }
          case 'capo':
            capo = (int.tryParse(value) ?? 0).clamp(0, 12);
          case 'meta':
            final sp = value.indexOf(RegExp(r'\s'));
            if (sp > 0) (meta[value.substring(0, sp)] ??= []).add(value.substring(sp).trim());
          case 'comment' || 'c' || 'comment_italic' || 'ci' || 'comment_box' || 'cb' || 'highlight':
            lines.add(SongLine.comment(value));
          case 'start_of_verse' || 'sov':
            begin(SectionKind.verse, value);
          case 'start_of_chorus' || 'soc':
            begin(SectionKind.chorus, value);
          case 'start_of_bridge' || 'sob':
            begin(SectionKind.bridge, value);
          case 'start_of_intro':
            begin(SectionKind.intro, value);
          case 'start_of_outro':
            begin(SectionKind.outro, value);
          case final n when n.startsWith('start_of_'):
            begin(SectionKind.other, value.isEmpty ? _titleCase(n.substring(9)) : value);
          case final n when n.startsWith('end_of_') || const {'eov', 'eoc', 'eob'}.contains(n):
            flush();
            inEnv = false;
          case 'chorus':
            flush();
            final c = lastChorus;
            if (c == null) {
              warnings.add('Line ${i + 1}: {chorus} before any chorus');
            } else {
              sections.add(
                SongSection(
                  kind: SectionKind.chorus,
                  label: value.isEmpty ? c.label : value,
                  lines: c.lines,
                  repeat: true,
                ),
              );
            }
          case final n when n.startsWith('x_'):
            break; // Custom extensions: ignored by design.
          default:
            warnings.add('Line ${i + 1}: {$name} ignored');
        }
        continue;
      }
      // Outside an environment, a blank line separates paragraphs.
      if (line.trim().isEmpty && !inEnv) {
        flush();
        continue;
      }
      lines.add(_parseLyricLine(line, warnings, i + 1));
    }
    flush();

    return Song(
      title: (title == null || title.isEmpty) ? 'Untitled' : title,
      subtitle: subtitle,
      artists: List.unmodifiable(artists),
      key: key,
      tempo: tempo,
      time: time,
      capo: capo,
      meta: Map.unmodifiable(meta),
      sections: List.unmodifiable(sections),
      warnings: List.unmodifiable(warnings),
    );
  }

  static SongLine _parseLyricLine(String line, List<String> warnings, int lineNo) {
    final segments = <LineSegment>[];
    var pos = 0;
    String? pending;
    for (final m in _chordRun.allMatches(line)) {
      final text = line.substring(pos, m.start);
      if (text.isNotEmpty || pending != null) {
        segments.add(
          LineSegment(text: text, chordText: pending, chord: _chord(pending, warnings, lineNo)),
        );
      }
      pending = m.group(1)!.trim();
      pos = m.end;
    }
    segments.add(
      LineSegment(
        text: line.substring(pos),
        chordText: pending,
        chord: _chord(pending, warnings, lineNo),
      ),
    );
    return SongLine(List.unmodifiable(segments));
  }

  static Chord? _chord(String? text, List<String> warnings, int lineNo) {
    if (text == null || text.isEmpty) return null;
    if (const {'N.C.', 'NC', 'N.C', '%', '/', 'x', '-'}.contains(text)) return null;
    final c = Chord.tryParse(text);
    if (c == null) warnings.add('Line $lineNo: chord “$text” not recognised');
    return c;
  }

  static String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');
}
