import 'package:flutter/foundation.dart';

import '../../../core/billing/billing_gateway.dart';

/// What a plan unlocks. Entitlements are the app's only source of truth for
/// premium behaviour; the store receipt is never consulted in the UI.
enum Entitlement {
  unlimitedTutor,
  fullLibrary,
  offlineLessons,
  detailedReports,
  multipleProfiles,
}

@immutable
class SubscriptionStatus {
  const SubscriptionStatus({
    required this.tier,
    required this.entitlements,
    this.expiresAt,
    this.willRenew = false,
    this.storeProductId,
    this.isTrial = false,
  });

  factory SubscriptionStatus.free() => const SubscriptionStatus(
        tier: SubscriptionTier.free,
        entitlements: {Entitlement.multipleProfiles},
      );

  final SubscriptionTier tier;
  final Set<Entitlement> entitlements;
  final DateTime? expiresAt;
  final bool willRenew;
  final String? storeProductId;
  final bool isTrial;

  bool get isPlus => tier == SubscriptionTier.plus;

  bool has(Entitlement entitlement) =>
      entitlements.contains(entitlement) || isPlus;

  int get trialDaysLeft {
    final expires = expiresAt;
    if (expires == null || !isTrial) return 0;
    final left = expires.difference(DateTime.now()).inDays;
    return left < 0 ? 0 : left;
  }

  String get renewsLabel {
    final expires = expiresAt;
    if (expires == null) return 'Active';
    final formatted =
        '${expires.day}/${expires.month}/${expires.year}';
    if (isTrial) return 'Trial ends $formatted';
    return willRenew ? 'Renews $formatted' : 'Expires $formatted';
  }

  SubscriptionStatus copyWith({
    SubscriptionTier? tier,
    Set<Entitlement>? entitlements,
    DateTime? expiresAt,
    bool? willRenew,
    String? storeProductId,
    bool? isTrial,
  }) {
    return SubscriptionStatus(
      tier: tier ?? this.tier,
      entitlements: entitlements ?? this.entitlements,
      expiresAt: expiresAt ?? this.expiresAt,
      willRenew: willRenew ?? this.willRenew,
      storeProductId: storeProductId ?? this.storeProductId,
      isTrial: isTrial ?? this.isTrial,
    );
  }

  Map<String, dynamic> toJson() => {
        'tier': tier.name,
        'expires_at': expiresAt?.toIso8601String(),
        'will_renew': willRenew,
        'product': storeProductId,
        'trial': isTrial,
      };

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) =>
      SubscriptionStatus(
        tier: SubscriptionTier.values.firstWhere(
          (tier) => tier.name == json['tier'],
          orElse: () => SubscriptionTier.free,
        ),
        entitlements: const {Entitlement.multipleProfiles},
        expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
        willRenew: json['will_renew'] as bool? ?? false,
        storeProductId: json['product'] as String?,
        isTrial: json['trial'] as bool? ?? false,
      );
}

enum SubscriptionTier { free, plus, plusTrial }

/// Plans offered, with the localised price labels Play/Apple return. The
/// product ids come from the store console — they are not secrets, but they are
/// also useless without a signed receipt from the store.
@immutable
class Plan {
  const Plan({
    required this.id,
    required this.title,
    required this.period,
    required this.priceLabel,
    required this.perMonthLabel,
    required this.trialDays,
    this.savingsLabel,
    this.isHighlighted = false,
    this.badge,
  });

  final String id;
  final String title;
  final BillingPeriod period;
  final String priceLabel;
  final String perMonthLabel;
  final int trialDays;
  final String? savingsLabel;
  final bool isHighlighted;
  final String? badge;

  /// "Yearly = $4.99/mo" is the single most persuasive line on a paywall, so it
  /// is computed here rather than hard-coded per locale.
  static String _perMonth(String priceLabel) {
    final amount = double.tryParse(
      priceLabel.replaceAll(RegExp(r'[^0-9.]'), ''),
    );
    if (amount == null) return '—';
    return '\$${(amount / 12).toStringAsFixed(2)}';
  }

  static List<Plan> fromPricing(List<PricingPlan> pricing) => [
        for (final plan in pricing)
          Plan(
            id: plan.id,
            title: plan.title,
            period: plan.billingPeriod,
            priceLabel: plan.priceLabel,
            perMonthLabel: switch (plan.billingPeriod) {
              BillingPeriod.monthly => 'per month',
              BillingPeriod.yearly => 'about ${_perMonth(plan.priceLabel)} / month',
              BillingPeriod.lifetime => 'one-time',
            },
            trialDays: plan.trialDays,
            savingsLabel: plan.savingsLabel,
            isHighlighted: plan.isHighlighted,
            badge: plan.savingsLabel,
          ),
      ];
}
