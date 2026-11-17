import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../fleet/presentation/widgets/vehicle_photo_gallery.dart';
import '../models/booking.dart';
import '../providers/booking_detail_providers.dart';

/// Everything about the vehicle on one booking, on its own screen.
///
/// Why this reads the booking rather than the fleet
/// ------------------------------------------------
/// There is already a vehicle details screen - `fleet/vehicle_details_screen`
/// - and it would have been less code to send the customer there. It would
/// also have been wrong. That screen shows the car *as it is now*: today's
/// daily rate, today's photographs, today's availability. This one has to show
/// the car *as it was hired*, because that is what the customer agreed to and
/// what the invoice is based on. Operators re-price vehicles, replace
/// photographs and eventually sell them, and a details screen that quietly
/// updated to a rate the customer never agreed to would be worse than useless
/// in a dispute.
///
/// So everything here comes from the snapshot the backend wrote onto the
/// booking at the moment it was made. The consequence is that this screen
/// cannot 404: a vehicle deleted from the fleet six months ago still renders.
class BookingVehicleScreen extends ConsumerWidget {
  const BookingVehicleScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailState = ref.watch(bookingDetailProvider(bookingId));

    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle details')),
      body: detailState.when(
        loading: () => const LoadingView(message: 'Loading vehicle details'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(bookingDetailProvider(bookingId)),
        ),
        data: (detail) {
          final booking = detail.booking;
          final vehicle = booking.vehicle;

          if (vehicle == null) {
            return const EmptyView(
              icon: Icons.directions_car_outlined,
              title: 'No vehicle details',
              message:
                  'This booking was made for a vehicle category rather than a '
                  'specific vehicle, so there is nothing more to show here.',
            );
          }

          return _VehicleDetailBody(booking: booking, vehicle: vehicle);
        },
      ),
    );
  }
}

class _VehicleDetailBody extends StatelessWidget {
  const _VehicleDetailBody({required this.booking, required this.vehicle});

  final Booking booking;
  final BookingVehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hire = booking.hire;
    final symbol = booking.currencySymbol;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageGutter,
        AppSpacing.md,
        AppSpacing.pageGutter,
        AppSpacing.xxl,
      ),
      children: [
        if (vehicle.hasPhotos) ...[
          VehiclePhotoGallery(
            photoUrls: vehicle.photos,
            heroTitle: vehicle.name ?? booking.vehicleTypeName,
            height: 240,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],

        // --- Identity ------------------------------------------------------
        Text(
          vehicle.name ?? booking.vehicleTypeName,
          style: theme.textTheme.headlineSmall,
        ),
        if (vehicle.makeAndModel.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(vehicle.makeAndModel, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: AppSpacing.md),

        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if ((vehicle.registrationNumber ?? '').isNotEmpty)
              InfoPill(
                icon: Icons.confirmation_number_rounded,
                label: vehicle.registrationNumber!,
              ),
            if ((vehicle.category ?? '').isNotEmpty)
              InfoPill(icon: Icons.category_rounded, label: vehicle.category!),
            if (vehicle.seatingCapacity != null)
              InfoPill(
                icon: Icons.airline_seat_recline_normal_rounded,
                label: '${vehicle.seatingCapacity} seats',
              ),
            if ((vehicle.fuelType ?? '').isNotEmpty)
              InfoPill(
                icon: Icons.local_gas_station_rounded,
                label: vehicle.fuelType!,
              ),
            if ((vehicle.transmission ?? '').isNotEmpty)
              InfoPill(icon: Icons.settings_rounded, label: vehicle.transmission!),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        // --- Specification --------------------------------------------------
        SectionCard(
          title: 'Specification',
          icon: Icons.tune_rounded,
          child: Column(
            children: [
              InfoRow(
                label: 'Vehicle',
                value: vehicle.name ?? booking.vehicleTypeName,
              ),
              if ((vehicle.brand ?? '').isNotEmpty)
                InfoRow(label: 'Make', value: vehicle.brand!),
              if ((vehicle.model ?? '').isNotEmpty)
                InfoRow(label: 'Model', value: vehicle.model!),
              if (vehicle.year != null)
                InfoRow(label: 'Year', value: '${vehicle.year}'),
              if ((vehicle.registrationNumber ?? '').isNotEmpty)
                InfoRow(
                  label: 'Registration number',
                  value: vehicle.registrationNumber!,
                  emphasised: true,
                ),
              if ((vehicle.category ?? '').isNotEmpty)
                InfoRow(label: 'Category', value: vehicle.category!),
              if (vehicle.seatingCapacity != null)
                InfoRow(
                  label: 'Seating capacity',
                  value: '${vehicle.seatingCapacity} passengers',
                ),
              if ((vehicle.fuelType ?? '').isNotEmpty)
                InfoRow(label: 'Fuel', value: vehicle.fuelType!),
              if ((vehicle.transmission ?? '').isNotEmpty)
                InfoRow(label: 'Transmission', value: vehicle.transmission!),
            ],
          ),
        ),

        // --- What it costs on this booking ----------------------------------
        if (hire != null) ...[
          const SizedBox(height: AppSpacing.lg),
          SectionCard(
            title: 'Hire charges for this booking',
            icon: Icons.payments_outlined,
            child: Column(
              children: [
                InfoRow(
                  label: 'Booking date',
                  value: Formatters.date(hire.startAt),
                  icon: Icons.event_rounded,
                ),
                InfoRow(
                  label: 'Return date',
                  value: Formatters.date(hire.endAt),
                  icon: Icons.event_repeat_rounded,
                ),
                InfoRow(
                  label: 'Duration',
                  value: hire.days == 1 ? '1 day' : '${hire.days} days',
                ),
                const Divider(height: AppSpacing.lg),
                InfoRow(
                  label: 'Daily rate',
                  value: Formatters.money(hire.dailyRate, symbol: symbol),
                ),
                InfoRow(
                  label: hire.days == 1
                      ? 'Hire charge (1 day)'
                      : 'Hire charge (${hire.days} days)',
                  value: Formatters.money(hire.hireCharge, symbol: symbol),
                ),
                if (hire.securityDeposit > 0)
                  InfoRow(
                    label: 'Security deposit',
                    value:
                        '${Formatters.money(hire.securityDeposit, symbol: symbol)} (refundable)',
                  ),
                const Divider(height: AppSpacing.lg),
                InfoRow(
                  label: booking.isFareFinal ? 'Final total' : 'Estimated total',
                  value: Formatters.money(
                    booking.displayFare,
                    symbol: symbol,
                  ),
                  emphasised: true,
                  valueColor: AppColors.brand,
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: AppSpacing.lg),
        Text(
          'These are the details recorded when booking ${booking.bookingCode} was '
          'made, so they stay accurate for this trip even if the vehicle is later '
          're-priced or re-photographed.',
          style: theme.textTheme.labelSmall,
        ),
      ],
    );
  }
}
