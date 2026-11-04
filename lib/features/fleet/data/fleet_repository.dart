import 'package:dio/dio.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/paginated_result.dart';
import '../models/fleet_vehicle.dart';

/// The fleet, and what hiring one of it would cost.
///
/// Every availability decision here is the server's. The app never decides a
/// vehicle is free: it asks for the vehicles free over a period, and asks again
/// for a quote before the customer commits, because another customer may have
/// taken the car between the two.
class FleetRepository {
  const FleetRepository(this._client);

  final ApiClient _client;

  /// The vehicles actually free for [period], newest-cheapest first.
  ///
  /// The period is sent as both ends or neither - the backend ignores a single
  /// one rather than guessing - which is why [HirePeriod] carries the pair.
  Future<PaginatedResult<FleetVehicle>> fetchAvailableVehicles({
    required HirePeriod period,
    String? category,
    int page = 1,
    int limit = 20,
    String sortBy = 'pricePerDay',
    String sortDir = 'asc',
    CancelToken? cancelToken,
  }) async {
    final data = await _client.get(
      ApiEndpoints.vehicles,
      query: {
        ...period.toQuery(),
        if (category != null && category.isNotEmpty) 'category': category,
        'page': page,
        'limit': limit,
        'sortBy': sortBy,
        'sortDir': sortDir,
      },
      cancelToken: cancelToken,
    );

    return PaginatedResult.fromJson(data, FleetVehicle.fromJson);
  }

  /// The whole fleet, with no dates applied. Used where there is no period yet.
  Future<PaginatedResult<FleetVehicle>> fetchVehicles({
    String? category,
    bool availableOnly = true,
    int page = 1,
    int limit = 20,
    CancelToken? cancelToken,
  }) async {
    final data = await _client.get(
      ApiEndpoints.vehicles,
      query: {
        if (category != null && category.isNotEmpty) 'category': category,
        if (availableOnly) 'availableOnly': true,
        'page': page,
        'limit': limit,
      },
      cancelToken: cancelToken,
    );

    return PaginatedResult.fromJson(data, FleetVehicle.fromJson);
  }

  /// One vehicle with its full photo set, for the details screen.
  Future<FleetVehicle> fetchVehicle(String vehicleId, {CancelToken? cancelToken}) async {
    final data = await _client.get(ApiEndpoints.vehicle(vehicleId), cancelToken: cancelToken);
    return FleetVehicle.fromJson(Map<String, dynamic>.from(data['vehicle'] as Map));
  }

  /// Which days a vehicle is already taken, so a date picker can grey them out.
  Future<VehicleAvailability> fetchAvailability(
    String vehicleId, {
    DateTime? from,
    DateTime? to,
    CancelToken? cancelToken,
  }) async {
    final data = await _client.get(
      ApiEndpoints.vehicleAvailability(vehicleId),
      query: {
        if (from != null) 'from': from.toUtc().toIso8601String(),
        if (to != null) 'to': to.toUtc().toIso8601String(),
      },
      cancelToken: cancelToken,
    );

    return VehicleAvailability.fromJson(data);
  }

  /// Prices a hire without creating anything.
  ///
  /// Called again on the confirmation screen rather than trusting the figure
  /// from the list, because this is the same code path that prices the booking
  /// itself - the number shown and the number charged cannot diverge.
  Future<HireQuote> quoteHire({
    required String vehicleId,
    required HirePeriod period,
    CancelToken? cancelToken,
  }) async {
    final data = await _client.post(
      ApiEndpoints.hireQuote,
      body: {
        'vehicleId': vehicleId,
        'startAt': period.startAt.toUtc().toIso8601String(),
        'endAt': period.endAt.toUtc().toIso8601String(),
      },
      cancelToken: cancelToken,
    );

    return HireQuote.fromJson(data);
  }
}
