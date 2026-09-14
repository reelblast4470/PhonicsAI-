import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/state/app_settings_controller.dart';
import '../../../core/domain/app_language.dart';
import '../../../core/domain/learner_profile.dart';
import '../../../core/domain/reading_level.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/kid_scaffold.dart';
import '../../../shared/widgets/status_views.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../application/profile_providers.dart';
import '../domain/profile_repository.dart';
import 'widgets/profile_widgets.dart';

/// Learner profiles — the heart of "one tablet, whole class of kids".
///
/// Two jobs in one screen: when nobody exists yet it *creates* the first
/// learner; afterwards it *chooses* between them (with edit/delete behind a
/// long-press, the pattern parents already know from other apps).
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({this.profileId, super.key});

  /// Set when editing an existing learner.
  final String? profileId;

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  static const maxProfiles = 4;

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  int _ageMonths = 60;
  String _avatarId = 'fox';
  ReadingLevel _level = ReadingLevel.letterSounds;
  bool _takeTest = true;
  String _homeLanguage = 'en';
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfEditing());
  }

  void _loadIfEditing() {
    final id = widget.profileId;
    if (id == null) return;
    final profile = ref.read(profileRepositoryProvider).findById(id);
    if (profile == null || !mounted) return;
    setState(() {
      _name.text = profile.displayName;
      _ageMonths = profile.ageMonths;
      _avatarId = profile.avatarId;
      _level = profile.level;
      _takeTest = false;
      _homeLanguage = profile.homeLanguageCode;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.profileId != null;

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final controller = ref.read(profileControllerProvider.notifier);
    final saved = _isEditing
        ? await controller.update(
            (ref.read(profileRepositoryProvider).findById(widget.profileId!))!
                .copyWith(
                  displayName: _name.text,
                  ageMonths: _ageMonths,
                  avatarId: _avatarId,
                  level: _level,
                  homeLanguageCode: _homeLanguage,
                  isAssessmentComplete: !_takeTest,
                ),
          )
        : await controller.create(
            displayName: _name.text,
            ageMonths: _ageMonths,
            avatarId: _avatarId,
            level: _takeTest ? ReadingLevelSeed.takeTest : ReadingLevelSeed.manual,
            homeLanguageCode: _homeLanguage,
            runAssessment: _takeTest,
          );
    if (saved == null) return;

    if (_isEditing) {
      if (!mounted) return;
      context.pop();
      return;
    }

    final needsOnboarding =
        !ref.read(appSettingsProvider).onboardingComplete;
    if (needsOnboarding && _takeTest) {
      if (!mounted) return;
      context.go(AppRoutes.onboardingAssessment);
      return;
    }
    await ref.read(appSettingsProvider.notifier).completeOnboarding();
    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profiles = ref.watch(profilesProvider);

    // Nobody yet -> straight into the form. Choosing between existing kids is
    // only meaningful once there is more than one.
    final shouldCreate = profiles.maybeWhen(
      data: (list) => list.isEmpty && !_isEditing,
      orElse: () => true,
    );

    if (shouldCreate) return _buildForm(l10n, isInOnboarding: false);

    return KidScaffold(
      title: l10n.profileWhosLearning,
      showBack: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AsyncStateView<List<LearnerProfile>>(
            value: profiles,
            loadingMessage: l10n.stateLoading,
            builder: (context, list) => list.isEmpty
                ? EmptyView(
                    title: 'No learners yet',
                    message: 'Add the first reader to begin.',
                    icon: Icons.child_care_rounded,
                    actionLabel: l10n.actionAdd,
                    onAction: () => context.push(AppRoutes.profileNew),
                  )
                : Column(
                    children: [
                      for (final profile in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: ProfileTile(
                            profile: profile,
                            isActive:
                                ref.watch(appSettingsProvider).activeProfileId ==
                                profile.id,
                            onTap: () async {
                              await ref
                                  .read(profileControllerProvider.notifier)
                                  .activate(profile.id);
                              if (context.mounted) {
                                final settings = ref.read(appSettingsProvider);
                                context.go(
                                  settings.onboardingComplete
                                      ? AppRoutes.home
                                      : AppRoutes.onboardingAssessment,
                                );
                              }
                            },
                            onLongPress: () => _showProfileMenu(profile),
                            trailing: IconButton(
                              onPressed: () => context.push(
                                '${AppRoutes.profileEditor}/${profile.id}',
                              ),
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              tooltip: l10n.actionEdit,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (profiles.valueOrNull != null &&
              profiles.valueOrNull!.length < maxProfiles)
            AppButton(
              label: l10n.profileAdd,
              icon: Icons.person_add_alt_1_rounded,
              tone: AppButtonTone.neutral,
              isExpanded: true,
              onPressed: () => context.push(AppRoutes.profileNew),
            )
          else if (profiles.valueOrNull != null)
            Text(
              'Up to $maxProfiles learners per device.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _buildForm(AppLocalizations l10n, {required bool isInOnboarding}) {
    final colors = AppColors.of(context);
    final mutation = ref.watch(profileControllerProvider);
    final isOnboarding =
        !ref.watch(appSettingsProvider.select((s) => s.onboardingComplete));
    final ageSuggestion = _suggestAgeLevel();

    return KidScaffold(
      title: _isEditing ? l10n.profileCreateTitle : l10n.profileWhosLearning,
      showBack: !isOnboarding || _isEditing,
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isOnboarding && !_isEditing)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  'Add another reader to this tablet.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.inkMuted,
                      ),
                ),
              ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.profileName,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppTextField(
                    label: l10n.profileNameHint,
                    controller: _name,
                    autofocus: !_isEditing,
                    textInputAction: TextInputAction.done,
                    maxLength: 20,
                    onSubmitted: (_) => _save(),
                    validator: (value) => (value ?? '').trim().length < 2
                        ? l10n.profileNameError
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.profileAge,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AgeStepper(
                    ageMonths: _ageMonths,
                    onChanged: (months) => setState(() {
                      _ageMonths = months;
                      if (!_dirty) _level = _suggestAgeLevel();
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.profileAvatar,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AvatarPicker(
                    selectedId: _avatarId,
                    onSelected: (id) => setState(() => _avatarId = id),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.profileLevel,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      // Flexible + ellipsis: this row is the classic overflow
                      // at 360dp with the OS text size turned up.
                      Flexible(
                        child: Text(
                          'Quick check-up',
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Switch(
                        value: _takeTest,
                        onChanged: (value) => setState(() => _takeTest = value),
                      ),
                    ],
                  ),
                  if (!_takeTest) ...[
                    const SizedBox(height: AppSpacing.sm),
                    LevelPicker(
                      selected: _level,
                      suggested: ageSuggestion,
                      onSelected: (level) => setState(() {
                        _level = level;
                        _dirty = true;
                      }),
                    ),
                  ] else
                    Text(
                      'Five short cards. Aria listens and picks the right '
                      'starting point — you can change it later.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Language at home',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final code in InstructionLanguage.codes.take(5))
                        ChoiceChip(
                          label: Text(InstructionLanguage.names[code]!),
                          selected: _homeLanguage == code,
                          onSelected: (_) => setState(() => _homeLanguage = code),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (mutation.failure case final failure?) ...[
              const SizedBox(height: AppSpacing.md),
              ErrorView(failure: failure),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: _isEditing
                  ? l10n.actionSave
                  : (isOnboarding ? l10n.actionContinue : l10n.actionDone),
              isExpanded: true,
              isLoading: mutation.isBusy,
              onPressed: mutation.isBusy ? null : _save,
            ),
            if (isOnboarding)
              Center(
                child: TextButton(
                  onPressed: _skipOnboarding,
                  child: const Text('Skip for now'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _skipOnboarding() async {
    await ref.read(appSettingsProvider.notifier).completeOnboarding();
    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  /// Age is a decent prior for a starting band; the check-up overrides it.
  ReadingLevel _suggestAgeLevel() {
    if (_ageMonths < 42) return ReadingLevel.preReader;
    if (_ageMonths < 54) return ReadingLevel.letterSounds;
    if (_ageMonths < 66) return ReadingLevel.cvcBlender;
    if (_ageMonths < 78) return ReadingLevel.earlyDecoder;
    return ReadingLevel.fluentReader;
  }

  Future<void> _showProfileMenu(LearnerProfile profile) async {
    final l10n = AppLocalizations.of(context);
    final action = await showModalBottomSheet<_ProfileAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text('${l10n.actionEdit} ${profile.displayName}'),
              onTap: () => Navigator.of(context).pop(_ProfileAction.edit),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: AppColors.of(context).error,
              ),
              title: Text('${l10n.actionDelete} ${profile.displayName}'),
              onTap: () => Navigator.of(context).pop(_ProfileAction.delete),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (action == _ProfileAction.edit) {
      if (!mounted) return;
      unawaited(context.push('${AppRoutes.profileEditor}/${profile.id}'));
      return;
    }
    {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove learner'),
            content: Text(
              l10n.profileDeleteConfirm(profile.displayName),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.actionCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.actionDelete),
              ),
            ],
          ),
        );
      if (!(confirmed ?? false)) return;
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      await ref.read(profileControllerProvider.notifier).delete(profile.id);
      messenger.showSnackBar(SnackBar(content: Text(l10n.profileDeleted)));
    }
  }
}

enum _ProfileAction { edit, delete }
