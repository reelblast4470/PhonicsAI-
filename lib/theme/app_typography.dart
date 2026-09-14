import 'package:flutter/material.dart';

/// Typography uses the platform font stack (Roboto on Android, SF on iOS,
/// Segoe on Windows) so the app works fully offline and passes text scaling.
///
/// To match Stitch exactly once an export lands: drop the font files into
/// `assets/fonts/`, list them under `flutter: fonts:` in pubspec.yaml and set
/// [fontFamily] below — no screen changes are needed.
abstract final class AppTypography {
  static const String? fontFamily = null;

  /// Kid screens are intentionally 1.25x the usual app scale; parents get a
  /// normal, information-dense rhythm.
  static TextTheme kidText(Color ink, Color muted) {
    return _base(ink, muted, scale: 1.18, kid: true);
  }

  static TextTheme parentText(Color ink, Color muted) =>
      _base(ink, muted, scale: 1.0, kid: false);

  static TextTheme _base(Color ink, Color muted, {
    required double scale,
    required bool kid,
  }) {
    TextStyle heading(double size, FontWeight weight, {double? height}) =>
        TextStyle(
          fontFamily: fontFamily,
          fontSize: size * scale,
          fontWeight: weight,
          height: height ?? (kid ? 1.15 : 1.2),
          letterSpacing: kid ? -0.3 : -0.2,
          color: ink,
        );

    TextStyle body(double size, FontWeight weight, Color color,
        {double? height}) =>
        TextStyle(
          fontFamily: fontFamily,
          fontSize: size * scale,
          fontWeight: weight,
          height: height ?? 1.45,
          color: color,
        );

    final headlineWeight = kid ? FontWeight.w800 : FontWeight.w700;
    return TextTheme(
      displayLarge: heading(kid ? 44 : 38, headlineWeight),
      displayMedium: heading(kid ? 36 : 32, headlineWeight),
      displaySmall: heading(kid ? 30 : 28, headlineWeight),
      headlineLarge: heading(kid ? 28 : 26, headlineWeight),
      headlineMedium: heading(kid ? 24 : 22, headlineWeight),
      headlineSmall: heading(kid ? 20 : 19, FontWeight.w700),
      titleLarge: body(kid ? 19 : 18, FontWeight.w700, ink),
      titleMedium: body(kid ? 17 : 16, FontWeight.w600, ink),
      titleSmall: body(kid ? 15 : 14, FontWeight.w600, ink),
      bodyLarge: body(kid ? 18 : 16, FontWeight.w400, ink),
      bodyMedium: body(kid ? 16 : 14, FontWeight.w400, ink),
      bodySmall: body(kid ? 14 : 12.5, FontWeight.w400, muted),
      labelLarge: body(kid ? 18 : 15, FontWeight.w700, ink, height: 1.1),
      labelMedium: body(kid ? 15 : 13, FontWeight.w600, muted, height: 1.1),
      labelSmall: body(11, FontWeight.w700, muted, height: 1.1),
    );
  }

  /// The oversized word a child is decoding, e.g. "c-a-t" -> "cat".
  static TextStyle phonemeHero(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: scale.scale(64),
      fontWeight: FontWeight.w800,
      letterSpacing: 2,
      height: 1.05,
    );
  }

  /// Letter tiles / tracing canvas glyphs.
  static TextStyle letterGlyph(BuildContext context, {double size = 56}) {
    final scale = MediaQuery.textScalerOf(context);
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: scale.scale(size),
      fontWeight: FontWeight.w700,
      height: 1.1,
    );
  }
}
