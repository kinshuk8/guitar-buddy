import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/design/motion.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/painting/chord_diagram.dart';
import 'package:fretlight/core/widgets/glass.dart';
import 'package:fretlight/core/widgets/glass_controls.dart';
import 'package:fretlight/core/widgets/music_text.dart';
import 'package:fretlight/features/chords/application/chord_library_provider.dart';
import 'package:fretlight/features/chords/domain/chord_library.dart';
import 'package:fretlight/features/settings/application/appearance.dart';
import 'package:go_router/go_router.dart';

/// Opens a chord's detail page.
void openChord(BuildContext context, ChordEntry entry) =>
    unawaited(context.push('/chords/chord?s=${Uri.encodeQueryComponent(entry.symbol)}'));

/// Browse by root, search, favourites. One root at a time and only the
/// everyday chords expanded, so the first view is eight cards, not eight
/// hundred.
class ChordsScreen extends ConsumerStatefulWidget {
  const ChordsScreen({super.key});

  @override
  ConsumerState<ChordsScreen> createState() => _ChordsScreenState();
}

class _ChordsScreenState extends ConsumerState<ChordsScreen> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  bool _favoritesOnly = false;
  final Set<QualityGroup> _expanded = {QualityGroup.essentials};

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(chordLibraryProvider);
    final text = context.stageText;
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 0),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(header: true, child: Text('Chords', style: text.display)),
                  ),
                  GlassPill(
                    label: '',
                    icon: _favoritesOnly ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    semantics: 'Favourites only',
                    selected: _favoritesOnly,
                    onTap: () => setState(() => _favoritesOnly = !_favoritesOnly),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, 0),
            sliver: SliverToBoxAdapter(
              child: _SearchField(controller: _search, focus: _focus),
            ),
          ),
          ...switch (library) {
            AsyncData(:final value) => _content(value),
            AsyncError() => [_message(context, 'The chord library could not be loaded.')],
            _ => [
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator.adaptive(strokeWidth: 2)),
              ),
            ],
          },
          // Clear of the floating tab bar.
          const SliverToBoxAdapter(child: SizedBox(height: 132)),
        ],
      ),
    );
  }

  List<Widget> _content(ChordLibrary library) {
    final query = _search.text.trim();
    final favorites = ref.watch(favoritesProvider);
    if (query.isNotEmpty) {
      var results = library.search(query);
      if (_favoritesOnly) results = results.where((e) => favorites.contains(e.symbol)).toList();
      return results.isEmpty
          ? [_message(context, 'No chord matches “$query”.')]
          : [_grid(results, top: Space.xl)];
    }
    if (_favoritesOnly) {
      final entries = [for (final s in favorites) ?library.bySymbol(s)];
      return entries.isEmpty
          ? [_message(context, 'Tap the heart on a chord to keep it here.')]
          : [_grid(entries, top: Space.xl)];
    }
    final root = PitchClass(ref.watch(browseRootProvider));
    final groups = library.browse(root);
    return [
      SliverPadding(
        padding: const EdgeInsets.only(top: Space.lg),
        sliver: SliverToBoxAdapter(
          child: _RootPicker(
            roots: library.roots,
            selected: root,
            onSelect: (pc) => ref.read(browseRootProvider.notifier).select(pc.value),
          ),
        ),
      ),
      for (final MapEntry(key: group, value: entries) in groups.entries) ...[
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          sliver: SliverToBoxAdapter(
            child: _GroupHeader(
              group: group,
              count: entries.length,
              expanded: _expanded.contains(group),
              // The everyday chords are always open.
              onToggle: group == QualityGroup.essentials
                  ? null
                  : () => setState(() {
                      if (!_expanded.remove(group)) _expanded.add(group);
                    }),
            ),
          ),
        ),
        if (_expanded.contains(group)) _grid(entries),
      ],
    ];
  }

  Widget _grid(List<ChordEntry> entries, {double top = 0}) {
    final leftHanded = ref.watch(appearanceProvider.select((a) => a.leftHanded));
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(Space.gutter, top, Space.gutter, 0),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 124,
          mainAxisSpacing: Space.md,
          crossAxisSpacing: Space.md,
          childAspectRatio: 0.66,
        ),
        itemCount: entries.length,
        itemBuilder: (context, i) => ChordCard(entry: entries[i], leftHanded: leftHanded),
      ),
    );
  }

  Widget _message(BuildContext context, String text) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xxxl, Space.gutter, 0),
    sliver: SliverToBoxAdapter(
      child: Text(text, textAlign: TextAlign.center, style: context.stageText.bodySecondary),
    ),
  );
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.focus});

  final TextEditingController controller;
  final FocusNode focus;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    final text = context.stageText;
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radii.pill),
      borderSide: BorderSide.none,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.glassFill,
        borderRadius: const BorderRadius.all(Radii.pill),
        border: Border.all(color: c.glassBorder),
      ),
      child: TextField(
        controller: controller,
        focusNode: focus,
        style: text.body,
        cursorColor: c.textPrimary,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search, e.g. Am7 or G/B',
          hintStyle: text.body.copyWith(color: c.textTertiary),
          prefixIcon: Icon(Icons.search_rounded, color: c.textTertiary, size: 20),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: Icon(Icons.close_rounded, color: c.textTertiary, size: 18),
                  onPressed: () {
                    controller.clear();
                    focus.unfocus();
                  },
                ),
          filled: false,
          border: border,
          enabledBorder: border,
          focusedBorder: border,
          contentPadding: const EdgeInsets.symmetric(vertical: Space.md + 2),
        ),
      ),
    );
  }
}

