import 'package:url_launcher/url_launcher.dart';

/// Opens an external maps application for a route or a point.
///
/// Why the universal `https://www.google.com/maps/...` URL comes first
/// -------------------------------------------------------------------
/// It is the one form that works everywhere. On Android and iOS with Google
/// Maps installed it is an app link, so the OS hands it straight to the app
/// without a browser flash; without the app it opens the same route in a
/// browser, which is still a usable map. The `geo:` and `comgooglemaps:`
/// schemes open the app a fraction sooner but fail outright when nothing
/// handles them, and `geo:` cannot express an origin at all - it can only drop
/// a pin - which is exactly the thing a route needs.
///
/// So the universal URL is the primary and `geo:` is the fallback for a device
/// whose browser is disabled.
class MapsLauncher {
  const MapsLauncher._();

  /// Opens turn-by-turn directions from [originLatitude]/[originLongitude] to
  /// the destination.
  ///
  /// Leaving the origin null is meaningful, not merely permitted: Google Maps
  /// then plots the route from wherever the device is *at the moment the map
  /// opens*, which is more useful than a fix this app took a minute ago and is
  /// the right behaviour when the customer has declined location permission.
  /// That is why a missing location degrades to a working route rather than an
  /// error.
  static Future<bool> openDirections({
    required double destinationLatitude,
    required double destinationLongitude,
    String? destinationLabel,
    double? originLatitude,
    double? originLongitude,
  }) async {
    final hasOrigin = originLatitude != null && originLongitude != null;

    final universal = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      if (hasOrigin) 'origin': '$originLatitude,$originLongitude',
      'destination': '$destinationLatitude,$destinationLongitude',
      'travelmode': 'driving',
      // Opens straight into the navigation view rather than the route preview.
      'dir_action': 'navigate',
    });

    if (await _tryLaunch(universal)) return true;

    // `geo:` cannot carry an origin, so this loses the "from here" part of the
    // request. It keeps the destination, which is the half that matters.
    final label = Uri.encodeComponent(destinationLabel ?? 'Drop location');
    final geo = Uri.parse(
      'geo:$destinationLatitude,$destinationLongitude'
      '?q=$destinationLatitude,$destinationLongitude($label)',
    );

    return _tryLaunch(geo);
  }

  /// Opens a single point on a map, with no route.
  static Future<bool> openPlace({
    required double latitude,
    required double longitude,
    String? label,
  }) async {
    final universal = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '$latitude,$longitude',
    });

    if (await _tryLaunch(universal)) return true;

    final encoded = Uri.encodeComponent(label ?? 'Location');
    return _tryLaunch(Uri.parse('geo:$latitude,$longitude?q=$latitude,$longitude($encoded)'));
  }

  /// `launchUrl` both returns false and throws, depending on the platform and
  /// on which part of the handoff failed, so both are treated as "did not
  /// open" and the caller gets one boolean to branch on.
  static Future<bool> _tryLaunch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }
}
