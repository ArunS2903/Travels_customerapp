import 'dart:math' as math;

/// A resolved location: an address string plus coordinates.
///
/// The app never sends an address without coordinates to the backend - the fare
/// depends on the route, and a geocode that failed silently would produce a
/// wrong price. Construction therefore always requires both.
class Place {
  const Place({
    required this.address,
    required this.latitude,
    required this.longitude,
    this.placeId,
    this.label,
  });

  final String address;
  final double latitude;
  final double longitude;

  /// Google Places id, when the address came from autocomplete.
  final String? placeId;

  /// `Home`, `Office`, or a free-form name, when this came from saved addresses.
  final String? label;

  factory Place.fromJson(Map<String, dynamic> json) => Place(
        address: (json['address'] ?? '') as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        placeId: json['placeId'] as String?,
        label: json['label'] as String?,
      );

  /// Shape the backend expects for `pickup` / `destination`.
  Map<String, dynamic> toJson() => {
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        if (placeId != null) 'placeId': placeId,
        if (label != null) 'label': label,
      };

  Place copyWith({
    String? address,
    double? latitude,
    double? longitude,
    String? placeId,
    String? label,
  }) =>
      Place(
        address: address ?? this.address,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        placeId: placeId ?? this.placeId,
        label: label ?? this.label,
      );

  /// First line of the address, for one-line list tiles.
  String get shortAddress {
    final comma = address.indexOf(',');
    return comma > 0 ? address.substring(0, comma).trim() : address;
  }

  /// Everything after the first line.
  String get addressDetail {
    final comma = address.indexOf(',');
    return comma > 0 && comma + 1 < address.length ? address.substring(comma + 1).trim() : '';
  }

  /// True when two places are close enough to be the same spot (~30 m).
  ///
  /// Used to stop the app offering a destination that is where you already are,
  /// and to deduplicate the recent-destinations list, where the same place can
  /// arrive with slightly different coordinates from different sources.
  bool isSameLocationAs(Place other, {double toleranceMetres = 30}) {
    const earthRadiusMetres = 6371000.0;
    final dLat = (other.latitude - latitude) * math.pi / 180;
    final dLng = (other.longitude - longitude) * math.pi / 180;
    final lat1 = latitude * math.pi / 180;
    final lat2 = other.latitude * math.pi / 180;

    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2);
    final distance = 2 * earthRadiusMetres * math.asin(math.min(1, math.sqrt(a)));

    return distance <= toleranceMetres;
  }

  /// Rejects the uninitialised coordinate pair, which otherwise reaches the
  /// backend as a trip to the Gulf of Guinea.
  bool get hasValidCoordinates =>
      !(latitude == 0 && longitude == 0) &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  @override
  bool operator ==(Object other) =>
      other is Place &&
      other.address == address &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(address, latitude, longitude);

  @override
  String toString() => 'Place($address, $latitude, $longitude)';
}
