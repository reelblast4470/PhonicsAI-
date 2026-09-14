import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonicsai/app/app.dart';
import 'package:phonicsai/app/di/infrastructure.dart';
import 'package:phonicsai/core/analytics/analytics_service.dart';
import 'package:phonicsai/core/audio/audio_service.dart';
import 'package:phonicsai/core/env/app_config.dart';
import 'package:phonicsai/core/notifications/reminder_scheduler.dart';
import 'package:phonicsai/core/speech/speech_service.dart';
import 'package:phonicsai/core/storage/in_memory_secure_vault.dart';
import 'package:phonicsai/core/storage/key_value_store.dart';
import 'package:phonicsai/l10n/generated/app_localizations.dart';
import 'package:phonicsai/theme/app_theme.dart';

/// Shared test plumbing for every feature test.
///
/// The sizes are the four windows PhonicsAI must survive: a small Android
/// phone, a big phone, an iPad-ish tablet and a Windows desktop window.
class ScreenSize {
  const ScreenSize(this.name, this.size, this.devicePixelRatio);

  final String name;
  final Size size;
  final double devicePixelRatio;

  static const phoneSmall = ScreenSize('360x640 phone', Size(360, 640), 2.0);
  static const phoneLarge = ScreenSize('412x915 phone', Size(412, 915), 2.6);
  static const tablet = ScreenSize('800x1180 tablet', Size(800, 1180), 2.0);
  static const desktop =
      ScreenSize('1440x900 windows', Size(1440, 900), 1.0);

  static const all = [phoneSmall, phoneLarge, tablet, desktop];
}

/// A store pre-seeded so the app opens on Home with one learner, as if the
/// family had already finished onboarding yesterday.
InMemoryKeyValueStore onboardedStore({
  String profileId = 'learner_test',
  String name = 'Aarav',
  String level = 'cvc_blender',
  int ageMonths = 60,
  int stars = 24,
}) {
  return InMemoryKeyValueStore({
    'phonicsai.onboarding_complete': true,
    'phonicsai.active_profile': profileId,
    'phonicsai.profiles.$profileId': jsonEncode({
      'id': profileId,
      'name': name,
      'age_months': ageMonths,
      'avatar': 'fox',
      'level': level,
      'created_at': '2026-09-01T09:00:00.000',
      'home_language': 'en',
      'assessed': true,
      'goal_minutes': 15,
      'stars': stars,
    }),
  });
}

/// Builds test overrides for the whole provider graph.
List<Override> harnessOverrides({KeyValueStore? store, AppConfig? config}) => [
      appConfigProvider.overrideWithValue(config ?? AppConfig.dev),
      keyValueStoreProvider.overrideWithValue(store ?? InMemoryKeyValueStore()),
      secureVaultProvider.overrideWithValue(InMemorySecureVault()),
      analyticsServiceProvider
          .overrideWithValue(LoggingAnalyticsService(enabled: false)),
      audioServiceProvider.overrideWithValue(NoopAudioService()),
      speechServiceProvider.overrideWithValue(MockSpeechService()),
      reminderSchedulerProvider
          .overrideWithValue(const InAppReminderScheduler()),
    ];

/// Pumps [child] inside the real app shell (theme, l10n, ProviderScope) at the
/// given size. Use with `expectNoOverflow`.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget child, {
  ScreenSize size = ScreenSize.tablet,
  List<Override> extraOverrides = const [],
  bool useRealTheme = true,
}) async {
  tester.view.physicalSize = size.size * size.devicePixelRatio;
  tester.view.devicePixelRatio = size.devicePixelRatio;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [...harnessOverrides(), ...extraOverrides],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        theme: AppTheme.kid(Brightness.light),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}

/// Fails if the tree logged any exception (overflow included) after settling.
void expectNoOverflow(WidgetTester tester) {
  expect(tester.takeException(), isNull,
      reason: 'layout or build exception (check for RenderFlex overflow)');
}

/// Pumps the *real* app (router, guards, theme, l10n) at [size] with a seeded
/// store. Use for navigation and end-to-end flows.
Future<void> pumpApp(
  WidgetTester tester, {
  ScreenSize size = ScreenSize.phoneLarge,
  KeyValueStore? store,
}) async {
  tester.view.physicalSize = size.size * size.devicePixelRatio;
  tester.view.devicePixelRatio = size.devicePixelRatio;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...harnessOverrides(store: store ?? onboardedStore()),
      ],
      child: const PhonicsAiApp(themeBrightnessOverride: Brightness.light),
    ),
  );
  await settlePastSplash(tester);
}

/// Advances past the splash animation + its cache warm without pumpAndSettle.
Future<void> settlePastSplash(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// Taps a widget, tolerating the 800ms animations the kid screens run.
Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  // Let a pending reveal-scroll from `ensureVisible` land first: tapping with
  // pre-scroll geometry would hit whatever overlaps the target's old spot.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pump(const Duration(milliseconds: 600));
}
