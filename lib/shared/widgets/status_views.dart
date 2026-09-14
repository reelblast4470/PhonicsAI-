import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/failure.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import 'app_button.dart';

/// One place that decides what loading / error / empty look like, so every
/// screen in the app behaves the same way.
class LoadingView extends StatelessWidget {
  const LoadingView({this.message, this.compact = false, super.key});

  final String? message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: compact ? 24 : 36,
            width: compact ? 24 : 36,
            child: CircularProgressIndicator(
              strokeWidth: compact ? 2.4 : 3.2,
              color: colors.brand,
            ),
          ),
          if (message case final msg?) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({
    this.failure,
    this.title,
    this.message,
    this.onRetry,
    super.key,
  }) : assert(failure != null || message != null, 'needs a failure or a message');

  final AppFailure? failure;
  final String? title;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final detail = message ?? failure?.message ?? l10n.stateErrorGeneric;
    final headline = title ?? l10n.stateErrorGeneric;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              failure?.kind == FailureKind.offline
                  ? Icons.wifi_off_rounded
                  : Icons.error_outline_rounded,
              size: 42,
              color: colors.warning,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (detail != headline) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: l10n.actionRetry,
                icon: Icons.refresh_rounded,
                onPressed: onRetry,
                isCompact: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    required this.title,
    this.message,
    this.icon = Icons.hourglass_empty_rounded,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String? message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 72,
              width: 72,
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: colors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (message case final msg?) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                msg,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (actionLabel case final label?) ...[
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: label,
                onPressed: onAction,
                isCompact: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Maps an [AsyncValue] to the three states + data. Use instead of ad-hoc
/// `if (state.isLoading)` branches inside a build method.
class AsyncStateView<T> extends StatelessWidget {
  const AsyncStateView({
    required this.value,
    required this.builder,
    this.loadingMessage,
    this.emptyWhen,
    this.emptyTitle,
    this.emptyMessage,
    this.onRetry,
    super.key,
  });

  final AsyncValue<T> value;
  final Widget Function(BuildContext context, T data) builder;
  final String? loadingMessage;
  final bool Function(T data)? emptyWhen;
  final VoidCallback? onRetry;
  final String? emptyTitle;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => LoadingView(message: loadingMessage),
      error: (error, _) => ErrorView(
        failure: error is AppFailure
            ? error
            : AppFailure.unknown('$error'),
        onRetry: onRetry,
      ),
      data: (data) {
        if (emptyWhen?.call(data) ?? false) {
          return EmptyView(
            title: emptyTitle ??
                AppLocalizations.of(context).stateEmptyGeneric,
            message: emptyMessage,
          );
        }
        return builder(context, data);
      },
    );
  }
}
