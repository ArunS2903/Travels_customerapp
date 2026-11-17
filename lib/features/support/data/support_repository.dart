import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../models/business_contact.dart';

/// Business contact details and server-declared capabilities.
class SupportRepository {
  const SupportRepository(this._client);

  final ApiClient _client;

  /// The official contact details. Unauthenticated, so the support screen works
  /// before sign-in.
  Future<BusinessContact> fetchBusinessContact() async {
    final data = await _client.get(ApiEndpoints.businessContact);
    return BusinessContact.fromJson(
      Map<String, dynamic>.from(data['businessContact'] as Map),
    );
  }

  /// Which optional integrations this deployment has, plus the enum
  /// vocabularies. Used to hide UI that cannot work rather than showing a
  /// button that will fail.
  Future<ServerCapabilities> fetchAppConfig() async {
    final data = await _client.get(ApiEndpoints.appConfig);
    return ServerCapabilities.fromJson(data);
  }
}

class ServerCapabilities {
  const ServerCapabilities({
    required this.paymentMethods,
    required this.cancellationReasons,
    required this.otpLength,
    required this.otpResendCooldownSeconds,
    required this.smsOtp,
    required this.routeAccurateDistances,
    required this.pushNotifications,
    required this.scheduledBookings,
    this.appName,
    this.paymentMethodLabels = const {},
    this.onlinePaymentMode,
    this.paymentNeedsVerification = false,
    this.upiPayeeVpa,
    this.upiPayeeName,
  });

  final List<String> paymentMethods;

  /// The product name the server reports, so a rebrand needs no app release.
  final String? appName;

  /// How to label each stored payment method: `GPay` reads as "Online
  /// Payment", `Cash` as "Cash on Pay".
  ///
  /// The labels are served rather than compiled in because the stored enum
  /// values are on every historical booking and cannot be renamed without a
  /// migration. The database keeps its vocabulary; the customer sees ours.
  final Map<String, String> paymentMethodLabels;

  /// `razorpay`, `upi`, or null when online payment is off.
  ///
  /// The difference matters to the UI, not just to the server: `razorpay`
  /// opens a checkout sheet that confirms itself, while `upi` launches the
  /// customer's own UPI app and then has to ask them for the UTR, because
  /// nothing can confirm a direct transfer on its own.
  final String? onlinePaymentMode;

  /// True when an online payment needs a reference from the customer and an
  /// administrator to confirm it.
  final bool paymentNeedsVerification;

  /// The UPI ID online payments collect into, shown on the payment sheet so
  /// the customer can check it against what their UPI app displays.
  final String? upiPayeeVpa;
  final String? upiPayeeName;

  bool get hasOnlinePayments => onlinePaymentMode != null;
  bool get usesDirectUpi => onlinePaymentMode == 'upi';

  /// The label for a stored payment method, falling back to the stored value
  /// so an unmapped historical method still renders as something.
  String labelForPaymentMethod(String apiValue) =>
      paymentMethodLabels[apiValue] ?? apiValue;
  final List<String> cancellationReasons;
  final int otpLength;
  final int otpResendCooldownSeconds;

  /// False when the backend's SMS provider is mocked - the OTP screen then
  /// shows the development code banner.
  final bool smsOtp;

  /// False when the backend has no Maps key, so distances are straight-line
  /// estimates. The UI adds an "approximate" note.
  final bool routeAccurateDistances;

  final bool pushNotifications;
  final bool scheduledBookings;

  factory ServerCapabilities.fromJson(Map<String, dynamic> json) {
    final features = json['features'] is Map
        ? Map<String, dynamic>.from(json['features'] as Map)
        : const <String, dynamic>{};
    final otp = json['otp'] is Map
        ? Map<String, dynamic>.from(json['otp'] as Map)
        : const <String, dynamic>{};

    final upi = json['upi'] is Map
        ? Map<String, dynamic>.from(json['upi'] as Map)
        : const <String, dynamic>{};
    final labels = json['paymentMethodLabels'] is Map
        ? Map<String, dynamic>.from(json['paymentMethodLabels'] as Map)
        : const <String, dynamic>{};

    return ServerCapabilities(
      appName: json['appName'] as String?,
      paymentMethodLabels: {
        for (final entry in labels.entries) entry.key: '${entry.value}',
      },
      onlinePaymentMode: features['onlinePaymentMode'] as String?,
      paymentNeedsVerification: features['paymentNeedsVerification'] as bool? ?? false,
      upiPayeeVpa: upi['vpa'] as String?,
      upiPayeeName: upi['name'] as String?,
      paymentMethods: _stringList(json['paymentMethods'], fallback: const ['Cash']),
      cancellationReasons: _stringList(json['cancellationReasons']),
      otpLength: (otp['length'] as num?)?.toInt() ?? 6,
      otpResendCooldownSeconds: (otp['resendCooldownSeconds'] as num?)?.toInt() ?? 30,
      smsOtp: features['smsOtp'] as bool? ?? false,
      routeAccurateDistances: features['routeAccurateDistances'] as bool? ?? false,
      pushNotifications: features['pushNotifications'] as bool? ?? false,
      scheduledBookings: features['scheduledBookings'] as bool? ?? true,
    );
  }

  /// Used before the config call returns, and if it fails. Deliberately
  /// pessimistic about optional features.
  static const ServerCapabilities fallback = ServerCapabilities(
    paymentMethods: ['Cash'],
    cancellationReasons: [
      'Driver is taking too long',
      'Booked by mistake',
      'Found another ride',
      'Plans changed',
      'Wrong pickup location',
      'Other',
    ],
    otpLength: 6,
    otpResendCooldownSeconds: 30,
    smsOtp: false,
    routeAccurateDistances: false,
    pushNotifications: false,
    scheduledBookings: true,
  );

  static List<String> _stringList(Object? raw, {List<String> fallback = const []}) {
    if (raw is List && raw.isNotEmpty) return raw.map((item) => '$item').toList();
    return fallback;
  }
}
