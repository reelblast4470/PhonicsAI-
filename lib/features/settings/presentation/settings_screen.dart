import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di/infrastructure.dart';
import '../../../app/router/app_routes.dart';
import '../../../app/state/app_settings_controller.dart';
import '../../../core/domain/app_language.dart';
import '../../../core/domain/reading_level.dart';
import '../../../core/notifications/reminder_scheduler.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../../auth/application/auth_providers.dart';
import '../../parent/application/parent_controls_controller.dart';
import '../../profile/application/profile_providers.dart';
import '../application/privacy_controller.dart';

/// Settings. Grouped, dense-but-calm, and every destructive action explains
/// itself before it asks.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    final auth = ref.watch(authStateProvider).valueOrNull;
    final controls = ref.watch(parentControlsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.xxxl,
        ),
        children: [
          const SectionHeader(title: 'Learner', leadingIcon: Icons.child_care_rounded),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.people_outline_rounded),
                  title: Text(l10n.profileSwitch),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(AppRoutes.onboardingProfiles),
                ),
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1_rounded),
                  title: Text(l10n.profileAdd),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(AppRoutes.profileNew),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Reading level', leadingIcon: Icons.stairs_rounded),
          const _LevelCard(),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Language', leadingIcon: Icons.translate_rounded),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.settingsLanguage,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    ChoiceChip(
                      label: const Text('📱 Device default'),
                      selected: settings.interfaceLocale == null,
                      onSelected: (_) => controller.setInterfaceLocale(null),
                    ),
                    for (final language in AppLanguage.supported)
                      ChoiceChip(
                        label: Text(
                          '${language.flag}  ${language.nativeName}',
                        ),
                        selected: settings.interfaceLocale == language.code,
                        onSelected: (_) =>
                            controller.setInterfaceLocale(language.code),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Appearance', leadingIcon: Icons.dark_mode_outlined),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text(l10n.settingsThemeSystem),
                      icon: const Icon(Icons.brightness_auto_rounded, size: 18),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text(l10n.settingsThemeLight),
                      icon: const Icon(Icons.light_mode_rounded, size: 18),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text(l10n.settingsThemeDark),
                      icon: const Icon(Icons.dark_mode_rounded, size: 18),
                    ),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (values) =>
                      controller.setThemeMode(values.first),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(l10n.settingsTextSize,
                    style: Theme.of(context).textTheme.titleSmall),
                Slider(
                  value: settings.textScale,
                  min: 0.9,
                  max: 1.5,
                  divisions: 6,
                  label: '${(settings.textScale * 100).round()}%',
                  onChanged: (value) => controller.setTextScale(value),
                ),
                Text(
                  'The system text size still applies on top of this.',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: AppSpacing.md),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: settings.soundEnabled,
                  onChanged: controller.setSoundEnabled,
                  title: Text(l10n.settingsSound),
                  secondary: const Icon(Icons.volume_up_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Practice reminders', leadingIcon: Icons.notifications_outlined),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: controls.remindersEnabled,
                  onChanged: (value) => ref
                      .read(parentControlsProvider.notifier)
                      .setReminders(enabled: value),
                  title: Text(l10n.settingsReminders),
                  subtitle: Text(
                    controls.remindersEnabled
                        ? 'Every day at ${controls.reminderTime.label}'
                        : 'Off',
                  ),
                ),
                if (controls.remindersEnabled)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        for (final time in const [
                          (7, 30),
                          (15, 0),
                          (17, 30),
                          (19, 0),
                        ])
                          ChoiceChip(
                            label: Text(
                              '${time.$1.toString().padLeft(2, '0')}:'
                              '${time.$2.toString().padLeft(2, '0')}',
                            ),
                            selected: controls.reminderTime.hour == time.$1 &&
                                controls.reminderTime.minute == time.$2,
                            onSelected: (_) => ref
                                .read(parentControlsProvider.notifier)
                                .setReminders(
                                  enabled: true,
                                  at: TimeOfDay24(time.$1, time.$2),
                                ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Account and data', leadingIcon: Icons.lock_outline_rounded),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: Text(l10n.parentDataPrivacy),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(AppRoutes.parentPrivacy),
                ),
                ListTile(
                  leading: const Icon(Icons.help_outline_rounded),
                  title: Text(l10n.settingsHelp),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('${AppRoutes.parentSettings}/help'),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: Text(l10n.settingsAbout),
                  subtitle: Text(l10n.settingsVersion('1.0.0')),
                ),
                if (auth != null && auth.user != null && !auth.user!.isGuest)
                  ListTile(
                    leading: const Icon(Icons.logout_rounded),
                    title: Text(l10n.actionSignOut),
                    subtitle: Text(
                      auth.user?.emailOrName ?? '',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    onTap: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(l10n.actionSignOut),
                          content: Text(l10n.settingsSignOutConfirm),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: Text(l10n.actionCancel),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: Text(l10n.actionSignOut),
                            ),
                          ],
                        ),
                      );
                      if (!(confirmed ?? false)) return;
                      await ref.read(authControllerProvider.notifier).signOut();
                      ref
                          .read(analyticsServiceProvider)
                          .setUser(null);
                    },
                  ),
                ListTile(
                  leading: Icon(Icons.delete_forever_rounded,
                      color: AppColors.of(context).error),
                  title: Text(
                    l10n.settingsDeleteAccount,
                    style: TextStyle(color: AppColors.of(context).error),
                  ),
                  onTap: () => _confirmDelete(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsDeleteAccount),
        content: Text(l10n.privacyDeleteWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.of(context).error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.actionDelete),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !context.mounted) return;
    await ref.read(privacyControllerProvider.notifier).eraseEverything();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.privacyDeleted)),
      );
      context.go(AppRoutes.onboardingLanguage);
    }
  }
}

class _LevelCard extends ConsumerWidget {
  const _LevelCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(activeProfileProvider);
    if (profile == null) {
      return AppCard(
        child: Text(
          'Add a learner to set a starting level.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${profile.displayName} · ${profile.level.label}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final level in ReadingLevel.values)
                ChoiceChip(
                  label: Text(level.label),
                  selected: level == profile.level,
                  onSelected: (_) => ref
                      .read(profileControllerProvider.notifier)
                      .update(profile.copyWith(level: level)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
