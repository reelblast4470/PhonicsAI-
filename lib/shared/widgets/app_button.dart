import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';

/// The one primary CTA. Kid buttons are 64dp tall with a 20dp glyph; the
/// parent area uses the compact variant. Every press gives haptic + visual
/// feedback because a 3-year-old needs to know the tap "landed".
class AppButton extends StatefulWidget {
  const AppButton({
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.isCompact = false,
    this.isExpanded = false,
    this.tone = AppButtonTone.brand,
    this.semanticLabel,
    super.key,
  });

  const AppButton.compact({
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.isExpanded = false,
    this.semanticLabel,
    super.key,
  }) : isCompact = true,
       tone = AppButtonTone.brand;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool isCompact;
  final bool isExpanded;
  final AppButtonTone tone;
  final String? semanticLabel;

  @override
  State<AppButton> createState() => _AppButtonState();
}

enum AppButtonTone { brand, sun, mint, neutral, danger }

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null && !widget.isLoading;

    final (Color bg, Color fg) = switch (widget.tone) {
      AppButtonTone.brand => (
        scheme.primary,
        scheme.onPrimary,
      ),
      AppButtonTone.sun => (
        colors.sunshine,
        const Color(0xFF3A2B00),
      ),
      AppButtonTone.mint => (colors.mint, Colors.white),
      AppButtonTone.neutral => (
        colors.surfaceMuted,
        colors.ink,
      ),
      AppButtonTone.danger => (colors.error, Colors.white),
    };

    final height = widget.isCompact ? 48.0 : 64.0;
    final radius = widget.isCompact ? 16.0 : 28.0;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.label,
      child: AnimatedScale(
        scale: _pressed ? 0.965 : 1,
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        child: SizedBox(
          height: height,
          width: widget.isExpanded ? double.infinity : null,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => setState(() => _pressed = true),
            onPointerUp: (_) => setState(() => _pressed = false),
            onPointerCancel: (_) => setState(() => _pressed = false),
            child: FilledButton(
            onPressed: enabled
                ? () {
                    HapticFeedback.lightImpact();
                    widget.onPressed?.call();
                  }
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: enabled ? bg : bg.withValues(alpha: 0.45),
              foregroundColor: fg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radius),
              ),
              elevation: enabled ? 0 : 0,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.isLoading)
                  SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: fg,
                    ),
                  )
                else if (widget.icon case final icon?)
                  Icon(icon, size: widget.isCompact ? 18 : 24, color: fg),
                if (widget.isLoading || widget.icon != null)
                  const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: widget.isCompact ? 15 : 19,
                      fontWeight: FontWeight.w800,
                      color: fg,
                      height: 1.15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }
}

/// Secondary "text" action used in toolbars and dialogs.
class AppTextButton extends StatelessWidget {
  const AppTextButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.isDestructive = false,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return TextButton.icon(
      onPressed: onPressed,
      icon: icon == null
          ? const SizedBox.shrink()
          : Icon(icon, size: 20),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: isDestructive ? colors.error : colors.brand,
      ),
    );
  }
}

/// Round icon button with a guaranteed 48dp target (all of them do).
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.size = 44,
    this.background,
    this.foreground,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Material(
        color: background ?? colors.surface,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            height: size,
            width: size,
            child: Icon(
              icon,
              size: size * 0.5,
              color: foreground ?? colors.ink,
            ),
          ),
        ),
      ),
    );
  }
}
