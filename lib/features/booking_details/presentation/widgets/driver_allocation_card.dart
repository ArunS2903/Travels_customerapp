import 'package:flutter/material.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/section_card.dart';
import '../../models/booking.dart';

/// Driver details, and - before there are any - the fact that there are none.
///
/// This card is always on the Booked Details screen, which is the point. The
/// question it answers is "has a driver been assigned to my vehicle?", and a
/// card that appeared only once the answer was yes would leave the customer
/// scrolling for something that was not there, unsure whether they had missed
/// it or the operator had not acted.
///
/// So the allocation status is a field with two states, and the unallocated one
/// says what happens next: the operator assigns somebody, and we text the
/// details to the number on the booking.
class DriverAllocationCard extends StatelessWidget {
  const DriverAllocationCard({
    super.key,
    required this.booking,
    this.onCall,
    this.onCopyNumber,
  });

  final Booking booking;

  /// Dials the driver. Null when there is no number to dial, which also hides
  /// the button rather than showing one that does nothing.
  final VoidCallback? onCall;

  final VoidCallback? onCopyNumber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allocation = booking.allocation;
    final driver = booking.driver;

    return SectionCard(
      title: 'Driver',
      icon: Icons.person_pin_circle_rounded,
      trailing: _StatusBadge(allocation: allocation),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The status field the brief asks for, stated as a row of its own so
          // it reads the same way whether or not a driver exists.
          InfoRow(
            label: 'Driver allocation status',
            value: allocation.status.label,
            valueColor: allocation.status.color,
            emphasised: true,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(allocation.status.description, style: theme.textTheme.bodySmall),

          if (!allocation.isAllocated || driver == null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.sms_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'You will get an SMS with the driver name and mobile number '
                      'on ${Formatters.phone(booking.customerPhone)}.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.lg),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),

            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.successSoft,
                  // Resolved like every other remote image: a driver photo
                  // served from the operator's own storage arrives as a path.
                  backgroundImage: AppConfig.resolveMediaUrl(driver.photoUrl) == null
                      ? null
                      : NetworkImage(AppConfig.resolveMediaUrl(driver.photoUrl)!),
                  child: (driver.photoUrl ?? '').isEmpty
                      ? Text(
                          Formatters.initials(driver.name),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppColors.success,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driver.name ?? 'Driver assigned',
                        style: theme.textTheme.titleSmall,
                      ),
                      if (driver.hasPhone)
                        Text(
                          Formatters.phone(driver.phone),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (driver.rating != null)
                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: AppColors.amberDark,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              driver.rating!.toStringAsFixed(1),
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                if (onCall != null)
                  IconButton(
                    onPressed: onCall,
                    tooltip: 'Call driver',
                    icon: const Icon(Icons.call_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.success.withValues(alpha: 0.14),
                      foregroundColor: AppColors.success,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: AppSpacing.md),

            InfoRow(label: 'Driver name', value: driver.name ?? '--'),
            InfoRow(
              label: 'Driver mobile number',
              value: driver.hasPhone ? Formatters.phone(driver.phone) : 'Not provided',
              valueWidget: driver.hasPhone && onCopyNumber != null
                  ? _CopyableValue(
                      value: Formatters.phone(driver.phone),
                      onCopy: onCopyNumber!,
                    )
                  : null,
            ),
            if ((driver.driverCode ?? '').isNotEmpty)
              InfoRow(label: 'Driver ID', value: driver.driverCode!),
            if ((driver.vehicleNumber ?? '').isNotEmpty)
              InfoRow(label: 'Vehicle number', value: driver.vehicleNumber!),
            if (driver.assignedAt != null)
              InfoRow(
                label: 'Allocated on',
                value: Formatters.dateTime(driver.assignedAt),
              ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.allocation});

  final BookingDriverAllocation allocation;

  @override
  Widget build(BuildContext context) {
    final status = allocation.status;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: status.softColor,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(status.icon, size: 13, color: status.color),
            const SizedBox(width: 4),
            Text(
              status.apiValue,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: status.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A value with a copy button, for the one field a customer actually needs to
/// get out of the app and into their dialler or a message.
class _CopyableValue extends StatelessWidget {
  const _CopyableValue({required this.value, required this.onCopy});

  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
        IconButton(
          onPressed: onCopy,
          icon: const Icon(Icons.copy_rounded, size: 15),
          tooltip: 'Copy number',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minHeight: 30, minWidth: 30),
        ),
      ],
    );
  }
}
