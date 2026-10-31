import '../../../core/constants/booking_status.dart';
import '../../../shared/models/place.dart';
import '../../vehicle_selection/models/vehicle_estimate.dart';

/// Business contact details as captured on a booking.
///
/// Snapshotted server-side at booking time, so a trip from last year still
/// shows the number the customer was given then, even after the admin changes
/// it. Never hardcoded in the app.
class BookingBusinessContact {
  const BookingBusinessContact({
    this.businessName,
    this.adminContactName,
    this.adminPhone,
    this.adminEmail,
    this.supportPhone,
    this.supportEmail,
  });

  final String? businessName;
  final String? adminContactName;
  final String? adminPhone;
  final String? adminEmail;
  final String? supportPhone;
  final String? supportEmail;

  factory BookingBusinessContact.fromJson(Map<String, dynamic> json) => BookingBusinessContact(
        businessName: json['businessName'] as String?,
        adminContactName: json['adminContactName'] as String?,
        adminPhone: json['adminPhone'] as String?,
        adminEmail: json['adminEmail'] as String?,
        supportPhone: json['supportPhone'] as String?,
        supportEmail: json['supportEmail'] as String?,
      );

  /// The number to call about this booking, preferring the support line.
  String? get callNumber => supportPhone ?? adminPhone;
  String? get emailAddress => supportEmail ?? adminEmail;

  bool get hasAnyContact =>
      (callNumber ?? '').isNotEmpty || (emailAddress ?? '').isNotEmpty;
}

class BookingDriver {
  const BookingDriver({
    this.name,
    this.phone,
    this.photoUrl,
    this.rating,
    this.vehicleNumber,
    this.vehicleModel,
    this.assignedAt,
  });

  final String? name;
  final String? phone;
  final String? photoUrl;
  final double? rating;
  final String? vehicleNumber;
  final String? vehicleModel;
  final DateTime? assignedAt;

  factory BookingDriver.fromJson(Map<String, dynamic> json) => BookingDriver(
        name: json['name'] as String?,
        phone: json['phone'] as String?,
        photoUrl: json['photoUrl'] as String?,
        rating: (json['rating'] as num?)?.toDouble(),
        vehicleNumber: json['vehicleNumber'] as String?,
        vehicleModel: json['vehicleModel'] as String?,
        assignedAt: json['assignedAt'] is String
            ? DateTime.tryParse(json['assignedAt'] as String)
            : null,
      );
}

class BookingCancellation {
  const BookingCancellation({
    this.reason,
    this.remarks,
    this.cancelledByRole,
    this.cancelledAt,
    this.fee = 0,
    this.feeWaived = false,
  });

  final String? reason;
  final String? remarks;
  final String? cancelledByRole;
  final DateTime? cancelledAt;
  final double fee;
  final bool feeWaived;

  bool get wasCancelledByCustomer => cancelledByRole == 'customer';

  factory BookingCancellation.fromJson(Map<String, dynamic> json) => BookingCancellation(
        reason: json['reason'] as String?,
        remarks: json['remarks'] as String?,
        cancelledByRole: json['cancelledByRole'] as String?,
        cancelledAt: json['cancelledAt'] is String
            ? DateTime.tryParse(json['cancelledAt'] as String)
            : null,
        fee: (json['fee'] as num?)?.toDouble() ?? 0,
        feeWaived: json['feeWaived'] as bool? ?? false,
      );
}

class BookingStatusEvent {
  const BookingStatusEvent({required this.status, required this.at, this.note});

  final BookingStatus status;
  final DateTime at;
  final String? note;

  factory BookingStatusEvent.fromJson(Map<String, dynamic> json) => BookingStatusEvent(
        status: BookingStatus.fromApi(json['status'] as String?),
        at: DateTime.tryParse((json['at'] ?? '') as String) ?? DateTime.now(),
        note: json['note'] as String?,
      );
}

