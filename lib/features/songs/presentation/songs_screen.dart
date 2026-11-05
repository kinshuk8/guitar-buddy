import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/widgets/glass.dart';
import 'package:fretlight/core/widgets/glass_controls.dart';
import 'package:fretlight/core/widgets/stage_buttons.dart';
import 'package:fretlight/features/chords/application/chord_library_provider.dart';
import 'package:fretlight/features/progressions/data/progression_pack.dart';
import 'package:fretlight/features/progressions/presentation/progressions_view.dart';
import 'package:fretlight/features/songs/application/songs_controller.dart';
import 'package:fretlight/features/songs/domain/chordpro.dart';
import 'package:go_router/go_router.dart';

void openSong(BuildContext context, String id) =>
    unawaited(context.push('/songs/play?id=${Uri.encodeQueryComponent(id)}'));

enum _View { songs, progressions }

/// Your songs first, then the public-domain starters; and, when the
/// optional pack is installed, common progressions to practise.
class SongsScreen extends ConsumerStatefulWidget {
  const SongsScreen({super.key});

  @override
  ConsumerState<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends ConsumerState<SongsScreen> {
  _View _view = _View.songs;

  @override
  Widget build(BuildContext context) {
    final songs = ref.watch(songsProvider);
    final pack = ref.watch(progressionPackProvider).value;
    final view = pack == null ? _View.songs : _view;
    final t = context.stageText;
    final c = context.stage;
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 0),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(header: true, child: Text('Songs', style: t.display)),
                  ),
                  if (view == _View.songs)
                    GlassIconButton(
                      icon: Icons.add_rounded,
                      semantics: 'Add a song',
                      onTap: () => showSongEditor(context),
                    ),
                ],
              ),
            ),
          ),
          if (pack != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, 0),
              sliver: SliverToBoxAdapter(
                child: StageSegmented<_View>(
                  options: _View.values,
                  selected: view,
                  labelOf: (v) => switch (v) {
                    _View.songs => 'Songs',
                    _View.progressions => 'Progressions',
                  },
                  onChanged: (v) => setState(() => _view = v),
                ),
              ),
            ),
          if (view == _View.progressions && pack != null)
            ...progressionSlivers(context, pack)
          else
            ...switch (songs) {
              AsyncData(:final value) => [
                if (value.any((e) => !e.bundled)) ...[
                  _header('Your songs'),
                  _list(value.where((e) => !e.bundled).toList()),
                ],
                _header('Starter songs'),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.gutter + Space.xs,
                    0,
                    Space.gutter,
                    Space.md,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Traditional and public-domain songs, arranged for beginners.',
                      style: t.caption.copyWith(color: c.textTertiary),
                    ),
                  ),
                ),
                _list(value.where((e) => e.bundled).toList()),
              ],
              AsyncError() => [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.gutter),
                    child: Text('Songs could not be loaded.', style: t.bodySecondary),
                  ),
                ),
              ],
              _ => [
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator.adaptive(strokeWidth: 2)),
                ),
              ],
            },
          // Developer tool: compiled out of release builds.
          if (kDebugMode)
            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: Space.xl),
                  child: StageButton.glass(
                    label: 'Widget gallery',
                    onPressed: () => context.push('/gallery'),
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 132)),
        ],
      ),
    );
  }

  Widget _header(String text) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
    sliver: SliverToBoxAdapter(child: SectionLabel(text)),
  );

  Widget _list(List<SongEntry> entries) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
    sliver: SliverList.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
      itemBuilder: (context, i) => _SongRow(entry: entries[i]),
    ),
  );
}

class _SongRow extends StatelessWidget {
  const _SongRow({required this.entry});

