import '../../../core/constants/booking_status.dart';
import '../../../shared/models/place.dart';
import '../../vehicle_selection/models/vehicle_estimate.dart';

/// Business contact details as captured on a booking.
///
/// Snapshotted server-side at booking time, so a trip from last year still
/// shows the number the customer was given then, even after the admin changes
/// it. Never hardcoded in the app.
/// The payment on a booking, as the backend reports it.
///
/// The field this exists for is [isTruePayment]. It is deliberately not the
/// same thing as `paymentStatus == Paid`:
///
///   * `Paid` is a *state*. The operator can reach it by taking cash, and a
///     customer who submitted a transaction reference reaches "Awaiting
///     Verification" on their way to it.
///   * [isTruePayment] is a *proof* - the payment provider confirmed a capture
///     for this exact booking and amount, or an administrator checked the bank
///     credit against the customer's UTR, or cash changed hands.
///
/// The Completed and Confirm Paid actions are gated on the proof, never on the
/// state, which is what stops an unverified claim unlocking them.
class BookingPayment {
  const BookingPayment({
    this.amount,
    this.currencySymbol = '₹',
    this.transactionId,
    this.reference,
    this.isPaid = false,
    this.isTruePayment = false,
    this.awaitingVerification = false,
    this.verifiedBy,
    this.verifiedAt,
    this.rejectionReason,
    this.customerConfirmedPaidAt,
    this.customerCompletedAt,
  });

  final double? amount;
  final String currencySymbol;

  /// The UTR the customer submitted, once they have submitted one.
  final String? transactionId;

  /// Our own reference, which goes in the UPI `tr` field so a line on a bank
  /// statement can be traced back to this booking.
  final String? reference;

  final bool isPaid;

  /// See the class note. The gate on the Completed / Confirm Paid actions.
  final bool isTruePayment;

  /// A reference has been submitted and nobody has checked it yet.
  final bool awaitingVerification;

  /// `gateway`, `admin` or `cash` - what proved the payment.
  final String? verifiedBy;
  final DateTime? verifiedAt;

  /// Why a submitted reference was turned down, when one was.
  final String? rejectionReason;

  final DateTime? customerConfirmedPaidAt;
  final DateTime? customerCompletedAt;

  bool get hasConfirmedPaid => customerConfirmedPaidAt != null;
  bool get hasConfirmedCompleted => customerCompletedAt != null;
  bool get wasRejected => (rejectionReason ?? '').isNotEmpty;

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  factory BookingPayment.fromJson(Map<String, dynamic> json) => BookingPayment(
        amount: (json['amount'] as num?)?.toDouble(),
        currencySymbol: (json['currencySymbol'] ?? '₹') as String,
        transactionId: json['transactionId'] as String?,
        reference: json['reference'] as String?,
        isPaid: json['isPaid'] == true,
        isTruePayment: json['isTruePayment'] == true,
        awaitingVerification: json['awaitingVerification'] == true,
        verifiedBy: json['verifiedBy'] as String?,
        verifiedAt: _date(json['verifiedAt']),
        rejectionReason: json['rejectionReason'] as String?,
        customerConfirmedPaidAt: _date(json['customerConfirmedPaidAt']),
        customerCompletedAt: _date(json['customerCompletedAt']),
      );
}

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

/// The driver allocated to a booking.
///
/// Written by the admin panel only - the app reads it and can never set it.
/// Null until somebody is allocated, which is why [BookingDriverAllocation]
/// exists alongside it: a screen has to be able to say "not allocated yet"
/// without first testing a null.
class BookingDriver {
  const BookingDriver({
    this.driverId,
    this.driverCode,
    this.name,
    this.phone,
    this.photoUrl,
    this.rating,
    this.vehicleNumber,
    this.vehicleModel,
    this.assignedAt,
  });

  final String? driverId;

  /// The printable roster code, e.g. `DRV-0007`, which is what an operator asks
  /// for over the phone.
  final String? driverCode;

  final String? name;

  /// The driver's mobile number in E.164 - the same number the allocation SMS
  /// carries.
  final String? phone;

  final String? photoUrl;
  final double? rating;
  final String? vehicleNumber;
  final String? vehicleModel;
  final DateTime? assignedAt;

  bool get hasPhone => (phone ?? '').isNotEmpty;

