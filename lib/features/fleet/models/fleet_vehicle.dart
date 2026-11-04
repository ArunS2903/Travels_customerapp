// The fleet: individual vehicles the operator owns, as the customer app reads
// them from `GET /vehicles`.
//
// Note what is *not* here: no prices are defined in the app. The daily rate,
// the deposit and the total all come from the backend, which reads them from
// the admin's Vehicle Collection.

/// A period a customer wants a vehicle for.
///
/// A value type with equality, because it is the key of the provider family
/// that loads the available vehicles - two rebuilds asking for the same dates
/// must hit the same cached request rather than re-fetching the list.
class HirePeriod {
  const HirePeriod({required this.startAt, required this.endAt});

  final DateTime startAt;
  final DateTime endAt;

  /// Billable days, mirroring `billableDays` in the backend's hire service.
  ///
  /// Recomputed here only to label the UI before a quote arrives. The number
  /// that is charged is always the server's, which is why the quote is fetched
  /// before anything is committed.
  int get days {
    final elapsed = endAt.difference(startAt);
    if (elapsed.inMinutes <= 0) return 1;

    // The same 15-minute grace the server forgives, so the day count shown
    // while the customer moves the dates matches the one it quotes back.
    final chargeable = elapsed - const Duration(minutes: 15);
    if (chargeable.inMilliseconds <= 0) return 1;

    final wholeDays = chargeable.inMilliseconds / Duration.millisecondsPerDay;
    return wholeDays.ceil().clamp(1, 90);
  }

  bool get isValid => endAt.isAfter(startAt);

  Map<String, String> toQuery() => {
        'availableFrom': startAt.toUtc().toIso8601String(),
        'availableTo': endAt.toUtc().toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      other is HirePeriod && other.startAt == startAt && other.endAt == endAt;

  @override
  int get hashCode => Object.hash(startAt, endAt);

  @override
  String toString() => 'HirePeriod(${startAt.toIso8601String()}..${endAt.toIso8601String()})';
}

/// One photograph of a vehicle, as uploaded by the admin.
class VehiclePhoto {
  const VehiclePhoto({required this.url, this.isPrimary = false, this.sortOrder = 0});

  final String url;

  /// The cover image. Exactly one photo per vehicle carries this, enforced
  /// server-side, so it is safe to rely on for a list thumbnail.
  final bool isPrimary;

  final int sortOrder;

  factory VehiclePhoto.fromJson(Map<String, dynamic> json) => VehiclePhoto(
        url: (json['url'] ?? '') as String,
        isPrimary: json['isPrimary'] as bool? ?? false,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      );
}

/// A specific vehicle in the fleet - a car with photographs and a daily rate,
/// not a category.
class FleetVehicle {
  const FleetVehicle({
    required this.id,
    required this.name,
    required this.brand,
    required this.model,
    required this.year,
    required this.category,
    required this.seatingCapacity,
    required this.fuelType,
    required this.transmission,
    required this.pricePerDay,
    this.description = '',
    this.features = const [],
    this.pricePerKm,
    this.securityDeposit = 0,
    this.currency = 'INR',
    this.currencySymbol = '',
    this.availabilityStatus = '',
    this.isAvailable = true,
    this.photos = const [],
    this.primaryImageUrl,
    this.isAvailableForPeriod,
  });

  final String id;
  final String name;
  final String brand;
  final String model;
  final int year;

  /// `car`, `suv`, `van`, `bus`, `bike`, `tempo` - the stored key, lowercase.
  final String category;

  final int seatingCapacity;
  final String fuelType;
  final String transmission;
  final String description;
  final List<String> features;

  final double pricePerDay;

  /// Null when this vehicle is not rented by distance.
  final double? pricePerKm;

  /// Refundable, and quoted separately from the hire charge.
  final double securityDeposit;

  final String currency;
  final String currencySymbol;

  /// `available`, `booked` or `under_maintenance` - the vehicle's own flag,
  /// which answers "is this car committed to anybody" rather than "is it free
  /// on my dates". For a date question, see [isAvailableForPeriod].
  final String availabilityStatus;

