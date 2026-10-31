// Models for the vehicle catalogue and the per-route fare estimates.
//
// Note what is *not* here: no prices are defined in the app. Every rate,
// multiplier and total below is parsed from the backend, which computes it
// from the administrator's FareRule.

/// The admin's rate card for a category, with no route applied.
class RateCard {
  const RateCard({
    required this.currency,
    required this.currencySymbol,
    required this.baseFare,
    required this.baseDistanceKm,
    required this.perKmRate,
    required this.perMinuteRate,
    required this.minimumFare,
    required this.taxPercent,
    this.waitingChargePerMinute = 0,
    this.freeWaitingMinutes = 0,
    this.surgeMultiplier = 1,
    this.cancellationFee = 0,
    this.freeCancellationMinutes = 0,
  });

  final String currency;
  final String currencySymbol;
  final double baseFare;
  final double baseDistanceKm;
  final double perKmRate;
  final double perMinuteRate;
  final double minimumFare;
  final double taxPercent;
  final double waitingChargePerMinute;
  final double freeWaitingMinutes;
  final double surgeMultiplier;
  final double cancellationFee;
  final double freeCancellationMinutes;

  bool get hasSurge => surgeMultiplier > 1;

  factory RateCard.fromJson(Map<String, dynamic> json) => RateCard(
        currency: (json['currency'] ?? 'INR') as String,
        currencySymbol: (json['currencySymbol'] ?? '') as String,
        baseFare: _toDouble(json['baseFare']),
        baseDistanceKm: _toDouble(json['baseDistanceKm']),
        perKmRate: _toDouble(json['perKmRate']),
        perMinuteRate: _toDouble(json['perMinuteRate']),
        minimumFare: _toDouble(json['minimumFare']),
        taxPercent: _toDouble(json['taxPercent']),
        waitingChargePerMinute: _toDouble(json['waitingChargePerMinute']),
        freeWaitingMinutes: _toDouble(json['freeWaitingMinutes']),
        surgeMultiplier: _toDouble(json['surgeMultiplier'], fallback: 1),
        cancellationFee: _toDouble(json['cancellationFee']),
        freeCancellationMinutes: _toDouble(json['freeCancellationMinutes']),
      );
}

/// One line in the fare breakdown shown on the confirmation screen.
class FareLine {
  const FareLine(this.label, this.amount);
  final String label;
  final double amount;
}

/// The itemised fare, exactly as the server computed it.
class FareBreakdown {
  const FareBreakdown({
    required this.currency,
    required this.currencySymbol,
    required this.baseFare,
    required this.distanceFare,
    required this.timeFare,
    required this.waitingCharge,
    required this.nightSurcharge,
    required this.platformFee,
    required this.additionalCharges,
    required this.surgeMultiplier,
    required this.subtotal,
    required this.minimumFareApplied,
    required this.taxPercent,
    required this.taxAmount,
    required this.total,
  });

  final String currency;
  final String currencySymbol;
  final double baseFare;
  final double distanceFare;
  final double timeFare;
  final double waitingCharge;
  final double nightSurcharge;
  final double platformFee;
  final List<FareLine> additionalCharges;
  final double surgeMultiplier;
  final double subtotal;
  final bool minimumFareApplied;
  final double taxPercent;
  final double taxAmount;
  final double total;

  factory FareBreakdown.fromJson(Map<String, dynamic> json) {
    final extras = json['additionalCharges'];

    return FareBreakdown(
      currency: (json['currency'] ?? 'INR') as String,
      currencySymbol: (json['currencySymbol'] ?? '') as String,
      baseFare: _toDouble(json['baseFare']),
      distanceFare: _toDouble(json['distanceFare']),
      timeFare: _toDouble(json['timeFare']),
      waitingCharge: _toDouble(json['waitingCharge']),
      nightSurcharge: _toDouble(json['nightSurcharge']),
      platformFee: _toDouble(json['platformFee']),
      additionalCharges: extras is List
          ? extras
              .whereType<Map>()
              .map((item) => FareLine(
                    (item['label'] ?? 'Additional charge') as String,
                    _toDouble(item['amount']),
                  ))
              .toList()
          : const [],
      surgeMultiplier: _toDouble(json['surgeMultiplier'], fallback: 1),
      subtotal: _toDouble(json['subtotal']),
      minimumFareApplied: json['minimumFareApplied'] as bool? ?? false,
      taxPercent: _toDouble(json['taxPercent']),
      taxAmount: _toDouble(json['taxAmount']),
      total: _toDouble(json['total']),
    );
  }

  /// The lines worth showing, skipping anything that is zero so the breakdown
  /// does not list five "0" rows.
  List<FareLine> get visibleLines => [
        FareLine('Base fare', baseFare),
        if (distanceFare > 0) FareLine('Distance', distanceFare),
        if (timeFare > 0) FareLine('Time', timeFare),
        if (nightSurcharge > 0) FareLine('Night surcharge', nightSurcharge),
        if (waitingCharge > 0) FareLine('Waiting charge', waitingCharge),
        if (platformFee > 0) FareLine('Booking fee', platformFee),
        ...additionalCharges.where((line) => line.amount > 0),
      ];

  bool get hasSurge => surgeMultiplier > 1;
}

/// The measured route, and whether it came from the Routes API or the fallback.
class RouteInfo {
  const RouteInfo({
    required this.distanceKm,
    required this.durationMinutes,
    required this.isApproximate,
    this.polyline,
    this.source = 'haversine',
  });

  final double distanceKm;
  final int durationMinutes;

  /// True when the backend had no Maps key and used a straight-line estimate.
  /// The UI shows an "approximate" note in that case rather than implying a
  /// precision it does not have.
  final bool isApproximate;

