import 'package:dio/dio.dart';

/// A failure the UI can act on.
///
/// Dio throws [DioException] for everything from a DNS failure to a 409, which
/// is not a useful distinction for a screen. [ApiException.from] collapses all
/// of it into one type carrying the backend's stable `code`, a message already
/// fit to show a customer, and per-field errors for forms.
class ApiException implements Exception {
  const ApiException({
    required this.message,
    required this.code,
    this.statusCode,
    this.fieldErrors = const {},
    this.details,
  });

  /// Safe to show to the customer as-is. The backend writes these for display;
  /// transport failures get a message written below.
  final String message;

  /// Stable machine-readable code. Switch on this, never on [message].
  final String code;

  final int? statusCode;

  /// Field name to error message, from a `VALIDATION_ERROR` response. Feed
  /// straight into form field `errorText`s.
  final Map<String, String> fieldErrors;

  final Map<String, dynamic>? details;

  // --- Codes the UI branches on ---------------------------------------------

  static const String networkUnavailable = 'NETWORK_UNAVAILABLE';
  static const String timeout = 'TIMEOUT';
  static const String cancelled = 'REQUEST_CANCELLED';
  static const String unknown = 'UNKNOWN_ERROR';
  static const String validation = 'VALIDATION_ERROR';
  static const String invalidCredentials = 'INVALID_CREDENTIALS';
  static const String tokenExpired = 'TOKEN_EXPIRED';
  static const String tokenRevoked = 'TOKEN_REVOKED';
  static const String authRequired = 'AUTH_REQUIRED';
  static const String refreshTokenReused = 'REFRESH_TOKEN_REUSED';
  static const String accountExists = 'ACCOUNT_EXISTS';
  static const String accountNotFound = 'ACCOUNT_NOT_FOUND';
  static const String accountSuspended = 'ACCOUNT_SUSPENDED';
  static const String otpCooldown = 'OTP_COOLDOWN';
  static const String otpIncorrect = 'OTP_INCORRECT';
  static const String otpExpired = 'OTP_EXPIRED';
  static const String otpAttemptsExceeded = 'OTP_ATTEMPTS_EXCEEDED';
  static const String otpLimitReached = 'OTP_LIMIT_REACHED';
  static const String verificationTokenMissing = 'VERIFICATION_TOKEN_MISSING';
  static const String bookingStateChanged = 'BOOKING_STATE_CHANGED';
  static const String bookingNotCancellable = 'BOOKING_NOT_CANCELLABLE';
  static const String bookingAlreadyCancelled = 'BOOKING_ALREADY_CANCELLED';
  static const String bookingAlreadyCompleted = 'BOOKING_ALREADY_COMPLETED';
  static const String businessContactNotConfigured = 'BUSINESS_CONTACT_NOT_CONFIGURED';
  static const String rateLimited = 'RATE_LIMITED';
  static const String sameLocation = 'SAME_LOCATION';
  static const String invalidCoordinates = 'INVALID_COORDINATES';

  /// True when retrying the identical request could plausibly succeed.
  bool get isRetryable =>
      code == networkUnavailable || code == timeout || (statusCode != null && statusCode! >= 500);

  /// True when the session is gone and the customer must sign in again.
  bool get requiresReauthentication =>
      code == tokenRevoked ||
      code == refreshTokenReused ||
      code == authRequired ||
      code == 'REFRESH_TOKEN_INVALID' ||
      code == 'REFRESH_TOKEN_EXPIRED' ||
      code == 'REFRESH_TOKEN_MISSING';

  /// Maps a [DioException] onto this type.
  factory ApiException.from(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      // A transform timeout means the body arrived but decoding it stalled.
      // Indistinguishable from a slow server as far as the customer is
      // concerned, so it gets the same message.
      case DioExceptionType.transformTimeout:
        return const ApiException(
          message: 'The server took too long to respond. Please try again.',
          code: timeout,
        );

      case DioExceptionType.connectionError:
        return const ApiException(
          message: 'No connection to the server. Check your internet and try again.',
          code: networkUnavailable,
        );

      case DioExceptionType.cancel:
        return const ApiException(message: 'Request cancelled.', code: cancelled);

      case DioExceptionType.badCertificate:
        return const ApiException(
          message: 'Could not establish a secure connection to the server.',
          code: 'BAD_CERTIFICATE',
        );

      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        return ApiException._fromResponse(error);
    }
  }

  factory ApiException._fromResponse(DioException error) {
    final response = error.response;
    final status = response?.statusCode;
    final data = response?.data;

    // The backend always answers with { success, message, code, details? }.
    if (data is Map) {
      final fields = <String, String>{};
      final rawFields = data['details'] is Map ? (data['details'] as Map)['fields'] : null;
      if (rawFields is Map) {
        rawFields.forEach((key, value) {
          fields['$key'] = '$value';
        });
      }

      return ApiException(
        message: (data['message'] as String?)?.trim().isNotEmpty == true
            ? data['message'] as String
            : _messageForStatus(status),
        code: (data['code'] as String?) ?? _codeForStatus(status),
        statusCode: status,
        fieldErrors: fields,
        details: data['details'] is Map ? Map<String, dynamic>.from(data['details'] as Map) : null,
      );
    }

    // An HTML error page or an empty body - the server is up but not ours, or
    // a proxy answered. Do not show the raw body to the customer.
    return ApiException(
      message: _messageForStatus(status),
      code: _codeForStatus(status),
      statusCode: status,
    );
  }

  static String _messageForStatus(int? status) {
    switch (status) {
      case 400:
        return 'That request was not valid. Please check your details.';
      case 401:
        return 'Please sign in to continue.';
      case 403:
        return 'You do not have permission to do that.';
      case 404:
        return 'We could not find what you were looking for.';
      case 409:
        return 'That conflicts with something that already exists.';
      case 429:
        return 'Too many requests. Please wait a moment and try again.';
      case 500:
      case 502:
      case 503:
      case 504:
        return 'The server is having trouble. Please try again shortly.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  static String _codeForStatus(int? status) {
    switch (status) {
      case 401:
        return authRequired;
      case 429:
        return rateLimited;
      case null:
        return unknown;
      default:
        return 'HTTP_$status';
    }
  }

  /// For a non-Dio error that still has to reach the UI as something sensible.
  factory ApiException.unexpected(Object error) => ApiException(
        message: 'Something went wrong. Please try again.',
        code: unknown,
        details: {'error': error.toString()},
      );

  @override
  String toString() => 'ApiException($code${statusCode != null ? ' $statusCode' : ''}): $message';
}
