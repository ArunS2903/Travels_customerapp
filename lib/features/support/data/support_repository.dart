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
  });

  final List<String> paymentMethods;
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

    return ServerCapabilities(
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
