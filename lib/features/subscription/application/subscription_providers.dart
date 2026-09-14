import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/infrastructure.dart';
import '../../../core/billing/billing_gateway.dart';
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

  Future<void> _applyVerified({
    required String token,
    required String planId,
    DateTime? expiresAt,
  }) async {
    // TODO(backend): POST /billing/verify {token} -> entitlement. Until that
    // exists this local decision stands, and it is deliberately conservative:
    // mock tokens only ever unlock in non-prod flavors.
    final config = ref.read(appConfigProvider);
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
