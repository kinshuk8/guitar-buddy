import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/widgets/glass.dart';
import 'package:fretlight/core/widgets/glass_controls.dart';
import 'package:fretlight/features/onboarding/application/onboarding.dart';
import 'package:go_router/go_router.dart';

/// Two questions at first launch, each one tap, both skippable.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  Experience? _experience;

  void _finish({bool? leftHanded}) {
    ref.read(onboardingProvider.notifier).finish(experience: _experience, leftHanded: leftHanded);
    // A new player goes on into a guided first session (Home opens it);
    // closing it lands on Home.
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    final second = _experience != null;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (second)
                      GlassIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        semantics: 'Back',
                        onTap: () => setState(() => _experience = null),
                      ),
                    const Spacer(),
                    GlassPill(label: 'Skip', semantics: 'Skip the questions', onTap: _finish),
                  ],
                ),
                const Spacer(),
                Text('${second ? 2 : 1} OF 2', style: t.overline),
                const SizedBox(height: Space.sm),
                Semantics(
                  header: true,
                  child: Text(
                    second ? 'Which hand do you strum with?' : 'Welcome to Fretlight',
                    style: t.title,
                  ),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  second
                      ? 'Left-handed players get mirrored chord diagrams.'
                      : 'How much guitar have you played? You can change your mind later.',
                  style: t.bodySecondary,
                ),
                const SizedBox(height: Space.xl),
                if (!second)
                  for (final e in Experience.values) ...[
                    _Choice(
                      title: e.label,
                      detail: e.detail,
                      onTap: () => setState(() => _experience = e),
                    ),
                    const SizedBox(height: Space.md),
                  ]
                else ...[
                  _Choice(
                    title: 'Right hand',
                    detail: 'The usual way round.',
                    onTap: () => _finish(leftHanded: false),
                  ),
                  const SizedBox(height: Space.md),
                  _Choice(
                    title: 'Left hand',
                    detail: 'Diagrams and the fretboard are mirrored.',
                    onTap: () => _finish(leftHanded: true),
                  ),
                ],
                const Spacer(flex: 2),
                Text(
                  'Fretlight works offline. Nothing you play is recorded.',
                  style: t.caption.copyWith(color: c.textTertiary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.title, required this.detail, required this.onTap});

  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    return Semantics(
      container: true,
      button: true,
      label: '$title. $detail',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: GlassPanel(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.heading),
                    const SizedBox(height: 2),
                    Text(detail, style: t.caption.copyWith(color: c.textTertiary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
