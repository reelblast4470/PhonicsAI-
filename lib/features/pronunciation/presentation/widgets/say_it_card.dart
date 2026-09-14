import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/infrastructure.dart';
import '../../../../core/speech/speech_service.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_dimens.dart';
import '../../../audio/tts_bridge.dart';

/// "Say it" — the one interaction every PhonicsAI stage can borrow.
///
/// It owns the whole loop (permission → listen → transcribe → score → coach) so
/// the lesson player, the tutor and the standalone practice screen all show the
/// same behaviour. Scoring is on-device by default; no audio is stored.
class SayItCard extends ConsumerStatefulWidget {
  const SayItCard({
    required this.targetWord,
    this.compact = false,
    this.onScored,
    super.key,
  });

  final String targetWord;
  final bool compact;
  final void Function(PronunciationScore score)? onScored;

  @override
  ConsumerState<SayItCard> createState() => SayItCardState();
}

@visibleForTesting
class SayItCardState extends ConsumerState<SayItCard> {
  SayItPhase _phase = SayItPhase.ready;
  double _level = 0;
  PronunciationScore? _score;
  SpeechRecognition? _recognition;
  Timer? _meter;

  SayItPhase get phase => _phase;
  PronunciationScore? get score => _score;

  @override
  void dispose() {
    _meter?.cancel();
    super.dispose();
  }

  Future<void> start() async {
    final speech = ref.read(speechServiceProvider);
    if (!speech.isAvailable) {
      setState(() => _phase = SayItPhase.unavailable);
      return;
    }
    if (await speech.requestPermission() != SpeechPermission.granted) {
      if (!mounted) return;
      setState(() => _phase = SayItPhase.needPermission);
      return;
    }
    if (!mounted) return;
    setState(() {
      _phase = SayItPhase.listening;
      _level = 0.15;
      _score = null;
    });
    // A child needs to see that the app is hearing them.
    _meter = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (mounted) setState(() => _level = 0.2 + math.Random().nextDouble() * 0.7);
    });
    try {
      final recognition = await speech.listenOnce(
        contextWords: [widget.targetWord],
        onLevel: (value) {
          if (mounted) setState(() => _level = value);
        },
      );
      if (!mounted) return;
      _recognition = recognition;
      final score = const LexicalPronunciationScorer().score(
        expected: widget.targetWord,
        recognition: recognition,
      );
      setState(() {
        _score = score;
        _phase = score.overall >= 0.5 ? SayItPhase.done : SayItPhase.retry;
      });
      unawaited(ref.read(ttsBridgeProvider).cue(score.overall >= 0.75));
      widget.onScored?.call(score);
    } catch (_) {
      if (mounted) setState(() => _phase = SayItPhase.unavailable);
    } finally {
      _meter?.cancel();
    }
  }

  void reset() => setState(() {
        _phase = SayItPhase.ready;
        _score = null;
        _recognition = null;
      });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final score = _score;

    return AppCard(
      padding: EdgeInsets.all(widget.compact ? AppSpacing.md : AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => ref.read(ttsBridgeProvider).say(widget.targetWord),
                icon: const Icon(Icons.play_circle_fill_rounded, size: 34),
                tooltip: 'Hear it first',
                color: colors.brand,
              ),
              Expanded(
                child: Text(
                  widget.targetWord,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AnimatedSwitcher(
            duration: AppMotion.normal,
            child: switch (_phase) {
              SayItPhase.ready => _MicButton(
                  key: const ValueKey('ready'),
                  label: l10n.pronunciationTapMic,
                  level: 0,
                  onTap: start,
                ),
              SayItPhase.listening => _MicButton(
                  key: const ValueKey('listening'),
                  label: l10n.tutorListening,
                  level: _level,
                  isLive: true,
                  onTap: () async {
                    await ref.read(speechServiceProvider).cancel();
                    reset();
                  },
                ),
              SayItPhase.done || SayItPhase.retry => _Scored(
                  key: const ValueKey('score'),
                  score: score,
                  heard: _recognition?.transcript,
                  onRetry: reset,
                ),
              SayItPhase.needPermission => _Notice(
                  key: const ValueKey('permission'),
                  icon: Icons.mic_off_rounded,
                  message: l10n.tutorMicDenied,
                  actionLabel: l10n.actionRetry,
                  onAction: start,
                ),
              SayItPhase.unavailable => _Notice(
                  key: const ValueKey('unavailable'),
                  icon: Icons.mic_off_rounded,
                  message: l10n.pronunciationMicNeeded,
                  actionLabel: l10n.actionTryAgain,
                  onAction: start,
                ),
            },
          ),
        ],
      ),
    );
  }

  static String feedbackCopy(PronunciationScore? score, AppLocalizations l10n) {
    if (score == null) return l10n.pronunciationNoSpeech;
    return switch (score.feedbackKey) {
      'feedback.silence' => l10n.pronunciationNoSpeech,
      'feedback.try_again' => 'Try again — make the sound longer and clearer.',
      'feedback.getting_there' => 'Getting there! Say each sound, then say them fast.',
      'feedback.nice' => 'Nice! Now say it in your story voice.',
      _ => 'Great job — that was clear!',
    };
  }
}

enum SayItPhase { ready, listening, done, retry, needPermission, unavailable }

class _Scored extends StatelessWidget {
  const _Scored({
    required this.score,
    required this.heard,
    required this.onRetry,
    super.key,
  });

  final PronunciationScore? score;
  final String? heard;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final value = score?.overall ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScoreBar(
          label: l10n.pronunciationScore((value * 100).round()),
          value: value,
          color: value >= 0.75 ? colors.success : colors.warning,
        ),
        ScoreBar(label: 'Clear sounds', value: score?.accuracy ?? 0, color: colors.mint),
        ScoreBar(label: 'Smooth pace', value: score?.fluency ?? 0, color: colors.sky),
        const SizedBox(height: AppSpacing.md),
        Text(
          SayItCardState.feedbackCopy(score, l10n),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: value >= 0.75 ? colors.success : colors.ink,
              ),
        ),
        if ((heard ?? '').isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${l10n.pronunciationHeard}: "$heard"',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.mic_rounded),
          label: Text(l10n.actionTryAgain),
        ),
      ],
    );
  }
}

class ScoreBar extends StatelessWidget {
  const ScoreBar({
    required this.label,
    required this.value,
    required this.color,
    super.key,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: value.clamp(0, 1)),
                duration: AppMotion.slow,
                builder: (context, animated, _) => LinearProgressIndicator(
                  value: animated,
                  minHeight: 10,
                  backgroundColor: color.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 36,
            child: Text(
              '${(value * 100).round()}%',
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.label,
    required this.level,
    required this.onTap,
    this.isLive = false,
    super.key,
  });

  final String label;
  final double level;
  final VoidCallback onTap;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        decoration: BoxDecoration(
          color: isLive
              ? colors.coral.withValues(alpha: 0.12 + level * 0.18)
              : colors.surfaceMuted,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isLive ? colors.coral : colors.inkMuted.withValues(alpha: 0.2),
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              isLive ? Icons.mic_rounded : Icons.mic_none_rounded,
              size: 40,
              color: isLive ? colors.coral : colors.brand,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleSmall),
            if (isLive) ...[
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: level, minHeight: 6),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        children: [
          Icon(icon, size: 34, color: colors.warning),
          const SizedBox(height: AppSpacing.sm),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
