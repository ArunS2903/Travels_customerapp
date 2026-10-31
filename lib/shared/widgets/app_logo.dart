import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// The app mark: a drawn badge rather than an image asset, so it stays crisp at
/// any size and the project ships without binary assets to keep in sync.
///
/// An operator replacing this with their own logo only needs to change the
/// [Icon] and the gradient here.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 56, this.showWordmark = false, this.wordmark});

  final double size;
  final bool showWordmark;

  /// Business name, when known. Falls back to the generic product name so the
  /// splash screen renders before the business-contact call returns.
  final String? wordmark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final badge = Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.amber, AppColors.amberDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Center(
        child: Icon(
          Icons.local_taxi_rounded,
          size: size * 0.56,
          color: AppColors.ink,
        ),
      ),
    );

    if (!showWordmark) return badge;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        badge,
        const SizedBox(height: AppSpacing.lg),
        Text(
          wordmark ?? 'Taxi Booking',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
