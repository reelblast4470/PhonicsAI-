import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/profile/presentation/widgets/profile_avatar_button.dart';
import '../../l10n/generated/app_localizations.dart';
import 'adaptive_shell.dart';
import 'app_routes.dart';

/// Learner navigation: Home → Learn → Games → Tutor → Progress.
class LearnerShell extends ConsumerWidget {
  const LearnerShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final destinations = [
      ShellDestination(
        label: l10n.navHome,
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
        route: AppRoutes.home,
      ),
      ShellDestination(
        label: l10n.navLearn,
        icon: Icons.menu_book_outlined,
        selectedIcon: Icons.menu_book_rounded,
        route: AppRoutes.learn,
      ),
      ShellDestination(
        label: l10n.navGames,
        icon: Icons.sports_esports_outlined,
        selectedIcon: Icons.sports_esports_rounded,
        route: AppRoutes.games,
      ),
      ShellDestination(
        label: l10n.navTutor,
        icon: Icons.record_voice_over_outlined,
        selectedIcon: Icons.record_voice_over_rounded,
        route: AppRoutes.tutor,
      ),
      ShellDestination(
        label: l10n.navProgress,
        icon: Icons.insights_outlined,
        selectedIcon: Icons.insights_rounded,
        route: AppRoutes.progress,
      ),
    ];

    return AdaptiveShell(
      destinations: destinations,
      currentIndex: navigationShell.currentIndex,
      isKidMode: true,
      onDestinationSelected: (index) => navigationShell.goBranch(
        index,
        // Tapping the active tab pops back to the top of that branch.
        initialLocation: index == navigationShell.currentIndex,
      ),
      header: const LearnerTopBar(),
      child: navigationShell,
    );
  }
}

/// The one place the child's avatar/streak lives in the chrome, shared by all
/// five learner tabs.
class LearnerTopBar extends StatelessWidget {
  const LearnerTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 4, 16, 0),
        child: const ProfileAvatarButton(),
      ),
    );
  }
}
