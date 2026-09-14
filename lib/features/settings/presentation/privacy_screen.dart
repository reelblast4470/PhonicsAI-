import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/infrastructure.dart';
import '../../../app/state/app_settings_controller.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/feedback/app_toast.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/kid_scaffold.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../../auth/application/auth_providers.dart';
import '../application/privacy_controller.dart';

/// Privacy and account controls, written for a parent reading it once, in a
/// hurry, on a phone. Every toggle states what it changes in plain words.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final state = ref.watch(privacyControllerProvider);
    final controller = ref.read(privacyControllerProvider.notifier);
    final auth = ref.watch(authStateProvider).valueOrNull;
    final settings = ref.watch(appSettingsProvider);

    return KidScaffold(
      title: l10n.privacyTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            color: colors.mint.withValues(alpha: 0.1),
            borderColor: colors.mint.withValues(alpha: 0.4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.shield_rounded, color: colors.mint),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        l10n.privacySummary,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _Bullet(icon: Icons.mic_off_rounded, text: l10n.privacyRecording),
                _Bullet(icon: Icons.block_rounded, text: l10n.privacyNoAds),
                _Bullet(
                  icon: Icons.file_download_rounded,
                  text: l10n.privacyExport,
                ),
                _Bullet(icon: Icons.gavel_rounded, text: l10n.privacyCoppa),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Sync and analytics', leadingIcon: Icons.sync_rounded),
          AppCard(
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: state.cloudSyncEnabled && (auth?.hasRealAccount ?? false),
                  onChanged: (auth?.hasRealAccount ?? false) && !state.isErasing
                      ? controller.setCloudSync
                      : null,
                  title: Text(
                    state.cloudSyncEnabled
                        ? l10n.privacyTurnOffSync
                        : l10n.privacyTurnOnSync,
                  ),
                  subtitle: Text(
                    (auth?.hasRealAccount ?? false)
                        ? 'Progress and stars are mirrored to your PhonicsAI '
                            'account so any device in the family is up to date.'
                        : 'Needs a PhonicsAI account (not a device-only guest).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const Divider(height: AppSpacing.lg),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: state.analyticsEnabled,
                  onChanged: (value) {
                    controller.setAnalytics(value);
                    ref
                        .read(analyticsServiceProvider)
                        .logEvent('analytics_consent', {'granted': value});
                  },
                  title: Text('Product analytics'),
                  subtitle: Text(
                    'Counts only — "lesson 3 finished, 2 stars". No names, no '
                    'audio, no advertising identifiers.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Your data', leadingIcon: Icons.folder_shared_outlined),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Everything PhonicsAI knows about ${settings.activeProfileId == null ? 'this device' : 'this learner'} '
                  'is on this tablet. Export it any time — it is your copy, in '
                  'plain JSON.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: l10n.settingsExportData,
                  icon: Icons.download_rounded,
                  isExpanded: true,
                  isCompact: true,
                  tone: AppButtonTone.neutral,
                  onPressed: () async {
                    final bundle = await controller.exportBundle();
                    await Clipboard.setData(ClipboardData(text: bundle));
                    if (context.mounted) {
                      AppToast.show(
                        context,
                        'Copied ${bundle.length} characters to the clipboard.',
                        icon: Icons.copy_rounded,
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            color: colors.error.withValues(alpha: 0.07),
            borderColor: colors.error.withValues(alpha: 0.35),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: colors.error),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        l10n.settingsDeleteAccount,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: colors.error,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.privacyDeleteWarning,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: state.isErasing
                      ? l10n.stateLoading
                      : l10n.actionDelete,
                  tone: AppButtonTone.danger,
                  isExpanded: true,
                  isCompact: true,
                  isLoading: state.isErasing,
                  onPressed: state.isErasing
                      ? null
                      : () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(l10n.settingsDeleteAccount),
                              content: Text(l10n.privacyDeleteWarning),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: Text(l10n.actionCancel),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor:
                                        AppColors.of(context).error,
                                  ),
                                  onPressed: () => Navigator.of(context).pop(true),
                                  child: Text(l10n.actionDelete),
                                ),
                              ],
                            ),
                          );
                          if (!(confirmed ?? false)) return;
                          await ref
                              .read(privacyControllerProvider.notifier)
                              .eraseEverything();
                          if (context.mounted) {
                            AppToast.show(
                              context,
                              l10n.privacyDeleted,
                              icon: Icons.delete_sweep_rounded,
                            );
                          }
                        },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Flavour: ${ref.read(appConfigProvider).flavor.name} · '
            'backend: ${ref.read(appConfigProvider).hasBackend ? 'connected' : 'this device only'}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.of(context).inkMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
