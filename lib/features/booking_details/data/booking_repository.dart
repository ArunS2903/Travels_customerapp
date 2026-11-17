import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/booking_status.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/paginated_result.dart';
import '../../../shared/models/place.dart';
import '../models/booking.dart';

/// Outcome of a create call, distinguishing a new booking from a deduplicated
/// retry so the UI can avoid celebrating the same booking twice.
class BookingCreationResult {
  const BookingCreationResult({
    required this.booking,
    required this.wasDeduplicated,
  });

  final Booking booking;

  /// True when this submission matched an `idempotencyKey` we had already used,
  /// i.e. the booking already existed.
  final bool wasDeduplicated;
}

class GatewayPaymentOrder {
  const GatewayPaymentOrder({
    required this.orderId,
    required this.keyId,
    required this.amount,
    required this.currency,
  });

  final String orderId;
  final String keyId;
  final int amount;
  final String currency;

  factory GatewayPaymentOrder.fromJson(Map<String, dynamic> json) =>
      GatewayPaymentOrder(
        orderId: json['orderId'] as String,
        keyId: json['keyId'] as String,
        amount: (json['amount'] as num).toInt(),
        currency: json['currency'] as String,
      );
}

/// The deep links and instructions for a direct-UPI payment.
///
/// `intentUrl` is the generic `upi://pay`, which Android offers to every
/// installed UPI app. That is the one to launch: the operator's UPI ID accepts
/// money from any of them, and insisting on one brand turns away customers who
/// use another. The per-app URLs exist only so a client can offer named
/// shortcut buttons.
class UpiPaymentIntent {
  const UpiPaymentIntent({
    required this.intentUrl,
    required this.payeeVpa,
    required this.payeeName,
    required this.amount,
    required this.currencySymbol,
    required this.reference,
    this.gpayUrl,
    this.phonePeUrl,
    this.paytmUrl,
    this.requiresReference = true,
    this.referenceLabel = 'UPI transaction ID (UTR)',
    this.referenceHint = '',
    this.instructions = '',
  });

  final String intentUrl;
  final String? gpayUrl;
  final String? phonePeUrl;
  final String? paytmUrl;

  final String payeeVpa;
  final String payeeName;
  final double amount;
  final String currencySymbol;

  /// Our reference, carried in the UPI `tr` field.
  final String reference;

  /// Whether the customer has to bring a UTR back. True for direct UPI, where
  /// nothing can confirm settlement on its own.
  final bool requiresReference;
  final String referenceLabel;
  final String referenceHint;

  /// What the server says happens next, so the app does not keep its own copy
  /// of a policy the server owns.
  final String instructions;

  factory UpiPaymentIntent.fromJson(Map<String, dynamic> json) {
    final payment = Map<String, dynamic>.from(json['payment'] as Map);
    final verification = json['verification'] is Map
        ? Map<String, dynamic>.from(json['verification'] as Map)
        : const <String, dynamic>{};

    return UpiPaymentIntent(
      intentUrl: payment['intentUrl'] as String,
      gpayUrl: payment['gpayUrl'] as String?,
      phonePeUrl: payment['phonePeUrl'] as String?,
      paytmUrl: payment['paytmUrl'] as String?,
      payeeVpa: (payment['payeeVpa'] ?? '') as String,
      payeeName: (payment['payeeName'] ?? '') as String,
      amount: (payment['amount'] as num?)?.toDouble() ?? 0,
      currencySymbol: (payment['currencySymbol'] ?? '₹') as String,
      reference: (payment['reference'] ?? '') as String,
      requiresReference: verification['required'] != false,
      referenceLabel:
          (payment['referenceLabel'] ?? 'UPI transaction ID (UTR)') as String,
      referenceHint: (payment['referenceHint'] ?? '') as String,
      instructions: (verification['instructions'] ?? '') as String,
    );
  }
}

class BookingRepository {
  const BookingRepository(this._client);

  final ApiClient _client;

  static const _uuid = Uuid();

  /// Generates an idempotency key for one booking *attempt*.
  ///
  /// The caller holds onto this across retries, which is the whole point: a
  /// double tap or a Dio retry after a timeout re-sends the same key, and the
  /// backend returns the original booking instead of creating a second one. A
  /// fresh key is only generated when the customer starts a genuinely new
  /// booking.
  static String newIdempotencyKey() => _uuid.v4();

