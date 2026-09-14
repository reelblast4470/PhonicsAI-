import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../app/state/app_settings_controller.dart';
import '../../../../theme/app_colors.dart';

/// The learner's buddy, tappable from any tab. Opens the profile switcher.
/// (Full multi-child sheet lands with the profile repository in Phase 2.)
class ProfileAvatarButton extends ConsumerWidget {
  const ProfileAvatarButton({this.size = 40, super.key});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final initial = (settings.activeProfileId ?? '?').characters.first.toUpperCase();
    final colors = AppColors.of(context);
    return Semantics(
      button: true,
      label: 'Switch learner',
      child: Material(
        color: colors.surface,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(
            settings.activeProfileId == null
                ? AppRoutes.profileNew
                : AppRoutes.onboardingProfiles,
          ),
          customBorder: const CircleBorder(),
          child: SizedBox(
            height: size,
            width: size,
            child: Center(
              child: Text(
                initial,
                style: TextStyle(
                  fontSize: size * 0.42,
                  fontWeight: FontWeight.w900,
                  color: colors.brand,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
