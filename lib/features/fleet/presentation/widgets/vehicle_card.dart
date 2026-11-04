import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/app_network_image.dart';
import '../../../../shared/widgets/status_chip.dart';
import '../../models/fleet_vehicle.dart';

/// One vehicle in the available-vehicles list: its cover photo and the few
/// facts somebody chooses on.
///
/// Only the basics are here on purpose - the photo, the name, seats, fuel,
/// transmission and what it costs for the chosen dates. Everything else (the
/// full gallery, the feature list, the description, the deposit) lives on the
/// details screen, because a list of eight vehicles each showing everything is
/// a list nobody can compare.
class VehicleCard extends StatelessWidget {
  const VehicleCard({
    super.key,
    required this.vehicle,
    required this.days,
    required this.onTap,
    this.onBook,
    this.isSelected = false,
  });

  final FleetVehicle vehicle;

  /// Billable days for the chosen period, so the card can show the total for
  /// the hire rather than only a daily rate the customer has to multiply.
  final int days;

  final VoidCallback onTap;

  /// Books this vehicle straight from the list. Null hides the button, which
  /// is what the selection flow wants when the details screen is the next step.
  final VoidCallback? onBook;

  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final symbol = vehicle.currencySymbol;
    final total = vehicle.pricePerDay * days;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(
          color: isSelected ? AppColors.amberDark : theme.colorScheme.outline,
          width: isSelected ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 160,
                  width: double.infinity,
                  child: AppNetworkImage(
                    url: vehicle.coverUrl,
                    displayWidth: MediaQuery.sizeOf(context).width,
                  ),
                ),
                Positioned(
                  left: AppSpacing.sm,
                  top: AppSpacing.sm,
                  child: _OverlayChip(
                    icon: Icons.verified_rounded,
                    label: 'Available',
                    color: AppColors.success,
                  ),
                ),
                if (vehicle.photoUrls.length > 1)
                  Positioned(
                    right: AppSpacing.sm,
                    top: AppSpacing.sm,
                    child: _OverlayChip(
                      icon: Icons.photo_library_rounded,
                      label: '${vehicle.photoUrls.length} photos',
                      color: Colors.black.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),

            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vehicle.name,
                              style: theme.textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              vehicle.makeAndModel,
                              style: theme.textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            Formatters.money(total, symbol: symbol),
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            days == 1
                                ? 'for 1 day'
                                : 'for $days days',
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),

                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      InfoPill(icon: Icons.category_rounded, label: vehicle.categoryLabel),
                      InfoPill(
                        icon: Icons.airline_seat_recline_normal_rounded,
                        label: '${vehicle.seatingCapacity} seats',
                      ),
                      InfoPill(
                        icon: Icons.local_gas_station_rounded,
                        label: vehicle.fuelLabel,
                      ),
                      InfoPill(icon: Icons.settings_rounded, label: vehicle.transmissionLabel),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),

                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${Formatters.money(vehicle.pricePerDay, symbol: symbol)} per day'
                          '${vehicle.securityDeposit > 0 ? '  |  ${Formatters.money(vehicle.securityDeposit, symbol: symbol)} deposit' : ''}',
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                      if (onBook != null)
                        TextButton(onPressed: onBook, child: const Text('Book'))
                      else
                        Row(
                          children: [
                            Text('View details', style: theme.textTheme.labelMedium),
                            const Icon(Icons.chevron_right_rounded, size: 18),
                          ],
                        ),
                    ],
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

/// A small label over a photo. Dark enough to stay legible on any image.
class _OverlayChip extends StatelessWidget {
  const _OverlayChip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2, vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 12, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
