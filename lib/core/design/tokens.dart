import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Raw palette. Widgets never use these directly; they read semantic
/// [StageColors] from the theme so light and dark stay in sync.
abstract final class Palette {
  // Night: near-black with a cool tint, so glass reads as glass, not grey.
  static const ink = Color(0xFF07080B);
  static const indigoMist = Color(0xFF2A2F6B);
  static const tealMist = Color(0xFF0D4B57);

  // Day: cool paper.
  static const paper = Color(0xFFEEF1F6);
  static const lavenderMist = Color(0xFFCBD3FF);
  static const peachMist = Color(0xFFFFE2C7);

  static const white = Color(0xFFFFFFFF);
  static const textNight = Color(0xFFF3F4F6);
  static const textDay = Color(0xFF0B0D12);

  /// The one warm accent: a stage lamp. Used for "live" things only
  /// (current chord, active beat, detected note), never for chrome.
  static const lamp = Color(0xFFFFB960);
  static const lampDeep = Color(0xFFC86F00);

  // Instrument
  static const ebony = Color(0xFF121317);
  static const ebonyGrain = Color(0xFF1D1F25);
  static const nickel = Color(0xFFB9BDC4);
  static const ivory = Color(0xFFE9E7E2);
  static const steelString = Color(0xFFE6E8EB);
  static const nickelWound = Color(0xFFA7ADB6);

  // State (always paired with an icon and a word, never colour alone)
  static const mint = Color(0xFF5EE6A8);
  static const mintDeep = Color(0xFF0F8A55);
  static const sky = Color(0xFF6CB8FF);
  static const skyDeep = Color(0xFF1F6FC4);
  static const coral = Color(0xFFFF7A6B);
  static const coralDeep = Color(0xFFC63B2C);
  static const red = Color(0xFFFF5C5C);
}

/// Semantic colours. One instance per theme (see `theme.dart`).
@immutable
final class StageColors {
  const StageColors({
    required this.background,
    required this.ambientA,
    required this.ambientB,
    required this.glassFill,
    required this.glassFillStrong,
    required this.glassBorder,
    required this.glassHighlight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.primaryFill,
    required this.onPrimary,
    required this.accent,
    required this.onAccent,
    required this.fretboardWood,
    required this.fretboardGrain,
    required this.fretWire,
    required this.nut,
    required this.inlay,
    required this.woundString,
    required this.plainString,
    required this.inTune,
    required this.flat,
    required this.sharp,
    required this.danger,
  });

  factory StageColors.lerp(StageColors a, StageColors b, double t) {
    Color l(Color x, Color y) => Color.lerp(x, y, t)!;
    return StageColors(
      background: l(a.background, b.background),
      ambientA: l(a.ambientA, b.ambientA),
      ambientB: l(a.ambientB, b.ambientB),
      glassFill: l(a.glassFill, b.glassFill),
      glassFillStrong: l(a.glassFillStrong, b.glassFillStrong),
      glassBorder: l(a.glassBorder, b.glassBorder),
      glassHighlight: l(a.glassHighlight, b.glassHighlight),
      textPrimary: l(a.textPrimary, b.textPrimary),
      textSecondary: l(a.textSecondary, b.textSecondary),
      textTertiary: l(a.textTertiary, b.textTertiary),
      primaryFill: l(a.primaryFill, b.primaryFill),
      onPrimary: l(a.onPrimary, b.onPrimary),
      accent: l(a.accent, b.accent),
      onAccent: l(a.onAccent, b.onAccent),
      fretboardWood: l(a.fretboardWood, b.fretboardWood),
      fretboardGrain: l(a.fretboardGrain, b.fretboardGrain),
      fretWire: l(a.fretWire, b.fretWire),
      nut: l(a.nut, b.nut),
      inlay: l(a.inlay, b.inlay),
      woundString: l(a.woundString, b.woundString),
      plainString: l(a.plainString, b.plainString),
      inTune: l(a.inTune, b.inTune),
      flat: l(a.flat, b.flat),
      sharp: l(a.sharp, b.sharp),
      danger: l(a.danger, b.danger),
    );
  }

  final Color background;

  /// Two soft light pools behind everything. Glass needs something to frost.
  final Color ambientA;
  final Color ambientB;

  /// Translucent panel fills (cards, controls) and their edge.
  final Color glassFill;
  final Color glassFillStrong;
  final Color glassBorder;

  /// Brighter top edge of glass, where light catches it.
  final Color glassHighlight;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// Primary button: solid, high-contrast, neutral (white on night).
  final Color primaryFill;
  final Color onPrimary;

  /// The lamp. Live state only.
  final Color accent;
  final Color onAccent;

  final Color fretboardWood;
  final Color fretboardGrain;
  final Color fretWire;
  final Color nut;
  final Color inlay;
  final Color woundString;
  final Color plainString;

  final Color inTune;
  final Color flat;
  final Color sharp;
  final Color danger;

