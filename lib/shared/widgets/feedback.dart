import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// Snackbars and confirmation dialogs.
///
/// Centralised so every screen reports success and failure the same way, and so
/// an [ApiException] is turned into a message in exactly one place.
class AppFeedback {
  const AppFeedback._();

  static void showSuccess(BuildContext context, String message) =>
      _show(context, message, icon: Icons.check_circle_rounded, accent: AppColors.success);

  static void showError(BuildContext context, Object error) {
    final message = error is ApiException
        ? error.message
        : 'Something went wrong. Please try again.';
    _show(context, message, icon: Icons.error_rounded, accent: AppColors.danger);
  }

  static void showInfo(BuildContext context, String message) =>
      _show(context, message, icon: Icons.info_rounded, accent: AppColors.info);

  static void _show(
    BuildContext context,
    String message, {
    required IconData icon,
    required Color accent,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    // Replace rather than queue: a stack of snackbars from a retry loop is
    // noise the customer has to sit through.
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: accent, size: 20),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(message)),
          ],
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Yes/no dialog. Returns false when dismissed by tapping outside.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool isDestructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);

        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(cancelLabel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: isDestructive ? theme.colorScheme.error : null,
              ),
              child: Text(
                confirmLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isDestructive ? theme.colorScheme.error : null,
                ),
              ),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }
}

/// A dismissible inline banner, for a warning that belongs on the screen rather
/// than in a transient snackbar - an unverified email, a stale fare quote, or a
/// missing build configuration.
class AppBanner extends StatelessWidget {
  const AppBanner({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.accent,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
  });

  final String message;
  final IconData icon;
  final Color? accent;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accent ?? AppColors.info;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: theme.brightness == Brightness.dark ? 0.14 : 0.09),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: theme.textTheme.bodySmall),
                if (actionLabel != null && onAction != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: InkWell(
                      onTap: onAction,
                      child: Text(
                        actionLabel!,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                          decorationColor: color,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, size: 17),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minHeight: 28, minWidth: 28),
              tooltip: 'Dismiss',
            ),
        ],
      ),
    );
  }
}
