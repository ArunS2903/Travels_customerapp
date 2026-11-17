import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/maps_launcher.dart';
import '../../../../shared/widgets/feedback.dart';
import '../../../../shared/widgets/section_card.dart';
import '../../../location/data/location_service.dart';
import '../../../location/providers/location_providers.dart';
import '../../models/booking.dart';

/// The two things a customer wants from a live booking: somebody to talk to,
/// and the way to where they are going.
///
/// Both are put near the top of the booking screen, side by side and large,
/// because both are wanted at the moment they are hardest to find - standing
/// on a kerb, one-handed, possibly in the dark. Everything else on that screen
/// is reference material that can live further down.
class BookingActionsCard extends ConsumerStatefulWidget {
  const BookingActionsCard({super.key, required this.booking});

  final Booking booking;

  @override
  ConsumerState<BookingActionsCard> createState() => _BookingActionsCardState();
}

class _BookingActionsCardState extends ConsumerState<BookingActionsCard> {
  bool _isOpeningMap = false;

  // --- Map ------------------------------------------------------------------

  /// Opens the route from where the customer is now to their drop location.
  ///
  /// The current position is obtained best-effort and on a short leash. A GPS
  /// fix can take fifteen seconds indoors, and a customer who taps "Route" and
  /// watches a spinner for that long has already decided the app is broken; a
  /// route that starts from the device's own idea of "here" - which is what
  /// omitting the origin gives - is a better answer than a correct one that
  /// arrives too late. So a timeout, a refusal and a disabled GPS all fall
  /// through to the same place rather than becoming three error paths.
  Future<void> _openRoute() async {
    final booking = widget.booking;
    setState(() => _isOpeningMap = true);

    double? originLat;
    double? originLng;
    String? permissionMessage;

    try {
      final position = await ref
          .read(locationServiceProvider)
          .getCurrentPosition()
          .timeout(const Duration(seconds: 6));
      originLat = position.latitude;
      originLng = position.longitude;
    } on LocationException catch (error) {
      // Worth saying out loud, because the customer asked for a route "from
      // here" and is about to get one that starts from the map's guess.
      permissionMessage = error.requiresSettings
          ? 'Location is turned off for this app, so the route starts from your '
                'last known position. Turn it on in Settings for turn-by-turn '
                'directions from where you are.'
          : 'We could not read your location, so Google Maps will work out your '
                'starting point.';
    } on Object {
      // A timeout or a platform error. Same handling: open the map anyway.
      permissionMessage = null;
    }

    final opened = await MapsLauncher.openDirections(
      destinationLatitude: booking.destination.latitude,
      destinationLongitude: booking.destination.longitude,
      destinationLabel: booking.destination.shortAddress,
      originLatitude: originLat,
      originLongitude: originLng,
    );

    if (!mounted) return;
    setState(() => _isOpeningMap = false);

    if (!opened) {
      AppFeedback.showError(
        context,
        'We could not open a maps application on this device.',
      );
      return;
    }

    if (permissionMessage != null) {
      AppFeedback.showInfo(context, permissionMessage);
    }
  }

  // --- Contact --------------------------------------------------------------

  void _openContactSheet() {
    final snapshot = widget.booking.businessContact;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _ContactSheet(
        snapshot: snapshot,
        bookingCode: widget.booking.bookingCode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SectionCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: _ActionTile(
              icon: Icons.support_agent_rounded,
              label: 'Contact',
              caption: 'Call or email us',
              onTap: _openContactSheet,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            height: 56,
            child: VerticalDivider(width: 1, color: theme.dividerColor),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _ActionTile(
              icon: Icons.map_rounded,
              label: 'Map',
              caption: 'Route to drop point',
              isBusy: _isOpeningMap,
              onTap: _isOpeningMap ? null : _openRoute,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.caption,
    this.onTap,
    this.isBusy = false,
  });

  final IconData icon;
  final String label;
  final String caption;
  final VoidCallback? onTap;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          children: [
            SizedBox(
              height: 26,
              width: 26,
              child: isBusy
                  ? const CircularProgressIndicator(strokeWidth: 2.2)
                  : ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (bounds) =>
                          AppColors.brandGradient.createShader(bounds),
                      child: Icon(icon, size: 26, color: Colors.white),
                    ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(label, style: theme.textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(
              caption,
              style: theme.textTheme.labelSmall,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// The operator's details, as a sheet.
///
/// Prefers the snapshot captured on the booking over the live record, for the
/// same reason the contact card does: a customer calling about a trip taken in
/// March should reach the number they were given in March.
class _ContactSheet extends ConsumerWidget {
  const _ContactSheet({required this.snapshot, required this.bookingCode});

  final BookingBusinessContact? snapshot;
  final String bookingCode;

  Future<void> _launch(BuildContext context, Uri uri, String failure) async {
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) AppFeedback.showError(context, failure);
    } on Object {
      if (context.mounted) AppFeedback.showError(context, failure);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final live = ref.watch(businessContactProvider).maybeWhen(
          data: (contact) => contact,
          orElse: () => null,
        );

    final businessName =
        snapshot?.businessName ?? live?.businessName ?? AppConfig.appName;
    final contactName =
        snapshot?.adminContactName ?? live?.adminContactName ?? AppConfig.serviceName;
    final phone = snapshot?.callNumber ?? live?.callNumber;
    final email = snapshot?.emailAddress ?? live?.emailAddress;
    final whatsapp = live?.whatsappNumber;

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
            Text(businessName, style: theme.textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(contactName, style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.lg),

            if ((phone ?? '').isNotEmpty)
              _ContactRow(
                icon: Icons.call_rounded,
                label: 'Call us',
                value: phone!,
                onTap: () => _launch(
                  context,
                  Uri(scheme: 'tel', path: phone),
                  'No dialler is available on this device.',
                ),
              ),

            if ((whatsapp ?? '').isNotEmpty)
              _ContactRow(
                icon: Icons.chat_rounded,
                label: 'WhatsApp',
                value: whatsapp!,
                onTap: () => _launch(
                  context,
                  // wa.me wants digits only: no plus, no spaces, no hyphens.
                  Uri.parse(
                    'https://wa.me/${whatsapp.replaceAll(RegExp(r'[^0-9]'), '')}'
                    '?text=${Uri.encodeComponent('Hello, I have a question about booking $bookingCode.')}',
                  ),
                  'WhatsApp is not available on this device.',
                ),
              ),

            if ((email ?? '').isNotEmpty)
              _ContactRow(
                icon: Icons.mail_outline_rounded,
                label: 'Email us',
                value: email!,
                onTap: () => _launch(
                  context,
                  Uri(
                    scheme: 'mailto',
                    path: email,
                    query: 'subject=${Uri.encodeComponent('Booking $bookingCode')}',
                  ),
                  'No email application is available on this device.',
                ),
              ),

            if ((phone ?? '').isEmpty && (email ?? '').isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Text(
                  'Contact details have not been published yet. Please try again '
                  'shortly.',
                  style: theme.textTheme.bodySmall,
                ),
              ),

            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.brandSoft,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.brandSoftBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.brandDark),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Quote booking $bookingCode when you get through. It is the '
                      'fastest way for us to find your trip.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.brand900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: AppColors.brandSoft,
        child: Icon(icon, size: 20, color: AppColors.brandDark),
      ),
      title: Text(label, style: theme.textTheme.titleSmall),
      subtitle: Text(value, style: theme.textTheme.bodySmall),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
    );
  }
}
