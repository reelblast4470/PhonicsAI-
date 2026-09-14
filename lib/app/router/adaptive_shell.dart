import 'package:flutter/material.dart';

import '../../core/responsive/responsive.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';

/// A navigation destination description shared by the bottom bar and the rail.
class ShellDestination {
  const ShellDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.route,
    this.badge,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String route;
  final String? badge;
}

/// Adaptive learner/parent shell.
///
/// * phones → bottom [NavigationBar] (thumb-reachable for a child)
/// * tablets / desktop → [NavigationRail] (extended on wide windows), so the
///   same build serves a 5" Android phone and a 27" Windows monitor.
class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({
    required this.destinations,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.child,
    this.isKidMode = true,
    this.header,
    super.key,
  });

  final List<ShellDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  /// Kids get bigger targets and always-visible labels.
  final bool isKidMode;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final breakpoint = context.breakpoint;

    if (!breakpoint.showRail) {
      return Scaffold(
        backgroundColor: colors.canvas,
        body: Column(
          children: [
            ?header,
            Expanded(child: child),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(
              top: BorderSide(color: colors.inkMuted.withValues(alpha: 0.1)),
            ),
          ),
          child: NavigationBar(
            height: isKidMode ? 78 : 68,
            selectedIndex: currentIndex,
            labelBehavior: isKidMode
                ? NavigationDestinationLabelBehavior.alwaysShow
                : NavigationDestinationLabelBehavior.onlyShowSelected,
            onDestinationSelected: onDestinationSelected,
            destinations: [
              for (final destination in destinations)
                NavigationDestination(
                  icon: destination.badge == null
                      ? Icon(destination.icon, size: isKidMode ? 30 : 26)
                      : Badge(
                          label: Text(destination.badge!),
                          backgroundColor: colors.coral,
                          textColor: Colors.white,
                          child: Icon(destination.icon, size: isKidMode ? 30 : 26),
                        ),
                  selectedIcon: Icon(
                    destination.selectedIcon,
                    size: isKidMode ? 30 : 26,
                  ),
                  label: destination.label,
                  tooltip: destination.label,
                ),
            ],
          ),
        ),
        extendBody: true,
      );
    }

    final extended = breakpoint.index >= Breakpoint.large.index;
    return Scaffold(
      backgroundColor: colors.canvas,
      body: Row(
        children: [
          NavigationRail(
            extended: extended,
            minExtendedWidth: 208,
            leading: Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.lg,
                bottom: AppSpacing.md,
              ),
              child: const BrandMark(),
            ),
            trailing: extended
                ? null
                : Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: const SizedBox(height: 4),
                  ),
            selectedIndex: currentIndex,
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            onDestinationSelected: onDestinationSelected,
            destinations: [
              for (final destination in destinations)
                NavigationRailDestination(
                  icon: Icon(destination.icon, size: 26),
                  selectedIcon: Icon(destination.selectedIcon, size: 26),
                  label: Text(destination.label),
                ),
            ],
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: colors.inkMuted.withValues(alpha: 0.14),
          ),
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  ?header,
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small logo used in the rail header and on splash.
class BrandMark extends StatelessWidget {
  const BrandMark({this.size = 40, this.showWordmark = false, super.key});

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final mark = Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.brand, colors.grape],
        ),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      alignment: Alignment.center,
      child: Text(
        'a',
        style: TextStyle(
          color: colors.onBrand,
          fontSize: size * 0.62,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
    if (!showWordmark) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: AppSpacing.sm),
        Text(
          'PhonicsAI',
          style: TextStyle(
            fontSize: size * 0.48,
            fontWeight: FontWeight.w900,
            color: colors.ink,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}
