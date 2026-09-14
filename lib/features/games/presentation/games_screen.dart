import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/badge_pill.dart';
import '../../../shared/widgets/kid_scaffold.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../../profile/application/profile_providers.dart';
import '../../progress/application/progress_providers.dart';
import '../../progress/domain/progress_models.dart';
import '../domain/game_models.dart';

/// Games hub. Every card shows the skill it drills, not just a picture — parents
/// and older learners choose deliberately, children just tap the fun one.
class GamesScreen extends ConsumerWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshot = ref.watch(profileProgressProvider).valueOrNull;
    final profile = ref.watch(activeProfileProvider);

    final available = GameDefinition.catalog
        .where((game) =>
            profile == null || game.minLevel.rank <= profile.level.rank)
        .toList(growable: false);
    final locked = GameDefinition.catalog
        .where((game) =>
            profile != null && game.minLevel.rank > profile.level.rank)
        .toList(growable: false);

    return KidScaffold(
      title: l10n.gamesTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.gamesPickOne,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.of(context).inkMuted,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Natural-height cards in a wrap. A grid with a fixed
          // childAspectRatio overflows as soon as text scale or a localised
          // string is longer than the designer assumed, so cards size
          // themselves and the row wraps instead.
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = constraints.maxWidth < 560
                  ? constraints.maxWidth
                  : (constraints.maxWidth - AppSpacing.md) / 2;
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  for (final game in available)
                    SizedBox(
                      width: cardWidth,
                      child: _GameCard(
                        game: game,
                        record: snapshot?.gameRecords[game.kind.name],
                        onTap: () => context.push(
                          AppRoutes.gameSession(game.kind.name),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (locked.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(title: 'Coming as you grow', leadingIcon: Icons.lock_outline_rounded),
            for (final game in locked)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Opacity(
                  opacity: 0.55,
                  child: AppCard(
                    child: Row(
                      children: [
                        Text(game.emoji, style: const TextStyle(fontSize: 30)),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(game.title,
                                  style: Theme.of(context).textTheme.titleMedium),
                              Text('Unlocks at ${game.minLevel.label}',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                        const Icon(Icons.lock_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.game, required this.record, required this.onTap});

  final GameDefinition game;
  final GameRecord? record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final best = record?.bestScore ?? 0;
    return PressableCard(
      onTap: onTap,
      radius: 26,
      padding: const EdgeInsets.all(AppSpacing.lg),
      semanticLabel: '${game.title}. ${game.blurb}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(game.emoji, style: const TextStyle(fontSize: 34)),
              const Spacer(),
              if (best > 0)
                BadgePill(label: l10n.gamesHighScore(best), tone: BadgeTone.sun),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            game.title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 2),
          const SizedBox(height: 2),
          Text(
            game.blurb,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          BadgePill(
            label: game.skillLabel,
            icon: Icons.psychology_alt_outlined,
            tone: BadgeTone.mint,
          ),
        ],
      ),
    );
  }
}
