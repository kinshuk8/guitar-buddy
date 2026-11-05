import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/widgets/glass.dart';
import 'package:fretlight/core/widgets/glass_controls.dart';
import 'package:fretlight/core/widgets/stage_buttons.dart';
import 'package:fretlight/features/chords/application/chord_library_provider.dart';
import 'package:fretlight/features/chords/application/chord_player.dart';

/// Draw a chord shape: tap a fret to put a finger there, tap above the nut
/// to switch a string between open and muted. It names itself from the
/// notes it plays; you can rename it.
Future<void> showChordEditor(BuildContext context, {String? id, String? name, List<int?>? frets}) =>
    showGlassSheet<void>(
      context,
      builder: (_) => _ChordEditor(id: id, name: name, frets: frets),
    );

class _ChordEditor extends ConsumerStatefulWidget {
  const _ChordEditor({this.id, this.name, this.frets});

  final String? id;
  final String? name;
  final List<int?>? frets;

  @override
  ConsumerState<_ChordEditor> createState() => _ChordEditorState();
}

class _ChordEditorState extends ConsumerState<_ChordEditor> {
  static const _rows = 5;

  late final List<int?> _frets = [...widget.frets ?? List<int?>.filled(6, 0)];
  late int _base = () {
    final fretted = _frets.whereType<int>().where((f) => f > 0);
    if (fretted.isEmpty) return 1;
    final hi = fretted.reduce((a, b) => a > b ? a : b);
    return hi <= _rows ? 1 : fretted.reduce((a, b) => a < b ? a : b);
  }();
  late final _name = TextEditingController(text: widget.name ?? '');
  bool _nameEdited = false;

