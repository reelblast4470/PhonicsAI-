import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di/infrastructure.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/feedback/app_toast.dart';
import '../../../shared/l10n_context.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/kid_scaffold.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../../audio/tts_bridge.dart';
import '../application/tutor_controller.dart';
import '../domain/tutor_models.dart';

/// Aria, the AI tutor.
///
/// Kid-first: the microphone is the primary input, big picture-chips are the
/// secondary one, and the keyboard is for a grown-up reading over a shoulder.
/// The body is one scrollable list (header → messages → note) rather than a
/// flex column, so it cannot overflow on a short landscape phone.
class TutorScreen extends ConsumerStatefulWidget {
  const TutorScreen({super.key});

  @override
  ConsumerState<TutorScreen> createState() => _TutorScreenState();
}

class _TutorScreenState extends ConsumerState<TutorScreen> {
  final _input = TextEditingController();
  bool _isListening = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send(String text) {
    if (text.trim().isEmpty) return;
    _input.clear();
    unawaited(ref.read(tutorProvider.notifier).send(text));
  }

  Future<void> _listen() async {
    if (_isListening) return;
    final speech = ref.read(speechServiceProvider);
    if (!speech.isAvailable) {
      if (mounted) {
        AppToast.show(context, AppLocalizations.of(context).tutorMicDenied,
            isError: true);
      }
      return;
    }
    setState(() => _isListening = true);
    try {
      final result = await speech.listenOnce();
      if (!result.isEmpty && mounted) _send(result.transcript);
    } finally {
      if (mounted) setState(() => _isListening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final thread = ref.watch(tutorProvider);

    return KidScaffold(
      // The body owns its own scrolling (a chat list), so the scaffold must not
      // wrap it in a second scroll view.
      scrollable: false,
      title: l10n.tutorTitle,
      actions: [
        IconButton(
          onPressed: () => ref.read(tutorProvider.notifier).clearThread(),
          icon: const Icon(Icons.delete_sweep_rounded),
          tooltip: 'Clear chat',
        ),
      ],
      bottomBar: _TutorInputBar(
        controller: _input,
        isListening: _isListening,
        onSend: _send,
        onMic: _listen,
      ),
      body: ListView(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: colors.brand.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Text('🦉', style: TextStyle(fontSize: 26)),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    l10n.tutorHint,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (thread.isEmpty)
            _Starters(
              onPick: _send,
              onSay: () => unawaited(
                ref
                    .read(ttsBridgeProvider)
                    .say('Hi! I am Aria. What sound shall we chase today?'),
              ),
            )
          else
            for (final message in thread.messages)
              _Bubble(
                message: message,
                onChip: _send,
                onAction: () => _runAction(message.action),
                onSpeak: () =>
                    unawaited(ref.read(ttsBridgeProvider).say(message.text)),
              ),
          if (thread.isThinking) const _ThinkingBubble(),
          if (thread.error case final error?)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: AppCard(
                color: colors.error.withValues(alpha: 0.08),
                borderColor: colors.error.withValues(alpha: 0.3),
                child: Row(
                  children: [
                    Icon(
                      Icons.wifi_tethering_off_rounded,
                      color: colors.error,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        error,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          ref.read(tutorProvider.notifier).clearError(),
                      child: Text(l10n.actionClose),
                    ),
                  ],
                ),
              ),
            ),
          if (thread.messages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                l10n.tutorSafetyNote,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }

  void _runAction(TutorAction? action) {
    if (action == null) return;
    switch (action.kind) {
      case TutorActionKind.openLesson:
        context.go('/learn');
      case TutorActionKind.openGame:
        context.go(
          action.target.isEmpty ? '/games' : '/game/${action.target}',
        );
      case TutorActionKind.openReading:
        context.go('/learn');
      case TutorActionKind.openPronunciation:
        context.go('/practice/pronunciation/${action.target}');
      case TutorActionKind.say:
        unawaited(ref.read(ttsBridgeProvider).say(action.target));
      case TutorActionKind.none:
        break;
    }
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.onChip,
    required this.onAction,
    required this.onSpeak,
  });

  final TutorMessage message;
  final ValueChanged<String> onChip;
  final VoidCallback onAction;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isLearner = message.role == TutorRole.learner;
    final bubbleMaxWidth = MediaQuery.sizeOf(context).width * 0.86;

    return Align(
      alignment: isLearner
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm, top: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: isLearner
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: isLearner ? colors.brand : colors.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(22),
                    topRight: const Radius.circular(22),
                    bottomLeft: Radius.circular(isLearner ? 22 : 6),
                    bottomRight: Radius.circular(isLearner ? 6 : 22),
                  ),
                  border: isLearner
                      ? null
                      : Border.all(
                          color: colors.inkMuted.withValues(alpha: 0.15),
                        ),
                ),
                child: Text(
                  message.text + (message.isStreaming ? ' ▌' : ''),
                  style: TextStyle(
                    fontSize: 17,
                    height: 1.4,
                    fontWeight: isLearner ? FontWeight.w600 : FontWeight.w500,
                    color: isLearner ? colors.onBrand : colors.ink,
                  ),
                ),
              ),
              if (!isLearner && message.text.isNotEmpty)
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      onPressed: onSpeak,
                      icon: const Icon(Icons.volume_up_rounded, size: 20),
                      tooltip: 'Hear it',
                      visualDensity: VisualDensity.compact,
                    ),
                    for (final chip in message.chips)
                      ActionChip(
                        label: Text(chip),
                        onPressed: () => onChip(chip),
                      ),
                    if (message.action?.label case final label?)
                      FilledButton.tonalIcon(
                        onPressed: onAction,
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: Text(label),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          const Text('🦉', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          // Flexible (loose) so the bubble is capped at the space the outer
          // Row has left after the emoji; without it the inner min-Row is
          // measured against the Row's *full* width and overflows.
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: AppColors.of(context).surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      l10n.tutorThinking,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Starters extends StatelessWidget {
  const _Starters({required this.onPick, required this.onSay});

  final ValueChanged<String> onPick;
  final VoidCallback onSay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final starters = [
      l10n.tutorSuggestionStuck,
      l10n.tutorSuggestionRead,
      l10n.tutorSuggestionWords,
      'Play a game with me',
      'Give me a rhyme',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),
        const Center(
          child: Text('👋', style: TextStyle(fontSize: 52)),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Ask me about sounds and words',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final starter in starters)
              ActionChip(
                avatar: const Icon(Icons.help_outline_rounded, size: 18),
                label: Text(starter),
                onPressed: () => onPick(starter),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: TextButton.icon(
            onPressed: onSay,
            icon: const Icon(Icons.record_voice_over_outlined),
            label: Text(l10n.tutorVoiceOnly),
          ),
        ),
      ],
    );
  }
}

class _TutorInputBar extends StatelessWidget {
  const _TutorInputBar({
    required this.controller,
    required this.isListening,
    required this.onSend,
    required this.onMic,
  });

  final TextEditingController controller;
  final bool isListening;
  final ValueChanged<String> onSend;
  final VoidCallback onMic;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Row(
          children: [
            SizedBox(
              height: AppSizes.kidTapTarget,
              width: AppSizes.kidTapTarget,
              child: FilledButton(
                onPressed: onMic,
                style: FilledButton.styleFrom(
                  backgroundColor: isListening ? colors.coral : colors.brand,
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                ),
                child: Icon(
                  isListening ? Icons.stop_rounded : Icons.mic_rounded,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.send,
                onSubmitted: onSend,
                decoration: InputDecoration(
                  hintText: l10n.tutorInputPlaceholder,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filled(
              onPressed: () => onSend(controller.text),
              icon: const Icon(Icons.arrow_upward_rounded),
              tooltip: 'Send',
            ),
          ],
        ),
      ),
    );
  }
}