  final SongEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    final s = entry.song;
    final artist = s.artists.isEmpty ? null : s.artists.first;
    final key = s.key?.symbol();
    return Semantics(
      button: true,
      label: '${s.title}${artist == null ? '' : ', $artist'}${key == null ? '' : ', key of $key'}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => openSong(context, entry.id),
        child: GlassPanel(
          radius: Radii.md,
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.title, style: t.heading, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (artist != null)
                      Text(
                        artist,
                        style: t.caption.copyWith(color: c.textTertiary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (key != null) ...[
                const SizedBox(width: Space.md),
                Text(key, style: t.label.copyWith(color: c.textSecondary)),
              ],
              const SizedBox(width: Space.sm),
              Icon(Icons.chevron_right_rounded, color: c.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paste or import ChordPro; with [editing] set, edits that song instead.
Future<void> showSongEditor(BuildContext context, {SongEntry? editing}) =>
    showGlassSheet<void>(context, builder: (_) => _SongEditor(editing: editing));

class _SongEditor extends ConsumerStatefulWidget {
  const _SongEditor({this.editing});

  final SongEntry? editing;

  @override
  ConsumerState<_SongEditor> createState() => _SongEditorState();
}

class _SongEditorState extends ConsumerState<_SongEditor> {
  late final _text = TextEditingController(text: widget.editing?.source ?? '');
  Song? _preview;

  @override
  void initState() {
    super.initState();
    _text.addListener(_reparse);
    _reparse();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _reparse() {
    final src = _text.text;
    setState(() => _preview = src.trim().isEmpty ? null : SongsController.preview(src));
  }

  /// Common chords, then the user's own shapes.
  List<String> get _chordChoices => <String>{
    ...const ['G', 'C', 'D', 'Em', 'Am', 'E', 'A', 'Dm', 'F', 'G7', 'D7', 'A7', 'E7', 'C7', 'B7'],
    for (final c in ref.read(customChordsProvider).values) c.name,
  }.toList();

  /// Inserts [text] at the cursor, leaving the cursor at [caretAt] within
  /// it (default: after it).
  void _insert(String text, {int? caretAt}) {
    final sel = _text.selection;
    final value = _text.text;
    final start = sel.isValid ? sel.start : value.length;
    final end = sel.isValid ? sel.end : value.length;
    _text.value = TextEditingValue(
      text: value.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + (caretAt ?? text.length)),
    );
  }

  Future<void> _importFile() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['cho', 'chordpro', 'chopro', 'crd', 'pro', 'txt'],
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    _text.text = utf8.decode(bytes, allowMalformed: true);
  }

  void _save() {
    final p = _preview;
    if (p == null || p.chords.isEmpty) return;
    final songs = ref.read(songsProvider.notifier);
    final editing = widget.editing;
    if (editing != null) {
      songs.edit(editing.id, _text.text);
      Navigator.of(context).pop();
    } else {
      final id = songs.add(_text.text);
      Navigator.of(context).pop();
      openSong(context, id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    final p = _preview;
    final canSave = p != null && p.chords.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(widget.editing == null ? 'Add a song' : 'Edit song', style: t.title),
                ),
              ),
              if (widget.editing == null)
                GlassPill(
                  label: 'Import file',
                  icon: Icons.file_open_rounded,
                  semantics: 'Import a ChordPro file',
                  onTap: () => unawaited(_importFile()),
                ),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(
            'Write or paste ChordPro: chords in brackets before the syllable, like '
            '[G]Amazing [C]grace. Tap a chord below to drop it in at the cursor.',
            style: t.caption.copyWith(color: c.textTertiary),
          ),
          const SizedBox(height: Space.md),
          // About twenty buttons: a plain scrolling row, all built up front.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (label, text, caret) in const [
                  ('Title', '{title: }', 8),
                  ('Verse', '{start_of_verse}\n\n{end_of_verse}', 17),
                  ('Chorus', '{start_of_chorus}\n\n{end_of_chorus}', 18),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: Space.xs),
                    child: GlassPill(
                      label: label,
                      semantics: 'Insert $label',
                      onTap: () => _insert(text, caretAt: caret),
                    ),
                  ),
                for (final chord in _chordChoices)
                  Padding(
                    padding: const EdgeInsets.only(right: Space.xs),
                    child: GlassPill(
                      label: chord,
                      semantics: 'Insert chord $chord',
                      onTap: () => _insert('[$chord]'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.sm),
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.glassFill,
              borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
              border: Border.all(color: c.glassBorder),
            ),
            child: TextField(
              controller: _text,
              minLines: 8,
              maxLines: 14,
              autocorrect: false,
              enableSuggestions: false,
              style: t.body.copyWith(fontFamily: 'Menlo', fontFamilyFallback: const ['monospace']),
              decoration: InputDecoration(
                hintText: '{title: My song}\n{key: G}\n{tempo: 90}\n\n[G]Words go [C]here',
                hintStyle: t.body.copyWith(color: c.textTertiary),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(Space.md),
              ),
            ),
          ),
          const SizedBox(height: Space.md),
          if (p != null)
            Text(
              [
                p.title,
                '${p.chords.length} chords',
                if (p.warnings.isNotEmpty) '${p.warnings.length} lines skipped',
              ].join(' · '),
              style: t.caption,
            ),
          if (p != null && p.warnings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                p.warnings.take(3).join('\n'),
                style: t.caption.copyWith(color: c.textTertiary),
              ),
            ),
          if (p != null && p.chords.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                'No chords found yet: put them in [brackets].',
                style: t.caption.copyWith(color: c.textSecondary),
              ),
            ),
          const SizedBox(height: Space.lg),
          StageButton(
            label: widget.editing == null ? 'Save and open' : 'Save',
            expand: true,
            onPressed: canSave ? _save : null,
          ),
        ],
      ),
    );
  }
}
