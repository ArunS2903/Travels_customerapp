import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../shared/models/paginated_result.dart';
import '../models/fleet_vehicle.dart';
import 'vehicle_cache.dart';

/// The vehicles free for a period.
///
/// Keyed on the period so changing the dates is a different request rather than
/// a mutation: a customer who moves the dates back and forth gets the cached
/// list for each, and a late reply for the old dates can never land on the new
/// ones. `autoDispose` so the list is re-read when they come back to it, which
/// matters here - another customer may have taken a car in the meantime.
final availableVehiclesProvider = FutureProvider.autoDispose
    .family<PaginatedResult<FleetVehicle>, HirePeriod>((ref, period) async {
  final cancelToken = CancelToken();
  ref.onDispose(() => cancelToken.cancel('availableVehiclesProvider disposed'));

  final page = await ref
      .watch(fleetRepositoryProvider)
      .fetchAvailableVehicles(period: period, limit: 50, cancelToken: cancelToken);

  /// Warm the cache so opening any of these renders instantly.
  ///
  /// Done here rather than in the list widget's build, because a build may run
  /// many times for one fetch and must not have side effects.
  ref.read(vehicleCacheProvider.notifier).putAll(page.items);

  return page;
});

/// One vehicle with its full photo set.
///
/// Fetched by id rather than passed through the route, so the details screen
/// works from a deep link or after the process is restarted - and so it always
/// shows the current photographs rather than whatever the list happened to
/// carry.
///
/// The screen does not *wait* on this when the vehicle is already in
/// [vehicleCacheProvider]: it paints the cached copy and lets this refresh it.
/// See `VehicleDetailsScreen`.
final vehicleDetailProvider =
    FutureProvider.autoDispose.family<FleetVehicle, String>((ref, vehicleId) async {
  final cancelToken = CancelToken();
  ref.onDispose(() => cancelToken.cancel('vehicleDetailProvider disposed'));

  final vehicle = await ref
      .watch(fleetRepositoryProvider)
      .fetchVehicle(vehicleId, cancelToken: cancelToken);

  // The freshest copy there is, so the list and any other screen showing this
  // vehicle pick it up too.
  ref.read(vehicleCacheProvider.notifier).put(vehicle);

  return vehicle;
});

/// Which days a vehicle is already taken, for the date picker on its details
/// screen.
final vehicleAvailabilityProvider =
    FutureProvider.autoDispose.family<VehicleAvailability, String>((ref, vehicleId) async {
  final cancelToken = CancelToken();
  ref.onDispose(() => cancelToken.cancel('vehicleAvailabilityProvider disposed'));

  final now = DateTime.now();

  return ref.watch(fleetRepositoryProvider).fetchAvailability(
        vehicleId,
        from: now,
        // The backend's own default window, stated here so the calendar and the
        // request agree about how far ahead "taken" is known.
        to: now.add(const Duration(days: 90)),
        cancelToken: cancelToken,
      );
});

/// Identifies one quote request: a vehicle and a period.
class HireQuoteRequest {
  const HireQuoteRequest({required this.vehicleId, required this.period});

  final String vehicleId;
  final HirePeriod period;

  @override
  bool operator ==(Object other) =>
      other is HireQuoteRequest && other.vehicleId == vehicleId && other.period == period;

  @override
  int get hashCode => Object.hash(vehicleId, period);
}

/// What this vehicle costs for these dates, and whether it is still free.
///
/// The confirmation screen watches this rather than reusing the figure from the
/// list, because the list may be minutes old and the car may have gone. The
/// response carries `isAvailable`, which is how the screen knows to refuse
/// rather than submit a booking that would be rejected.
final hireQuoteProvider =
    FutureProvider.autoDispose.family<HireQuote, HireQuoteRequest>((ref, request) async {
  final cancelToken = CancelToken();
  ref.onDispose(() => cancelToken.cancel('hireQuoteProvider disposed'));

  return ref.watch(fleetRepositoryProvider).quoteHire(
        vehicleId: request.vehicleId,
        period: request.period,
        cancelToken: cancelToken,
      );
});
