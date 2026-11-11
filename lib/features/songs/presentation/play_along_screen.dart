import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/audio/output/audio_output.dart';
import 'package:fretlight/core/audio/wav.dart';
import 'package:fretlight/core/design/motion.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/music/music.dart';
import 'package:fretlight/core/painting/chord_diagram.dart';
import 'package:fretlight/core/storage/local_store.dart';
import 'package:fretlight/core/widgets/glass.dart';
import 'package:fretlight/core/widgets/glass_controls.dart';
import 'package:fretlight/core/widgets/music_text.dart';
import 'package:fretlight/core/widgets/screen_header.dart';
import 'package:fretlight/core/widgets/stage_buttons.dart';
import 'package:fretlight/features/chords/application/chord_library_provider.dart';
import 'package:fretlight/features/chords/application/chord_player.dart';
import 'package:fretlight/features/practice/application/practice_controller.dart';
import 'package:fretlight/features/practice/presentation/practice_screen.dart';
import 'package:fretlight/features/settings/application/appearance.dart';
import 'package:fretlight/features/songs/application/songs_controller.dart';
import 'package:fretlight/features/songs/domain/backing.dart';
import 'package:fretlight/features/songs/domain/chordpro.dart';
import 'package:fretlight/features/songs/domain/song_timeline.dart';
import 'package:fretlight/features/songs/presentation/songs_screen.dart';
import 'package:fretlight/features/tuner/presentation/tuner_button.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class PlayAlongScreen extends ConsumerWidget {
  const PlayAlongScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(songsProvider).value;
    final entry = songs?.where((e) => e.id == id).firstOrNull;
    return SafeArea(
      bottom: false,
      child: switch ((songs, entry)) {
        (null, _) => const Center(child: CircularProgressIndicator.adaptive(strokeWidth: 2)),
        (_, null) => Center(
          child: EmptyState(
            message: 'This song is no longer here.',
            action: 'Back to songs',
            onAction: () => context.go('/songs'),
          ),
        ),
        (_, final SongEntry e) => _Player(key: ValueKey(e.source), entry: e),
      },
    );
  }
}

class _Player extends ConsumerStatefulWidget {
  const _Player({required this.entry, super.key});

  final SongEntry entry;

  @override
  ConsumerState<_Player> createState() => _PlayerState();
}

class _PlayerState extends ConsumerState<_Player> with SingleTickerProviderStateMixin {
  static const _keepAwakeKey = 'songs.keepAwake';

  late final Song _song = widget.entry.song;
  late final SongTimeline _timeline = SongTimeline.of(_song);
  late SongPrefs _prefs = ref.read(songsProvider.notifier).prefs(widget.entry.id, _song);
  late final Ticker _ticker = createTicker(_onTick);
  final _scroll = ScrollController();
  final _lineKeys = <(int, int), GlobalKey>{};

  /// Playback position in beats. A notifier, not state: it changes every
  /// frame, but the sheet only rebuilds when the current chord changes.
  final _beat = ValueNotifier<double>(0);
  double _startBeat = 0;
  int _index = 0;
  bool _playing = false;
  int? _loopSection;

  // ---- Sound: the guitar part, scheduled on the audio engine. ----
  static const _soundKey = 'songs.sound';
  static const _patternKey = 'songs.pattern';
  static const _clickKey = 'songs.click';
  static const _sampleRate = 48000;

  /// Read once: dispose must stop audio without touching providers.
  late final AudioOutput _out;

