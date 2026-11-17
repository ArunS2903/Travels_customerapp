import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../core/providers/app_providers.dart';

/// Shown while the session is being resolved.
///
/// Does no work of its own: `main()` has already kicked off the keystore read
/// and profile fetch, and the router's redirect moves off this screen the
/// moment the auth state resolves. It exists so that first moment is a brand
/// moment rather than a blank frame or a login screen that vanishes.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // The business name, if the public contact call has already resolved. It is
    // allowed to be absent - we never block the splash on a network call.
    final businessName = ref.watch(businessContactProvider).maybeWhen(
          data: (contact) => contact.businessName,
          orElse: () => null,
        );

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppLogo(size: 92, showWordmark: true, wordmark: businessName),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Travel and cab booking, a few taps away',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.huge),
              const SizedBox(
                height: 26,
                width: 26,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
