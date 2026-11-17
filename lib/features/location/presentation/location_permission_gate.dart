import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/primary_button.dart';
import '../data/location_service.dart';
import '../providers/location_providers.dart';

/// Asks for location permission once, when the app opens, and explains what to
/// do when it has been refused.
///
/// Why ask here rather than at the point of use
/// --------------------------------------------
/// The pickup field, the map preview and the route button all need a location,
/// and each of them used to trigger the system prompt on its own. That meant
/// the customer could meet the dialogue at an arbitrary moment with no context
/// for why it had appeared, and - worse - that a refusal at one of those
/// points left the other two silently broken. Asking once at launch makes the
/// request legible and gives one place to handle the answer.
///
/// What it deliberately does not do
/// --------------------------------
/// It does not block. The app works without a location: addresses can be
/// typed, a pin can be dropped, and bookings complete normally. So a refusal
/// shows an explanation the customer can dismiss, not a wall. Anything else
/// would be holding a booking hostage to a permission the booking does not
/// require.
///
/// Android's second refusal is permanent - the system will not show the
/// dialogue again - which is why that case routes to the Settings app instead
/// of asking once more.
class LocationPermissionGate extends ConsumerStatefulWidget {
  const LocationPermissionGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LocationPermissionGate> createState() => _LocationPermissionGateState();
}

class _LocationPermissionGateState extends ConsumerState<LocationPermissionGate> {
  /// Guards against asking twice if the widget rebuilds, which would put a
  /// second system dialogue behind the first.
  bool _hasAsked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestOnce());
  }

  Future<void> _requestOnce() async {
    if (_hasAsked) return;
    _hasAsked = true;

    try {
      await ref.read(locationServiceProvider).ensurePermission();
    } on LocationException catch (error) {
      if (!mounted) return;
      await _explain(error);
    } on Object {
      // A platform error rather than a refusal. Nothing to explain, and the
      // app is fully usable without a fix.
    }
  }

  Future<void> _explain(LocationException error) async {
    final service = ref.read(locationServiceProvider);

    final isServiceOff = error.failure == LocationFailure.serviceDisabled;
    final isPermanent = error.requiresSettings;

    /// This widget sits above the router's navigator, so its own `context`
    /// has none - a sheet opened from it would assert. The root navigator's
    /// context is the one that can host a sheet.
    final navigatorContext = rootNavigatorKey.currentContext;
    if (navigatorContext == null) return;

    await showModalBottomSheet<void>(
      context: navigatorContext,
      isScrollControlled: true,
      builder: (sheetContext) => _LocationPromptSheet(
        isServiceOff: isServiceOff,
        isPermanent: isPermanent,
        onOpenSettings: () async {
          Navigator.of(sheetContext).pop();
          if (isServiceOff) {
            await service.openLocationSettings();
          } else {
            await service.openSettings();
          }
        },
        onRetry: isPermanent || isServiceOff
            ? null
            : () async {
                Navigator.of(sheetContext).pop();
                _hasAsked = false;
                await _requestOnce();
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _LocationPromptSheet extends StatelessWidget {
  const _LocationPromptSheet({
    required this.isServiceOff,
    required this.isPermanent,
    required this.onOpenSettings,
    this.onRetry,
  });

  final bool isServiceOff;
  final bool isPermanent;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final title = isServiceOff
        ? 'Turn on location services'
        : isPermanent
            ? 'Location is blocked for this app'
            : 'Let us find your pickup point';

    final body = isServiceOff
        ? 'Location services are switched off on this device, so we cannot find '
            'your pickup point or show you the route to your drop location. Turn '
            'them on in your device settings.'
        : isPermanent
            ? 'You have declined location for this app, and Android will not ask '
                'again. You can turn it back on in Settings > Apps > permissions. '
                'Until then, enter your pickup address by hand.'
            : 'We use your location to fill in your pickup point and to show the '
                'route from where you are to your drop location. You can always '
                'type an address instead.';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageGutter,
          0,
          AppSpacing.pageGutter,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 48,
              width: 48,
              decoration: const BoxDecoration(
                gradient: AppColors.brandGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_on_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.xl),

            if (onRetry != null) ...[
              PrimaryButton(
                label: 'Allow location',
                icon: Icons.my_location_rounded,
                onPressed: () => onRetry!(),
              ),
              const SizedBox(height: AppSpacing.sm),
            ] else ...[
              PrimaryButton(
                label: isServiceOff ? 'Open location settings' : 'Open app settings',
                icon: Icons.settings_rounded,
                onPressed: () => onOpenSettings(),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],

            SecondaryButton(
              label: 'Not now',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
