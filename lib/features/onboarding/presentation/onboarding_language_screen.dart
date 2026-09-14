import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/state/app_settings_controller.dart';
import '../../../core/domain/app_language.dart';
import '../../../core/responsive/responsive.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/l10n_context.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/kid_scaffold.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../application/onboarding_controller.dart';
import 'widgets/language_option.dart';

/// Step 1 — language. Two distinct choices, because in a bilingual home they
/// are not the same question: what the *app* speaks vs what *explains* a sound
/// best to this child.
class OnboardingLanguageScreen extends ConsumerStatefulWidget {
  const OnboardingLanguageScreen({super.key});

  @override
  ConsumerState<OnboardingLanguageScreen> createState() =>
      _OnboardingLanguageScreenState();
}

class _OnboardingLanguageScreenState
    extends ConsumerState<OnboardingLanguageScreen> {
  String? _homeLanguage;

  @override
  void initState() {
    super.initState();
    _homeLanguage = 'en';
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final isWide = context.breakpoint.index >= Breakpoint.medium.index;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.languageTitle,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.languageSubtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.inkMuted,
                ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Expanded(
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ScrollableColumn(
                          child: _appLanguageColumn(l10n, settings),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xl),
                      Expanded(
                        child: ScrollableColumn(
                          child: _homeLanguageColumn(l10n),
                        ),
                      ),
                    ],
                  )
                : ListView(
                    children: [
                      _appLanguageColumn(l10n, settings),
                      const SizedBox(height: AppSpacing.xl),
                      _homeLanguageColumn(l10n),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: l10n.actionContinue,
            isExpanded: true,
            onPressed: () => context.go(OnboardingStep.language.nextRoute),
          ),
          TextButton(
            onPressed: () =>
                context.go(OnboardingStep.profiles.route),
            child: Text(l10n.actionLater),
          ),
        ],
      ),
    );
  }

  Widget _appLanguageColumn(AppLocalizations l10n, AppSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.languageInterface, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        LanguageOption(
          title: '📱  Device default',
          subtitle: 'Follow the phone or tablet language',
          isSelected: settings.interfaceLocale == null,
          onTap: () =>
              ref.read(appSettingsProvider.notifier).setInterfaceLocale(null),
        ),
        for (final language in AppLanguage.supported)
          LanguageOption(
            title: '${language.flag}  ${language.nativeName}',
            subtitle: language.englishName,
            isSelected: settings.interfaceLocale == language.code,
            onTap: () => ref
                .read(appSettingsProvider.notifier)
                .setInterfaceLocale(language.code),
          ),
      ],
    );
  }

  Widget _homeLanguageColumn(AppLocalizations l10n) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.languageHome, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final code in InstructionLanguage.codes)
              ChoiceChip(
                label: Text(InstructionLanguage.names[code]!),
                selected: _homeLanguage == code,
                onSelected: (_) => setState(() => _homeLanguage = code),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Aria gives instructions in this language and models every English '
          'sound herself.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          color: colors.brand.withValues(alpha: 0.08),
          borderColor: colors.brand.withValues(alpha: 0.2),
          child: Row(
            children: [
              Icon(Icons.record_voice_over_outlined, color: colors.brand),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Sounds and words are always English — only the coaching '
                  'changes language.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
