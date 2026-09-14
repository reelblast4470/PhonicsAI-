import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/assessment/presentation/assessment_screen.dart';
import '../../features/auth/presentation/auth_screen.dart';
import '../../features/curriculum/presentation/curriculum_screen.dart';
import '../../features/curriculum/presentation/lesson_player_screen.dart';
import '../../features/games/presentation/game_play_screen.dart';
import '../../features/games/presentation/games_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/onboarding/application/onboarding_controller.dart';
import '../../features/onboarding/presentation/onboarding_frame.dart';
import '../../features/onboarding/presentation/onboarding_language_screen.dart';
import '../../features/parent/application/parent_gate_controller.dart';
import '../../features/parent/presentation/child_report_screen.dart';
import '../../features/parent/presentation/parent_dashboard_screen.dart';
import '../../features/parent/presentation/parent_gate_screen.dart';
import '../../features/profile/presentation/profile_setup_screen.dart';
import '../../features/progress/presentation/progress_screen.dart';
import '../../features/pronunciation/presentation/pronunciation_screen.dart';
import '../../features/reading/presentation/reading_screen.dart';
import '../../features/rewards/presentation/rewards_screen.dart';
import '../../features/settings/presentation/help_screen.dart';
import '../../features/settings/presentation/privacy_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/subscription/presentation/subscription_screen.dart';
import '../../features/tutor/presentation/tutor_screen.dart';
import '../../features/writing/presentation/writing_screen.dart';
import '../../theme/app_dimens.dart';
import '../state/app_settings_controller.dart';
import 'app_routes.dart';
import 'learner_shell.dart';
import 'parent_shell.dart';

/// Snapshot of everything a route decision depends on. Watching this one
/// provider (instead of three) is what makes `refreshListenable` cheap.
@immutable
class RouteGuards {
  const RouteGuards({
    required this.onboardingComplete,
    required this.hasActiveProfile,
    required this.parentUnlocked,
  });

  final bool onboardingComplete;
  final bool hasActiveProfile;
  final bool parentUnlocked;

  @override
  bool operator ==(Object other) =>
      other is RouteGuards &&
      other.onboardingComplete == onboardingComplete &&
      other.hasActiveProfile == hasActiveProfile &&
      other.parentUnlocked == parentUnlocked;

  @override
  int get hashCode =>
      Object.hash(onboardingComplete, hasActiveProfile, parentUnlocked);
}

final routeGuardsProvider = Provider<RouteGuards>((ref) {
  final settings = ref.watch(appSettingsProvider);
  final gate = ref.watch(parentGateProvider);
  return RouteGuards(
    onboardingComplete: settings.onboardingComplete,
    hasActiveProfile: settings.activeProfileId != null,
    parentUnlocked: gate.isUnlocked,
  );
});