  @override
  void initState() {
    super.initState();
    _nameEdited = widget.name != null;
    if (!_nameEdited) _name.text = _suggested?.symbol() ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Voicing get _voicing => Voicing(frets: _frets);

  Chord? get _suggested {
    final v = _voicing;
    if (v.pitchClasses.length < 2) return null;
    return ChordNamer.name(v.pitchClasses, bass: v.bass?.pitchClass);
  }

  void _changed() {
    if (!_nameEdited) _name.text = _suggested?.symbol() ?? '';
    setState(() {});
  }

  void _tapCell(int string, int row) {
    unawaited(HapticFeedback.selectionClick());
    final fret = _base + row;
    _frets[string] = _frets[string] == fret ? 0 : fret;
    _changed();
  }

  void _tapTop(int string) {
    unawaited(HapticFeedback.selectionClick());
    _frets[string] = _frets[string] == null ? 0 : null;
    _changed();
  }

  void _shift(int delta) {
    final next = (_base + delta).clamp(1, 15);
    if (next == _base) return;
    setState(() => _base = next);
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty || _voicing.notes.isEmpty) return;
    ref.read(customChordsProvider.notifier).save(name, [..._frets], id: widget.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    final v = _voicing;
    final suggested = _suggested;
    final notes = v.notes.map((n) => n.pitchClass.name()).toSet().join(' ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(widget.id == null ? 'New chord' : 'Edit chord', style: t.title),
          ),
          const SizedBox(height: Space.xs),
          Text(
            'Tap a fret to place a finger; tap above the nut for open or muted.',
            style: t.caption.copyWith(color: c.textTertiary),
          ),
          const SizedBox(height: Space.lg),
          Center(child: _grid(context)),
          const SizedBox(height: Space.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GlassIconButton(
                icon: Icons.keyboard_arrow_up_rounded,
                semantics: 'Towards the nut',
                onTap: () => _shift(-1),
              ),
              SizedBox(
                width: 110,
                child: Text(
                  _base == 1 ? 'From the nut' : 'From fret $_base',
                  style: t.label,
                  textAlign: TextAlign.center,
                ),
              ),
              GlassIconButton(
                icon: Icons.keyboard_arrow_down_rounded,
                semantics: 'Up the neck',
                onTap: () => _shift(1),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          Text(
            [
              if (notes.isNotEmpty) 'Notes $notes',
              if (suggested != null) 'sounds like ${suggested.symbol()}',
            ].join(' · '),
            style: t.caption,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.md),
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.glassFill,
              borderRadius: const BorderRadius.all(Radii.pill),
              border: Border.all(color: c.glassBorder),
            ),
            child: TextField(
              controller: _name,
              style: t.body,
              textAlign: TextAlign.center,
              autocorrect: false,
              onChanged: (_) => setState(() => _nameEdited = true),
              decoration: InputDecoration(
                hintText: 'Name, e.g. Gadd9',
                hintStyle: t.body.copyWith(color: c.textTertiary),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: Space.md),
              ),
            ),
          ),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              Expanded(
                child: StageButton.glass(
                  label: 'Hear it',
                  icon: Icons.volume_up_rounded,
                  expand: true,
                  onPressed: v.notes.isEmpty
                      ? null
                      : () => unawaited(ref.read(chordPlayerProvider).strum(v)),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: StageButton(
                  label: 'Save',
                  icon: Icons.check_rounded,
                  expand: true,
                  onPressed: _name.text.trim().isEmpty || v.notes.isEmpty ? null : _save,
                ),
              ),
            ],
          ),
          if (widget.id != null) ...[
            const SizedBox(height: Space.md),
            StageButton.glass(
              label: 'Delete this shape',
              icon: Icons.delete_outline_rounded,
              expand: true,
              onPressed: () {
                ref.read(customChordsProvider.notifier).delete(widget.id!);
                Navigator.of(context).pop();
              },
            ),
          ],
        ],
      ),
    );
  }

  /// Six strings (low E left), an open/muted row, five frets.
  Widget _grid(BuildContext context) {
    final c = context.stage;
    final t = context.stageText;
    const cell = 44.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var s = 0; s < 6; s++)
              Semantics(
                button: true,
                label:
                    'String ${6 - s}: ${switch (_frets[s]) {
                      null => 'muted',
                      0 => 'open',
                      final f => 'fret $f',
                    }}. Tap for ${_frets[s] == null ? 'open' : 'muted'}',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _tapTop(s),
                  child: SizedBox(
                    width: cell,
                    height: 36,
                    child: Center(
                      child: Text(switch (_frets[s]) {
                        null => '×',
                        0 => '○',
                        _ => '',
                      }, style: t.title.copyWith(color: c.textSecondary)),
                    ),
                  ),
                ),
              ),
          ],
        ),
        Container(
          width: cell * 6 - cell + 4,
          height: _base == 1 ? 5 : 1,
          color: c.textPrimary.withValues(alpha: _base == 1 ? 0.8 : 0.3),
        ),
        for (var row = 0; row < _rows; row++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var s = 0; s < 6; s++)
                Semantics(
                  button: true,
                  selected: _frets[s] == _base + row,
                  label: 'String ${6 - s}, fret ${_base + row}',
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _tapCell(s, row),
                    child: SizedBox(
                      width: cell,
                      height: cell,
                      child: CustomPaint(
                        painter: _CellPainter(
                          string: c.textSecondary.withValues(alpha: 0.7),
                          fret: c.textTertiary.withValues(alpha: 0.45),
                          dot: _frets[s] == _base + row ? c.primaryFill : null,
                          thickness: 2.6 - s * 0.3,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

final class _CellPainter extends CustomPainter {
  _CellPainter({
    required this.string,
    required this.fret,
    required this.dot,
    required this.thickness,
  });

  final Color string;
  final Color fret;
  final Color? dot;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    canvas
      ..drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = string
          ..strokeWidth = thickness,
      )
      ..drawLine(
        Offset(0, size.height),
        Offset(size.width, size.height),
        Paint()
          ..color = fret
          ..strokeWidth = 1,
      );
    if (dot case final d?) {
      canvas.drawCircle(Offset(x, size.height / 2), size.width * 0.32, Paint()..color = d);
    }
  }

  @override
  bool shouldRepaint(_CellPainter old) => old.dot != dot || old.string != string;
}
