import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';

/// The scaffold every child-facing screen is built on:
/// rounded canvas, safe top padding, optional soft header gradient, a
/// scrollable column that never overflows, and content width clamped for
/// tablet/desktop.
class KidScaffold extends StatelessWidget {
  const KidScaffold({
    required this.body,
    this.title,
    this.titleWidget,
    this.leading,
    this.actions = const [],
    this.floatingActionButton,
    this.background,
    this.headerGradient,
    this.showBack = true,
    this.bottomBar,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.screenSidePadding,
      AppSpacing.sm,
      AppSpacing.screenSidePadding,
      AppSpacing.xxxl,
    ),
    this.onRefresh,
    this.extendBodyBehindHeader = false,
    this.scrollable = true,
    super.key,
  });

  final Widget body;
  final String? title;
  final Widget? titleWidget;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? floatingActionButton;
  final Color? background;
  final Gradient? headerGradient;
  final bool showBack;
  final Widget? bottomBar;
  final EdgeInsetsGeometry padding;
  final Future<void> Function()? onRefresh;
  final bool extendBodyBehindHeader;

  /// True for screens that are a tall list of cards; false for screens that
  /// own their scroll (a body with `Expanded`, e.g. the lesson stages).
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final canPop = Navigator.of(context).canPop();
    final appBar = AppBar(
      leading: showBack && canPop
          ? (leading ??
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: MaterialLocalizations.of(context)
                      .backButtonTooltip,
                ))
          : leading,
      title: titleWidget ??
          (title == null
              ? null
              : Text(title!, maxLines: 2, overflow: TextOverflow.ellipsis)),
      actions: actions,
    );

    final Widget padded = Padding(
      padding: padding,
      child: SafeArea(top: false, child: body),
    );

    Widget content;
    if (!scrollable) {
      content = padded;
    } else {
      Widget scroller = LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          // Content is at least viewport-tall, so a screen can use Spacer()
          // for a footer *and* scroll when it has more to say. Derived from the
          // incoming constraints — never a hard-coded screen height.
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: padded,
          ),
        ),
      );
      if (onRefresh != null) {
        scroller = RefreshIndicator(
          onRefresh: onRefresh!,
          color: colors.brand,
          child: scroller,
        );
      }
      content = scroller;
    }

    return Scaffold(
      backgroundColor: background ?? colors.canvas,
      extendBodyBehindAppBar: extendBodyBehindHeader,
      resizeToAvoidBottomInset: true,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomBar,
      body: headerGradient == null
          ? content
          : DecoratedBox(
              decoration: BoxDecoration(
                gradient: headerGradient,
              ),
              position: DecorationPosition.background,
              child: content,
            ),
    );
  }
}

/// A column that scrolls when it cannot fit — used inside responsive rows where
/// a `Column` would otherwise overflow on short windows.
class ScrollableColumn extends StatelessWidget {
  const ScrollableColumn({
    required this.child,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: padding,
        physics: const ClampingScrollPhysics(),
        child: child,
      );
}
