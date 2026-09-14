import 'package:flutter/material.dart';

/// PhonicsAI colour tokens.
///
/// These are the only colour literals allowed in the app: screens read them via
/// the theme (`Theme.of(context).colorScheme` or [AppColors.of]) so that a
/// palette coming back from Stitch is a one-file change.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.brand,
    required this.brandDeep,
    required this.sunshine,
    required this.mint,
    required this.sky,
    required this.coral,
    required this.grape,
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.ink,
    required this.inkMuted,
    required this.onBrand,
    required this.success,
    required this.warning,
    required this.error,
    required this.gold,
    required this.streakFlame,
  });

  static const AppColors light = AppColors(
    brand: Color(0xFF6C4CFF),
    brandDeep: Color(0xFF3A1FA8),
    sunshine: Color(0xFFFFC83D),
    mint: Color(0xFF22C9A0),
    sky: Color(0xFF39A0FF),
    coral: Color(0xFFFF6A5B),
    grape: Color(0xFF9B5CFF),
    canvas: Color(0xFFF5F1FF),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF0ECFB),
    ink: Color(0xFF231A4A),
    inkMuted: Color(0xFF6A6390),
    onBrand: Color(0xFFFFFFFF),
    success: Color(0xFF17B67A),
    warning: Color(0xFFF5A623),
    error: Color(0xFFD8442F),
    gold: Color(0xFFFFB300),
    streakFlame: Color(0xFFFF7A1A),
  );

  static const AppColors dark = AppColors(
    brand: Color(0xFFA894FF),
    brandDeep: Color(0xFF6C53E8),
    sunshine: Color(0xFFFFD668),
    mint: Color(0xFF3ADFB6),
    sky: Color(0xFF6BBBFF),
    coral: Color(0xFFFF8C7E),
    grape: Color(0xFFB78AFF),
    canvas: Color(0xFF15102C),
    surface: Color(0xFF211A40),
    surfaceMuted: Color(0xFF2B2352),
    ink: Color(0xFFEFEAFF),
    inkMuted: Color(0xFFA79FD0),
    onBrand: Color(0xFF1B1340),
    success: Color(0xFF3ED9A0),
    warning: Color(0xFFFFC860),
    error: Color(0xFFFF8A75),
    gold: Color(0xFFFFC94D),
    streakFlame: Color(0xFFFF9A4D),
  );

  /// Per-phoneme / per-category accents used by chips, games and mastery tiles.
  static const List<Color> palette = <Color>[
    Color(0xFF6C4CFF),
    Color(0xFF22C9A0),
    Color(0xFFFFC83D),
    Color(0xFF39A0FF),
    Color(0xFFFF6A5B),
    Color(0xFF9B5CFF),
    Color(0xFF14B8A6),
    Color(0xFFF97316),
  ];

  final Color brand;
  final Color brandDeep;
  final Color sunshine;
  final Color mint;
  final Color sky;
  final Color coral;
  final Color grape;
  final Color canvas;
  final Color surface;
  final Color surfaceMuted;
  final Color ink;
  final Color inkMuted;
  final Color onBrand;
  final Color success;
  final Color warning;
  final Color error;
  final Color gold;
  final Color streakFlame;

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? light;

  /// Stable accent for a string key (lesson id, phoneme, game id) so the same
  /// item always keeps the same colour across screens.
  static Color accentFor(String key) {
    var hash = 0;
    for (final unit in key.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return palette[hash % palette.length];
  }

  /// Reads well on any of [palette]'s saturated fills.
  static Color contrastOn(Color background) {
    final luminance = background.computeLuminance();
    return luminance > 0.55 ? const Color(0xFF231A4A) : Colors.white;
  }

  @override
  AppColors copyWith({
    Color? brand,
    Color? brandDeep,
    Color? sunshine,
    Color? mint,
    Color? sky,
    Color? coral,
    Color? grape,
    Color? canvas,
    Color? surface,
    Color? surfaceMuted,
    Color? ink,
    Color? inkMuted,
    Color? onBrand,
    Color? success,
    Color? warning,
    Color? error,
    Color? gold,
    Color? streakFlame,
  }) {
    return AppColors(
      brand: brand ?? this.brand,
      brandDeep: brandDeep ?? this.brandDeep,
      sunshine: sunshine ?? this.sunshine,
      mint: mint ?? this.mint,
      sky: sky ?? this.sky,
      coral: coral ?? this.coral,
      grape: grape ?? this.grape,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      onBrand: onBrand ?? this.onBrand,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      gold: gold ?? this.gold,
      streakFlame: streakFlame ?? this.streakFlame,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      brand: Color.lerp(brand, other.brand, t)!,
      brandDeep: Color.lerp(brandDeep, other.brandDeep, t)!,
      sunshine: Color.lerp(sunshine, other.sunshine, t)!,
      mint: Color.lerp(mint, other.mint, t)!,
      sky: Color.lerp(sky, other.sky, t)!,
      coral: Color.lerp(coral, other.coral, t)!,
      grape: Color.lerp(grape, other.grape, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      streakFlame: Color.lerp(streakFlame, other.streakFlame, t)!,
    );
  }
}
