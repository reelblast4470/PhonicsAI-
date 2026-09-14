import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_dimens.dart';
import 'app_typography.dart';

/// Builds the two app themes (kid mode + parent mode) from the token files.
abstract final class AppTheme {
  static ThemeData kid(Brightness brightness) =>
      _build(brightness, kidMode: true);

  static ThemeData parent(Brightness brightness) =>
      _build(brightness, kidMode: false);

  static ThemeData _build(Brightness brightness, {required bool kidMode}) {
    final isDark = brightness == Brightness.dark;
    final colors = isDark ? AppColors.dark : AppColors.light;
    final text = kidMode
        ? AppTypography.kidText(colors.ink, colors.inkMuted)
        : AppTypography.parentText(colors.ink, colors.inkMuted);

    final scheme = ColorScheme.fromSeed(
      seedColor: colors.brand,
      brightness: brightness,
    ).copyWith(
      primary: colors.brand,
      onPrimary: colors.onBrand,
      secondary: colors.sunshine,
      onSecondary: const Color(0xFF3A2B00),
      tertiary: colors.mint,
      surface: colors.surface,
      onSurface: colors.ink,
      onSurfaceVariant: colors.inkMuted,
      error: colors.error,
      outline: colors.inkMuted.withValues(alpha: 0.35),
      outlineVariant: colors.surfaceMuted,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: text.apply(fontFamily: AppTypography.fontFamily),
      scaffoldBackgroundColor: colors.canvas,
      canvasColor: colors.canvas,
      splashFactory: kidMode ? null : InkSparkle.splashFactory,
      extensions: <ThemeExtension<dynamic>>[colors],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.headlineSmall?.copyWith(color: colors.ink),
        iconTheme: IconThemeData(color: colors.ink, size: 26),
        actionsIconTheme: IconThemeData(color: colors.ink, size: 24),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
      ),
      dividerTheme: DividerThemeData(
        color: colors.inkMuted.withValues(alpha: 0.15),
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(64, kidMode ? 64 : 48),
          padding: EdgeInsets.symmetric(horizontal: kidMode ? 24 : 20),
          textStyle: (kidMode ? text.titleLarge : text.titleMedium)
              ?.copyWith(fontWeight: FontWeight.w700),
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: Size(kidMode ? 64 : 48, kidMode ? 64 : 48),
          side: BorderSide(color: colors.brand.withValues(alpha: 0.5), width: 2),
          foregroundColor: colors.brand,
          padding: EdgeInsets.symmetric(horizontal: kidMode ? 20 : 16),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: colors.brand,
          textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          shape: const StadiumBorder(),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          // A square minimum, not `Size.fromHeight`: fromHeight leaves width
          // infinite and blows up any unbounded parent (e.g. AppBar actions).
          minimumSize: Size(kidMode ? 56 : 44, kidMode ? AppSizes.kidTapTarget : 44),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 74,
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colors.brand.withValues(alpha: 0.14),
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 28,
              color: states.contains(WidgetState.selected)
                  ? colors.brand
                  : colors.inkMuted,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => (text.labelSmall ?? const TextStyle(fontSize: 11))
              .copyWith(
            color: states.contains(WidgetState.selected)
                ? colors.brand
                : colors.inkMuted,
            fontWeight: FontWeight.w700,
            fontSize: 11.5,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.brand.withValues(alpha: 0.14),
        selectedIconTheme: IconThemeData(color: colors.brand, size: 26),
        unselectedIconTheme: IconThemeData(color: colors.inkMuted, size: 24),
        selectedLabelTextStyle: text.labelMedium?.copyWith(
          color: colors.brand,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(
          color: colors.inkMuted,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: const OutlineInputBorder(
          borderRadius: AppRadius.pill,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.pill,
          borderSide: BorderSide(color: colors.brand, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.pill,
          borderSide: BorderSide(color: colors.error, width: 2),
        ),
        helperStyle: text.bodySmall,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceMuted,
        selectedColor: colors.brand.withValues(alpha: 0.16),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        labelStyle: text.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: colors.canvas),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
        showDragHandle: true,
        dragHandleColor: colors.inkMuted.withValues(alpha: 0.4),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.brand,
        linearTrackColor: colors.surfaceMuted,
        circularTrackColor: colors.surfaceMuted,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.ink,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: text.bodySmall?.copyWith(color: colors.canvas),
        waitDuration: const Duration(milliseconds: 400),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.inkMuted,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodySmall,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minVerticalPadding: 10,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: colors.brand,
        inactiveTrackColor: colors.surfaceMuted,
        thumbColor: colors.brand,
        overlayColor: colors.brand.withValues(alpha: 0.12),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : colors.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.brand
              : colors.inkMuted.withValues(alpha: 0.3),
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    );
  }
}
