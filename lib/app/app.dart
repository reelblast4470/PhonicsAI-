import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import 'router/app_router.dart';
import 'state/app_settings_controller.dart';

/// Root widget. Chooses kid vs parent theme per route and drives the app's
/// Material 3 theme, locale and text scaling from [AppSettings].
class PhonicsAiApp extends ConsumerWidget {
  const PhonicsAiApp({this.themeBrightnessOverride, super.key});

  /// Used by golden/widget tests to pin light or dark.
  final Brightness? themeBrightnessOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final brightness =
        themeBrightnessOverride ?? MediaQuery.platformBrightnessOf(context);
    final themeMode = settings.themeMode;

    return MaterialApp.router(
      title: 'PhonicsAI',
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
      themeMode: themeMode,
      theme: AppTheme.kid(_lightOrDark(themeMode, brightness, light: true)),
      darkTheme:
          AppTheme.kid(_lightOrDark(themeMode, brightness, light: false)),
      locale: settings.interfaceLocale == null
          ? null
          : Locale(settings.interfaceLocale!),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        // Clamp the OS text slider so a 200% setting can never blow up a
        // child-sized layout, while still honouring accessibility entirely.
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 2.0,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }

  static Brightness _lightOrDark(
    ThemeMode mode,
    Brightness platform, {
    required bool light,
  }) {
    return switch (mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => platform,
    };
  }
}

/// Route-aware theming helper: kid screens get the playful theme, the parent
/// area gets the compact, information-dense one.
class ParentThemeScope extends StatelessWidget {
  const ParentThemeScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Theme(
      data: AppTheme.parent(brightness),
      child: child,
    );
  }
}

/// Where the "am I in the grown-up area" question is answered once.
bool isParentRoute(String location) => location.startsWith('/parent');
