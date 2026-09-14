import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive/responsive.dart';
import '../../features/parent/application/parent_gate_controller.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import 'adaptive_shell.dart';
import 'app_routes.dart';

/// Parent navigation: Dashboard → Child progress → Subscription → Settings.
/// Deliberately denser and quieter than the learner area — adults read numbers,
/// children read pictures.
class ParentShell extends ConsumerStatefulWidget {
  const ParentShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  @override
  ConsumerState<ParentShell> createState() => _ParentShellState();
}

class _ParentShellState extends ConsumerState<ParentShell> {
  /// The gate is a plain (not autoDispose) provider, so the notifier stays
  /// alive after this element is gone — capture it once in initState because
  /// `ref` itself is unusable by dispose() time.
  late final ParentGateController _gate;

  @override
  void initState() {
    super.initState();
    _gate = ref.read(parentGateProvider.notifier);
  }

  /// Leaves the grown-up area locked as soon as the user steps out, so a child
  /// picking the tablet back up never resumes on the paywall.
  @override
  void dispose() {
    _gate.lock();
    super.dispose();
  }

  String get location => widget.location;
  Widget get child => widget.child;

  static const _tabs = <String>[
    AppRoutes.parent,
    AppRoutes.parentChild,
    AppRoutes.parentSubscription,
    AppRoutes.parentSettings,
  ];

  int get _index {
    for (var i = _tabs.length - 1; i >= 0; i--) {
      if (location.startsWith(_tabs[i])) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final l10n = AppLocalizations.of(context);
    final isDesktop = context.breakpoint.showRail;
    final railExtended = context.breakpoint.index >= Breakpoint.large.index;

    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: Text(l10n.parentTitle),
              actions: [
                IconButton(
                  onPressed: () {
                    ref.read(parentGateProvider.notifier).lock();
                    context.go(AppRoutes.home);
                  },
                  icon: const Icon(Icons.child_care_rounded),
                  tooltip: 'Back to kid mode',
                ),
              ],
            ),
      body: Row(
        children: [
          if (isDesktop)
            NavigationRail(
              // `extended` and labelled destinations are mutually exclusive;
              // NavigationRail also gives `leading` unbounded width, so the
              // brand row must size itself, never via flex.
              extended: railExtended,
              leading: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandMark(size: 36),
                    if (railExtended) ...[
                      const SizedBox(width: AppSpacing.sm),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          l10n.parentTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              selectedIndex: _index,
              onDestinationSelected: (index) =>
                  context.go(_tabs[index] == AppRoutes.parentChild
                      ? AppRoutes.parentReports
                      : _tabs[index]),
              labelType:
                  railExtended ? null : NavigationRailLabelType.all,
              destinations: [
                for (final destination in _destinations(l10n))
                  NavigationRailDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: Text(destination.label),
                  ),
              ],
            ),
          Expanded(
            child: Container(
              color: AppColors.of(context).canvas,
              child: child,
            ),
          ),
        ],
      ),
      bottomNavigationBar: isDesktop
          ? null
          : NavigationBar(
              selectedIndex: _index,
              height: 66,
              labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
              onDestinationSelected: (index) => context.go(
                _tabs[index] == AppRoutes.parentChild
                    ? AppRoutes.parentReports
                    : _tabs[index],
              ),
              destinations: [
                for (final destination in _destinations(l10n))
                  NavigationDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: destination.label,
                  ),
              ],
            ),
    );
  }

  List<ShellDestination> _destinations(AppLocalizations l10n) => [
        ShellDestination(
          label: l10n.navParent,
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard_rounded,
          route: AppRoutes.parent,
        ),
        ShellDestination(
          label: 'Progress',
          icon: Icons.person_outline_rounded,
          selectedIcon: Icons.person_rounded,
          route: AppRoutes.parentChild,
        ),
        ShellDestination(
          label: 'Plan',
          icon: Icons.workspace_premium_outlined,
          selectedIcon: Icons.workspace_premium_rounded,
          route: AppRoutes.parentSubscription,
        ),
        ShellDestination(
          label: l10n.settingsTitle,
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings_rounded,
          route: AppRoutes.parentSettings,
        ),
      ];
}
