import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_config.dart';
import '../../../shared/models/place.dart';
import 'location_service.dart';

/// A search suggestion, before its coordinates have been resolved.
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.title,
    required this.subtitle,
    this.placeId,
    this.resolved,
  });

  final String title;
  final String subtitle;

  /// Google place id, when the suggestion came from Places Autocomplete. The
  /// coordinates then need a second "details" call.
  final String? placeId;

  /// Already-known coordinates, when the suggestion came from the on-device
  /// geocoder and no second call is needed.
  final Place? resolved;

  String get fullAddress => subtitle.isEmpty ? title : '$title, $subtitle';
}

/// Address autocomplete.
///
/// Two backends, chosen by whether a Maps key was supplied at build time:
///
///   - Google Places Autocomplete, which is what customers expect: partial
///     words, business names, ranked by proximity.
///   - The on-device geocoder, which needs no key or network quota but only
///     matches fairly complete addresses.
///
/// Falling back rather than failing means a developer without an API key can
/// still exercise the entire booking flow. [isUsingFallback] lets the UI say so
/// instead of looking broken.
class PlacesService {
  PlacesService({Dio? dio, LocationService? locationService})
      : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 8))),
        _locationService = locationService ?? const LocationService();

  final Dio _dio;
  final LocationService _locationService;

  static const _uuid = Uuid();

  /// Groups the autocomplete keystrokes and the final details call into one
  /// billable session. Without it, Google bills per keystroke.
  String _sessionToken = _uuid.v4();

  bool get isUsingFallback => !AppConfig.enablePlacesAutocomplete;

  /// Starts a new billing session. Call when a search screen opens.
  void newSession() => _sessionToken = _uuid.v4();

  Future<List<PlaceSuggestion>> autocomplete(
    String query, {
    double? latitude,
    double? longitude,
    CancelToken? cancelToken,
  }) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return const [];

    if (isUsingFallback) {
      return _autocompleteWithDeviceGeocoder(trimmed);
    }

    try {
      final response = await _dio.get<dynamic>(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json',
        queryParameters: {
          'input': trimmed,
          'key': AppConfig.googleMapsApiKey,
          'sessiontoken': _sessionToken,
          // Bias toward where the customer is, so "station" means the nearby
          // one rather than one on another continent.
          if (latitude != null && longitude != null) 'location': '$latitude,$longitude',
          if (latitude != null && longitude != null) 'radius': 50000,
        },
        cancelToken: cancelToken,
      );

      final data = response.data;
      if (data is! Map) return const [];

      final status = data['status'];
      if (status != 'OK' && status != 'ZERO_RESULTS') {
        // REQUEST_DENIED usually means the key lacks the Places API, which is
        // a configuration problem the fallback can paper over.
        return _autocompleteWithDeviceGeocoder(trimmed);
      }

      final predictions = data['predictions'];
      if (predictions is! List) return const [];

      return predictions.whereType<Map>().map((prediction) {
        final structured = prediction['structured_formatting'];
        return PlaceSuggestion(
          title: structured is Map
              ? (structured['main_text'] ?? prediction['description'] ?? '') as String
              : (prediction['description'] ?? '') as String,
          subtitle: structured is Map ? (structured['secondary_text'] ?? '') as String : '',
          placeId: prediction['place_id'] as String?,
        );
      }).toList();
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) return const [];
      return _autocompleteWithDeviceGeocoder(trimmed);
    } on Object {
      return const [];
    }
  }

  Future<List<PlaceSuggestion>> _autocompleteWithDeviceGeocoder(String query) async {
    final places = await _locationService.searchByAddress(query);

    return places
        .map((place) => PlaceSuggestion(
              title: place.shortAddress,
              subtitle: place.addressDetail,
              resolved: place,
            ))
        .toList();
  }

  /// Turns a suggestion into a [Place] with coordinates.
  ///
  /// Returns null when the lookup fails, so the caller can tell the customer to
  /// try another result rather than booking a trip to nowhere.
  Future<Place?> resolve(PlaceSuggestion suggestion) async {
    // Device-geocoder suggestions already carry their coordinates.
    final resolved = suggestion.resolved;
    if (resolved != null) return resolved;

    final placeId = suggestion.placeId;
    if (placeId == null || !AppConfig.enablePlacesAutocomplete) return null;

    try {
      final response = await _dio.get<dynamic>(
        'https://maps.googleapis.com/maps/api/place/details/json',
        queryParameters: {
          'place_id': placeId,
          'key': AppConfig.googleMapsApiKey,
          'sessiontoken': _sessionToken,
          // Ask only for what we use; Places bills by field group.
          'fields': 'formatted_address,geometry/location,name',
        },
      );

      final data = response.data;
      if (data is! Map || data['status'] != 'OK') return null;

      final result = data['result'];
      if (result is! Map) return null;

      final location = result['geometry'] is Map
          ? (result['geometry'] as Map)['location']
          : null;
      if (location is! Map) return null;

      final latitude = (location['lat'] as num?)?.toDouble();
      final longitude = (location['lng'] as num?)?.toDouble();
      if (latitude == null || longitude == null) return null;

      // The details call ends the billing session; the next search starts a new one.
      newSession();

      return Place(
        address: (result['formatted_address'] ?? suggestion.fullAddress) as String,
        latitude: latitude,
        longitude: longitude,
        placeId: placeId,
      );
    } on Object {
      return null;
    }
  }
}
