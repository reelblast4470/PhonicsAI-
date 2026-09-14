import '../../../app/router/app_routes.dart';

/// The onboarding path, as data.
///
/// No controller on purpose: the URL is the single source of truth, so a deep
/// link, a hot restart or "back" all agree on the step. The frame derives the
/// progress dots from it, and screens advance with `context.go(step.nextRoute)`.
enum OnboardingStep {
  language(route: AppRoutes.onboardingLanguage),
  account(route: AppRoutes.onboardingAuth),
  profiles(route: AppRoutes.onboardingProfiles),
  assessment(route: AppRoutes.onboardingAssessment);

  const OnboardingStep({required this.route});

  final String route;

  bool get isFirst => this == OnboardingStep.language;

  OnboardingStep get next =>
      index == values.length - 1 ? this : values[index + 1];

  OnboardingStep get previous => index == 0 ? this : values[index - 1];

  String get nextRoute => next.route;
  String get previousRoute => previous.route;

  static OnboardingStep fromPath(String path) => values.firstWhere(
    (step) => step.route == path,
    orElse: () => OnboardingStep.language,
  );
}
