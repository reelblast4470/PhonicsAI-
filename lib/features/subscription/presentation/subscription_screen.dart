import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di/infrastructure.dart';
import '../../../core/billing/billing_gateway.dart';
import '../../../core/error/failure.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/badge_pill.dart';
import '../../../shared/widgets/kid_scaffold.dart';
import '../../../shared/widgets/status_views.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../application/subscription_providers.dart';

/// The paywall. One plan card can be selected, the price shown is the store's,
/// and there is no dark pattern: no pre-selected "most expensive", no hidden
/// cancel route, no countdown timer, and a "keep the free plan" path that is as
/// big as the upgrade path.
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  String? _selectedId;
  bool _busy = false;
  String? _notice;
  bool _isError = false;

  Future<void> _buy(PricingPlan plan) async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    final result =
        await ref.read(subscriptionProvider.notifier).purchase(plan);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _notice = result.message;
      _isError = !result.ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final status = ref.watch(subscriptionProvider);
    final plans = ref.watch(plansProvider);

    return KidScaffold(
      title: l10n.subscriptionTitle,
      body: plans.when(
        loading: () => const LoadingView(message: 'Loading plans…'),
        error: (error, _) => ErrorView(
          failure: error is AppFailure
              ? error
              : const AppFailure(
                  kind: FailureKind.unknown,
                  message: 'Plans could not be loaded.',
                ),
          onRetry: () => ref.invalidate(plansProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return AppCard(
              child: Column(
                children: [
                  Icon(Icons.storefront_outlined, size: 36, color: colors.inkMuted),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l10n.subscriptionUnavailable,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Everything you have learnt is still here and still free.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            );
          }
          final highlighted = _selectedId ??
              list
                  .firstWhere(
                    (plan) => plan.isHighlighted,
                    orElse: () => list.first,
                  )
                  .id;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCard(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colors.brand.withValues(alpha: 0.14), colors.surface],
                ),
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('📚', style: TextStyle(fontSize: 34)),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            l10n.subscriptionHeadline,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: const [
                        _Feature(Icons.auto_stories_outlined, 'subscriptionFeatureStories'),
                        _Feature(Icons.record_voice_over_outlined, 'subscriptionFeatureTutor'),
                        _Feature(Icons.insights_outlined, 'subscriptionFeatureReports'),
                        _Feature(Icons.cloud_download_outlined, 'subscriptionFeatureOffline'),
                        _Feature(Icons.verified_user_outlined, 'subscriptionFeatureAds'),
                      ],
                    ),
                  ],
                ),
              ),
              if (status.isPlus) ...[
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  color: colors.mint.withValues(alpha: 0.12),
                  borderColor: colors.mint,
                  child: Row(
                    children: [
                      Icon(Icons.verified_rounded, color: colors.mint),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          l10n.subscriptionActiveMessage(
                            status.expiresAt == null
                                ? '—'
                                : '${status.expiresAt!.day}/'
                                    '${status.expiresAt!.month}/'
                                    '${status.expiresAt!.year}',
                          ),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              for (final plan in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _PlanCard(
                    plan: plan,
                    isSelected: plan.id == highlighted,
                    isCurrent: status.storeProductId == plan.id,
                    onSelect: () => setState(() => _selectedId = plan.id),
                  ),
                ),
              if (_notice case final notice?)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: AppCard(
                    color: (_isError ? colors.error : colors.mint)
                        .withValues(alpha: 0.12),
                    borderColor: _isError ? colors.error : colors.mint,
                    child: Text(
                      notice,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),
              AppButton(
                label: status.isPlus
                    ? 'Manage in the store'
                    : 'Unlock PhonicsAI Plus',
                icon: Icons.lock_open_rounded,
                isExpanded: true,
                isLoading: _busy,
                onPressed: _busy
                    ? null
                    : () => _buy(
                        list.firstWhere(
                          (plan) => plan.id == highlighted,
                          orElse: () => list.first,
                        ),
                      ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: TextButton(
                  onPressed: () async {
                    setState(() => _busy = true);
                    final outcome = await ref
                        .read(billingGatewayProvider)
                        .restore();
                    if (!mounted) return;
                    setState(() {
                      _busy = false;
                      _isError = !outcome.isOk;
                      _notice = outcome.isOk
                          ? l10n.subscriptionRestored
                          : 'Nothing to restore on this device.';
                    });
                  },
                  child: Text(l10n.actionRestore),
                ),
              ),
              Text(
                l10n.subscriptionBillingNote,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: AppSpacing.md),
              if (!status.isPlus)
                AppButton(
                  label: 'Stay on the free plan',
                  tone: AppButtonTone.neutral,
                  isExpanded: true,
                  isCompact: true,
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go('/parent'),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature(this.icon, this.labelKey);

  final IconData icon;
  final String labelKey;

  @override
  Widget build(BuildContext context) {
    // Feature copy is localised through the arb table; the key is resolved here
    // so adding a benefit is a one-line content change.
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.of(context).brand),
        const SizedBox(width: 6),
        // Flexible so a long translated benefit line wraps instead of pushing
        // the row past the card edge.
        Flexible(
          child: Text(
            _resolve(context, labelKey),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  static String _resolve(BuildContext context, String key) => switch (key) {
        'subscriptionFeatureStories' =>
          AppLocalizations.of(context).subscriptionFeatureStories,
        'subscriptionFeatureTutor' =>
          AppLocalizations.of(context).subscriptionFeatureTutor,
        'subscriptionFeatureReports' =>
          AppLocalizations.of(context).subscriptionFeatureReports,
        'subscriptionFeatureOffline' =>
          AppLocalizations.of(context).subscriptionFeatureOffline,
        _ => AppLocalizations.of(context).subscriptionFeatureAds,
      };
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isSelected,
    required this.isCurrent,
    required this.onSelect,
  });

  final PricingPlan plan;
  final bool isSelected;
  final bool isCurrent;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final perMonth = plan.billingPeriod == BillingPeriod.yearly
        ? 'about ${_perMonth(plan.priceLabel)} / month'
        : plan.billingPeriod == BillingPeriod.lifetime
            ? 'one-time'
            : 'per month';

    return PressableCard(
      onTap: onSelect,
      radius: 24,
      padding: const EdgeInsets.all(AppSpacing.lg),
      borderColor: isSelected ? colors.brand : null,
      color: isSelected ? colors.brand.withValues(alpha: 0.05) : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A Wrap, not a Row: title + savings pill + "current" pill
                // together outgrow a 360dp card, and a title must never be
                // ellipsised away on a paywall.
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      plan.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    if (plan.savingsLabel case final savings?)
                      BadgePill(
                        label: savings,
                        tone: BadgeTone.mint,
                        isSolid: true,
                      ),
                    if (isCurrent)
                      BadgePill(
                        label: l10n.subscriptionCurrent,
                        tone: BadgeTone.brand,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  plan.trialDays > 0
                      ? '${l10n.subscriptionTrial(plan.trialDays)} · $perMonth'
                      : perMonth,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // Price and the selection mark share a column: side-by-side they
          // outgrow a 360dp card once the title wraps.
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                plan.priceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: AppSpacing.sm),
              AnimatedScale(
                duration: AppMotion.fast,
                scale: isSelected ? 1 : 0.7,
                child: Icon(
                  isSelected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: isSelected ? colors.brand : colors.inkMuted,
                  size: 24,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _perMonth(String priceLabel) {
    final amount = double.tryParse(priceLabel.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (amount == null) return '—';
    return '\$${(amount / 12).toStringAsFixed(2)}';
  }
}