  final String? polyline;
  final String source;

  factory RouteInfo.fromJson(Map<String, dynamic> json) => RouteInfo(
        distanceKm: _toDouble(json['distanceKm']),
        durationMinutes: (json['durationMinutes'] as num?)?.round() ?? 0,
        isApproximate: json['isApproximate'] as bool? ?? true,
        polyline: json['polyline'] as String?,
        source: (json['source'] ?? 'haversine') as String,
      );
}

class CancellationPolicy {
  const CancellationPolicy({required this.fee, required this.freeCancellationMinutes});

  final double fee;
  final double freeCancellationMinutes;

  factory CancellationPolicy.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const CancellationPolicy(fee: 0, freeCancellationMinutes: 0);
    return CancellationPolicy(
      fee: _toDouble(json['fee']),
      freeCancellationMinutes: _toDouble(json['freeCancellationMinutes']),
    );
  }
}

/// A category from `GET /vehicles/types`, before a route is known.
class VehicleType {
  const VehicleType({
    required this.id,
    required this.name,
    required this.code,
    required this.passengerCapacity,
    this.description,
    this.imageUrl,
    this.iconName,
    this.luggageCapacity = 0,
    this.defaultEtaMinutes = 0,
    this.isBookable = true,
    this.rateCard,
  });

  final String id;
  final String name;
  final String code;
  final int passengerCapacity;
  final String? description;
  final String? imageUrl;
  final String? iconName;
  final int luggageCapacity;
  final int defaultEtaMinutes;

  /// False when the admin has not configured pricing for this category. The
  /// list shows it greyed out with a reason rather than hiding it.
  final bool isBookable;

  final RateCard? rateCard;

  factory VehicleType.fromJson(Map<String, dynamic> json) => VehicleType(
        id: json['id'] as String,
        name: (json['name'] ?? '') as String,
        code: (json['code'] ?? '') as String,
        passengerCapacity: (json['passengerCapacity'] as num?)?.toInt() ?? 4,
        description: json['description'] as String?,
        imageUrl: json['imageUrl'] as String?,
        iconName: json['iconName'] as String?,
        luggageCapacity: (json['luggageCapacity'] as num?)?.toInt() ?? 0,
        defaultEtaMinutes: (json['defaultEtaMinutes'] as num?)?.toInt() ?? 0,
        isBookable: json['isBookable'] as bool? ?? true,
        rateCard: json['rateCard'] is Map
            ? RateCard.fromJson(Map<String, dynamic>.from(json['rateCard'] as Map))
            : null,
      );
}

/// A category priced for a specific route - one row in the vehicle selector.
class VehicleEstimate {
  const VehicleEstimate({
    required this.vehicleType,
    required this.isAvailable,
    this.unavailableReason,
    this.etaMinutes,
    this.fare,
    this.cancellationPolicy,
  });

  final VehicleType vehicleType;

  /// False when this category cannot be booked for this route right now.
  final bool isAvailable;
  final String? unavailableReason;

  final int? etaMinutes;

  /// Null when [isAvailable] is false.
  final FareBreakdown? fare;

  final CancellationPolicy? cancellationPolicy;

  String get id => vehicleType.id;

  factory VehicleEstimate.fromJson(Map<String, dynamic> json) {
    final rawFare = json['fare'];
    final breakdown = rawFare is Map && rawFare['breakdown'] is Map
        ? FareBreakdown.fromJson(Map<String, dynamic>.from(rawFare['breakdown'] as Map))
        : null;

    return VehicleEstimate(
      // The estimate response inlines the vehicle fields alongside the fare.
      vehicleType: VehicleType.fromJson(json),
      isAvailable: json['isAvailable'] as bool? ?? false,
      unavailableReason: json['unavailableReason'] as String?,
      etaMinutes: (json['etaMinutes'] as num?)?.toInt(),
      fare: breakdown,
      cancellationPolicy: json['cancellationPolicy'] is Map
          ? CancellationPolicy.fromJson(
              Map<String, dynamic>.from(json['cancellationPolicy'] as Map))
          : null,
    );
  }
}

/// The whole response from `POST /fares/estimate` without a vehicleTypeId.
class FareEstimateResult {
  const FareEstimateResult({
    required this.route,
    required this.estimates,
    required this.disclaimer,
    required this.quotedAt,
  });

  final RouteInfo route;
  final List<VehicleEstimate> estimates;

  /// The server's own wording about these being estimates. Displayed verbatim
  /// so the disclaimer the operator is held to is the one the customer reads.
  final String disclaimer;

  final DateTime quotedAt;

  factory FareEstimateResult.fromJson(Map<String, dynamic> json) {
    final rawEstimates = json['estimates'];

    return FareEstimateResult(
      route: RouteInfo.fromJson(Map<String, dynamic>.from(json['route'] as Map)),
      estimates: rawEstimates is List
          ? rawEstimates
              .whereType<Map>()
              .map((item) => VehicleEstimate.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : const [],
      disclaimer: (json['disclaimer'] ?? 'Fares shown are estimates.') as String,
      quotedAt: json['quotedAt'] is String
          ? (DateTime.tryParse(json['quotedAt'] as String) ?? DateTime.now())
          : DateTime.now(),
    );
  }

  List<VehicleEstimate> get available => estimates.where((e) => e.isAvailable).toList();

  /// The cheapest bookable option, pre-selected when the screen opens.
  VehicleEstimate? get cheapest {
    final bookable = available.where((e) => e.fare != null).toList();
    if (bookable.isEmpty) return null;
    bookable.sort((a, b) => a.fare!.total.compareTo(b.fare!.total));
    return bookable.first;
  }
}

double _toDouble(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}
