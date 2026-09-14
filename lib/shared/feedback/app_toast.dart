import 'package:flutter/material.dart';

/// Non-blocking confirmation used after saves/purchases/unlocks. Kept as one
/// helper so snackbars never get styled ad-hoc.
abstract final class AppToast {
  static void show(
    BuildContext context,
    String message, {
    IconData? icon,
    bool isError = false,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final scheme = Theme.of(context).colorScheme;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: Duration(seconds: isError ? 5 : 3),
          content: Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 18,
                  color: isError ? scheme.onError : scheme.secondary,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }
}
