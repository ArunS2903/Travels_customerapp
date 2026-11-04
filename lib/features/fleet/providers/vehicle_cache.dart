import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fleet_vehicle.dart';

/// The vehicles the app has already loaded, kept by id.
///
/// Why this exists
/// ---------------
/// The available-vehicles list and the details screen show the same objects,
/// but the details screen fetches by id so that a deep link works. On a remote
/// database that fetch is a few hundred milliseconds, and it used to be the
/// *only* source for the screen — so tapping a vehicle the app had just
/// rendered produced a full-page spinner, and going back and forward produced
/// another. The data was in memory the whole time.
///
/// So the list writes what it rendered here, and the details screen paints from
/// it immediately while the network read refreshes underneath. The fetch is not
/// skipped: a cached vehicle may be minutes old, and the price and photographs
/// are the operator's to change. This only removes the blank screen in front of
/// an answer the app already had.
///
/// Deliberately *not* `autoDispose`. A cache that is thrown away on navigation
/// is not a cache, and the entries are small — a handful of strings and a list
/// of URLs per vehicle, with no decoded images (those live in Flutter's own
/// image cache).
class VehicleCache extends StateNotifier<Map<String, FleetVehicle>> {
  VehicleCache() : super(const {});

  /// How many vehicles to remember.
  ///
  /// Bounded because nothing else evicts: a customer who browses a large fleet
  /// over a long session would otherwise accumulate every vehicle they looked
  /// at. The oldest entries go first, which is the right order — the one just
  /// tapped is the one about to be needed.
  static const int maxEntries = 60;

  FleetVehicle? operator [](String id) => state[id];

  void put(FleetVehicle vehicle) => putAll([vehicle]);

  /// Adds a page of vehicles in one state change.
  ///
  /// One write rather than one per vehicle, so rendering a page of twenty does
  /// not notify every listener twenty times.
  void putAll(Iterable<FleetVehicle> vehicles) {
    if (vehicles.isEmpty) return;

    final next = {...state};
    for (final vehicle in vehicles) {
      if (vehicle.id.isEmpty) continue;
      // Removed first so a re-put moves the entry to the end, making the map's
      // insertion order a least-recently-written order for the trim below.
      next.remove(vehicle.id);
      next[vehicle.id] = vehicle;
    }

    if (next.length > maxEntries) {
      final trimmed = next.entries.skip(next.length - maxEntries);
      state = Map.fromEntries(trimmed);
      return;
    }

    state = next;
  }
}

final vehicleCacheProvider =
    StateNotifierProvider<VehicleCache, Map<String, FleetVehicle>>(
  (ref) => VehicleCache(),
);

/// The cached vehicle for an id, or null. Read for a first paint, never relied
/// on as the final answer.
final cachedVehicleProvider = Provider.family<FleetVehicle?, String>(
  (ref, vehicleId) => ref.watch(vehicleCacheProvider)[vehicleId],
);