  /// Books one specific vehicle for one period.
  ///
  /// What is deliberately *not* sent: no amount, no day count, no daily rate.
  /// All three come from the vehicle and the dates server-side, so the client
  /// cannot propose a price. The quote the customer was shown comes from the
  /// same code path that prices the booking, which is why the two agree.
  Future<BookingCreationResult> createBooking({
    required String vehicleId,
    required DateTime startAt,
    required DateTime endAt,
    required Place pickup,
    required Place destination,
    required PaymentMethod paymentMethod,
    required String idempotencyKey,
    String? specialInstructions,
  }) async {
    final response = await _client.postRaw(
      ApiEndpoints.bookings,
      body: {
        'vehicleId': vehicleId,
        'startAt': startAt.toUtc().toIso8601String(),
        'endAt': endAt.toUtc().toIso8601String(),
        'pickup': pickup.toJson(),
        'destination': destination.toJson(),
        'paymentMethod': paymentMethod.apiValue,
        'idempotencyKey': idempotencyKey,
        if (specialInstructions != null &&
            specialInstructions.trim().isNotEmpty)
          'specialInstructions': specialInstructions.trim(),
      },
      // Safe to retry precisely because of the idempotency key above.
      retryable: true,
    );

    final body = response.data as Map;
    final data = Map<String, dynamic>.from(body['data'] as Map);

    return BookingCreationResult(
      booking: Booking.fromJson(
        Map<String, dynamic>.from(data['booking'] as Map),
      ),
      // 200 (rather than 201) also means "already existed", so trust either signal.
      wasDeduplicated:
          (data['deduplicated'] as bool? ?? false) ||
          response.statusCode == 200,
    );
  }

  Future<PaginatedResult<BookingSummary>> fetchBookings({
    BookingTab? tab,
    int page = 1,
    int limit = 10,
    CancelToken? cancelToken,
  }) async {
    final data = await _client.get(
      ApiEndpoints.bookings,
      query: {
        if (tab != null) 'tab': tab.apiValue,
        'page': page,
        'limit': limit,
      },
      cancelToken: cancelToken,
    );
    return PaginatedResult.fromJson(data, BookingSummary.fromJson);
  }

  Future<BookingDetail> fetchBooking(
    String bookingId, {
    CancelToken? cancelToken,
  }) async {
    final data = await _client.get(
      ApiEndpoints.booking(bookingId),
      cancelToken: cancelToken,
    );
    return BookingDetail.fromJson(data);
  }

  Future<GatewayPaymentOrder> createPaymentOrder(String bookingId) async {
    final data = await _client.post(
      ApiEndpoints.bookingPaymentOrder(bookingId),
    );
    return GatewayPaymentOrder.fromJson(
      Map<String, dynamic>.from(data['payment'] as Map),
    );
  }

  Future<Booking> verifyGatewayPayment({
    required String bookingId,
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    final data = await _client.post(
      ApiEndpoints.verifyBookingPayment(bookingId),
      body: {
        'orderId': orderId,
        'paymentId': paymentId,
        'signature': signature,
      },
    );
    return Booking.fromJson(Map<String, dynamic>.from(data['booking'] as Map));
  }

  Future<Booking> confirmCashPayment(String bookingId) async {
    final data = await _client.post(ApiEndpoints.confirmCashPayment(bookingId));
    return Booking.fromJson(Map<String, dynamic>.from(data['booking'] as Map));
  }

  /// The UPI deep links for this booking, rebuilt server-side on every call.
  ///
  /// Fetched rather than constructed here on purpose: the amount, the payee
  /// and the reference are the server's to decide, and a client that built its
  /// own intent could build one for the wrong amount.
  Future<UpiPaymentIntent> fetchUpiIntent(String bookingId) async {
    final data = await _client.post(ApiEndpoints.bookingPaymentIntent(bookingId));
    return UpiPaymentIntent.fromJson(data);
  }

  /// Submits the UTR from the customer's UPI receipt. Moves the booking to
  /// Awaiting Verification; it does not mark it paid.
  Future<Booking> submitPaymentReference({
    required String bookingId,
    required String transactionId,
  }) async {
    final data = await _client.post(
      ApiEndpoints.bookingPaymentReference(bookingId),
      body: {'transactionId': transactionId},
    );
    return Booking.fromJson(Map<String, dynamic>.from(data['booking'] as Map));
  }

  /// Records a Completed or Confirm Paid acknowledgement. The server refuses
  /// both unless the payment has actually been verified.
  Future<Booking> acknowledgePayment({
    required String bookingId,
    required String action,
  }) async {
    final data = await _client.post(
      ApiEndpoints.acknowledgePayment(bookingId),
      body: {'action': action},
    );
    return Booking.fromJson(Map<String, dynamic>.from(data['booking'] as Map));
  }

  /// What cancelling right now would cost. Fetched when the sheet opens so the
  /// fee shown is current rather than whatever the detail call said earlier.
  Future<CancellationInfo> fetchCancellationPolicy(String bookingId) async {
    final data = await _client.get(ApiEndpoints.cancellationPolicy(bookingId));
    return CancellationInfo.fromJson(data);
  }

  /// Cancels a booking. The backend refuses if the booking has moved on, and
  /// that conflict surfaces as an `ApiException` with a `BOOKING_*` code.
  Future<Booking> cancelBooking({
    required String bookingId,
    required String reason,
    String? remarks,
  }) async {
    final data = await _client.post(
      ApiEndpoints.cancelBooking(bookingId),
      body: {
        'reason': reason,
        if (remarks != null && remarks.trim().isNotEmpty)
          'remarks': remarks.trim(),
      },
    );
    return Booking.fromJson(Map<String, dynamic>.from(data['booking'] as Map));
  }
}
