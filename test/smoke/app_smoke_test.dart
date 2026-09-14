import 'package:flutter/material.dart';
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

/// Pumps the real app (real router, real guards, in-memory adapters) and walks
/// the primary navigation. This is the "no broken navigation" gate.
void main() {
  testWidgets('splash boots into the onboarding language step', (tester) async {
    await pumpPhonicsAi(tester);
    await settlePastSplash(tester);
    expect(
      find.text('Which language helps you learn best?'),
      findsOneWidget,
      reason: 'a first run must land on onboarding, not on an empty home',
    );
    // The onboarding frame paints exactly four progress dots.
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing,
        reason: 'step 1 has nowhere to go back to');
  });

  testWidgets('an onboarded device with a profile goes straight to home', (tester) async {
    final store = InMemoryKeyValueStore({
      'phonicsai.onboarding_complete': true,
      'phonicsai.active_profile': 'aarav',
    });
    await pumpPhonicsAi(tester, store: store);
    await settlePastSplash(tester);
    expect(find.text('Home'), findsWidgets);
  });
}

/// The splash animates for 900ms and then awaits a cache warm, so tests pump a
/// fixed schedule instead of `pumpAndSettle` (the splash pips repeat forever).
Future<void> settlePastSplash(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Pumps the whole app with test adapters. Every widget test starts here.
Future<void> pumpPhonicsAi(
  WidgetTester tester, {
  KeyValueStore? store,
  AppConfig? config,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: testOverrides(store: store, config: config),
      child: const PhonicsAiApp(themeBrightnessOverride: Brightness.light),
    ),
  );
}

/// Shared override set for every test in the suite.
List<Override> testOverrides({KeyValueStore? store, AppConfig? config}) => [
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
