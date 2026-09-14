import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/state/app_settings_controller.dart';
import '../../../core/domain/reading_level.dart';
import '../../audio/tts_bridge.dart';
import '../../profile/application/profile_providers.dart';
import '../domain/assessment_content.dart';
import '../domain/assessment_scoring.dart';

enum AssessmentPhase { intro, questions, result }

class AssessmentState {
  const AssessmentState({
    required this.phase,
    required this.index,
    required this.answers,
    this.outcome,
    this.isRevealing = false,
    this.isPlayingPrompt = false,
  });

  final AssessmentPhase phase;
  final int index;

  /// One slot per question; null means "not answered yet".
  final List<int?> answers;
  final AssessmentOutcome? outcome;

  /// True between tapping an answer and the Next affordance appearing — the
  /// child gets to see their choice marked before it moves on.
  final bool isRevealing;
  final bool isPlayingPrompt;

  AssessmentQuestion get question => AssessmentContent.questions[index];
  int get total => AssessmentContent.questions.length;
  bool get isOnLastQuestion => index == total - 1;

  AssessmentState copyWith({
    AssessmentPhase? phase,
    int? index,
    List<int?>? answers,
    AssessmentOutcome? outcome,
    bool? isRevealing,
    bool? isPlayingPrompt,
  }) {
    return AssessmentState(
      phase: phase ?? this.phase,
      index: index ?? this.index,
      answers: answers ?? this.answers,
      outcome: outcome ?? this.outcome,
      isRevealing: isRevealing ?? this.isRevealing,
      isPlayingPrompt: isPlayingPrompt ?? this.isPlayingPrompt,
    );
  }
}

class AssessmentController extends Notifier<AssessmentState> {
  AssessmentController({this.simulateFeedbackDelay = true});

  /// Tests flip this off; production keeps the short pause that lets a child
  /// see the tick appear.
  final bool simulateFeedbackDelay;

  static const feedbackPause = Duration(milliseconds: 650);

  @override
  AssessmentState build() => AssessmentState(
    phase: AssessmentPhase.intro,
    index: 0,
    answers: List<int?>.filled(AssessmentContent.questions.length, null),
  );

  void begin() => state = state.copyWith(phase: AssessmentPhase.questions);

  Future<void> playPrompt() async {
    await ref.read(ttsBridgeProvider).say(state.question.spokenPrompt);
  }

  Future<void> answer(int optionIndex) async {
    if (state.isRevealing) return;
    final answers = [...state.answers];
    answers[state.index] = optionIndex;
    state = state.copyWith(answers: answers, isRevealing: true);

    final isCorrect = optionIndex == state.question.correctIndex;
    await ref.read(ttsBridgeProvider).cue(isCorrect);

    if (simulateFeedbackDelay) {
      await Future<void>.delayed(feedbackPause);
    }
    if (!state.isRevealing) return; // superseded by a newer tap
    state = state.copyWith(isRevealing: false);
  }

  Future<void> next() async {
    if (state.isOnLastQuestion) {
      await finish();
      return;
    }
    state = state.copyWith(index: state.index + 1);
  }

  Future<void> skipAll() async {
    // "Skip" keeps the age-based suggestion the profile step already set.
    state = state.copyWith(phase: AssessmentPhase.result, outcome: null);
  }

  Future<void> finish() async {
    final outcome = const AssessmentScoring().evaluate(state.answers);
    state = state.copyWith(
      phase: AssessmentPhase.result,
      outcome: outcome,
    );
    await _applyLevel(outcome.level);
  }

  Future<void> _applyLevel(ReadingLevel level) async {
    final active = ref.read(activeProfileProvider);
    if (active == null) return;
    await ref
        .read(profileControllerProvider.notifier)
        .update(active.copyWith(level: level, isAssessmentComplete: true));
  }

  /// Called by the result screen: onboarding is over, learning starts now.
  Future<void> completeOnboarding() =>
      ref.read(appSettingsProvider.notifier).completeOnboarding();

  /// Re-runs the whole check-up (parent override / fresh start).
  void retake() {
    state = AssessmentState(
      phase: AssessmentPhase.questions,
      index: 0,
      answers: List<int?>.filled(
        AssessmentContent.questions.length,
        null,
      ),
    );
  }
}

final assessmentProvider =
    NotifierProvider<AssessmentController, AssessmentState>(
  AssessmentController.new,
);