  static const dark = StageColors(
    background: Palette.ink,
    ambientA: Palette.indigoMist,
    ambientB: Palette.tealMist,
    glassFill: Color(0x0FFFFFFF), // 6% white
    glassFillStrong: Color(0x1AFFFFFF), // 10%
    glassBorder: Color(0x14FFFFFF), // 8%
    glassHighlight: Color(0x33FFFFFF), // 20%
    textPrimary: Palette.textNight,
    textSecondary: Color(0x99F3F4F6), // 60%
    textTertiary: Color(0x61F3F4F6), // 38%
    primaryFill: Palette.textNight,
    onPrimary: Palette.ink,
    accent: Palette.lamp,
    onAccent: Palette.ink,
    fretboardWood: Palette.ebony,
    fretboardGrain: Palette.ebonyGrain,
    fretWire: Palette.nickel,
    nut: Palette.ivory,
    inlay: Color(0x40FFFFFF),
    woundString: Palette.nickelWound,
    plainString: Palette.steelString,
    inTune: Palette.mint,
    flat: Palette.sky,
    sharp: Palette.coral,
    danger: Palette.red,
  );

  static const light = StageColors(
    background: Palette.paper,
    ambientA: Palette.lavenderMist,
    ambientB: Palette.peachMist,
    glassFill: Color(0x8CFFFFFF), // 55% white
    glassFillStrong: Color(0xBFFFFFFF), // 75%
    glassBorder: Color(0x120B0D12), // 7% ink
    glassHighlight: Color(0xE6FFFFFF),
    textPrimary: Palette.textDay,
    textSecondary: Color(0x990B0D12),
    textTertiary: Color(0x660B0D12),
    primaryFill: Palette.textDay,
    onPrimary: Palette.white,
    accent: Palette.lampDeep,
    onAccent: Palette.white,
    fretboardWood: Palette.ebony,
    fretboardGrain: Palette.ebonyGrain,
    fretWire: Palette.nickel,
    nut: Palette.ivory,
    inlay: Color(0x40FFFFFF),
    woundString: Palette.nickelWound,
    plainString: Palette.steelString,
    inTune: Palette.mintDeep,
    flat: Palette.skyDeep,
    sharp: Palette.coralDeep,
    danger: Color(0xFFD32F2F),
  );
}

/// 4-pt spacing grid.
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Minimum touch target. Larger than Material's 48 because the phone is
  /// often on a music stand at arm's length and tapped with one hand.
  static const double touchTarget = 52;

  /// Page side margin.
  static const double gutter = 20;
}

abstract final class Radii {
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const pill = Radius.circular(999);
}

/// Glass parameters.
abstract final class GlassTokens {
  /// Blur behind floating chrome (nav bar, app bar, sheets). Content cards
  /// do not blur; see `GlassPanel`.
  static const double blur = 28;
}

/// Font family. Bundled (never fetched at runtime).
abstract final class FontFamilies {
  static const ui = 'Inter';
  static const fallback = ['SF Pro Text', 'Roboto', 'sans-serif'];
}

/// Type scale. Big where it matters at arm's length (chords, readouts),
/// small and quiet everywhere else.
abstract final class TypeScale {
  static const double chordHero = 120;
  static const double chordLarge = 64;
  static const double readout = 56;
  static const double display = 34;
  static const double title = 22;
  static const double heading = 17;
  static const double body = 16;
  static const double label = 15;
  static const double caption = 13;
  static const double micro = 11;
}

/// Motion tokens. Every animation picks a duration/curve or spring from here,
/// and `Motion.of(context)` swaps them for instant ones under reduced motion.
abstract final class MotionTokens {
  static const quick = Duration(milliseconds: 140);
  static const standard = Duration(milliseconds: 260);
  static const emphasized = Duration(milliseconds: 420);

  /// Chord-diagram fingers travelling between shapes.
  static const fingerTravel = Duration(milliseconds: 320);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve move = Curves.easeInOutCubicEmphasized;

  /// Tuner needle. Slightly under-damped (ratio 0.7): settles fast with a
  /// hair of overshoot, so it reads as a physical needle. Tuned on device in M2.
  static final needle = SpringDescription.withDampingRatio(mass: 1, stiffness: 220, ratio: 0.7);

  /// Beat pulse and button press. Stiffer and fully damped: no wobble.
  static final press = SpringDescription.withDampingRatio(mass: 1, stiffness: 600);

  /// Plucked string: decays over about a second.
  static const stringDecay = Duration(milliseconds: 1100);
}

/// Shadows and glows. Kept faint: the UI should recede, not shout.
abstract final class Glows {
  /// Soft light around a live element (current chord, in-tune state).
  static List<BoxShadow> soft(Color glow, {double strength = 1}) => [
    BoxShadow(color: glow.withValues(alpha: 0.22 * strength), blurRadius: 32, spreadRadius: -8),
  ];

  /// Lift for floating chrome.
  static const List<BoxShadow> float = [
    BoxShadow(color: Color(0x33000000), blurRadius: 30, offset: Offset(0, 12), spreadRadius: -6),
  ];
}
