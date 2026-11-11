import 'package:flutter/material.dart';
import 'package:fretlight/core/widgets/glass_controls.dart';
import 'package:fretlight/features/tuner/presentation/tuner_screen.dart';

/// Opens the tuner on top of whatever is showing. Back returns to the same
/// spot: a lesson, a song, a drill.
///
/// Pushed on the root navigator rather than through the router so it sits
/// above everything, including lessons (which are pushed the same way).
void openTuner(BuildContext context) {
  Navigator.of(
    context,
    rootNavigator: true,
  ).push(MaterialPageRoute<void>(builder: (_) => const TunerScreen()));
}

/// The tuner, one tap from every screen.
class TunerButton extends StatelessWidget {
  const TunerButton({super.key});

  @override
  Widget build(BuildContext context) => GlassPill(
    label: 'Tuner',
    icon: Icons.graphic_eq_rounded,
    semantics: 'Open the tuner',
    onTap: () => openTuner(context),
  );
}
