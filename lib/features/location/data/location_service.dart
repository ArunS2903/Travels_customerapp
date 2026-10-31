import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../../../shared/models/place.dart';

/// Why we cannot provide a location. Each value maps to a different thing the
/// customer can actually do about it, which is the point of distinguishing them
/// rather than returning one "failed" state.
enum LocationFailure {
  /// The customer said no, but can be asked again.
  permissionDenied,

  /// Denied with "don't ask again" - only the system settings can fix it.
  permissionDeniedForever,

  /// Location services are switched off device-wide.
  serviceDisabled,

  /// We asked and got nothing back in time.
  timeout,

  unknown,
}

class LocationException implements Exception {
  const LocationException(this.failure, this.message);

  final LocationFailure failure;
  final String message;

  /// True when sending the customer to system settings is the fix.
  bool get requiresSettings => failure == LocationFailure.permissionDeniedForever;

  /// True when asking again might work.
  bool get isRetryable =>
      failure == LocationFailure.timeout ||
      failure == LocationFailure.unknown ||
      failure == LocationFailure.permissionDenied;

  @override
  String toString() => 'LocationException($failure): $message';
}

/// Device location and address lookup.
///
/// Every failure is an explicit [LocationException] with a cause, because the
/// booking flow has to stay usable when location is unavailable: the home
/// screen falls back to letting the customer search or drop a pin, and never
/// dead-ends on a spinner.
class LocationService {
  const LocationService();

  static const Duration _fixTimeout = Duration(seconds: 12);

  /// Checks services and permission, prompting if we have not asked yet.
  Future<void> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(
        LocationFailure.serviceDisabled,
        'Location services are turned off. Switch them on to use your current location.',
      );
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        LocationFailure.permissionDeniedForever,
        'Location access is blocked for this app. You can allow it in your device settings, '
        'or set your pickup manually.',
      );
    }

    if (permission == LocationPermission.denied) {
      throw const LocationException(
        LocationFailure.permissionDenied,
        'We need location access to find your pickup point. You can also set it manually.',
      );
    }
  }

  /// Current position, with a bounded wait.
  ///
  /// `medium` accuracy rather than `best`: a street-level fix in two seconds is
  /// more useful for hailing a taxi than a doorstep-accurate one in fifteen,
  /// and the customer confirms the pin anyway.
  Future<Position> getCurrentPosition() async {
    await ensurePermission();

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: _fixTimeout,
        ),
      );
    } on LocationServiceDisabledException {
      throw const LocationException(
        LocationFailure.serviceDisabled,
        'Location services were turned off. Switch them on and try again.',
      );
    } on Object catch (error) {
      // geolocator throws TimeoutException on time limit, and platform
      // exceptions for a handful of transient conditions.
      if (error.toString().toLowerCase().contains('timeout')) {
        // A last known position beats nothing at all.
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) return lastKnown;

        throw const LocationException(
          LocationFailure.timeout,
          'We could not get a location fix. Move somewhere with a clearer view of the sky, '
          'or set your pickup manually.',
        );
      }

      throw LocationException(
        LocationFailure.unknown,
        'We could not read your location. Please set your pickup manually.',
      );
    }
  }

  /// Current position as a [Place], with the address filled in where possible.
  ///
  /// A failed reverse geocode is not a failed location: we keep the coordinates
  /// and label them, because the fare depends on the coordinates and not on the
  /// prettiness of the address string.
  Future<Place> getCurrentPlace() async {
    final position = await getCurrentPosition();

    final address = await reverseGeocode(
      latitude: position.latitude,
      longitude: position.longitude,
    );

    return Place(
      address: address ??
          'Current location (${position.latitude.toStringAsFixed(5)}, '
              '${position.longitude.toStringAsFixed(5)})',
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }

  /// Coordinates to a human address, using the on-device geocoder.
  ///
  /// Returns null rather than throwing: an address is a nicety, and the caller
  /// always has the coordinates it actually needs.
  Future<String?> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isEmpty) return null;
      return formatPlacemark(placemarks.first);
    } on Object {
      return null;
    }
  }

  /// Address text to coordinates, for the fallback search path.
  Future<List<Place>> searchByAddress(String query) async {
    if (query.trim().length < 3) return const [];

    try {
      final locations = await locationFromAddress(query);

      // The device geocoder returns coordinates but no tidy address, so label
      // each hit by reverse-geocoding it back.
      final results = <Place>[];
      for (final location in locations.take(5)) {
        final address = await reverseGeocode(
          latitude: location.latitude,
          longitude: location.longitude,
        );
        results.add(Place(
          address: address ?? query.trim(),
          latitude: location.latitude,
          longitude: location.longitude,
        ));
      }
      return results;
    } on Object {
      return const [];
    }
  }

  /// Builds a readable one-line address, skipping the empty and duplicated
  /// fields the platform geocoders are generous with.
  static String formatPlacemark(Placemark placemark) {
    final parts = <String>[
      placemark.name ?? '',
      placemark.subLocality ?? '',
      placemark.locality ?? '',
      placemark.administrativeArea ?? '',
      placemark.postalCode ?? '',
    ];

    final seen = <String>{};
    final cleaned = <String>[];

    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      // `name` is often the street number and `thoroughfare` the same street.
      if (!seen.add(trimmed.toLowerCase())) continue;
      cleaned.add(trimmed);
    }

    return cleaned.isEmpty ? 'Unnamed location' : cleaned.join(', ');
  }

  /// Opens the system settings page, for a permanently denied permission.
  Future<void> openSettings() => Geolocator.openAppSettings();

  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}
