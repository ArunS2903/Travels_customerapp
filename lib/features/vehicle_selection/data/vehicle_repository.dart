import 'package:dio/dio.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/place.dart';
import '../models/vehicle_estimate.dart';

/// Vehicle catalogue and fare estimation.
class VehicleRepository {
  const VehicleRepository(this._client);

  final ApiClient _client;

  /// The categories and their rate cards, with no route applied.
  Future<List<VehicleType>> fetchVehicleTypes({CancelToken? cancelToken}) async {
    final data = await _client.get(ApiEndpoints.vehicleTypes, cancelToken: cancelToken);
    final items = data['items'];

    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((item) => VehicleType.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  /// Prices every active category for one route.
  ///
  /// Takes a [CancelToken] because the customer can change the destination
  /// while a quote is in flight; the vehicle selection controller cancels the
  /// stale request rather than letting a late response overwrite a newer one.
  Future<FareEstimateResult> estimateAll({
    required Place pickup,
    required Place destination,
    CancelToken? cancelToken,
  }) async {
    final data = await _client.post(
      ApiEndpoints.fareEstimate,
      body: {'pickup': pickup.toJson(), 'destination': destination.toJson()},
      cancelToken: cancelToken,
    );
    return FareEstimateResult.fromJson(data);
  }

  /// Re-prices a single category, used on the confirmation screen to refresh a
  /// quote that has been on screen long enough to go stale.
  Future<VehicleEstimate> estimateOne({
    required String vehicleTypeId,
    required Place pickup,
    required Place destination,
    CancelToken? cancelToken,
  }) async {
    final data = await _client.post(
      ApiEndpoints.fareEstimate,
      body: {
        'vehicleTypeId': vehicleTypeId,
        'pickup': pickup.toJson(),
        'destination': destination.toJson(),
      },
      cancelToken: cancelToken,
    );

    // The single-vehicle response splits the vehicle and the fare, so rebuild
    // the flat shape VehicleEstimate expects from the list endpoint.
    final vehicleJson = Map<String, dynamic>.from(data['vehicleType'] as Map);
    final fareJson = data['fare'] is Map ? Map<String, dynamic>.from(data['fare'] as Map) : null;

    return VehicleEstimate.fromJson({
      ...vehicleJson,
      'isAvailable': true,
      'etaMinutes': vehicleJson['defaultEtaMinutes'],
      'fare': fareJson,
      'cancellationPolicy': data['cancellationPolicy'],
    });
  }
}
