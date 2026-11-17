import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/validators.dart';
import '../models/auth_session.dart';
import '../models/customer.dart';

/// All authentication calls.
///
/// Phone numbers are normalised to E.164 here, in one place, so the number the
/// customer typed and the number the account is keyed on can never diverge -
/// which is the difference between "wrong password" and an OTP that goes to a
/// number nobody owns.
class AuthRepository {
  const AuthRepository(this._client);

  final ApiClient _client;

  /// Builds the identifier part of a request body from whatever the customer
  /// typed into a combined "mobile number or email" field.
  static Map<String, dynamic> identifierBody(String identifier) {
    final trimmed = identifier.trim();
    if (Validators.looksLikeEmail(trimmed)) {
      return {'email': trimmed.toLowerCase()};
    }
    return {'phone': Validators.normalizePhone(trimmed)};
  }

  /// Sends a one-time code. `purpose` decides what the code may then be used
  /// for; the backend will not accept a `login` code for a password reset.
  /// Requests a one-time code.
  ///
  /// `deliveryEmail` is only meaningful when [identifier] is a mobile number
  /// and [purpose] is registration: there is no account yet, so there is no
  /// address on file to email the code to, and the one being registered has
  /// to travel with the request.
  ///
  /// For every other purpose the server ignores it and uses the address on the
  /// account - which is deliberate. If it honoured a caller-supplied address,
  /// anyone who knew a customer's mobile number could have that customer's
  /// sign-in code sent to an inbox of their own choosing.
  Future<OtpChallenge> sendOtp({
    required String identifier,
    required OtpPurpose purpose,
    String? deliveryEmail,
  }) async {
    final email = deliveryEmail?.trim() ?? '';

    final data = await _client.post(
      ApiEndpoints.sendOtp,
      body: {
        ...identifierBody(identifier),
        if (email.isNotEmpty && purpose == OtpPurpose.register) 'email': email,
        'purpose': purpose.apiValue,
      },
    );
    return OtpChallenge.fromJson(data);
  }

  /// Verifies a code for a purpose other than login, returning the one-use
  /// token that authorises the follow-up call.
  Future<OtpVerification> verifyOtp({
    required String identifier,
    required OtpPurpose purpose,
    required String code,
  }) async {
    final data = await _client.post(
      ApiEndpoints.verifyOtp,
      body: {
        ...identifierBody(identifier),
        'purpose': purpose.apiValue,
        'otp': code.trim(),
      },
    );
    return OtpVerification.fromJson(data);
  }

  /// Login option B: verifying a `login` code signs the customer straight in.
  Future<AuthSession> verifyOtpAndSignIn({
    required String identifier,
    required String code,
    String? fcmToken,
  }) async {
    final data = await _client.post(
      ApiEndpoints.verifyOtp,
      body: {
        ...identifierBody(identifier),
        'purpose': OtpPurpose.login.apiValue,
        'otp': code.trim(),
        if (fcmToken != null) 'fcmToken': fcmToken,
        if (fcmToken != null) 'platform': 'android',
      },
    );
    return AuthSession.fromJson(data);
  }

  /// Creates an account. A `phone` registration requires [verificationToken]
  /// from a verified `register` OTP; the backend rejects it otherwise.
  Future<AuthSession> register({
    required String fullName,
    required String password,
    String? phone,
    String? email,
    String? verificationToken,
    String? fcmToken,
  }) async {
    final data = await _client.post(
      ApiEndpoints.register,
      body: {
        'fullName': fullName.trim(),
        if (phone != null && phone.isNotEmpty) 'phone': Validators.normalizePhone(phone),
        if (email != null && email.isNotEmpty) 'email': email.trim().toLowerCase(),
        'password': password,
        'confirmPassword': password,
        if (verificationToken != null) 'verificationToken': verificationToken,
        if (fcmToken != null) 'fcmToken': fcmToken,
        if (fcmToken != null) 'platform': 'android',
      },
    );
    return AuthSession.fromJson(data);
  }

  /// Login options A and C: identifier plus password.
  Future<AuthSession> loginWithPassword({
    required String identifier,
    required String password,
    String? fcmToken,
  }) async {
    final data = await _client.post(
      ApiEndpoints.login,
      body: {
        ...identifierBody(identifier),
        'password': password,
        if (fcmToken != null) 'fcmToken': fcmToken,
        if (fcmToken != null) 'platform': 'android',
      },
    );
    return AuthSession.fromJson(data);
  }

  /// Starts a password reset. The response is identical whether or not the
  /// account exists, so this cannot be used to discover customers.
  Future<OtpChallenge> forgotPassword({required String identifier}) async {
    final data = await _client.post(
      ApiEndpoints.forgotPassword,
      body: identifierBody(identifier),
    );
    return OtpChallenge.fromJson(data);
  }

  /// Completes a reset and signs the customer in on this device, while
  /// revoking every other session.
  Future<AuthSession> resetPassword({
    required String identifier,
    required String verificationToken,
    required String password,
  }) async {
    final data = await _client.post(
      ApiEndpoints.resetPassword,
      body: {
        ...identifierBody(identifier),
        'verificationToken': verificationToken,
        'password': password,
        'confirmPassword': password,
      },
    );
    return AuthSession.fromJson(data);
  }

  /// Revokes the session server-side. Best-effort: the caller clears local
  /// tokens regardless, so a failure here cannot trap someone signed in.
  Future<void> logout({String? refreshToken, String? fcmToken, bool allDevices = false}) async {
    await _client.post(
      ApiEndpoints.logout,
      body: {
        if (refreshToken != null) 'refreshToken': refreshToken,
        if (fcmToken != null) 'fcmToken': fcmToken,
        if (allDevices) 'allDevices': true,
      },
    );
  }

  Future<Customer> fetchProfile() async {
    final data = await _client.get(ApiEndpoints.me);
    return Customer.fromJson(Map<String, dynamic>.from(data['customer'] as Map));
  }
}