  factory BookingDriver.fromJson(Map<String, dynamic> json) => BookingDriver(
        driverId: json['driverId'] as String?,
        driverCode: json['driverCode'] as String?,
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

/// Whether a driver has been allocated, as a state in its own right.
///
/// The backend derives this from the driver snapshot and sends it on every
/// booking, allocated or not, so the Booked Details screen can show a
/// "Driver allocated" field that reads correctly from the moment the booking is
/// made rather than appearing only once there is a driver.
class BookingDriverAllocation {
  const BookingDriverAllocation({
    required this.status,
    this.allocatedAt,
    this.driverName,
    this.driverPhone,
  });

  final DriverAllocationStatus status;
  final DateTime? allocatedAt;
  final String? driverName;
  final String? driverPhone;

  bool get isAllocated => status.isAllocated;

  /// For a booking that arrived without the block - the socket's payload, or an
  /// older server. Derived from the driver, which is the rule the backend's own
  /// virtual applies.
  factory BookingDriverAllocation.fromDriver(BookingDriver? driver) =>
      BookingDriverAllocation(
        status: (driver?.name ?? '').isNotEmpty
            ? DriverAllocationStatus.allocated
            : DriverAllocationStatus.notAllocated,
        allocatedAt: driver?.assignedAt,
        driverName: driver?.name,
        driverPhone: driver?.phone,
      );

  factory BookingDriverAllocation.fromJson(Map<String, dynamic> json) =>
      BookingDriverAllocation(
        status: DriverAllocationStatus.fromApi(json['status'] as String?),
        allocatedAt: json['allocatedAt'] is String
            ? DateTime.tryParse(json['allocatedAt'] as String)
            : null,
        driverName: json['driverName'] as String?,
        driverPhone: json['driverPhone'] as String?,
      );
}

/// The vehicle as it was when it was booked, with its photographs.
///
/// A snapshot, not a live read: the operator re-prices vehicles, replaces
/// photographs and eventually sells them, and a booking from March must still
/// show the car that went out. The gallery is part of the snapshot for the same
/// reason the registration number is.
class BookingVehicle {
  const BookingVehicle({
    this.id,
    this.name,
    this.brand,
    this.model,
    this.year,
    this.registrationNumber,
    this.category,
    this.seatingCapacity,
    this.fuelType,
    this.transmission,
    this.imageUrl,
    this.imageUrls = const [],
  });

  final String? id;
  final String? name;
  final String? brand;
  final String? model;
  final int? year;
  final String? registrationNumber;
  final String? category;
  final int? seatingCapacity;
  final String? fuelType;
  final String? transmission;

  /// The cover photo.
  final String? imageUrl;

  /// Every photo, cover first.
  final List<String> imageUrls;

  /// The gallery to show, falling back to the cover for a booking written
  /// before the whole set was snapshotted.
  List<String> get photos {
    if (imageUrls.isNotEmpty) return imageUrls;
    return (imageUrl ?? '').isEmpty ? const [] : [imageUrl!];
  }

  bool get hasPhotos => photos.isNotEmpty;

  /// `Maruti Swift Dzire 2022`.
  String get makeAndModel =>
      [brand, model, year?.toString()].where((part) => (part ?? '').isNotEmpty).join(' ');

  factory BookingVehicle.fromJson(Map<String, dynamic> json) {
    final urls = json['imageUrls'];

    return BookingVehicle(
      id: json['id'] as String?,
      name: json['name'] as String?,
      brand: json['brand'] as String?,
      model: json['model'] as String?,
      year: (json['year'] as num?)?.toInt(),
      registrationNumber: json['registrationNumber'] as String?,
      category: json['category'] as String?,
      seatingCapacity: (json['seatingCapacity'] as num?)?.toInt(),
      fuelType: json['fuelType'] as String?,
      transmission: json['transmission'] as String?,
      imageUrl: json['imageUrl'] as String?,
      imageUrls: urls is List
          ? urls.map((url) => '$url').where((url) => url.isNotEmpty).toList()
          : const [],
    );
  }
}

/// The hire period and the arithmetic that turned it into money.
class BookingHire {
  const BookingHire({
    required this.startAt,
    required this.endAt,
    required this.days,
    required this.dailyRate,
    required this.hireCharge,
    required this.securityDeposit,
    required this.amountDue,
    this.currencySymbol = '',
  });

  /// The booking date the customer chose.
  final DateTime startAt;

  /// When the vehicle comes back.
  final DateTime endAt;

  /// Billable days, as charged. Sent by the server rather than recomputed here,
  /// because this is the multiplier the customer was shown.
  final int days;

  final double dailyRate;
  final double hireCharge;

  /// Refundable, and separate from [hireCharge] so the UI can say so.
  final double securityDeposit;

  /// The one number the customer is asked to pay.
  final double amountDue;

  final String currencySymbol;

  factory BookingHire.fromJson(Map<String, dynamic> json) => BookingHire(
        startAt: DateTime.tryParse('${json['startAt']}')?.toLocal() ?? DateTime.now(),
        endAt: DateTime.tryParse('${json['endAt']}')?.toLocal() ?? DateTime.now(),
        days: (json['days'] as num?)?.toInt() ?? 1,
        dailyRate: (json['dailyRate'] as num?)?.toDouble() ?? 0,
        hireCharge: (json['hireCharge'] as num?)?.toDouble() ?? 0,
        securityDeposit: (json['securityDeposit'] as num?)?.toDouble() ?? 0,
        amountDue: (json['amountDue'] as num?)?.toDouble() ?? 0,
        currencySymbol: (json['currencySymbol'] ?? '') as String,
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
    this.payment,
    required this.createdAt,
    this.customerId,
    this.customerPhone,
    this.customerEmail,
    this.vehicleTypeId,
    this.vehicleTypeCode,
    this.vehicle,
    this.hire,
    this.finalFare,
    this.fareBreakdown,
    this.routePolyline,
    this.scheduledAt,
    this.specialInstructions,
    this.driver,
    this.driverAllocation,
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

  /// The actual vehicle, with its photographs. Null on a historical booking
  /// that only ever recorded a category.
  final BookingVehicle? vehicle;

  /// The hire period. Null on a historical point-to-point trip.
  final BookingHire? hire;

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

  /// The payment trail, including whether the money has actually been
  /// verified. Null on a booking written before the field existed.
  final BookingPayment? payment;

  final DateTime? scheduledAt;
  final String? specialInstructions;

  final BookingDriver? driver;

  /// Whether a driver has been allocated, readable before one has been.
  final BookingDriverAllocation? driverAllocation;

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

  bool get isHire => hire != null;

  /// The date the vehicle is wanted - the "Booking Date" on the details screen.
  /// Falls back to the scheduled pickup for a historical trip.
  DateTime? get bookingDate => hire?.startAt ?? scheduledAt;

  /// Never null, so a screen can show the field without a null check. Derived
  /// from the driver when the server did not send the block.
  BookingDriverAllocation get allocation =>
      driverAllocation ?? BookingDriverAllocation.fromDriver(driver);

  bool get isDriverAllocated => allocation.isAllocated;

  /// The photographs to show for this booking's vehicle.
  List<String> get vehiclePhotos => vehicle?.photos ?? const [];

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
      vehicle: json['vehicle'] is Map
          ? BookingVehicle.fromJson(Map<String, dynamic>.from(json['vehicle'] as Map))
          : null,
      hire: json['hire'] is Map
          ? BookingHire.fromJson(Map<String, dynamic>.from(json['hire'] as Map))
          : null,
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
      payment: json['payment'] is Map
          ? BookingPayment.fromJson(
              Map<String, dynamic>.from(json['payment'] as Map))
          : null,
      scheduledAt: json['scheduledAt'] is String
          ? DateTime.tryParse(json['scheduledAt'] as String)
          : null,
      specialInstructions: json['specialInstructions'] as String?,
      driver: json['driver'] is Map
          ? BookingDriver.fromJson(Map<String, dynamic>.from(json['driver'] as Map))
          : null,
      driverAllocation: json['driverAllocation'] is Map
          ? BookingDriverAllocation.fromJson(
              Map<String, dynamic>.from(json['driverAllocation'] as Map))
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
    this.vehicleName,
    this.registrationNumber,
    this.vehicleImageUrl,
    this.hireStartAt,
    this.hireEndAt,
    this.hireDays,
    this.allocationStatus = DriverAllocationStatus.notAllocated,
    this.driverName,
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

  /// Enough of the car to render a row without fetching the whole booking.
  final String? vehicleName;
  final String? registrationNumber;
  final String? vehicleImageUrl;

  final DateTime? hireStartAt;
  final DateTime? hireEndAt;
  final int? hireDays;

  /// Whether a driver is on it yet, so the list can badge it without opening
  /// the booking. This is the reason the backend sends the status as a string.
  final DriverAllocationStatus allocationStatus;
  final String? driverName;

  bool get isFareFinal => finalFare != null;

  bool get isHire => hireStartAt != null;

  DateTime? get bookingDate => hireStartAt ?? scheduledAt;

  bool get isDriverAllocated => allocationStatus.isAllocated;

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
        vehicleName: json['vehicleName'] as String?,
        registrationNumber: json['registrationNumber'] as String?,
        vehicleImageUrl: json['vehicleImageUrl'] as String?,
        hireStartAt: json['hireStartAt'] is String
            ? DateTime.tryParse(json['hireStartAt'] as String)?.toLocal()
            : null,
        hireEndAt: json['hireEndAt'] is String
            ? DateTime.tryParse(json['hireEndAt'] as String)?.toLocal()
            : null,
        hireDays: (json['hireDays'] as num?)?.toInt(),
        allocationStatus: DriverAllocationStatus.fromApi(
          json['driverAllocationStatus'] as String?,
        ),
        driverName: json['driverName'] as String?,
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
