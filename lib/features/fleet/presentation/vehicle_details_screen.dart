import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../booking_confirmation/providers/booking_draft_controller.dart';
import '../models/fleet_vehicle.dart';
import '../providers/fleet_providers.dart';
import '../providers/vehicle_cache.dart';
import 'widgets/vehicle_photo_gallery.dart';

/// One vehicle, in full: every photograph, every specification, what it costs
/// for the chosen dates, and which days it is already taken.
///
/// Fetched by id rather than handed the object from the list, so this screen
/// works from a deep link and always shows the operator's current photographs
/// and rate - the list it was opened from may be minutes old.
///
/// It does not *wait* for that fetch when it does not have to. A vehicle the
/// customer just tapped is already in [vehicleCacheProvider], so the screen
/// paints from it on the first frame and the network read refreshes underneath.
/// Only a cold open - a deep link, or a return after the cache was trimmed -
/// shows a loading state, and only then is there actually nothing to show.
class VehicleDetailsScreen extends ConsumerStatefulWidget {
  const VehicleDetailsScreen({super.key, required this.vehicleId});

  final String vehicleId;

  @override
  ConsumerState<VehicleDetailsScreen> createState() =>
      _VehicleDetailsScreenState();
}

class _VehicleDetailsScreenState extends ConsumerState<VehicleDetailsScreen> {
  bool _isSelecting = false;

  Future<void> _refresh() async {
    ref.invalidate(vehicleDetailProvider(widget.vehicleId));
    ref.invalidate(vehicleAvailabilityProvider(widget.vehicleId));
    await ref.read(vehicleDetailProvider(widget.vehicleId).future);
  }

  /// Chooses this vehicle and moves to the confirmation screen.
  ///
  /// The quote is fetched here, before navigating, for one reason: it is the
  /// server's last word on whether the car is still free. Between the list
  /// loading and this tap another customer may have booked it, and finding that
  /// out now - with the dates still on screen - is far better than on the
  /// confirmation screen with a payment method already chosen.
  Future<void> _selectVehicle(FleetVehicle vehicle) async {
    final draft = ref.read(bookingDraftProvider);
    final period = draft.period;

    if (period == null) {
      AppFeedback.showInfo(
        context,
        'Choose your booking dates on the home screen first.',
      );
      return;
    }

    if (!draft.hasRoute) {
      AppFeedback.showInfo(
        context,
        'Set your pickup and drop locations on the home screen before booking.',
      );
      return;
    }

    if (!draft.isReadyToSearch) {
      AppFeedback.showInfo(
        context,
        'Choose a different drop location before booking.',
      );
      return;
    }

    setState(() => _isSelecting = true);

    try {
      final quote = await ref
          .read(fleetRepositoryProvider)
          .quoteHire(vehicleId: vehicle.id, period: period);

      if (!mounted) return;

      if (!quote.isAvailable) {
        // The dates are listed because "not available" without saying which
        // days leaves the customer with nothing to act on.
        AppFeedback.showError(
          context,
          quote.conflictingDays.isEmpty
              ? '${vehicle.name} has just been booked for those dates. Please choose another vehicle.'
              : '${vehicle.name} is already booked on ${quote.conflictingDays.join(', ')}. '
                    'Choose different dates or another vehicle.',
        );
        ref.invalidate(vehicleAvailabilityProvider(widget.vehicleId));
        return;
      }

      ref
          .read(bookingDraftProvider.notifier)
          .selectVehicle(quote.vehicle, quote: quote);
      context.push(AppRoutes.bookingConfirmation);
    } on ApiException catch (error) {
      if (mounted) AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isSelecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicleState = ref.watch(vehicleDetailProvider(widget.vehicleId));
    final draft = ref.watch(bookingDraftProvider);

    /// The best copy available right now: the fetched one if it has arrived,
    /// otherwise whatever the list left in the cache.
    final vehicle =
        vehicleState.valueOrNull ??
        ref.watch(cachedVehicleProvider(widget.vehicleId));

    /// A failure only matters when there is nothing to show. With a cached copy
    /// on screen, a failed background refresh is a stale-data notice, not an
    /// error page that throws away a perfectly good answer.
    final hardError = vehicleState.hasError && vehicle == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(vehicle?.name ?? 'Vehicle details'),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'Refresh',
            icon: vehicleState.isLoading && vehicle != null
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: hardError
          ? ErrorView(error: vehicleState.error!, onRetry: _refresh)
          : vehicle == null
          ? const LoadingView(message: 'Loading vehicle details')
          : _buildBody(vehicle, draft, isStale: vehicleState.hasError),
      bottomNavigationBar: vehicle == null
          ? null
          : _buildBottomBar(vehicle, draft),
    );
  }

