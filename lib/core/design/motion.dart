import 'package:flutter/widgets.dart';
import 'package:fretlight/core/design/tokens.dart';

/// Motion settings for the current context, honouring the OS reduced-motion
/// setting (`MediaQuery.disableAnimations`, i.e. iOS "Reduce Motion" and
/// Android "Remove animations").
///
/// Reduced motion does not mean "no feedback": state changes still happen
/// (a beat still highlights), they just jump instead of travel.
@immutable
final class Motion {
  const Motion._(this.reduced);

  factory Motion.of(BuildContext context) =>
      Motion._(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  final bool reduced;

  Duration get quick => reduced ? Duration.zero : MotionTokens.quick;
  Duration get standard => reduced ? Duration.zero : MotionTokens.standard;
  Duration get emphasized => reduced ? Duration.zero : MotionTokens.emphasized;
  Duration get fingerTravel => reduced ? Duration.zero : MotionTokens.fingerTravel;

  /// Whether decorative motion (string vibration, glow breathing) should run.
  bool get decorative => !reduced;
}