/// Navigation graph + guards.
///
/// * two shells (learner / parent) that adapt bottom bar ↔ rail by breakpoint
/// * immersive full-screen routes for lessons, games and practice, so the nav
///   chrome never eats a child's tap space
/// * guards: onboarding, "needs a profile", parental gate
final routerProvider = Provider<GoRouter>((ref) {
  final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  final refresh = ValueNotifier<int>(0);
  ref
    ..listen<RouteGuards>(
      routeGuardsProvider,
      (_, _) => refresh.value++,
    )
    ..onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),

      // ------------------------------------------------------------- onboarding
      ShellRoute(
        builder: (context, state, child) => OnboardingFrame(
          step: OnboardingStep.fromPath(state.uri.path),
          child: child,
        ),
        routes: [
          GoRoute(
            path: AppRoutes.onboardingLanguage,
            name: 'onboarding-language',
            builder: (context, state) => const OnboardingLanguageScreen(),
          ),
          GoRoute(
            path: AppRoutes.onboardingAuth,
            name: 'onboarding-auth',
            builder: (context, state) => const AuthScreen(),
          ),
          GoRoute(
            path: AppRoutes.onboardingProfiles,
            name: 'onboarding-profiles',
            builder: (context, state) => const ProfileSetupScreen(),
          ),
          GoRoute(
            path: AppRoutes.onboardingAssessment,
            name: 'onboarding-assessment',
            builder: (context, state) => const AssessmentScreen(),
          ),
        ],
      ),

      // ------------------------------------------------------------- learner
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => LearnerShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                name: 'home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.learn,
                name: 'learn',
                builder: (context, state) => const CurriculumScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.games,
                name: 'games',
                builder: (context, state) => const GamesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.tutor,
                name: 'tutor',
                builder: (context, state) => const TutorScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.progress,
                name: 'progress',
                builder: (context, state) => const ProgressScreen(),
              ),
            ],
          ),
        ],
      ),

      // ------------------------------------------------------------- immersive
      GoRoute(
        path: '${AppRoutes.lesson}/:lessonId',
        name: 'lesson',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => LessonPlayerScreen(
          lessonId: state.pathParameters['lessonId'] ?? '',
        ),
      ),
      GoRoute(
        path: '${AppRoutes.game}/:gameId',
        name: 'game',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => GamePlayScreen(
          gameId: state.pathParameters['gameId'] ?? '',
        ),
      ),
      GoRoute(
        path: '${AppRoutes.pronunciation}/:wordId',
        name: 'pronunciation',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => PronunciationScreen(
          wordId: state.pathParameters['wordId'] ?? '',
        ),
      ),
      GoRoute(
        path: '${AppRoutes.reading}/:passageId',
        name: 'reading',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => ReadingScreen(
          passageId: state.pathParameters['passageId'] ?? '',
        ),
      ),
      GoRoute(
        path: '${AppRoutes.writing}/:targetId',
        name: 'writing',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => WritingScreen(
          targetId: state.pathParameters['targetId'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.rewards,
        name: 'rewards',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const RewardsScreen(),
      ),
      GoRoute(
        path: AppRoutes.profileNew,
        name: 'profile-new',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ProfileSetupScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.profileEditor}/:profileId',
        name: 'profile-edit',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => ProfileSetupScreen(
          profileId: state.pathParameters['profileId'],
        ),
      ),

      // ------------------------------------------------------------- parent
      GoRoute(
        path: AppRoutes.parentUnlock,
        name: 'parent-unlock',
        builder: (context, state) => ParentGateScreen(
          returnTo: state.uri.queryParameters['from'],
        ),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            ParentShell(location: state.uri.toString(), child: child),
        routes: [
          GoRoute(
            path: AppRoutes.parent,
            name: 'parent',
            builder: (context, state) => const ParentDashboardScreen(),
          ),
          GoRoute(
            path: '${AppRoutes.parentChild}/:profileId',
            name: 'parent-child',
            builder: (context, state) => ChildReportScreen(
              profileId: state.pathParameters['profileId'],
            ),
          ),
          GoRoute(
            path: AppRoutes.parentReports,
            name: 'parent-reports',
            builder: (context, state) => const ChildReportScreen(),
          ),
          GoRoute(
            path: AppRoutes.parentSubscription,
            name: 'parent-subscription',
            builder: (context, state) => const SubscriptionScreen(),
          ),
          GoRoute(
            path: AppRoutes.parentSettings,
            name: 'parent-settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.parentHelp,
        name: 'parent-help',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const HelpScreen(),
      ),
      GoRoute(
        path: AppRoutes.parentPrivacy,
        name: 'parent-privacy',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const PrivacyScreen(),
      ),
    ],
    redirect: (context, state) {
      final guards = ref.read(routeGuardsProvider);
      final location = state.matchedLocation;
      final isSplash = location == AppRoutes.splash;
      final isOnboarding =
          location.startsWith(AppRoutes.onboarding) ||
          location == AppRoutes.profileNew;
      final isParentArea = location.startsWith(AppRoutes.parent);

      // The splash screen owns the first decision (it also waits on startup).
      if (isSplash) return null;

      if (!guards.onboardingComplete) {
        if (isOnboarding) return null;
        return guards.hasActiveProfile ? AppRoutes.home : AppRoutes.onboardingProfiles;
      }

      if (isOnboarding) return AppRoutes.home;

      if (!guards.hasActiveProfile && !isParentArea) {
        return AppRoutes.onboardingProfiles;
      }

      if (isParentArea && !guards.parentUnlocked) {
        final from = Uri.encodeComponent(state.uri.toString());
        return '${AppRoutes.parentUnlock}?from=$from';
      }

      return null;
    },
    errorBuilder: (context, state) => _RouteNotFound(location: state.uri.path),
  );
});

class _RouteNotFound extends StatelessWidget {
  const _RouteNotFound({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_off_rounded, size: 42),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'That page is not part of PhonicsAI.\n$location',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: () => context.go(AppRoutes.home),
                child: const Text('Go to home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
