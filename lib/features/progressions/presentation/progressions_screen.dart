import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/widgets/screen_header.dart';
import 'package:fretlight/features/progressions/data/progression_pack.dart';
import 'package:fretlight/features/progressions/presentation/progressions_view.dart';
import 'package:fretlight/features/tuner/presentation/tuner_button.dart';
import 'package:go_router/go_router.dart';

/// The chord loops songs use most, each one a drill.
class ProgressionsScreen extends ConsumerWidget {
  const ProgressionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pack = ref.watch(progressionPackProvider);
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 0),
            sliver: SliverToBoxAdapter(
              child: ScreenHeader(
                title: 'Progressions',
                onBack: () => context.pop(),
                actions: const [TunerButton()],
              ),
            ),
          ),
          ...switch (pack) {
            AsyncData(:final value?) => progressionSlivers(context, value),
            AsyncLoading() => const [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator.adaptive(strokeWidth: 2)),
              ),
            ],
            _ => [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: EmptyState(
                    message: 'The progression pack isn’t installed in this build.',
                    action: 'Back to Practice',
                    onAction: () => context.pop(),
                  ),
                ),
              ),
            ],
          },
          const SliverToBoxAdapter(child: SizedBox(height: 132)),
        ],
      ),
    );
  }
}
