import 'dart:async';

/// Purchase layer seam (Google Play Billing on Android, StoreKit2 on iOS,
/// manual/redirect checkout on Windows).
///
/// The client only ever learns product ids and purchase tokens. Receipt
/// validation, entitlements and the "is this child premium" answer always come
/// from our backend, so a rooted device cannot unlock content.
abstract interface class BillingGateway {
  bool get isSupported;
  Future<void> start();
  Future<List<PricingPlan>> loadPlans();
  Future<PurchaseOutcome> purchase(PricingPlan plan);
  Future<PurchaseOutcome> restore();
  Stream<PurchaseOutcome> get purchaseUpdates;
  Future<void> completePurchase(String purchaseToken);
  Future<void> dispose();
}

class PricingPlan {
  const PricingPlan({
    required this.id,
    required this.storeProductId,
    required this.title,
    required this.billingPeriod,
    required this.priceLabel,
    required this.trialDays,
    this.savingsLabel,
    this.isHighlighted = false,
  });

  final String id;

  /// Play Console / App Store id. Never a secret, but only used by the store.
  final String storeProductId;
  final String title;
  final BillingPeriod billingPeriod;
  final String priceLabel;
  final int trialDays;
  final String? savingsLabel;
  final bool isHighlighted;
}

enum BillingPeriod { monthly, yearly, lifetime }

extension BillingPeriodX on BillingPeriod {
  int get months => switch (this) {
    BillingPeriod.monthly => 1,
    BillingPeriod.yearly => 12,
    BillingPeriod.lifetime => 0,
  };
}

class PurchaseOutcome {
  const PurchaseOutcome({
    required this.status,
    this.purchaseToken,
    this.expiresAt,
    this.message,
  });

  factory PurchaseOutcome.success(String token, {DateTime? expiresAt}) =>
      PurchaseOutcome(
        status: PurchaseStatus.purchased,
        purchaseToken: token,
        expiresAt: expiresAt,
      );

  factory PurchaseOutcome.failed(String message) => PurchaseOutcome(
    status: PurchaseStatus.failed,
    message: message,
  );

  final PurchaseStatus status;
  final String? purchaseToken;
  final DateTime? expiresAt;
  final String? message;

  bool get isOk =>
      status == PurchaseStatus.purchased || status == PurchaseStatus.restored;
}

enum PurchaseStatus { idle, pending, purchased, restored, cancelled, failed }

/// Stand-in used by mock mode, tests and Windows desktop (where the app offers
/// a web checkout instead of Play Billing).
class MockBillingGateway implements BillingGateway {
  MockBillingGateway({this.latency = const Duration(milliseconds: 900)});

  final Duration latency;
  final _updates = StreamController<PurchaseOutcome>.broadcast();

  @override
  bool get isSupported => true;

  @override
  Future<void> start() async {}

  @override
  Future<List<PricingPlan>> loadPlans() async => const [
    PricingPlan(
      id: 'plus_monthly',
      storeProductId: 'phonicsai_plus_monthly',
      title: 'Monthly',
      billingPeriod: BillingPeriod.monthly,
      priceLabel: r'$8.99',
      trialDays: 7,
    ),
    PricingPlan(
      id: 'plus_yearly',
      storeProductId: 'phonicsai_plus_yearly',
      title: 'Yearly',
      billingPeriod: BillingPeriod.yearly,
      priceLabel: r'$59.99',
      trialDays: 14,
      savingsLabel: 'Save 44%',
      isHighlighted: true,
    ),
    PricingPlan(
      id: 'plus_lifetime',
      storeProductId: 'phonicsai_plus_lifetime',
      title: 'Forever',
      billingPeriod: BillingPeriod.lifetime,
      priceLabel: r'$149',
      trialDays: 0,
    ),
  ];

  @override
  Future<PurchaseOutcome> purchase(PricingPlan plan) async {
    await Future<void>.delayed(latency);
    return PurchaseOutcome.success('mock-token-${plan.id}');
  }

  @override
  Future<PurchaseOutcome> restore() async {
    await Future<void>.delayed(latency);
    return const PurchaseOutcome(status: PurchaseStatus.restored);
  }

  @override
  Stream<PurchaseOutcome> get purchaseUpdates => _updates.stream;

  @override
  Future<void> completePurchase(String purchaseToken) async {}

  @override
  Future<void> dispose() => _updates.close();
}