/// A booking, in full. Returned by create, detail and the realtime socket.
class Booking {
  const Booking({
    required this.id,
    required this.bookingCode,
    required this.customerName,
    required this.vehicleTypeName,
    required this.pickup,
    required this.destination,
    required this.distanceKm,
    required this.durationMinutes,
    required this.estimatedFare,
    required this.status,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.createdAt,
    this.customerId,
    this.customerPhone,
    this.customerEmail,
    this.vehicleTypeId,
    this.vehicleTypeCode,
    this.finalFare,
    this.fareBreakdown,
    this.routePolyline,
    this.scheduledAt,
    this.specialInstructions,
    this.driver,
    this.businessContact,
    this.cancellation,
    this.statusHistory = const [],
    this.completedAt,
    this.updatedAt,
  });

  final String id;

  /// The reference shown to the customer, e.g. `TX-000042`.
  final String bookingCode;

  final String? customerId;
  final String customerName;
  final String? customerPhone;
  final String? customerEmail;

  final String? vehicleTypeId;
  final String vehicleTypeName;
  final String? vehicleTypeCode;

  final Place pickup;
  final Place destination;

  final double distanceKm;
  final int durationMinutes;
  final String? routePolyline;

  final double estimatedFare;

  /// Null until the trip is finished and the operator sets the real fare.
  final double? finalFare;

  final FareBreakdown? fareBreakdown;

  final BookingStatus status;
  final PaymentMethod paymentMethod;
  final PaymentStatus paymentStatus;

  final DateTime? scheduledAt;
  final String? specialInstructions;

  final BookingDriver? driver;
  final BookingBusinessContact? businessContact;
  final BookingCancellation? cancellation;
  final List<BookingStatusEvent> statusHistory;

  final DateTime createdAt;
  final DateTime? completedAt;
  final DateTime? updatedAt;

  /// Whether to label the fare "Estimated" or "Total".
  bool get isFareFinal => finalFare != null;

  double get displayFare => finalFare ?? estimatedFare;

  String get currencySymbol => fareBreakdown?.currencySymbol ?? '';

  bool get isScheduled => scheduledAt != null;

  factory Booking.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'];
    final vehicleType = json['vehicleType'];
    final history = json['statusHistory'];

    return Booking(
      id: json['id'] as String,
      bookingCode: (json['bookingCode'] ?? '') as String,
      customerId: customer is Map ? customer['id'] as String? : null,
      customerName: customer is Map ? ((customer['name'] ?? '') as String) : '',
      customerPhone: customer is Map ? customer['phone'] as String? : null,
      customerEmail: customer is Map ? customer['email'] as String? : null,
      vehicleTypeId: vehicleType is Map ? vehicleType['id'] as String? : null,
      vehicleTypeName: vehicleType is Map ? ((vehicleType['name'] ?? '') as String) : '',
      vehicleTypeCode: vehicleType is Map ? vehicleType['code'] as String? : null,
      pickup: Place.fromJson(Map<String, dynamic>.from(json['pickup'] as Map)),
      destination: Place.fromJson(Map<String, dynamic>.from(json['destination'] as Map)),
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
      durationMinutes: (json['durationMinutes'] as num?)?.round() ?? 0,
      routePolyline: json['routePolyline'] as String?,
      estimatedFare: (json['estimatedFare'] as num?)?.toDouble() ?? 0,
      finalFare: (json['finalFare'] as num?)?.toDouble(),
      fareBreakdown: json['fareBreakdown'] is Map
          ? FareBreakdown.fromJson(Map<String, dynamic>.from(json['fareBreakdown'] as Map))
          : null,
      status: BookingStatus.fromApi(json['bookingStatus'] as String?),
      paymentMethod: PaymentMethod.fromApi(json['paymentMethod'] as String?),
      paymentStatus: PaymentStatus.fromApi(json['paymentStatus'] as String?),
      scheduledAt: json['scheduledAt'] is String
          ? DateTime.tryParse(json['scheduledAt'] as String)
          : null,
      specialInstructions: json['specialInstructions'] as String?,
      driver: json['driver'] is Map
          ? BookingDriver.fromJson(Map<String, dynamic>.from(json['driver'] as Map))
          : null,
      businessContact: json['businessContact'] is Map
          ? BookingBusinessContact.fromJson(
              Map<String, dynamic>.from(json['businessContact'] as Map))
          : null,
      cancellation: json['cancellation'] is Map
          ? BookingCancellation.fromJson(Map<String, dynamic>.from(json['cancellation'] as Map))
          : null,
      statusHistory: history is List
          ? history
              .whereType<Map>()
              .map((item) => BookingStatusEvent.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : const [],
      createdAt: DateTime.tryParse((json['createdAt'] ?? '') as String) ?? DateTime.now(),
      completedAt: json['completedAt'] is String
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
      updatedAt:
          json['updatedAt'] is String ? DateTime.tryParse(json['updatedAt'] as String) : null,
    );
  }
}

