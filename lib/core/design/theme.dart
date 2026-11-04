import 'package:flutter/material.dart';
import 'package:fretlight/core/design/tokens.dart';

/// Carries [StageColors] through [ThemeData] so painters and widgets read
/// `context.stage` instead of reaching for raw palette values.
@immutable
final class StageTheme extends ThemeExtension<StageTheme> {
  const StageTheme(this.colors);

  final StageColors colors;

  @override
  StageTheme copyWith({StageColors? colors}) => StageTheme(colors ?? this.colors);

  @override
  StageTheme lerp(StageTheme? other, double t) =>
      other == null ? this : StageTheme(StageColors.lerp(colors, other.colors, t));
}

extension StageContext on BuildContext {
  StageColors get stage => Theme.of(this).extension<StageTheme>()!.colors;
  StageText get stageText => StageText(stage);
}

/// Text styles derived from the type scale and current colours.
final class StageText {
  const StageText(this.c);

  final StageColors c;

  /// Inter is bundled as one variable font, so weight and optical size are
  /// set through font variations. `fontWeight` is set too, for the fallback
  /// fonts and for anything that reads it (e.g. semantics, bold text mode).
  /// Optical size follows the font size: large text gets Inter's tighter
  /// "display" cut, small text gets the open, legible one.
  static TextStyle style(
    double size, {
    required int weight,
    required Color color,
    double tracking = 0,
    double height = 1.35,
    bool tabular = false,
  }) => TextStyle(
    fontFamily: FontFamilies.ui,
    fontFamilyFallback: FontFamilies.fallback,
    fontSize: size,
    fontWeight: FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)],
    fontVariations: [
      FontVariation('wght', weight.toDouble()),
      FontVariation('opsz', size.clamp(14, 32)),
    ],
    fontFeatures: [
      if (tabular) const FontFeature.tabularFigures(),
      // Inter's contextual alternates: better-centred colons and arrows.
      const FontFeature.contextualAlternates(),
    ],
    letterSpacing: tracking * size,
    height: height,
    color: color,
  );

  TextStyle get chordHero =>
      style(TypeScale.chordHero, weight: 600, color: c.textPrimary, tracking: -0.045, height: 1);
  TextStyle get chordLarge =>
      style(TypeScale.chordLarge, weight: 600, color: c.textPrimary, tracking: -0.04, height: 1);
  TextStyle get readout => style(
    TypeScale.readout,
    weight: 300,
    color: c.textPrimary,
    tracking: -0.03,
    height: 1,
    tabular: true,
  );
  TextStyle get display =>
      style(TypeScale.display, weight: 700, color: c.textPrimary, tracking: -0.03, height: 1.1);
  TextStyle get title =>
      style(TypeScale.title, weight: 600, color: c.textPrimary, tracking: -0.02, height: 1.2);
  TextStyle get heading =>
      style(TypeScale.heading, weight: 600, color: c.textPrimary, tracking: -0.01);
  TextStyle get body => style(TypeScale.body, weight: 400, color: c.textPrimary);
  TextStyle get bodySecondary => style(TypeScale.body, weight: 400, color: c.textSecondary);
  TextStyle get label => style(TypeScale.label, weight: 500, color: c.textPrimary, height: 1.2);
  TextStyle get caption => style(TypeScale.caption, weight: 400, color: c.textSecondary);

  /// Quiet spaced section label (VERSE, CHORUS).
  TextStyle get overline =>
      style(TypeScale.micro, weight: 600, color: c.textTertiary, tracking: 0.12, height: 1.2);
}

abstract final class StageThemeData {
  static ThemeData dark() => _build(StageColors.dark, Brightness.dark);
  static ThemeData light() => _build(StageColors.light, Brightness.light);

  static ThemeData _build(StageColors c, Brightness brightness) {
    final text = StageText(c);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primaryFill,
      onPrimary: c.onPrimary,
      secondary: c.accent,
      onSecondary: c.onAccent,
      error: c.danger,
      onError: c.onPrimary,
      surface: c.background,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      outline: c.glassBorder,
      surfaceContainerHighest: c.glassFillStrong,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      fontFamily: FontFamilies.ui,
      fontFamilyFallback: FontFamilies.fallback,
      extensions: [StageTheme(c)],
      // Ink splashes look like default Material; presses use scale instead.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      textTheme: TextTheme(
        displayLarge: text.display,
        titleLarge: text.title,
        titleMedium: text.heading,
        bodyLarge: text.body,
        bodyMedium: text.body,
        labelLarge: text.label,
        bodySmall: text.caption,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.textPrimary,
        inactiveTrackColor: c.glassFillStrong,
        thumbColor: c.textPrimary,
        overlayColor: c.glassFill,
        trackHeight: 4,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onPrimary : c.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.primaryFill : c.glassFillStrong,
        ),
        trackOutlineColor: WidgetStatePropertyAll(c.glassBorder),
      ),
      dividerTheme: DividerThemeData(color: c.glassBorder, thickness: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: c.textPrimary,
        titleTextStyle: text.heading,
        centerTitle: true,
      ),
    );
  }
}
