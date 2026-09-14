import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/responsive.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../application/onboarding_controller.dart';

/// Persistent chrome for the onboarding steps: soft gradient, progress line and
/// a "back" affordance that never traps a child (or a parent) mid-flow.
class OnboardingFrame extends StatelessWidget {
  const OnboardingFrame({required this.child, required this.step, super.key});

  final Widget child;
  final OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final total = OnboardingStep.values.length;

    return Scaffold(
      backgroundColor: colors.canvas,
      body: DecoratedBox(
        position: DecorationPosition.background,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colors.brand.withValues(alpha: 0.16),
              colors.canvas,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  0,
                ),
                child: ContentLimits(
                  child: Row(
                    children: [
                      if (!step.isFirst)
                        IconButton(
                          onPressed: () => context.go(step.previousRoute),
                          icon: const Icon(Icons.arrow_back_rounded),
                          tooltip: MaterialLocalizations.of(context)
                              .backButtonTooltip,
                        ),
                      const Spacer(),
                      for (var i = 0; i < total; i++)
                        AnimatedContainer(
                          duration: AppMotion.normal,
                          margin: const EdgeInsets.only(right: 6),
                          height: 6,
                          width: i <= step.index ? 26 : 14,
                          decoration: BoxDecoration(
                            color: i <= step.index
                                ? colors.brand
                                : colors.inkMuted.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ContentLimits(
                  extraPadding: AppSpacing.xxxl,
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
