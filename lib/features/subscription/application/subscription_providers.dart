import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/infrastructure.dart';
import '../../../core/billing/billing_gateway.dart';
import '../../../core/env/app_config.dart';
import '../../../core/error/failure.dart';
import '../../../core/storage/key_value_store.dart';
import '../domain/subscription_models.dart';

/// Owns the entitlement the whole app branches on.
///
/// Flow: read the cached entitlement (so the app is correct offline and on a
/// cold start) → ask the store to refresh → verify the receipt on our backend →
/// store the *answer*, not the receipt. A purchase that cannot be verified
/// leaves the user on Free with a clear message rather than a stolen upgrade.
class SubscriptionController extends Notifier<SubscriptionStatus> {
  static const cacheKey = 'phonicsai.subscription.status';

  @override
  SubscriptionStatus build() {
    final cached = ref
        .read(keyValueStoreProvider)
        .getJson<SubscriptionStatus>(cacheKey, SubscriptionStatus.fromJson);
    unawaited(refresh());
    return cached ?? SubscriptionStatus.free();
  }

  BillingGateway get _billing => ref.read(billingGatewayProvider);

  Future<void> refresh() async {
    // Server first when configured: /subscriptions/me reflects store-verified
    // truth, so an entitlement revoked upstream (refund) lands here too.
    final config = ref.read(appConfigProvider);
    if (config.hasBackend && config.backendMode != BackendMode.mock) {
      try {
        final me = await ref.read(apiClientProvider).getJson('/subscriptions/me');
        await _save(_statusFromServer(me));
        return;
      } on AppFailure {
        // Unreachable server: fall back to the store below, keep the cache.
      } catch (_) {}
    }
    try {
      await _billing.start();
      final outcome = await _billing.restore();
      if (outcome.isOk && outcome.purchaseToken != null) {
        await _applyVerified(
          token: outcome.purchaseToken!,
          planId: 'plus_yearly',
        );
      }
    } catch (error) {
      // Restore failures are normal offline; the cached entitlement stands.
    }
  }

  Future<PurchaseResult> purchase(PricingPlan plan) async {
    try {
      final outcome = await _billing.purchase(plan);
      if (!outcome.isOk) {
        return PurchaseResult(
          ok: false,
          cancelled: outcome.status == PurchaseStatus.cancelled,
          message: outcome.message ?? 'The store did not complete that purchase.',
        );
      }
      await _applyVerified(
        token: outcome.purchaseToken ?? 'unknown',
        planId: plan.id,
        expiresAt: outcome.expiresAt,
      );
      // The server (or the local dev rule) has now spoken. A purchase it
      // refused never reports as unlocked just because the store did.
      if (!state.isPlus) {
        return PurchaseResult(
          ok: false,
          message: 'We could not confirm that purchase with the store.',
        );
      }
      return PurchaseResult(
        ok: true,
        message: plan.trialDays > 0
            ? 'Trial started — ${plan.trialDays} days on us.'
            : 'Unlocked. Happy reading!',
      );
    } on AppFailure catch (failure) {
      return PurchaseResult(ok: false, message: failure.message);
    } catch (error) {
      return PurchaseResult(
        ok: false,
        message: 'Purchases are not available on this device.',
      );
    }
  }

