import 'customer.dart';

/// What the backend returns from register / login / verify-otp / refresh.
class AuthSession {
  const AuthSession({
    required this.customer,
    required this.accessToken,
    required this.refreshToken,
    this.accessTokenExpiresIn,
    this.refreshTokenExpiresAt,
  });

  final Customer customer;
  final String accessToken;
  final String refreshToken;

  /// Seconds until the access token expires. Informational - the interceptor
  /// refreshes reactively on a 401 rather than scheduling against this.
  final int? accessTokenExpiresIn;
  final DateTime? refreshTokenExpiresAt;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        customer: Customer.fromJson(Map<String, dynamic>.from(json['customer'] as Map)),
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        accessTokenExpiresIn: (json['accessTokenExpiresIn'] as num?)?.toInt(),
        refreshTokenExpiresAt: json['refreshTokenExpiresAt'] is String
            ? DateTime.tryParse(json['refreshTokenExpiresAt'] as String)
            : null,
      );
}

/// Result of `POST /auth/send-otp` and `POST /auth/forgot-password`.
class OtpChallenge {
  const OtpChallenge({
    required this.maskedDestination,
    required this.expiresInSeconds,
    required this.resendInSeconds,
    this.deliveryChannel = 'sms',
    this.deliveredTo,
    this.devOtp,
  });

  /// The identifier the customer typed, masked: `+91••••••10`. Confirms we are
  /// working on the right account.
  final String maskedDestination;

  /// Where the code was actually sent: `email` or `sms`.
  ///
  /// These are two different facts and the screen needs both. A customer signs
  /// in with their *mobile number*, but the deployment emails the code to the
  /// address on that account - so [maskedDestination] is a phone number while
  /// [deliveredTo] is an inbox. Collapsing them would mean telling someone to
  /// wait for a text that is never coming, which is the single most expensive
  /// way to lose a sign-in.
  final String deliveryChannel;

  /// The masked address or number the code went to: `ar••••••@gmail.com`.
  final String? deliveredTo;

  final int expiresInSeconds;
  final int resendInSeconds;

  bool get wasEmailed => deliveryChannel == 'email';

  /// Only ever populated when the backend's provider is mocked and it is not
  /// running in production. The OTP screen shows it in a clearly-labelled
  /// development banner so the flow is testable without a live gateway.
  final String? devOtp;

  bool get isDevelopmentCode => devOtp != null && devOtp!.isNotEmpty;

  factory OtpChallenge.fromJson(Map<String, dynamic> json) => OtpChallenge(
        maskedDestination: (json['maskedDestination'] ?? '') as String,
        deliveryChannel: (json['deliveryChannel'] ?? 'sms') as String,
        deliveredTo: json['deliveredTo'] as String?,
        expiresInSeconds: (json['expiresInSeconds'] as num?)?.toInt() ?? 300,
        resendInSeconds: (json['resendInSeconds'] as num?)?.toInt() ?? 30,
        devOtp: json['devOtp'] as String?,
      );
}

/// Result of verifying an OTP for a purpose other than login: a one-use token
/// to present to register / reset-password / profile update.
class OtpVerification {
  const OtpVerification({required this.verificationToken, this.expiresAt});

  final String verificationToken;
  final DateTime? expiresAt;

  factory OtpVerification.fromJson(Map<String, dynamic> json) => OtpVerification(
        verificationToken: json['verificationToken'] as String,
        expiresAt: json['verificationTokenExpiresAt'] is String
            ? DateTime.tryParse(json['verificationTokenExpiresAt'] as String)
            : null,
      );
}

/// Why an OTP was requested. Must match the backend's `purpose` enum.
enum OtpPurpose {
  register('register'),
  login('login'),
  verifyPhone('verify_phone'),
  verifyEmail('verify_email'),
  resetPassword('reset_password');

  const OtpPurpose(this.apiValue);

  final String apiValue;

  String get screenTitle {
    switch (this) {
      case register:
        return 'Verify your number';
      case login:
        return 'Sign in with a code';
      case verifyPhone:
        return 'Verify your new number';
      case verifyEmail:
        return 'Verify your email';
      case resetPassword:
        return 'Reset your password';
    }
  }
}
