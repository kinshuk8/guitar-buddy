import 'package:flutter/material.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/widgets/screen_header.dart';
import 'package:fretlight/features/tuner/presentation/tuner_button.dart';
import 'package:go_router/go_router.dart';

/// Everything that isn't a lesson or a song: the tuner, the metronome,
/// the identifier, the chord library, and settings.
class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 132),
      children: [
        const ScreenHeader(title: 'Tools', large: true),
        const SizedBox(height: Space.lg),
        NavRow(
          icon: Icons.graphic_eq_rounded,
          title: 'Tuner',
          detail: 'Tune each string. Other tunings under Advanced.',
          onTap: () => openTuner(context),
        ),
        const SizedBox(height: Space.sm),
        NavRow(
          icon: Icons.av_timer_rounded,
          title: 'Metronome',
          detail: 'A steady click to play along with.',
          onTap: () => context.push('/tools/metronome'),
        ),
        const SizedBox(height: Space.sm),
        NavRow(
          icon: Icons.hearing_rounded,
          title: 'Identify',
          detail: 'Play a note or chord and see its name.',
          onTap: () => context.push('/tools/identify'),
        ),
        const SizedBox(height: Space.sm),
        NavRow(
          icon: Icons.grid_view_rounded,
          title: 'Chord library',
          detail: 'Look up any chord, save favourites, draw your own.',
          onTap: () => context.push('/tools/chords'),
        ),
        const SizedBox(height: Space.sm),
        NavRow(
          icon: Icons.settings_outlined,
          title: 'Settings',
          detail: 'Left-handed mode, theme, microphone sensitivity.',
          onTap: () => context.push('/settings'),
        ),
      ],
    ),
  );
}