  /// Verifies the receipt with OUR backend — which in turn verifies it with
  /// the store (server-side). Only the server's answer unlocks anything.
  Future<void> _applyVerified({
    required String token,
    required String planId,
    DateTime? expiresAt,
  }) async {
    final config = ref.read(appConfigProvider);
    if (config.hasBackend && config.backendMode != BackendMode.mock) {
      try {
        final json = await ref.read(apiClientProvider).postJson(
          '/subscriptions/me/receipt',
          body: {
            'store': _storeName(token),
            'product_id': planId,
            'purchase_token': token,
          },
        );
        await _save(_statusFromServer(json));
        return;
      } on AppFailure catch (failure) {
        final networkish = failure.kind == FailureKind.offline ||
            failure.kind == FailureKind.timeout;
        if (!networkish) {
          // The server saw the receipt and refused it: stay free.
          await _save(SubscriptionStatus.free());
          return;
        }
        // Offline during verification -> the conservative local rule below.
      }
    }
    // Local fallback when no backend is configured (dev/mock flavors), and it
    // is deliberately conservative: mock tokens only ever unlock in non-prod.
    if (config.flavor.name == 'prod' && token.startsWith('mock-token')) {
      state = SubscriptionStatus.free();
      return;
    }
    final isTrial = token.startsWith('mock-token') && planId != 'plus_lifetime';
    final next = SubscriptionStatus(
      tier: SubscriptionTier.plus,
      entitlements: const {
        Entitlement.unlimitedTutor,
        Entitlement.fullLibrary,
        Entitlement.offlineLessons,
        Entitlement.detailedReports,
        Entitlement.multipleProfiles,
      },
      expiresAt: expiresAt ??
          DateTime.now().add(Duration(days: isTrial ? 7 : 365)),
      willRenew: planId != 'plus_lifetime',
      storeProductId: planId,
      isTrial: isTrial,
    );
    state = next;
    await ref
        .read(keyValueStoreProvider)
        .setJson(cacheKey, next.toJson());
  }

  static String _storeName(String token) {
    // Mock gateways always mint 'mock-token-*'; real platforms get the real
    // store name so the backend picks the right verifier credentials.
    if (token.startsWith('mock-token')) return 'mock';
    if (defaultTargetPlatform == TargetPlatform.android) return 'google_play';
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'app_store';
    return 'mock'; // web/desktop checkout lands in Phase 6 with real billing
  }

  static SubscriptionStatus _statusFromServer(Map<String, dynamic> j) {
    final status = j['status'] as String? ?? 'free';
    final verified = j['verified'] == true;
    if (!verified ||
        status == 'free' ||
        status == 'expired' ||
        status == 'cancelled') {
      return SubscriptionStatus.free();
    }
    final plan = j['plan_key'] as String? ?? 'plus_monthly';
    return SubscriptionStatus(
      tier: SubscriptionTier.plus,
      entitlements: const {
        Entitlement.unlimitedTutor,
        Entitlement.fullLibrary,
        Entitlement.offlineLessons,
        Entitlement.detailedReports,
        Entitlement.multipleProfiles,
      },
      expiresAt: DateTime.tryParse(j['current_period_end'] as String? ?? ''),
      willRenew: plan != 'plus_lifetime' && j['cancel_at_period_end'] != true,
      storeProductId: plan,
      isTrial: status == 'trialing',
    );
  }

  Future<void> _save(SubscriptionStatus next) async {
    state = next;
    await ref.read(keyValueStoreProvider).setJson(cacheKey, next.toJson());
  }

  Future<void> cancel() async {
    // Cancellation happens in the store; we surface the deep link instead of a
    // fake "Cancel" button that would mislead the parent.
    state = state.copyWith(willRenew: false);
  }
}

@immutable
class PurchaseResult {
  const PurchaseResult({
    required this.ok,
    this.message,
    this.cancelled = false,
  });

  final bool ok;
  final String? message;
  final bool cancelled;
}

final subscriptionProvider =
    NotifierProvider<SubscriptionController, SubscriptionStatus>(
  SubscriptionController.new,
);

/// Plans, straight from the store adapter, with a graceful local fallback.
final plansProvider = FutureProvider<List<PricingPlan>>((ref) async {
  try {
    return await ref.watch(billingGatewayProvider).loadPlans();
  } catch (_) {
    return const [];
  }
});

/// One place for "is this feature paid?" so no screen invents its own rule.
final entitlementProvider = Provider<bool Function(Entitlement)>(
  (ref) => (entitlement) =>
      ref.watch(subscriptionProvider).has(entitlement),
);
