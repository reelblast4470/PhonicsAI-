import 'package:flutter/material.dart';

/// Spacing / radius / elevation tokens + the kid sizing rules.
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;

  /// Bottom bar height incl. safe area is handled by the shell; this is the
  /// content clearance so nothing hides under it.
  static const double navBarContentPadding = 104;
  static const double screenSidePadding = 16;
}

abstract final class AppRadius {
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 44;
  static const BorderRadius card = BorderRadius.all(Radius.circular(24));
  static const BorderRadius sheet = BorderRadius.vertical(
    top: Radius.circular(32),
  );
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

abstract final class AppSizes {
  /// WCAG-style minimum, but a 4-year-old needs more than 44px.
  static const double minTapTarget = 48;
  static const double kidTapTarget = 72;
  static const double lessonHeroMinHeight = 190;
  static const double avatar = 56;
  static const double avatarLarge = 96;
  static const double navIcon = 28;
  static const double gameTile = 120;
  static const double phonemeTile = 96;
}

abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
  static const Duration celebrate = Duration(milliseconds: 900);
  static const Curve curve = Curves.easeOutCubic;
  static const Curve bouncy = Curves.easeOutBack;

  /// Honour "reduce motion" system settings — the app stays usable, just calm.
  static bool disabled(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
}
