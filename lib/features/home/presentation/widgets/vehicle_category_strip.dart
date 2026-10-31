import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../vehicle_selection/models/vehicle_estimate.dart';
import '../../../vehicle_selection/providers/vehicle_providers.dart';

/// Icon for a category, keyed off the admin-set `iconName` or the code.
///
/// Falls back to a generic car rather than nothing, so a category the admin
/// invents after this build shipped still renders sensibly.
IconData vehicleIconFor(VehicleType vehicle) {
  final key = (vehicle.iconName ?? vehicle.code).toLowerCase();

  if (key.contains('mini') || key.contains('hatch'))
    return Icons.directions_car_rounded;
  if (key.contains('sedan') || key.contains('saloon'))
    return Icons.local_taxi_rounded;
  if (key.contains('suv') || key.contains('xl'))
    return Icons.airport_shuttle_rounded;
  if (key.contains('premium') || key.contains('lux')) return Icons.star_rounded;
  if (key.contains('auto') || key.contains('rick'))
    return Icons.electric_rickshaw_rounded;
  if (key.contains('bike') || key.contains('moto'))
    return Icons.two_wheeler_rounded;
  if (key.contains('van') || key.contains('tempo'))
    return Icons.airport_shuttle_rounded;
  return Icons.directions_car_filled_rounded;
}

/// Horizontal strip of categories on the home screen.
///
/// Shows the admin's *rate card* ("from ₹16/km"), never a trip total - there is
/// no route yet, so a total would be a fiction. The real fares appear on the
/// vehicle selection screen once a destination exists.
class VehicleCategoryStrip extends ConsumerWidget {
  const VehicleCategoryStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehiclesState = ref.watch(vehicleTypesProvider);

    return SizedBox(
      height: 132,
      child: vehiclesState.when(
        loading: () => ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 3,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
          itemBuilder: (_, __) => const _CategorySkeleton(),
        ),
        error: (error, _) => ErrorView(
          error: error,
          compact: true,
          onRetry: () => ref.invalidate(vehicleTypesProvider),
        ),
        data: (vehicles) {
          if (vehicles.isEmpty) {
            return Center(
              child: Text(
                'No vehicle categories are available right now.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            );
          }

          return ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: vehicles.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) =>
                _CategoryCard(vehicle: vehicles[index]),
          );
        },
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.vehicle});

  final VehicleType vehicle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rateCard = vehicle.rateCard;

    return Container(
      width: 148,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 34,
                width: 34,
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  vehicleIconFor(vehicle),
                  size: 19,
                  color: AppColors.amberDark,
                ),
              ),
              const Spacer(),
              if (vehicle.defaultEtaMinutes > 0)
                Text(
                  Formatters.eta(vehicle.defaultEtaMinutes),
                  style: theme.textTheme.labelSmall,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            vehicle.name,
            style: theme.textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            '${vehicle.passengerCapacity} seats',
            style: theme.textTheme.labelSmall,
          ),
          const Spacer(),
          if (!vehicle.isBookable)
            Text(
              'Unavailable',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            )
          else if (rateCard != null)
            Text(
              'from ${Formatters.money(rateCard.perKmRate, symbol: rateCard.currencySymbol)}/km',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

/// Placeholder card shown while the catalogue loads, sized to match the real
/// one so the strip does not resize when data arrives.
class _CategorySkeleton extends StatelessWidget {
  const _CategorySkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 148,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    );
  }
}
