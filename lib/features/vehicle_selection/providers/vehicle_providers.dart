import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../models/vehicle_estimate.dart';

/// The vehicle catalogue: the bookable categories and their rate cards, with no
/// route and no dates applied.
///
/// Used by the home screen's category strip, which shows the *kinds* of vehicle
/// the operator runs. It is not what a booking is made against - a booking is
/// one specific car, chosen from the fleet for a set of dates, which lives in
/// `features/fleet`. This exists so the home screen has something to show
/// before the customer has picked a date.
final vehicleTypesProvider = FutureProvider<List<VehicleType>>(
  (ref) => ref.watch(vehicleRepositoryProvider).fetchVehicleTypes(),
);