  final bool isAvailable;

  final List<VehiclePhoto> photos;
  final String? primaryImageUrl;

  /// True when the backend confirmed this vehicle is free for the dates that
  /// were asked about. Null when no period was sent.
  final bool? isAvailableForPeriod;

  bool get isUnderMaintenance => availabilityStatus == 'under_maintenance';

  /// Cover first, then the admin's own order, so a gallery opens on the photo
  /// the operator chose as the face of the vehicle.
  List<String> get photoUrls {
    final sorted = [...photos]..sort((a, b) {
      if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
      return a.sortOrder.compareTo(b.sortOrder);
    });

    final urls = sorted.map((photo) => photo.url).where((url) => url.isNotEmpty).toList();

    // A vehicle whose cover came through without the gallery still shows one.
    if (urls.isEmpty && (primaryImageUrl ?? '').isNotEmpty) return [primaryImageUrl!];
    return urls;
  }

  String? get coverUrl => photoUrls.isEmpty ? primaryImageUrl : photoUrls.first;

  bool get hasPhotos => photoUrls.isNotEmpty;

  /// `Maruti Swift Dzire 2022`, for a subtitle under the display name.
  String get makeAndModel => [brand, model, '$year'].where((part) => part.isNotEmpty).join(' ');

  /// `Car`, `SUV` - the label for the stored key.
  ///
  /// Spelt out rather than derived by capitalising, for the same reason the
  /// backend's `VEHICLE_CATEGORY_LABELS` is: `SUV` is an acronym and `Car` is a
  /// word, and no rule based on length tells them apart.
  String get categoryLabel {
    switch (category) {
      case 'car':
        return 'Car';
      case 'suv':
        return 'SUV';
      case 'van':
        return 'Van';
      case 'bus':
        return 'Bus';
      case 'bike':
        return 'Bike';
      case 'tempo':
        return 'Tempo';
      default:
        return category.isEmpty
            ? 'Vehicle'
            : category[0].toUpperCase() + category.substring(1);
    }
  }

  String get fuelLabel => _titleCase(fuelType);
  String get transmissionLabel => _titleCase(transmission);

