import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/badge_pill.dart';
import '../../../shared/widgets/kid_scaffold.dart';
import '../../../shared/widgets/star_row.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../../parent/application/parent_controls_controller.dart';
import '../../progress/application/progress_providers.dart';
import '../application/pronunciation_controller.dart';
import 'widgets/say_it_card.dart';

/// Standalone pronunciation practice: a word, a mic, and a coach that explains
/// the mouth shape instead of just a score.
class PronunciationScreen extends ConsumerWidget {
  const PronunciationScreen({required this.wordId, super.key});

  final String wordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final target = ref.watch(pronunciationTargetProvider(wordId));
    final history = ref.watch(pronunciationControllerProvider(wordId));
    final controls = ref.watch(parentControlsProvider);

    if (target == null) {
      return KidScaffold(
        title: l10n.pronunciationTitle,
        body: AppCard(
          child: Column(
            children: [
              const Text('🤫', style: TextStyle(fontSize: 46)),
              const SizedBox(height: AppSpacing.md),
              Text('No word selected.',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: l10n.navLearn,
                isCompact: true,
                onPressed: () => context.go(AppRoutes.learn),
              ),
            ],
          ),
        ),
      );
    }

    return KidScaffold(
      title: l10n.pronunciationTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [colors.brand.withValues(alpha: 0.1), colors.surface],
            ),
            child: Column(
              children: [
                Text(
                  target.emoji,
                  style: const TextStyle(fontSize: 76),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  target.word,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSpacing.sm,
                  children: [
                    for (final chunk in target.chunks)
                      BadgePill(label: chunk, tone: BadgeTone.brand),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (!controls.allowMicrophone)
            AppCard(
              color: colors.warning.withValues(alpha: 0.1),
              borderColor: colors.warning,
              child: Row(
                children: [
                  Icon(Icons.mic_off_rounded, color: colors.warning),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'A grown-up turned the microphone off. Tap a sound chip '
                      'above to hear it instead.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            )
          else
            SayItCard(
              targetWord: target.word,
              onScored: (score) {
                ref
                    .read(pronunciationControllerProvider(wordId).notifier)
                    .record(target.word, score);
                ref
                    .read(progressRepositoryProvider)
                    .recordSoundReview(
                      profileId: ref.read(activeProfileIdProvider) ?? '',
                      phoneme: target.chunks.first,
                      grade: score.overall >= 0.75 ? 5 : 2,
                    )
                    .ignore();
              },
            ),
          if (history.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const SectionTitleRow(title: 'Today\'s tries'),
            for (final attempt in history.reversed.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: AppCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      StarRow(
                        earned: attempt.stars,
                        size: 18,
                        animate: false,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          '${(attempt.score.overall * 100).round()}% match · '
                          '${attempt.score.feedbackKey.split('.').last}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      Text(
                        '${attempt.at.hour.toString().padLeft(2, '0')}:'
                        '${attempt.at.minute.toString().padLeft(2, '0')}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.md),
          AppCard(
            color: colors.surfaceMuted,
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline_rounded, color: colors.gold),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    target.tip,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SectionTitleRow extends StatelessWidget {
  const SectionTitleRow({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
