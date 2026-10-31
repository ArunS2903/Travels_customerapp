import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/feedback.dart';
import '../../../../shared/widgets/section_card.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../booking_details/models/booking.dart';

/// The operator's official contact details, with tap-to-call and tap-to-email.
///
/// Two sources, and which one is used matters:
///
///   - [snapshot], when rendering a booking. That is the copy captured on the
///     booking at the time it was made, so an old trip shows the number the
///     customer was actually given, not whatever the admin has since changed it
///     to.
///   - otherwise `GET /public/business-contact`, the current details.
///
/// Nothing here is hardcoded. When the admin has configured no contact details
/// the card says so plainly instead of inventing a number.
class BusinessContactCard extends ConsumerWidget {
  const BusinessContactCard({
    super.key,
    this.snapshot,
    this.title = 'Contact',
    this.subtitle,
  });

  /// Contact details captured on a booking. Takes precedence when present.
  final BookingBusinessContact? snapshot;

  final String title;
  final String? subtitle;

  Future<void> _launch(BuildContext context, Uri uri, String failureMessage) async {
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        AppFeedback.showError(context, failureMessage);
      }
    } on Object {
      // No dialer, no mail client, or the platform refused the intent.
      if (context.mounted) AppFeedback.showError(context, failureMessage);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final captured = snapshot;

    if (captured != null) {
      return _buildCard(
        context,
        businessName: captured.businessName,
        contactName: captured.adminContactName,
        phone: captured.callNumber,
        email: captured.emailAddress,
        note: 'These are the details recorded when you made this booking.',
      );
    }

    final contactState = ref.watch(businessContactProvider);

    return contactState.when(
      loading: () => SectionCard(
        title: title,
        icon: Icons.support_agent_rounded,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Center(
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ),
      error: (error, _) => SectionCard(
        title: title,
        icon: Icons.support_agent_rounded,
        child: ErrorView(
          error: error,
          compact: true,
          onRetry: () => ref.invalidate(businessContactProvider),
        ),
      ),
      data: (contact) => _buildCard(
        context,
        businessName: contact.businessName,
        contactName: contact.adminContactName,
        phone: contact.callNumber,
        email: contact.emailAddress,
        address: contact.address,
        supportHours: contact.supportHours,
        whatsapp: contact.whatsappNumber,
        note: subtitle,
      ),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required String? businessName,
    String? contactName,
    String? phone,
    String? email,
    String? address,
    String? supportHours,
    String? whatsapp,
    String? note,
  }) {
    final theme = Theme.of(context);
    final hasAnything = (phone ?? '').isNotEmpty || (email ?? '').isNotEmpty;

    return SectionCard(
      title: title,
      icon: Icons.support_agent_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            businessName ?? 'Taxi service',
            style: theme.textTheme.titleMedium,
          ),
          if ((contactName ?? '').isNotEmpty)
            Text(contactName!, style: theme.textTheme.bodySmall),

          if (note != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(note, style: theme.textTheme.labelSmall),
          ],

          const SizedBox(height: AppSpacing.md),

          if (!hasAnything)
            Text(
              'Contact details have not been published yet. Please check back later.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),

          if ((phone ?? '').isNotEmpty)
            _ContactAction(
              icon: Icons.call_rounded,
              label: 'Call',
              value: phone!,
              onTap: () => _launch(
                context,
                Uri(scheme: 'tel', path: phone),
                'No phone app available on this device.',
              ),
            ),

          if ((whatsapp ?? '').isNotEmpty)
            _ContactAction(
              icon: Icons.chat_rounded,
              label: 'WhatsApp',
              value: whatsapp!,
              onTap: () => _launch(
                context,
                // wa.me wants the number without a plus or separators.
                Uri.parse('https://wa.me/${whatsapp.replaceAll(RegExp(r'[^0-9]'), '')}'),
                'WhatsApp is not installed on this device.',
              ),
            ),

          if ((email ?? '').isNotEmpty)
            _ContactAction(
              icon: Icons.mail_outline_rounded,
              label: 'Email',
              value: email!,
              onTap: () => _launch(
                context,
                Uri(scheme: 'mailto', path: email),
                'No email app available on this device.',
              ),
            ),

          if ((address ?? '').isNotEmpty)
            _ContactAction(
              icon: Icons.location_on_outlined,
              label: 'Office',
              value: address!,
              onTap: () => _launch(
                context,
                Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': address}),
                'No maps app available on this device.',
              ),
            ),

          if ((supportHours ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text('Support hours: $supportHours', style: theme.textTheme.labelSmall),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ContactAction extends StatelessWidget {
  const _ContactAction({
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

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
        child: Row(
          children: [
            Container(
              height: 34,
              width: 34,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, size: 17, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.labelSmall),
                  Text(
                    value,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 19, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
