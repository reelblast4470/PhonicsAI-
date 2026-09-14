import 'package:flutter/widgets.dart';

/// Window-size classes used for the whole app. Values follow the Material 3
/// window size classes so phone / foldable / tablet / desktop all get a plan.
enum Breakpoint {
  compact(0, 599),
  medium(600, 839),
  expanded(840, 1199),
  large(1200, 1599),
  extraLarge(1600, 100000);

  const Breakpoint(this.minWidth, this.maxWidth);
  final int minWidth;
  final int maxWidth;

  static Breakpoint of(double width) => values.firstWhere(
    (b) => width >= b.minWidth && width <= b.maxWidth,
    orElse: () => extraLarge,
  );

  bool get isCompact => this == Breakpoint.compact;
  bool get isPhoneOrTabletPortrait => index <= Breakpoint.medium.index;
  bool get showRail => index >= Breakpoint.medium.index;

  /// Widest comfortable text/content column per class (keeps a 27" desktop
  /// window from stretching a 4-year-old's lesson across 2500 pixels).
  double get maxContentWidth => switch (this) {
    Breakpoint.compact => double.infinity,
    Breakpoint.medium => 720,
    Breakpoint.expanded => 860,
    Breakpoint.large => 1040,
    Breakpoint.extraLarge => 1200,
  };

  /// Base scale for hero sizes and picture books.
  double get displayScale => switch (this) {
    Breakpoint.compact => 1.0,
    Breakpoint.medium => 1.15,
    Breakpoint.expanded => 1.25,
    Breakpoint.large => 1.35,
    Breakpoint.extraLarge => 1.45,
  };

  int get gridColumns => switch (this) {
    Breakpoint.compact => 2,
    Breakpoint.medium => 3,
    Breakpoint.expanded => 3,
    Breakpoint.large => 4,
    Breakpoint.extraLarge => 5,
  };
}

extension ResponsiveBuildContext on BuildContext {
  Size get windowSize => MediaQuery.sizeOf(this);
  Breakpoint get breakpoint => Breakpoint.of(windowSize.width);
  double get displayScale => breakpoint.displayScale;
  bool get isCompactLayout => breakpoint.isCompact;
  bool get isDesktopLayout => breakpoint.index >= Breakpoint.expanded.index;
  double get textScale =>
      MediaQuery.textScalerOf(this).clamp(minScaleFactor: 0.85, maxScaleFactor: 1.6).scale(14) / 14;

  /// Children need big targets; the parent area is information-dense and can
  /// use the platform default of 48.
  double get minTouchTarget => 48;
  double get kidTouchTarget => 72;
}

/// Puts [child] in a centred, width-capped column. Use on every screen.
class ContentLimits extends StatelessWidget {
  const ContentLimits({required this.child, this.extraPadding = 0, super.key});

  final Widget child;
  final double extraPadding;

  @override
  Widget build(BuildContext context) {
    final max = context.breakpoint.maxContentWidth + extraPadding;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: max),
        child: child,
      ),
    );
  }
}

/// Value that changes with the breakpoint; avoids `if (isPhone)` ladders.
class ResponsiveValue<T> {
  const ResponsiveValue({required this.compact, T? medium, T? expanded, T? large})
    : medium = medium ?? compact,
      expanded = expanded ?? medium ?? compact,
      large = large ?? expanded ?? medium ?? compact;

  final T compact;
  final T medium;
  final T expanded;
  final T large;

  T resolve(Breakpoint b) => switch (b) {
    Breakpoint.compact => compact,
    Breakpoint.medium => medium,
    Breakpoint.expanded || Breakpoint.large || Breakpoint.extraLarge =>
      large,
  };

  T of(BuildContext context) => resolve(context.breakpoint);
}
