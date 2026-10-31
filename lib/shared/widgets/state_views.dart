import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_spacing.dart';
import 'primary_button.dart';

/// Centred spinner with an optional caption, for a screen that has nothing to
/// show yet.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            height: 32,
            width: 32,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(message!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// A failure, with a retry when retrying could help.
///
/// Takes the [ApiException] rather than a string so the view can tell a network
/// blip (worth a Retry button) from a 403 (not worth one), and can show the
/// backend's own wording instead of a generic apology.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry, this.compact = false});

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  ApiException? get _apiError => error is ApiException ? error as ApiException : null;

  String get _title {
    final api = _apiError;
    if (api == null) return 'Something went wrong';

    switch (api.code) {
      case ApiException.networkUnavailable:
        return 'No connection';
      case ApiException.timeout:
        return 'That took too long';
      case ApiException.rateLimited:
        return 'Too many attempts';
      default:
        return api.statusCode != null && api.statusCode! >= 500
            ? 'Server trouble'
            : 'Something went wrong';
    }
  }

  String get _message =>
      _apiError?.message ?? 'Please try again. If it keeps happening, contact support.';

  IconData get _icon {
    switch (_apiError?.code) {
      case ApiException.networkUnavailable:
        return Icons.wifi_off_rounded;
      case ApiException.timeout:
        return Icons.hourglass_disabled_rounded;
      case ApiException.rateLimited:
        return Icons.timer_outlined;
      default:
        return Icons.error_outline_rounded;
    }
  }

  /// Retrying a validation error or a 403 would just fail again, so the button
  /// is only offered where it makes sense.
  bool get _canRetry {
    if (onRetry == null) return false;
    final api = _apiError;
    if (api == null) return true;
    return api.isRetryable || api.statusCode == null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (compact) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Icon(_icon, size: 20, color: theme.colorScheme.error),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(_message, style: theme.textTheme.bodySmall)),
            if (_canRetry)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_icon, size: 52, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.lg),
            Text(_title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _message,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (_canRetry) ...[
              const SizedBox(height: AppSpacing.xxl),
              SecondaryButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                onPressed: onRetry,
                expand: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Nothing here yet", with an optional action.
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(message, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xxl),
              PrimaryButton(label: actionLabel!, onPressed: onAction, expand: false),
            ],
          ],
        ),
      ),
    );
  }
}
