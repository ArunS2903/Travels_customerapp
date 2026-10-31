import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Decodes Google's encoded polyline format into map points.
///
/// Written out rather than pulled in as a package: it is twenty lines, and the
/// backend already returns the encoded string from the Routes API so this is
/// the only place the format is touched.
///
/// Format reference: each coordinate is stored as a signed, zig-zag encoded
/// delta from the previous one, in 5-bit chunks with a continuation bit.
class PolylineDecoder {
  const PolylineDecoder._();

  static List<LatLng> decode(String? encoded) {
    if (encoded == null || encoded.isEmpty) return const [];

    final points = <LatLng>[];
    int index = 0;
    int latitude = 0;
    int longitude = 0;

    while (index < encoded.length) {
      final latDelta = _decodeValue(encoded, index);
      if (latDelta == null) break;
      index = latDelta.nextIndex;
      latitude += latDelta.value;

      final lngDelta = _decodeValue(encoded, index);
      if (lngDelta == null) break;
      index = lngDelta.nextIndex;
      longitude += lngDelta.value;

      points.add(LatLng(latitude / 1e5, longitude / 1e5));
    }

    return points;
  }

  static _Decoded? _decodeValue(String encoded, int startIndex) {
    int index = startIndex;
    int shift = 0;
    int result = 0;
    int byte;

    do {
      if (index >= encoded.length) return null;
      byte = encoded.codeUnitAt(index) - 63;
      index++;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);

    // Undo the zig-zag encoding: odd values are negative.
    final value = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    return _Decoded(value, index);
  }

  /// Bounds that fit every point, with a little padding so markers at the edge
  /// are not flush against the map frame.
  static LatLngBounds? boundsFor(List<LatLng> points, {double padding = 0.004}) {
    if (points.isEmpty) return null;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat - padding, minLng - padding),
      northeast: LatLng(maxLat + padding, maxLng + padding),
    );
  }
}

class _Decoded {
  const _Decoded(this.value, this.nextIndex);
  final int value;
  final int nextIndex;
}
