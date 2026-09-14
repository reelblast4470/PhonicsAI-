import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/domain/reading_level.dart';
import '../../../core/responsive/responsive.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/badge_pill.dart';
import '../../../shared/widgets/kid_scaffold.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../../profile/application/profile_providers.dart';
import '../../progress/application/progress_providers.dart';
import '../application/reading_controller.dart';
import '../data/reading_library.dart';
import '../domain/reading_models.dart';
import 'widgets/read_along_card.dart';

/// Reading practice. `passageId` empty (or "library") shows the shelf; a real
/// id opens one book. Deep links from a lesson's Read stage land directly in
/// the matching reader.
class ReadingScreen extends ConsumerWidget {
  const ReadingScreen({required this.passageId, super.key});

  final String passageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final wantsLibrary =
        passageId.isEmpty || passageId == 'library' || passageId == 'reader';
    if (wantsLibrary) {
      return _ShelfScreen(title: l10n.readingTitle);
    }
    final passage = ReadingLibrary.byId(passageId);
    if (passage == null) {
      return KidScaffold(
        title: l10n.readingTitle,
        body: AppCard(
          child: Column(
            children: [
              const Text('📕', style: TextStyle(fontSize: 46)),
              const SizedBox(height: AppSpacing.md),
              Text('That reader is not on this device yet.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.lg),
              TextButton(
                onPressed: () => context.go(AppRoutes.readingPassage('library')),
                child: Text(l10n.readingPassages),
              ),
            ],
          ),
        ),
      );
    }
    return KidScaffold(
      title: passage.title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReadAlongCard(
            passage: passage,
            onAttempt: (attempt) => ref
                .read(readingControllerProvider(passage.id).notifier)
                .recordAttempt(attempt),
          ),
          const SizedBox(height: AppSpacing.lg),
          _AttemptsFor(passageId: passage.id),
        ],
      ),
    );
  }
}

class _ShelfScreen extends ConsumerWidget {
  const _ShelfScreen({required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final profile = ref.watch(activeProfileProvider);
    final snapshot = ref.watch(profileProgressProvider).valueOrNull;
    final passages = ReadingLibrary.all();
    final maxRank = (profile?.level ?? ReadingLevel.letterSounds).rank;
    final isWide = !context.breakpoint.isCompact;

    return KidScaffold(
      title: title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: l10n.readingPassages,
            subtitle: isWide
                ? 'Books that only use sounds already taught — the level filter '
                    'is what makes them decodable.'
                : 'Only sounds already taught.',
          ),
          for (final passage in passages)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _BookCard(
                passage: passage,
                isUnlocked: passage.level.rank <= maxRank,
                finished: snapshot != null &&
                    snapshot
                        .lessons
                        .values
                        .any((lesson) => lesson.isComplete) &&
                    passage.level.rank < maxRank,
                onTap: () =>
                    context.push(AppRoutes.readingPassage(passage.id)),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            color: colors.surfaceMuted,
            child: Row(
              children: [
                const Text('🎧', style: TextStyle(fontSize: 26)),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Tap any word to hear it. Tap it twice if you fix it '
                    'yourself — that counts as a win.',
                    style: Theme.of(context).textTheme.bodySmall,
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

class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.passage,
    required this.isUnlocked,
    required this.finished,
    required this.onTap,
  });

  final DecodablePassage passage;
  final bool isUnlocked;
  final bool finished;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final accent = AppColors.accentFor(passage.id);
    return PressableCard(
      onTap: isUnlocked ? onTap : null,
      radius: 22,
      child: Row(
        children: [
          Container(
            height: 62,
            width: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isUnlocked ? 0.22 : 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              isUnlocked ? passage.emoji : '🔒',
              style: const TextStyle(fontSize: 22),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  passage.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${passage.sentences.length} pages · ${passage.wordCount} words',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final phoneme in passage.targetPhonemes.take(4))
                      BadgePill(label: phoneme, tone: BadgeTone.neutral),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (finished)
            Icon(Icons.check_circle_rounded, color: colors.success, size: 22)
          else if (!isUnlocked)
            Icon(Icons.lock_outline_rounded, color: colors.inkMuted, size: 20),
        ],
      ),
    );
  }
}

class _AttemptsFor extends ConsumerWidget {
  const _AttemptsFor({required this.passageId});

  final String passageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attempts = ref.watch(readingControllerProvider(passageId));
    if (attempts.isEmpty) return const SizedBox.shrink();
    final best = attempts.reduce((a, b) => a.accuracy > b.accuracy ? a : b);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Your reads', leadingIcon: Icons.timeline_rounded),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              BadgePill(
                label: '${attempts.length} attempts',
                tone: BadgeTone.brand,
              ),
              BadgePill(
                label: 'best ${best.wordsPerMinute} wpm',
                tone: BadgeTone.mint,
              ),
              BadgePill(
                label: '${(best.accuracy * 100).round()}% accurate',
                tone: BadgeTone.sun,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