  @override
  void initState() {
    super.initState();
    _out = ref.read(audioOutputProvider);
    // After the frame: providers can't change while the tree is building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(recentSongsProvider.notifier).opened(widget.entry.id);
    });
  }

  /// Voices playing now: the first pass, and (when looping) the loop.
  final List<LoopVoice> _voices = [];

  /// Engine time and beat where the audio started; the visuals read the
  /// engine clock from here, so what you see stays on what you hear.
  Duration? _audioAt;
  double _audioBeat = 0;

  /// Bumps on every (re)start so a slow render can't start stale audio.
  int _audioGen = 0;

  /// The guitar part is being rendered: the song waits for it rather than
  /// running ahead and jumping back when the sound starts.
  bool _preparing = false;

  bool get _sound => ref.read(localStoreProvider).setting(_soundKey) != 'false';
  StrumPattern get _pattern =>
      StrumPattern.values.asNameMap()[ref.read(localStoreProvider).setting(_patternKey)] ??
      StrumPattern.bar;
  bool get _click => ref.read(localStoreProvider).setting(_clickKey) == 'true';

  int get _bpm => _prefs.tempo ?? _song.tempo ?? 90;
  Arrangement get _arrangement => _prefs.arrangement;
  (double, double)? get _loop => _loopSection == null ? null : _timeline.sectionSpan(_loopSection!);

  @override
  void dispose() {
    _audioGen++;
    _stopAudio();
    _ticker.dispose();
    _scroll.dispose();
    _beat.dispose();
    unawaited(_setAwake(on: false));
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final at = _audioAt;
    if (at != null) {
      // Sound on: position comes from the audio engine's clock.
      final clock = _out.clock;
      var beat = _audioBeat + (clock - at).inMicroseconds / 1e6 * _bpm / 60;
      if (beat < _audioBeat) beat = _audioBeat; // not started yet
      final loop = _loop;
      if (loop != null && beat >= loop.$2) {
        beat = loop.$1 + (beat - loop.$2) % (loop.$2 - loop.$1);
      } else if (loop == null && beat >= _timeline.totalBeats) {
        _pause(atBeat: 0);
        return;
      }
      _beat.value = beat;
      _sync();
      return;
    }
    var beat = _startBeat + elapsed.inMicroseconds / 1e6 * _bpm / 60;
    final loop = _loop;
    if (loop != null && beat >= loop.$2) {
      // Wrap to the top of the loop, carrying the overshoot.
      beat = loop.$1 + (beat - loop.$2) % (loop.$2 - loop.$1);
      _restartFrom(beat);
    } else if (beat >= _timeline.totalBeats) {
      _pause(atBeat: 0);
      return;
    }
    _beat.value = beat;
    _sync();
  }

  void _restartFrom(double beat) {
    _startBeat = beat;
    _ticker
      ..stop()
      ..start();
  }

  void _sync() {
    final i = _timeline.indexAt(_beat.value);
    if (i == _index) return;
    setState(() => _index = i);
    _follow();
  }

  /// Keeps the current line in the upper third, where the eye is.
  void _follow() {
    if (_timeline.events.isEmpty) return;
    final e = _timeline.events[_index];
    final ctx = _lineKeys[(e.section, e.line)]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.3,
      duration: Motion.of(context).standard,
      curve: MotionTokens.move,
    );
  }

  void _play() {
    if (_timeline.events.isEmpty) return;
    unawaited(HapticFeedback.lightImpact());
    setState(() => _playing = true);
    _startBeat = _beat.value;
    unawaited(_setAwake(on: _keepAwake));
    if (_sound) {
      unawaited(_startAudio());
    } else {
      _ticker.start();
    }
  }

  /// Renders the guitar part from the current beat and schedules it. Until
  /// it starts (a render takes a moment), the visuals run on their own.
  Future<void> _startAudio() async {
    _stopAudio();
    final gen = ++_audioGen;
    if (_ticker.isActive) _ticker.stop();
    setState(() => _preparing = true);
    try {
      await _renderAndSchedule(gen);
    } on Object catch (e, st) {
      // No sound is better than no song: carry on silently.
      debugPrint('Backing track failed: $e\n$st');
      _audioAt = null;
    } finally {
      if (mounted && gen == _audioGen) {
        setState(() => _preparing = false);
        if (_playing && !_ticker.isActive) {
          _startBeat = _beat.value;
          _ticker.start();
        }
      }
    }
  }

  Future<void> _renderAndSchedule(int gen) async {
    final from = _beat.value;
    final loop = _loop;
    final library = await ref.read(chordLibraryProvider.future);
    final events = [
      for (final e in _timeline.events)
        BackingEvent(
          startBeat: e.startBeat,
          beats: e.beats,
          // Sound is the transposed chord; the capo changes shapes, not pitch.
          frets: e.chord == null
              ? null
              : library.byChord(e.chord!.transpose(_arrangement.transpose))?.voicings.first.frets,
        ),
    ];
    final bpm = _bpm.toDouble();
    final bar = _timeline.beatsPerBar;
    final pattern = _pattern;
    final click = _click;
    final end = loop?.$2 ?? _timeline.totalBeats;
    Future<Uint8List> render(double a, double b, {required double tail}) => Isolate.run(
      () => encodeWav16(
        renderBacking(
          events: events,
          beatsPerBar: bar,
          bpm: bpm,
          sampleRate: _sampleRate,
          fromBeat: a,
          toBeat: b,
          pattern: pattern,
          click: click,
          tailSeconds: tail,
        ),
        _sampleRate,
      ),
    );
    final first = await render(from, end, tail: loop == null ? 1.5 : 0);
    final looped = loop == null ? null : await render(loop.$1, loop.$2, tail: 0);
    if (!mounted || gen != _audioGen || !_playing) return;
    final out = _out;
    // Start a beat-fraction from now; the clock catches the visuals up.
    final at = out.clock + const Duration(milliseconds: 80);
    _voices.add(await out.scheduleOnce(first, at: at));
    if (looped != null) {
      final firstLen = Duration(microseconds: ((end - from) * 60 / bpm * 1e6).round());
      _voices.add(await out.scheduleLoop(looped, at: at + firstLen));
    }
    if (!mounted || gen != _audioGen) {
      _stopAudio();
      return;
    }
    _audioAt = at;
    _audioBeat = from;
  }

  void _stopAudio() {
    final out = _out;
    final now = out.clock;
    for (final v in _voices) {
      out.stopLoopAt(v, now);
    }
    _voices.clear();
    _audioAt = null;
  }

  /// After a change that alters the sound (tempo, key, pattern, position,
  /// loop): pick up from where we are with the new audio.
  void _resound() {
    if (!_playing) return;
    _audioGen++;
    _stopAudio();
    _startBeat = _beat.value;
    _ticker.stop();
    if (_sound) {
      unawaited(_startAudio());
    } else {
      _ticker.start();
    }
  }

  void _pause({double? atBeat}) {
    _ticker.stop();
    _audioGen++;
    _stopAudio();
    _preparing = false;
    if (atBeat != null) _beat.value = atBeat;
    setState(() {
      _playing = false;
      _index = _timeline.indexAt(_beat.value);
    });
    unawaited(_setAwake(on: false));
  }

  void _seekTo(double beat) {
    _beat.value = beat;
    setState(() => _index = _timeline.indexAt(beat));
    _follow();
    _resound();
  }

  void _toggleLoop(int section) {
    final span = _timeline.sectionSpan(section);
    if (span == null) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() => _loopSection = _loopSection == section ? null : section);
    if (_loopSection != null && (_beat.value < span.$1 || _beat.value >= span.$2)) {
      _seekTo(span.$1);
    } else {
      _resound();
    }
  }

  void _practise() {
    if (_playing) _pause();
    final events = _timeline.events.where((e) => e.chord != null).toList();
    if (events.isEmpty) return;
    startPractice(
      context,
      ref,
      PracticePlan(
        title: _song.title,
        // The mic hears what sounds: transposed, capo or not.
        sounding: [for (final e in events) e.chord!.transpose(_arrangement.transpose)],
        capo: _arrangement.capo,
        lines: [for (final e in events) _song.sections[e.section].lines[e.line].lyrics],
      ),
    );
  }

  bool get _keepAwake => ref.read(localStoreProvider).setting(_keepAwakeKey) != 'false';

  Future<void> _setAwake({required bool on}) async {
    try {
      await (on ? WakelockPlus.enable() : WakelockPlus.disable());
    } on Object {
      // Not available (tests, some desktops): the screen just sleeps as usual.
    }
  }

  void _savePrefs(SongPrefs p) {
    setState(() => _prefs = p);
    ref.read(songsProvider.notifier).savePrefs(widget.entry.id, p);
    _resound();
  }

  void _setTempo(int bpm) =>
      _savePrefs(SongPrefs(arrangement: _arrangement, tempo: bpm.clamp(30, 240)));

  void _toggleSound() {
    final on = !_sound;
    ref.read(localStoreProvider).setSetting(_soundKey, '$on');
    setState(() {});
    if (!_playing) return;
    if (on) {
      _resound();
    } else {
      _audioGen++;
      _stopAudio();
      _startBeat = _beat.value;
      _ticker
        ..stop()
        ..start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    final shapeKey = _song.key == null ? null : _arrangement.shape(_song.key!);
    final current = _timeline.events.isEmpty ? null : _timeline.events[_index];
    final next = _timeline.events.isEmpty ? null : _timeline.nextChord(_index, loop: _loop);
    final subtitle = [
      if (_arrangement.soundingKey(_song.key) case final k?) 'Key ${k.symbol()}',
      if (_arrangement.capo > 0) 'Capo ${_arrangement.capo}',
      '$_bpm BPM',
    ].join(' · ');

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.sm),
              child: Row(
                children: [
                  GlassIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    semantics: 'Back',
                    onTap: () => context.pop(),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            _song.title,
                            style: t.heading,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(subtitle, style: t.caption.copyWith(color: c.textTertiary)),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  const TunerButton(),
                ],
              ),
            ),
            // What you can do with this song, in words.
            Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                child: Row(
                  children: [
                    GlassPill(
                      label: 'Practise',
                      icon: Icons.hearing_rounded,
                      semantics: 'Practise this song: it waits for each chord',
                      onTap: _practise,
                    ),
                    const SizedBox(width: Space.sm),
                    GlassPill(
                      label: 'Key and capo',
                      icon: Icons.tune_rounded,
                      semantics: 'Key, capo and tempo',
                      onTap: () => _showArrangeSheet(context),
                    ),
                    if (!widget.entry.bundled) ...[
                      const SizedBox(width: Space.sm),
                      GlassPill(
                        label: 'Edit',
                        icon: Icons.edit_rounded,
                        semantics: 'Edit this song',
                        onTap: () => unawaited(showSongEditor(context, editing: widget.entry)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (si, section) in _song.sections.indexed)
                      _Section(
                        section: section,
                        index: si,
                        looping: _loopSection == si,
                        canLoop: _timeline.sectionSpan(si) != null,
                        onLabelTap: () => _toggleLoop(si),
                        current: current,
                        display: (text) => _arrangement.display(text, _song.key),
                        keyFor: (li) => _lineKeys.putIfAbsent((si, li), GlobalKey.new),
                        onLineTap: (li) {
                          final e = _timeline.events.where((e) => e.section == si && e.line == li);
                          if (e.isNotEmpty) _seekTo(e.first.startBeat);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Positioned(
          left: Space.gutter,
          right: Space.gutter,
          bottom: 100,
          child: _Dock(
            current: current,
            next: next,
            playing: _playing,
            loopLabel: _loopSection == null ? null : _song.sections[_loopSection!].displayLabel,
            onClearLoop: () {
              setState(() => _loopSection = null);
              _resound();
            },
            totalBeats: _timeline.totalBeats,
            onSeek: _seekTo,
            bpm: _bpm,
            onTempo: _setTempo,
            sound: _sound,
            onToggleSound: _toggleSound,
            shape: (e) => e.chord == null ? null : _arrangement.shape(e.chord!),
            spelling: _arrangement.spelling(_song.key),
            onPlayPause: () => _playing ? _pause() : _play(),
            preparing: _preparing,
            beat: _beat,
            beatsPerBar: _timeline.beatsPerBar,
          ),
        ),
        if (shapeKey == null) const SizedBox.shrink(),
      ],
    );
  }

  Future<void> _showArrangeSheet(BuildContext context) => showGlassSheet<void>(
    context,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheet) {
        // Each change reads the *current* arrangement when tapped, so two
        // quick taps before a rebuild add up instead of repeating.
        void change({int transpose = 0, int capo = 0, int tempo = 0, int? setCapo}) {
          final now = _arrangement;
          _savePrefs(
            SongPrefs(
              arrangement: Arrangement(
                transpose: (now.transpose + transpose).clamp(-6, 6),
                capo: (setCapo ?? now.capo + capo).clamp(0, 9),
              ),
              tempo: tempo == 0 ? _prefs.tempo : (_bpm + tempo).clamp(30, 300),
            ),
          );
          setSheet(() {});
        }

        final a = _arrangement;
        final sounding = [for (final ch in _song.chords) ch.transpose(a.transpose)];
        final suggested = Transposer.suggestCapo(sounding);
        final keepAwake = _keepAwake;
        final t = sheetContext.stageText;
        final c = sheetContext.stage;
        final key = a.soundingKey(_song.key);
        return Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(header: true, child: Text('Key, capo and tempo', style: t.title)),
              const SizedBox(height: Space.md),
              _Stepper(
                label: 'Transpose',
                value: [
                  if (key != null) key.symbol(),
                  if (a.transpose != 0) '(${a.transpose > 0 ? '+' : ''}${a.transpose})',
                ].join(' '),
                onMinus: a.transpose > -6 ? () => change(transpose: -1) : null,
                onPlus: a.transpose < 6 ? () => change(transpose: 1) : null,
              ),
              _Stepper(
                label: 'Capo',
                value: a.capo == 0 ? 'None' : 'Fret ${a.capo}',
                hint: suggested != a.capo ? 'Fret $suggested gives the easiest shapes' : null,
                onHint: () => change(setCapo: suggested),
                onMinus: a.capo > 0 ? () => change(capo: -1) : null,
                onPlus: a.capo < 9 ? () => change(capo: 1) : null,
              ),
              _Stepper(
                label: 'Tempo',
                value: '$_bpm BPM',
                onMinus: _bpm > 30 ? () => change(tempo: -4) : null,
                onPlus: _bpm < 240 ? () => change(tempo: 4) : null,
              ),
              const SizedBox(height: Space.md),
              Text('Guitar part', style: t.body),
              const SizedBox(height: Space.sm),
              StageSegmented<StrumPattern>(
                options: StrumPattern.values,
                selected: _pattern,
                labelOf: (p) => p.label,
                onChanged: (p) {
                  ref.read(localStoreProvider).setSetting(_patternKey, p.name);
                  setSheet(() {});
                  _resound();
                },
              ),
              const SizedBox(height: Space.sm),
              Row(
                children: [
                  Expanded(child: Text('Click on every beat', style: t.body)),
                  Switch.adaptive(
                    value: _click,
                    activeTrackColor: c.textSecondary,
                    onChanged: (v) {
                      ref.read(localStoreProvider).setSetting(_clickKey, '$v');
                      setSheet(() {});
                      _resound();
                    },
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              Row(
                children: [
                  Expanded(child: Text('Keep screen on while playing', style: t.body)),
                  Switch.adaptive(
                    value: keepAwake,
                    activeTrackColor: c.textSecondary,
                    onChanged: (v) {
                      ref.read(localStoreProvider).setSetting(_keepAwakeKey, '$v');
                      if (_playing) unawaited(_setAwake(on: v));
                      setSheet(() {});
                    },
                  ),
                ],
              ),
              if (!widget.entry.bundled) ...[
                const SizedBox(height: Space.md),
                Row(
                  children: [
                    Expanded(
                      child: StageButton.glass(
                        label: 'Edit',
                        icon: Icons.edit_rounded,
                        expand: true,
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          unawaited(showSongEditor(context, editing: widget.entry));
                        },
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: StageButton.glass(
                        label: 'Delete',
                        icon: Icons.delete_outline_rounded,
                        expand: true,
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          ref.read(songsProvider.notifier).delete(widget.entry.id);
                          context.pop();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.section,
    required this.index,
    required this.looping,
    required this.canLoop,
    required this.onLabelTap,
    required this.current,
    required this.display,
    required this.keyFor,
    required this.onLineTap,
  });

  final SongSection section;
  final int index;
  final bool looping;
  final bool canLoop;
  final VoidCallback onLabelTap;
  final SongEvent? current;
  final String Function(String written) display;
  final GlobalKey Function(int line) keyFor;
  final void Function(int line) onLineTap;

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    final label = section.displayLabel;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty || canLoop)
            Semantics(
              button: canLoop,
              label:
                  '${label.isEmpty ? 'Section' : label}. ${looping ? 'Looping. Tap to stop looping' : 'Tap to loop'}',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: canLoop ? onLabelTap : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.sm),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label.isEmpty ? '' : label.toUpperCase(),
                        style: t.overline.copyWith(color: looping ? c.accent : null),
                      ),
                      if (canLoop) ...[
                        const SizedBox(width: Space.xs + 2),
                        Icon(
                          Icons.repeat_rounded,
                          size: 14,
                          color: looping ? c.accent : c.textTertiary.withValues(alpha: 0.5),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          for (final (li, line) in section.lines.indexed)
            _Line(
              key: keyFor(li),
              line: line,
              isCurrent: current != null && current!.section == index && current!.line == li,
              currentSegment: current != null && current!.section == index && current!.line == li
                  ? current!.segment
                  : null,
              display: display,
              onTap: () => onLineTap(li),
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.line,
    required this.isCurrent,
    required this.currentSegment,
    required this.display,
    required this.onTap,
    super.key,
  });

  final SongLine line;
  final bool isCurrent;
  final int? currentSegment;
  final String Function(String written) display;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    if (line.comment case final text?) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
        child: Text(text, style: t.caption.copyWith(fontStyle: FontStyle.italic)),
      );
    }
    // Large enough to read from a music stand.
    final lyric = StageText.style(
      20,
      weight: 400,
      color: isCurrent ? c.textPrimary : c.textSecondary,
      height: 1.25,
    );
    final chordStyle = StageText.style(17, weight: 650, color: c.textSecondary, height: 1.2);
    final hasChords = line.hasChords;
    // Read the lyric as a sentence, then the chords: splicing chord names
    // mid-word ("A G mazing") is unreadable by ear.
    final chords = [for (final s in line.segments) ?s.chordText].map(display).toList();
    final words = line.lyrics.trim();
    final spoken = [
      if (words.isNotEmpty) words,
      if (chords.isNotEmpty) 'Chords: ${chords.join(', ')}',
    ].join('. ');
    return Semantics(
      button: hasChords,
      label: spoken,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: hasChords ? onTap : null,
        child: AnimatedContainer(
          duration: Motion.of(context).quick,
          margin: const EdgeInsets.only(bottom: Space.sm),
          padding: const EdgeInsets.only(left: Space.md),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: isCurrent ? c.accent : Colors.transparent, width: 3),
            ),
          ),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              for (final (i, seg) in line.segments.indexed)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasChords)
                      Padding(
                        padding: const EdgeInsets.only(right: Space.sm),
                        child: Text(
                          seg.chordText == null ? ' ' : display(seg.chordText!),
                          style: i == currentSegment
                              ? chordStyle.copyWith(color: c.accent)
                              : chordStyle,
                        ),
                      ),
                    Text(seg.text.isEmpty ? ' ' : seg.text, style: lyric),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Always in view: the chord to play now, the one coming, play/pause.
class _Dock extends ConsumerWidget {
  const _Dock({
    required this.current,
    required this.next,
    required this.playing,
    required this.loopLabel,
    required this.onClearLoop,
    required this.shape,
    required this.spelling,
    required this.onPlayPause,
    required this.beat,
    required this.beatsPerBar,
    required this.totalBeats,
    required this.onSeek,
    required this.bpm,
    required this.onTempo,
    required this.sound,
    required this.onToggleSound,
    this.preparing = false,
  });

  final bool preparing;
  final double totalBeats;
  final ValueChanged<double> onSeek;
  final int bpm;
  final ValueChanged<int> onTempo;
  final bool sound;
  final VoidCallback onToggleSound;

  final SongEvent? current;
  final SongEvent? next;
  final bool playing;
  final String? loopLabel;
  final VoidCallback onClearLoop;
  final Chord? Function(SongEvent) shape;
  final Spelling spelling;
  final VoidCallback onPlayPause;
  final ValueListenable<double> beat;
  final int beatsPerBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.stageText;
    final c = context.stage;
    final library = ref.watch(chordLibraryProvider).value;
    final leftHanded = ref.watch(appearanceProvider.select((a) => a.leftHanded));

    Widget chordCard(SongEvent? e, {required bool now}) {
      final chord = e == null ? null : shape(e);
      final voicing = chord == null ? null : library?.byChord(chord)?.voicings.first;
      return Opacity(
        opacity: now ? 1 : 0.55,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(now ? 'NOW' : 'NEXT', style: t.overline),
            const SizedBox(height: Space.xs),
            SizedBox(
              height: 34,
              child: chord == null
                  ? Text(e?.chordText ?? '–', style: t.title)
                  : ChordSymbol(
                      chord,
                      size: 30,
                      spelling: spelling,
                      color: now ? c.textPrimary : c.textSecondary,
                    ),
            ),
            const SizedBox(height: Space.xs),
            SizedBox(
              width: now ? 78 : 62,
              child: voicing == null
                  ? const SizedBox(height: 60)
                  : ChordDiagram(voicing: voicing, compact: true, leftHanded: leftHanded),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (loopLabel case final l?)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: GlassPill(
              label: 'Looping ${l.isEmpty ? 'section' : l}',
              icon: Icons.repeat_rounded,
              semantics: 'Looping $l. Tap to stop looping',
              selected: true,
              onTap: onClearLoop,
            ),
          ),
        GlassPanel(
          blur: true,
          strong: true,
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  chordCard(current, now: true),
                  const SizedBox(width: Space.lg),
                  chordCard(next, now: false),
                  const Spacer(),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        button: true,
                        label: playing ? 'Pause' : 'Play',
                        excludeSemantics: true,
                        child: GestureDetector(
                          onTap: onPlayPause,
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(color: c.primaryFill, shape: BoxShape.circle),
                            child: preparing
                                ? Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: c.onPrimary,
                                    ),
                                  )
                                : Icon(
                                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    size: 34,
                                    color: c.onPrimary,
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: Space.sm),
                      // Beat within the bar: a quiet pulse to count along to.
                      ValueListenableBuilder<double>(
                        valueListenable: beat,
                        builder: (context, b, _) {
                          final within = b % beatsPerBar;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < beatsPerBar; i++)
                                Container(
                                  width: 6,
                                  height: 6,
                                  margin: const EdgeInsets.symmetric(horizontal: 2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: playing && within.floor() == i
                                        ? c.accent
                                        : c.glassBorder,
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              _Sliders(
                beat: beat,
                beatsPerBar: beatsPerBar,
                totalBeats: totalBeats,
                onSeek: onSeek,
                bpm: bpm,
                onTempo: onTempo,
                sound: sound,
                onToggleSound: onToggleSound,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Where you are in the song, and how fast it goes: both always in reach.
class _Sliders extends StatefulWidget {
  const _Sliders({
    required this.beat,
    required this.beatsPerBar,
    required this.totalBeats,
    required this.onSeek,
    required this.bpm,
    required this.onTempo,
    required this.sound,
    required this.onToggleSound,
  });

  final ValueListenable<double> beat;
  final int beatsPerBar;
  final double totalBeats;
  final ValueChanged<double> onSeek;
  final int bpm;
  final ValueChanged<int> onTempo;
  final bool sound;
  final VoidCallback onToggleSound;

  @override
  State<_Sliders> createState() => _SlidersState();
}

class _SlidersState extends State<_Sliders> {
  /// While dragging, the thumb follows the finger; the song jumps on release.
  double? _dragBeat;
  double? _dragBpm;

  @override
  Widget build(BuildContext context) {
    final c = context.stage;
    final t = context.stageText;
    final theme = SliderThemeData(
      trackHeight: 3,
      activeTrackColor: c.textSecondary,
      inactiveTrackColor: c.glassBorder,
      thumbColor: c.primaryFill,
      overlayColor: c.glassFill,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      showValueIndicator: ShowValueIndicator.never,
    );
    final caption = t.caption.copyWith(
      color: c.textTertiary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final total = math.max(1, widget.totalBeats).toDouble();
    final bars = (total / widget.beatsPerBar).ceil();
    return SliderTheme(
      data: theme,
      child: Column(
        children: [
          ValueListenableBuilder<double>(
            valueListenable: widget.beat,
            builder: (context, b, _) {
              final value = (_dragBeat ?? b).clamp(0, total).toDouble();
              final bar = (value / widget.beatsPerBar).floor() + 1;
              return Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text('Bar ${math.min(bar, bars)}/$bars', style: caption),
                  ),
                  Expanded(
                    child: Slider(
                      value: value,
                      max: total,
                      semanticFormatterCallback: (v) =>
                          'Bar ${(v / widget.beatsPerBar).floor() + 1} of $bars',
                      onChanged: (v) => setState(() => _dragBeat = v),
                      onChangeEnd: (v) {
                        // Land on a bar line: songs restart on the downbeat.
                        final snapped =
                            (v / widget.beatsPerBar).floor() * widget.beatsPerBar.toDouble();
                        setState(() => _dragBeat = null);
                        widget.onSeek(snapped);
                      },
                    ),
                  ),
                ],
              );
            },
          ),
          Row(
            children: [
              SizedBox(
                width: 64,
                child: Text('${(_dragBpm ?? widget.bpm).round()} BPM', style: caption),
              ),
              Expanded(
                child: Slider(
                  value: (_dragBpm ?? widget.bpm.toDouble()).clamp(40, 200).toDouble(),
                  min: 40,
                  max: 200,
                  divisions: 160,
                  semanticFormatterCallback: (v) => 'Tempo ${v.round()} beats per minute',
                  onChanged: (v) => setState(() => _dragBpm = v),
                  onChangeEnd: (v) {
                    setState(() => _dragBpm = null);
                    widget.onTempo(v.round());
                  },
                ),
              ),
              Semantics(
                button: true,
                label: widget.sound ? 'Mute the guitar part' : 'Play the guitar part',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onToggleSound,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(
                      widget.sound ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                      size: 20,
                      color: widget.sound ? c.textSecondary : c.textTertiary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
    this.hint,
    this.onHint,
  });

  final String label;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final String? hint;
  final VoidCallback? onHint;

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: t.body)),
              _round(context, Icons.remove_rounded, 'Less $label', onMinus),
              SizedBox(
                width: 112,
                child: Text(
                  value,
                  textAlign: TextAlign.center,
                  style: t.label.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
              _round(context, Icons.add_rounded, 'More $label', onPlus),
            ],
          ),
          if (hint case final h?)
            GestureDetector(
              onTap: onHint,
              child: Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text(
                  '$h · use it',
                  style: t.caption.copyWith(
                    color: c.textSecondary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _round(BuildContext context, IconData icon, String semantics, VoidCallback? onTap) {
    final c = context.stage;
    return Opacity(
      opacity: onTap == null ? 0.35 : 1,
      child: GlassIconButton(
        icon: icon,
        semantics: semantics,
        onTap: onTap ?? () {},
        color: c.textPrimary,
      ),
    );
  }
}
