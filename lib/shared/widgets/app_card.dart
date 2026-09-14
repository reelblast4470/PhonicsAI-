import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';

/// Base content card. Never use a raw `Card` in this app.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.onLongPress,
    this.borderColor,
    this.color,
    this.gradient,
    this.radius = 24,
    this.semanticsLabel,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? borderColor;
  final Color? color;
  final Gradient? gradient;
  final double radius;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    final Widget card = DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? colors.surface) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? colors.inkMuted.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      // The transparent Material sits *between* the card's coloured
      // DecoratedBox and its content, so ListTiles inside the card paint ink
      // on it instead of on the Scaffold's Material — otherwise the card's
      // background hides splashes (and Flutter asserts about it in tests).
      child: Material(
        type: MaterialType.transparency,
        child: Padding(padding: padding, child: child),
      ),
    );

    if (onTap == null) {
      if (semanticsLabel == null) return card;
      return MergeSemantics(child: Semantics(label: semanticsLabel, child: card));
    }
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
        color: Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: card,
        ),
      ),
    );
  }
}

/// Card that lifts slightly while pressed — the "physical" feel the Stitch
/// prototypes use for lesson/game tiles.
class PressableCard extends StatefulWidget {
  const PressableCard({
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.radius = 24,
    this.color,
    this.borderColor,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Color? borderColor;
  final String? semanticLabel;

  @override
  State<PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<PressableCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _down ? 0.97 : 1,
      duration: AppMotion.fast,
      curve: AppMotion.curve,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => setState(() => _down = true),
        onPointerUp: (_) => setState(() => _down = false),
        onPointerCancel: (_) => setState(() => _down = false),
        child: AppCard(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          padding: widget.padding,
          radius: widget.radius,
          color: widget.color,
          borderColor: widget.borderColor,
          semanticsLabel: widget.semanticLabel,
          child: widget.child,
        ),
      ),
    );
  }
}