  factory FleetVehicle.fromJson(Map<String, dynamic> json) {
    final images = json['images'];
    final features = json['features'];

    return FleetVehicle(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      brand: (json['brand'] ?? '') as String,
      model: (json['model'] ?? '') as String,
      year: (json['year'] as num?)?.toInt() ?? 0,
      category: (json['category'] ?? '') as String,
      seatingCapacity: (json['seatingCapacity'] as num?)?.toInt() ?? 0,
      fuelType: (json['fuelType'] ?? '') as String,
      transmission: (json['transmission'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      features: features is List ? features.map((item) => '$item').toList() : const [],
      pricePerDay: (json['pricePerDay'] as num?)?.toDouble() ?? 0,
      pricePerKm: (json['pricePerKm'] as num?)?.toDouble(),
      securityDeposit: (json['securityDeposit'] as num?)?.toDouble() ?? 0,
      currency: (json['currency'] ?? 'INR') as String,
      currencySymbol: (json['currencySymbol'] ?? '') as String,
      availabilityStatus: (json['availabilityStatus'] ?? '') as String,
      isAvailable: json['isAvailable'] as bool? ?? true,
      photos: images is List
          ? images
              .whereType<Map>()
              .map((item) => VehiclePhoto.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : const [],
      primaryImageUrl: json['primaryImageUrl'] as String?,
      isAvailableForPeriod: json['isAvailableForPeriod'] as bool?,
    );
  }
}

/// What a hire would cost, and whether the vehicle is actually free for it.
///
/// Returned by `POST /bookings/quote`. An unavailable vehicle is a successful
/// response with [isAvailable] false and the clashing dates listed, not an
/// error - "that car is taken on the 13th" is an answer.
class HireQuote {
  const HireQuote({
    required this.vehicle,
    required this.startAt,
    required this.endAt,
    required this.days,
    required this.dailyRate,
    required this.hireCharge,
    required this.securityDeposit,
    required this.amountDue,
    required this.currency,
    required this.currencySymbol,
    required this.isAvailable,
    this.conflictingDays = const [],
    this.paymentMethods = const [],
  });

  final FleetVehicle vehicle;
  final DateTime startAt;
  final DateTime endAt;

  /// Billable days as the server counted them. This is the multiplier the
  /// customer is shown and the one stored on the booking.
  final int days;

  final double dailyRate;
  final double hireCharge;

  /// Refundable, and separate from [hireCharge] so the UI can say so.
  final double securityDeposit;

  /// The one number the customer is asked to pay: charge plus deposit.
  final double amountDue;

  final String currency;
  final String currencySymbol;

  final bool isAvailable;

  /// `YYYY-MM-DD` days some other booking already holds.
  final List<String> conflictingDays;

  /// The payment methods the operator can actually take right now, from the
  /// server - so a GPay option never appears when GPay is not configured.
  final List<String> paymentMethods;

  factory HireQuote.fromJson(Map<String, dynamic> json) {
    final hire = json['hire'] is Map
        ? Map<String, dynamic>.from(json['hire'] as Map)
        : const <String, dynamic>{};
    final clashes = json['conflictingDays'];
    final methods = json['paymentMethods'];

    return HireQuote(
      vehicle: FleetVehicle.fromJson(Map<String, dynamic>.from(json['vehicle'] as Map)),
      startAt: DateTime.tryParse('${hire['startAt']}')?.toLocal() ?? DateTime.now(),
      endAt: DateTime.tryParse('${hire['endAt']}')?.toLocal() ?? DateTime.now(),
      days: (hire['days'] as num?)?.toInt() ?? 1,
      dailyRate: (hire['dailyRate'] as num?)?.toDouble() ?? 0,
      hireCharge: (hire['hireCharge'] as num?)?.toDouble() ?? 0,
      securityDeposit: (hire['securityDeposit'] as num?)?.toDouble() ?? 0,
      amountDue: (hire['amountDue'] as num?)?.toDouble() ?? 0,
      currency: (hire['currency'] ?? 'INR') as String,
      currencySymbol: (hire['currencySymbol'] ?? '') as String,
      isAvailable: json['isAvailable'] as bool? ?? false,
      conflictingDays: clashes is List ? clashes.map((day) => '$day').toList() : const [],
      paymentMethods: methods is List ? methods.map((method) => '$method').toList() : const [],
    );
  }
}

/// Which days in a window are already taken, so the date picker can grey them
/// out before the customer chooses a period and is told no.
class VehicleAvailability {
  const VehicleAvailability({
    required this.vehicleId,
    required this.takenDays,
    this.underMaintenance = false,
    this.pricePerDay = 0,
    this.securityDeposit = 0,
    this.currencySymbol = '',
  });

  final String vehicleId;

  /// `YYYY-MM-DD` in the operator's own timezone, as the server stores holds.
  final List<String> takenDays;

  final bool underMaintenance;
  final double pricePerDay;
  final double securityDeposit;
  final String currencySymbol;

  bool isTaken(DateTime day) => takenDays.contains(dayKey(day));

  /// `YYYY-MM-DD` from local date parts.
  ///
  /// Deliberately not `toIso8601String().substring(0, 10)`, which would shift
  /// the date by the UTC offset and grey out the wrong day.
  static String dayKey(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  factory VehicleAvailability.fromJson(Map<String, dynamic> json) {
    final days = json['takenDays'];

    return VehicleAvailability(
      vehicleId: (json['vehicleId'] ?? '') as String,
      takenDays: days is List ? days.map((day) => '$day').toList() : const [],
      underMaintenance: json['underMaintenance'] as bool? ?? false,
      pricePerDay: (json['pricePerDay'] as num?)?.toDouble() ?? 0,
      securityDeposit: (json['securityDeposit'] as num?)?.toDouble() ?? 0,
      currencySymbol: (json['currencySymbol'] ?? '') as String,
    );
  }
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  // `cng` and `lpg` are acronyms; everything else is a word.
  if (value.length <= 3) return value.toUpperCase();
  return value[0].toUpperCase() + value.substring(1);
}