/// Compact shape returned by the list endpoints, for the My Bookings cards.
class BookingSummary {
  const BookingSummary({
    required this.id,
    required this.bookingCode,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.vehicleTypeName,
    required this.status,
    required this.paymentStatus,
    required this.createdAt,
    required this.displayFare,
    this.currencySymbol = '',
    this.distanceKm = 0,
    this.finalFare,
    this.scheduledAt,
  });

  final String id;
  final String bookingCode;
  final String pickupAddress;
  final String destinationAddress;
  final String vehicleTypeName;
  final BookingStatus status;
  final PaymentStatus paymentStatus;
  final DateTime createdAt;
  final double displayFare;
  final String currencySymbol;
  final double distanceKm;
  final double? finalFare;
  final DateTime? scheduledAt;

  bool get isFareFinal => finalFare != null;

  factory BookingSummary.fromJson(Map<String, dynamic> json) => BookingSummary(
        id: json['id'] as String,
        bookingCode: (json['bookingCode'] ?? '') as String,
        pickupAddress: (json['pickupAddress'] ?? '') as String,
        destinationAddress: (json['destinationAddress'] ?? '') as String,
        vehicleTypeName: (json['vehicleTypeName'] ?? '') as String,
        status: BookingStatus.fromApi(json['bookingStatus'] as String?),
        paymentStatus: PaymentStatus.fromApi(json['paymentStatus'] as String?),
        createdAt: DateTime.tryParse((json['createdAt'] ?? '') as String) ?? DateTime.now(),
        displayFare: (json['displayFare'] as num?)?.toDouble() ??
            (json['estimatedFare'] as num?)?.toDouble() ??
            0,
        currencySymbol: (json['currencySymbol'] ?? '') as String,
        distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
        finalFare: (json['finalFare'] as num?)?.toDouble(),
        scheduledAt: json['scheduledAt'] is String
            ? DateTime.tryParse(json['scheduledAt'] as String)
            : null,
      );
}

/// What the detail endpoint reports about cancelling this booking right now.
class CancellationInfo {
  const CancellationInfo({
    required this.canCancel,
    required this.estimatedFee,
    required this.feeWaived,
    required this.reasons,
  });

  final bool canCancel;
  final double estimatedFee;
  final bool feeWaived;

  /// The reason list comes from the server so admin and app always agree.
  final List<String> reasons;

  factory CancellationInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const CancellationInfo(
        canCancel: false,
        estimatedFee: 0,
        feeWaived: true,
        reasons: [],
      );
    }

    final reasons = json['reasons'];
    return CancellationInfo(
      canCancel: json['canCancel'] as bool? ?? false,
      estimatedFee: (json['estimatedFee'] as num?)?.toDouble() ?? 0,
      feeWaived: json['feeWaived'] as bool? ?? true,
      reasons: reasons is List ? reasons.map((r) => '$r').toList() : const [],
    );
  }
}

/// Detail response: the booking plus its cancellation metadata.
class BookingDetail {
  const BookingDetail({required this.booking, required this.cancellation});

  final Booking booking;
  final CancellationInfo cancellation;

  factory BookingDetail.fromJson(Map<String, dynamic> json) => BookingDetail(
        booking: Booking.fromJson(Map<String, dynamic>.from(json['booking'] as Map)),
        cancellation: CancellationInfo.fromJson(
          json['cancellation'] is Map
              ? Map<String, dynamic>.from(json['cancellation'] as Map)
              : null,
        ),
      );
}
