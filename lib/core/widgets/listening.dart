import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fretlight/core/design/theme.dart';
import 'package:fretlight/core/design/tokens.dart';
import 'package:fretlight/core/widgets/stage_buttons.dart';

/// Tells [onChanged] whether this screen should be listening: visible (its
/// tab is the active one) and the app in the foreground.
///
/// The tab shell keeps hidden tabs alive with tickers disabled; following
/// TickerMode means the mic closes the moment you switch tabs, without the
/// screen knowing anything about the router.
class ListenWhileVisible extends StatefulWidget {
  const ListenWhileVisible({required this.onChanged, required this.child, super.key});

  final void Function({required bool active}) onChanged;
  final Widget child;

  @override
  State<ListenWhileVisible> createState() => _ListenWhileVisibleState();
}

class _ListenWhileVisibleState extends State<ListenWhileVisible> {
  late final AppLifecycleListener _lifecycle;
  ValueListenable<TickerModeData>? _tickerMode;
  bool? _active;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: (_) => _sync());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = TickerMode.getValuesNotifier(context);
    if (notifier != _tickerMode) {
      _tickerMode?.removeListener(_sync);
      _tickerMode = notifier..addListener(_sync);
    }
    _sync();
  }

  void _sync() {
    final visible = _tickerMode?.value.enabled ?? true;
    final foreground = switch (WidgetsBinding.instance.lifecycleState) {
      AppLifecycleState.resumed || null => true,
      _ => false,
    };
    final active = visible && foreground;
    if (active == _active) return;
    _active = active;
    // Deferred: _sync can run during build (didChangeDependencies).
    scheduleMicrotask(() {
      if (mounted) widget.onChanged(active: active);
    });
  }

  @override
  void dispose() {
    _tickerMode?.removeListener(_sync);
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Why the microphone isn't running, and the one thing that fixes it.
class MicBlocked extends StatelessWidget {
  const MicBlocked({
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
    super.key,
  });

  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.stageText;
    final c = context.stage;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_none_rounded, size: 36, color: c.textTertiary),
          const SizedBox(height: Space.md),
          Text(title, style: t.heading, textAlign: TextAlign.center),
          const SizedBox(height: Space.sm),
          Text(body, style: t.bodySecondary, textAlign: TextAlign.center),
          const SizedBox(height: Space.xl),
          StageButton(label: action, onPressed: onAction),
        ],
      ),
    );
  }
}