  Widget _buildBody(
    FleetVehicle vehicle,
    BookingDraft draft, {
    bool isStale = false,
  }) {
    final theme = Theme.of(context);
    final symbol = vehicle.currencySymbol;
    final period = draft.period;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageGutter,
          AppSpacing.lg,
          AppSpacing.pageGutter,
          AppSpacing.xxl,
        ),
        children: [
          // The refresh failed but a cached copy is on screen. Say so rather
          // than either hiding it or discarding what we have.
          if (isStale)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: AppBanner(
                icon: Icons.cloud_off_rounded,
                accent: AppColors.warning,
                message:
                    'Showing the details we already had - we could not reach the '
                    'operator just now. The price is confirmed before you book.',
                actionLabel: 'Try again',
                onAction: _refresh,
              ),
            ),

          // --- Photographs --------------------------------------------------
          VehiclePhotoGallery(
            photoUrls: vehicle.photoUrls,
            heroTitle: vehicle.name,
            height: 230,
          ),
          const SizedBox(height: AppSpacing.lg),

          if (!vehicle.hasPhotos)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: AppBanner(
                icon: Icons.photo_camera_back_outlined,
                accent: AppColors.info,
                message:
                    'The operator has not uploaded photographs of this vehicle yet. '
                    'Its specifications below are complete.',
              ),
            ),

          // --- Name and headline facts --------------------------------------
          SectionCard(
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
                          Text(vehicle.name, style: theme.textTheme.titleLarge),
                          const SizedBox(height: 2),
                          Text(
                            vehicle.makeAndModel,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (vehicle.isUnderMaintenance)
                      const InfoPill(
                        icon: Icons.build_rounded,
                        label: 'Under maintenance',
                      )
                    else if (period != null)
                      const InfoPill(
                        icon: Icons.verified_rounded,
                        label: 'Free for your dates',
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    InfoPill(
                      icon: Icons.category_rounded,
                      label: vehicle.categoryLabel,
                    ),
                    InfoPill(
                      icon: Icons.airline_seat_recline_normal_rounded,
                      label: '${vehicle.seatingCapacity} seats',
                    ),
                    InfoPill(
                      icon: Icons.local_gas_station_rounded,
                      label: vehicle.fuelLabel,
                    ),
                    InfoPill(
                      icon: Icons.settings_rounded,
                      label: vehicle.transmissionLabel,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- What it costs ------------------------------------------------
          SectionCard(
            title: 'Price',
            icon: Icons.sell_rounded,
            child: Column(
              children: [
                InfoRow(
                  label: 'Daily rate',
                  value: Formatters.money(vehicle.pricePerDay, symbol: symbol),
                ),
                if (vehicle.pricePerKm != null)
                  InfoRow(
                    label: 'Per kilometre',
                    value: Formatters.money(vehicle.pricePerKm, symbol: symbol),
                  ),
                InfoRow(
                  label: 'Security deposit',
                  value: vehicle.securityDeposit > 0
                      ? '${Formatters.money(vehicle.securityDeposit, symbol: symbol)} (refundable)'
                      : 'None',
                ),
                if (period != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const Divider(height: 1),
                  const SizedBox(height: AppSpacing.sm),
                  InfoRow(
                    label: period.days == 1
                        ? 'Hire charge for 1 day'
                        : 'Hire charge for ${period.days} days',
                    value: Formatters.money(
                      vehicle.pricePerDay * period.days,
                      symbol: symbol,
                    ),
                  ),
                  InfoRow(
                    label: 'Estimated total',
                    value: Formatters.money(
                      vehicle.pricePerDay * period.days +
                          vehicle.securityDeposit,
                      symbol: symbol,
                    ),
                    emphasised: true,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      'The operator confirms the exact total on the next screen.',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Specifications -----------------------------------------------
          SectionCard(
            title: 'Specifications',
            icon: Icons.tune_rounded,
            child: Column(
              children: [
                InfoRow(label: 'Brand', value: vehicle.brand),
                InfoRow(label: 'Model', value: vehicle.model),
                InfoRow(label: 'Year', value: '${vehicle.year}'),
                InfoRow(label: 'Category', value: vehicle.categoryLabel),
                InfoRow(
                  label: 'Seating capacity',
                  value: '${vehicle.seatingCapacity}',
                ),
                InfoRow(label: 'Fuel type', value: vehicle.fuelLabel),
                InfoRow(
                  label: 'Transmission',
                  value: vehicle.transmissionLabel,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Features -----------------------------------------------------
          if (vehicle.features.isNotEmpty) ...[
            SectionCard(
              title: 'Features',
              icon: Icons.checklist_rounded,
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: vehicle.features
                    .map(
                      (feature) =>
                          InfoPill(icon: Icons.check_rounded, label: feature),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          // --- Description --------------------------------------------------
          if (vehicle.description.trim().isNotEmpty) ...[
            SectionCard(
              title: 'About this vehicle',
              icon: Icons.notes_rounded,
              child: Text(
                vehicle.description,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          // --- Dates already taken ------------------------------------------
          _TakenDatesCard(vehicleId: widget.vehicleId),
        ],
      ),
    );
  }

  Widget _buildBottomBar(FleetVehicle vehicle, BookingDraft draft) {
    final theme = Theme.of(context);
    final period = draft.period;
    final symbol = vehicle.currencySymbol;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.pageGutter,
        AppSpacing.md,
        AppSpacing.pageGutter,
        AppSpacing.md + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (period == null)
            PrimaryButton(
              label: 'Choose your dates',
              icon: Icons.event_rounded,
              onPressed: () => context.go(AppRoutes.home),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${Formatters.date(period.startAt)} - ${Formatters.date(period.endAt)}',
                        style: theme.textTheme.labelSmall,
                      ),
                      Text(
                        Formatters.money(
                          vehicle.pricePerDay * period.days +
                              vehicle.securityDeposit,
                          symbol: symbol,
                        ),
                        style: theme.textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
                Text(
                  period.days == 1 ? '1 day' : '${period.days} days',
                  style: theme.textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              label: 'Book this vehicle',
              icon: Icons.event_available_rounded,
              isLoading: _isSelecting,
              onPressed: _isSelecting || vehicle.isUnderMaintenance
                  ? null
                  : () => _selectVehicle(vehicle),
            ),
          ],
        ],
      ),
    );
  }
}

/// The days this vehicle is already let, so a customer can see why a date they
/// wanted was refused - and pick around it.
class _TakenDatesCard extends ConsumerWidget {
  const _TakenDatesCard({required this.vehicleId});

  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(vehicleAvailabilityProvider(vehicleId));

    return state.when(
      loading: () => const SizedBox.shrink(),
      // A failure here costs nothing: the dates are a courtesy, and the quote
      // on the next screen is what actually decides availability.
      error: (_, __) => const SizedBox.shrink(),
      data: (availability) {
        if (availability.underMaintenance) {
          return AppBanner(
            icon: Icons.build_rounded,
            accent: AppColors.warning,
            message:
                'This vehicle is off the road for maintenance and cannot be booked '
                'at the moment.',
          );
        }

        if (availability.takenDays.isEmpty) {
          return SectionCard(
            title: 'Availability',
            icon: Icons.event_available_rounded,
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: AppColors.success,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'This vehicle is free for the next 90 days.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          );
        }

        // Only the next few, in order. A customer planning around a car does
        // not read a list of forty dates.
        final upcoming = [...availability.takenDays]..sort();
        final shown = upcoming.take(12).toList();

        return SectionCard(
          title: 'Already booked on',
          icon: Icons.event_busy_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: shown
                    .map(
                      (day) => InfoPill(
                        icon: Icons.block_rounded,
                        label: _prettyDay(day),
                      ),
                    )
                    .toList(),
              ),
              if (upcoming.length > shown.length)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    'and ${upcoming.length - shown.length} more date'
                    '${upcoming.length - shown.length == 1 ? '' : 's'}.',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// `2026-11-12` -> `12 Nov`. Falls back to the raw key rather than throwing
  /// if the server ever sends something unexpected.
  String _prettyDay(String dayKey) {
    final parsed = DateTime.tryParse(dayKey);
    if (parsed == null) return dayKey;
    return Formatters.date(parsed).replaceAll(RegExp(r' \d{4}$'), '');
  }
}