/// Twelve roots in one swipeable row; the chosen one is lit glass.
class _RootPicker extends StatelessWidget {
  const _RootPicker({required this.roots, required this.selected, required this.onSelect});

  final List<String> roots;
  final PitchClass selected;
  final ValueChanged<PitchClass> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    final motion = Motion.of(context);
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        itemCount: roots.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
        itemBuilder: (context, i) {
          final pc = PitchClass.tryParse(roots[i])!;
          final on = pc == selected;
          final name = roots[i];
          return Semantics(
            button: true,
            selected: on,
            label: 'Root ${spokenNote(name)}',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () {
                unawaited(HapticFeedback.selectionClick());
                onSelect(pc);
              },
              child: AnimatedContainer(
                duration: motion.quick,
                width: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? c.primaryFill : c.glassFill,
                  shape: BoxShape.circle,
                  border: Border.all(color: on ? c.primaryFill : c.glassBorder),
                ),
                child: Text(
                  name.replaceAll('#', '♯').replaceAll('b', '♭'),
                  style: context.stageText.label.copyWith(
                    color: on ? c.onPrimary : c.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.count,
    required this.expanded,
    required this.onToggle,
  });

  final QualityGroup group;
  final int count;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    final text = context.stageText;
    final toggle = onToggle;
    return Semantics(
      button: toggle != null,
      expanded: toggle == null ? null : expanded,
      header: true,
      label: '${group.label}, $count chords',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: toggle,
        child: Padding(
          padding: const EdgeInsets.only(top: Space.xl, bottom: Space.md, left: Space.xs),
          child: Row(
            children: [
              Text(group.label.toUpperCase(), style: text.overline),
              const SizedBox(width: Space.sm),
              Text(
                '$count',
                style: text.overline.copyWith(color: c.textTertiary.withValues(alpha: 0.6)),
              ),
              const Spacer(),
              if (toggle != null)
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: Motion.of(context).standard,
                  child: Icon(Icons.expand_more_rounded, size: 20, color: c.textTertiary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A chord in the grid: symbol and its first shape.
class ChordCard extends StatelessWidget {
  const ChordCard({required this.entry, this.leftHanded = false, super.key});

  final ChordEntry entry;
  final bool leftHanded;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    final shapes = entry.voicings.length;
    return Semantics(
      button: true,
      label:
          '${spokenChord(entry.chord, _spelling(entry))}, $shapes ${shapes == 1 ? 'shape' : 'shapes'}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => openChord(context, entry),
        child: GlassPanel(
          radius: Radii.md,
          padding: const EdgeInsets.fromLTRB(Space.sm, Space.md, Space.sm, Space.sm),
          child: Column(
            children: [
              SizedBox(
                height: 30,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: ChordSymbol(entry.chord, size: 24, spelling: _spelling(entry)),
                ),
              ),
              const SizedBox(height: Space.xs),
              Expanded(
                child: Center(
                  child: ChordDiagram(
                    voicing: entry.voicings.first,
                    compact: true,
                    leftHanded: leftHanded,
                  ),
                ),
              ),
              Text(
                shapes == 1 ? '1 shape' : '$shapes shapes',
                style: context.stageText.caption.copyWith(
                  color: c.textTertiary,
                  fontSize: TypeScale.micro,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Matches the library's spelling: `Eb`, not `D#`.
Spelling _spelling(ChordEntry e) => e.rootName.contains('b') ? Spelling.flats : Spelling.sharps;

/// `C#` → `C sharp`, `Eb` → `E flat`.
String spokenNote(String name) =>
    name.replaceAll('#', ' sharp').replaceAll(RegExp('(?<=[A-G])b'), ' flat');

/// Exposed for the detail screen.
Spelling chordSpelling(ChordEntry e) => _spelling(e);
