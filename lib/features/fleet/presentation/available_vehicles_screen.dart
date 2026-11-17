import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/app_network_image.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/state_views.dart';
import '../../booking_confirmation/providers/booking_draft_controller.dart';
import '../models/fleet_vehicle.dart';
import '../providers/fleet_providers.dart';
import 'widgets/vehicle_card.dart';

/// The vehicles that are actually free for the dates the customer chose.
///
/// Availability is the server's answer, not a filter applied here: the screen
/// sends the period and renders whatever comes back. That matters because the
/// question "is this car free on the 12th" is answered by the hold rows in the
/// bookings database, which the app cannot see and should not try to guess at.
///
/// It is also re-read every time the screen is opened rather than cached for
/// the session - another customer may have taken a car in the meantime, and a
/// list that quietly went stale would send somebody to a confirmation screen
/// that then refuses them.
class AvailableVehiclesScreen extends ConsumerWidget {
  const AvailableVehiclesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(bookingDraftProvider);
    final period = draft.period;

    if (period == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Available vehicles')),
        body: EmptyView(
          icon: Icons.event_busy_rounded,
          title: 'Choose your dates first',
          message:
              'Vehicles are shown for the dates you need them, so pick a booking '
              'date on the home screen and we will check what is free.',
          actionLabel: 'Go to home',
          onAction: () => context.go(AppRoutes.home),
        ),
      );
    }

    final vehiclesState = ref.watch(availableVehiclesProvider(period));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Available vehicles'),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(availableVehiclesProvider(period)),
            tooltip: 'Check again',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          _PeriodBar(period: period, onChange: () => context.go(AppRoutes.home)),
          Expanded(
            child: vehiclesState.when(
              loading: () => const LoadingView(message: 'Checking what is free for your dates'),
              error: (error, _) => ErrorView(
                error: error,
                onRetry: () => ref.invalidate(availableVehiclesProvider(period)),
              ),
              data: (page) {
                if (page.items.isEmpty) {
                  return EmptyView(
                    icon: Icons.no_transfer_rounded,
                    title: 'No vehicles free for these dates',
                    message:
                        'Everything in the fleet is either booked or off the road for '
                        '${Formatters.date(period.startAt)} to ${Formatters.date(period.endAt)}. '
                        'Try different dates.',
                    actionLabel: 'Change dates',
                    onAction: () => context.go(AppRoutes.home),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(availableVehiclesProvider(period));
                    await ref.read(availableVehiclesProvider(period).future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pageGutter,
                      AppSpacing.lg,
                      AppSpacing.pageGutter,
                      AppSpacing.xxl,
                    ),
                    itemCount: page.items.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.lg),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: Text(
                            page.total == 1
                                ? '1 vehicle is free for your dates'
                                : '${page.total} vehicles are free for your dates',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        );
                      }

                      final vehicle = page.items[index - 1];

                      return VehicleCard(
                        vehicle: vehicle,
                        days: period.days,
                        isSelected: draft.vehicle?.id == vehicle.id,
                        onTap: () => _openDetails(context, vehicle),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the full-screen details rather than booking from the list.
  ///
  /// The brief asks for the complete details to be seen before booking, and
  /// there is a practical reason beyond that: the deposit, the feature list and
  /// the photographs are what a customer would be annoyed to discover after
  /// committing.
  void _openDetails(BuildContext context, FleetVehicle vehicle) {
    context.push(AppRoutes.vehicleDetailsFor(vehicle.id));
  }
}

/// The chosen dates, pinned above the list so the customer can see what the
/// availability they are looking at is *for*.
class _PeriodBar extends StatelessWidget {
  const _PeriodBar({required this.period, required this.onChange});

  final HirePeriod period;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageGutter,
        AppSpacing.md,
        AppSpacing.pageGutter,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_available_rounded, size: 19, color: AppColors.brand),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your booking dates', style: theme.textTheme.labelSmall),
                Text(
                  '${Formatters.date(period.startAt)} to ${Formatters.date(period.endAt)}'
                  '  |  ${period.days == 1 ? '1 day' : '${period.days} days'}',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onChange, child: const Text('Change')),
        ],
      ),
    );
  }
}

/// Shown on the home screen: a short strip of what is free for the chosen
/// dates, so the customer sees that the date actually did something before
/// they commit to a whole screen of results.
class AvailableVehiclesPreview extends ConsumerWidget {
  const AvailableVehiclesPreview({super.key, required this.period});

  final HirePeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(availableVehiclesProvider(period));

    return state.when(
      loading: () => const SectionCard(
        child: Row(
          children: [
            SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: AppSpacing.md),
            Expanded(child: Text('Checking which vehicles are free')),
          ],
        ),
      ),
      error: (error, _) => AppBanner(
        icon: Icons.cloud_off_rounded,
        accent: AppColors.warning,
        message: 'We could not check availability just now.',
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(availableVehiclesProvider(period)),
      ),
      data: (page) {
        if (page.items.isEmpty) {
          return AppBanner(
            icon: Icons.no_transfer_rounded,
            accent: AppColors.warning,
            message: 'No vehicles are free for those dates. Try different ones.',
          );
        }

        return SectionCard(
          title: 'Free for your dates',
          icon: Icons.directions_car_filled_rounded,
          trailing: Text(
            page.total == 1 ? '1 vehicle' : '${page.total} vehicles',
            style: theme.textTheme.labelSmall,
          ),
          child: SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: page.items.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
              itemBuilder: (context, index) {
                final vehicle = page.items[index];

                return InkWell(
                  onTap: () => context.push(AppRoutes.vehicleDetailsFor(vehicle.id)),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: SizedBox(
                    width: 132,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 66,
                          width: 132,
                          child: AppNetworkImage(
                            url: vehicle.coverUrl,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            // 132 logical pixels, so a 3000px photo decodes to
                            // a few hundred KB instead of tens of megabytes.
                            displayWidth: 132,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          vehicle.name,
                          style: theme.textTheme.labelMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          Formatters.money(
                            vehicle.pricePerDay,
                            symbol: vehicle.currencySymbol,
                          ),
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
