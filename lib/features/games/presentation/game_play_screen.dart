import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/badge_pill.dart';
import '../../../shared/widgets/confetti_burst.dart';
import '../../../shared/widgets/star_row.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../../audio/tts_bridge.dart';
import '../application/game_controller.dart';
import '../domain/game_models.dart';
import 'widgets/game_boards.dart';

/// One round of one game. Full screen, no nav chrome, big targets, and a
/// summary that celebrates what happened rather than what was missed.
class GamePlayScreen extends ConsumerStatefulWidget {
  const GamePlayScreen({required this.gameId, super.key});

  final String gameId;

  @override
  ConsumerState<GamePlayScreen> createState() => _GamePlayScreenState();
}

class _GamePlayScreenState extends ConsumerState<GamePlayScreen> {
  int _burst = 0;

  GameKind get _kind =>
      GameDefinition.byId(widget.gameId)?.kind ?? GameKind.soundMatch;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(gameProvider(_kind));
    final controller = ref.read(gameProvider(_kind).notifier);

    if (session == null) {
      return Scaffold(
        body: Center(
          child: AppCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('That game is not ready yet.'),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: l10n.actionBack,
                  isCompact: true,
                  onPressed: () => context.pop(),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final current = session.current;
    final chosenId = session.selected.length == 1 ? session.selected.first : null;
    GameChoiceState? feedbackFor(GameChoice choice) {
      if (chosenId == null) return null;
      final isRight = choice.id == current.correctId;
      if (choice.id == chosenId) {
        return isRight ? GameChoiceState.correct : GameChoiceState.wrong;
      }
      return isRight ? GameChoiceState.correct : GameChoiceState.idle;
    }

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: l10n.actionClose,
                      ),
                      Expanded(
                        child: Text(
                          session.definition.title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: controller.togglePause,
                        icon: Icon(session.isPaused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded),
                        tooltip: session.isPaused ? 'Resume' : 'Pause',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      BadgePill(
                        label: '${l10n.gamesScore} ${session.score}',
                        icon: Icons.bolt_rounded,
                        tone: BadgeTone.sun,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      BadgePill(
                        label: '${session.streak} in a row',
                        icon: Icons.local_fire_department_rounded,
                        tone: session.streak >= 2
                            ? BadgeTone.flame
                            : BadgeTone.neutral,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      BadgePill(
                        label: '${session.index + 1}/${session.items.length}',
                        icon: Icons.format_list_numbered_rounded,
                        tone: BadgeTone.brand,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (session.index + 1) / session.items.length,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (session.isPaused)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('⏸️', style: TextStyle(fontSize: 54)),
                            const SizedBox(height: AppSpacing.md),
                            Text('Paused',
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: AppSpacing.lg),
                            AppButton(
                              label: 'Keep playing',
                              icon: Icons.play_arrow_rounded,
                              onPressed: controller.togglePause,
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (session.isOver)
                    Expanded(
                      child: _RoundSummary(
                        session: session,
                        onReplay: () {
                          controller.restart();
                          setState(() => _burst++);
                        },
                      ),
                    )
                  else ...[
                    AppCard(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => ref
                                .read(ttsBridgeProvider)
                                .say(current.prompt),
                            icon: const Icon(Icons.volume_up_rounded, size: 26),
                            tooltip: l10n.actionListen,
                          ),
                          Expanded(
                            child: Text(
                              current.prompt,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Expanded(
                      child: SingleChildScrollView(
                        child: GameBoard(
                          kind: session.definition.kind,
                          choices: current.choices,
                          selected: session.selected,
                          onPick: (id) {
                            controller.toggleChoice(id);
                            final stillRunning = ref
                                .read(gameProvider(_kind));
                            if (stillRunning?.lastGain != null &&
                                stillRunning!.score > session.score) {
                              setState(() => _burst++);
                              unawaitedCelebrate();
                            }
                          },
                          feedbackFor: feedbackFor,
                        ),
                      ),
                    ),
                    if (session.definition.kind == GameKind.spellBuilder)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: Row(
                          children: [
                            Expanded(
                              child: AppButton(
                                label: l10n.actionCheck,
                                tone: AppButtonTone.sun,
                                isExpanded: true,
                                isCompact: true,
                                onPressed: session.selected.isEmpty
                                    ? null
                                    : controller.submitSpelling,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            IconButton(
                              onPressed: () => ref
                                  .read(ttsBridgeProvider)
                                  .say(current.answer.label),
                              icon: const Icon(Icons.volume_up_rounded),
                              tooltip: 'Hear the word',
                            ),
                          ],
                        ),
                      ),
                    if (current.hint case final hint?)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Text(
                          hint,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ],
              ),
            ),
            Positioned.fill(child: ConfettiBurst(trigger: _burst)),
          ],
        ),
      ),
    );
  }

  void unawaitedCelebrate() {
    ref.read(ttsBridgeProvider).celebrate().ignore();
  }
}

class _RoundSummary extends ConsumerWidget {
  const _RoundSummary({required this.session, required this.onReplay});

  final GameSession session;
  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return Center(
      child: SingleChildScrollView(
        child: AppCard(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.sunshine.withValues(alpha: 0.2), colors.surface],
          ),
          child: Column(
            children: [
              Text(
                session.stars >= 3
                    ? 'You are on fire!'
                    : session.stars == 2
                    ? 'Great round!'
                    : 'Nice try — again?',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: AppSpacing.md),
              StarRow(earned: session.stars, size: 40),
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.gamesStarsEarned(session.score),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${session.correctCount} of ${session.items.length} right · '
                '${session.elapsed.inSeconds}s',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: l10n.gamesPlayAgain,
                icon: Icons.refresh_rounded,
                isExpanded: true,
                onPressed: onReplay,
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextButton(
                label: l10n.actionClose,
                onPressed: () => context.pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
