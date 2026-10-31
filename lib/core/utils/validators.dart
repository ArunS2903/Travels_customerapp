/// Form validators.
///
/// These mirror the backend's rules so a customer gets instant feedback, but
/// they are never the enforcement point - the server validates everything
/// again, and a server-side field error is shown in preference to these.
class Validators {
  const Validators._();

  /// Matches the backend's `^\+[1-9]\d{7,14}$` once a country code is added,
  /// and also accepts a bare 10-digit national number.
  static final RegExp _digitsOnly = RegExp(r'\D');
  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  static final RegExp _namePattern = RegExp(r"^[\p{L}\p{M}\s.'-]+$", unicode: true);

  static String? required(String? value, {String field = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$field is required.';
    return null;
  }

  static String? fullName(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return 'Enter your full name.';
    if (trimmed.length < 2) return 'That name looks too short.';
    if (trimmed.length > 80) return 'Please use 80 characters or fewer.';
    if (!_namePattern.hasMatch(trimmed)) {
      return 'Use letters, spaces, apostrophes and hyphens only.';
    }
    return null;
  }

  static String? phone(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return 'Enter your mobile number.';

    final digits = trimmed.replaceAll(_digitsOnly, '');
    if (digits.length < 10) return 'Enter all 10 digits of your mobile number.';
    if (!trimmed.startsWith('+') && digits.length > 12) {
      return 'That number has too many digits.';
    }
    if (digits.length > 15) return 'That number has too many digits.';
    return null;
  }

  static String? email(String? value, {bool optional = false}) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return optional ? null : 'Enter your email address.';
    if (!_emailPattern.hasMatch(trimmed)) return 'Enter a valid email address.';
    if (trimmed.length > 160) return 'That email address is too long.';
    return null;
  }

  /// Same policy as the backend: 8+ characters, at least one letter and digit.
  static String? password(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Enter a password.';
    if (password.length < 8) return 'Use at least 8 characters.';
    if (password.length > 128) return 'Use 128 characters or fewer.';
    if (!RegExp(r'[A-Za-z]').hasMatch(password)) return 'Include at least one letter.';
    if (!RegExp(r'\d').hasMatch(password)) return 'Include at least one number.';
    return null;
  }

  /// For a sign-in field, where we must not hint at the stored password's shape.
  static String? passwordPresent(String? value) {
    if ((value ?? '').isEmpty) return 'Enter your password.';
    return null;
  }

  static String? confirmPassword(String? value, String? original) {
    if ((value ?? '').isEmpty) return 'Re-enter your password.';
    if (value != original) return 'Passwords do not match.';
    return null;
  }

  static String? otp(String? value, {int length = 6}) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return 'Enter the code we sent you.';
    if (trimmed.length != length) return 'Enter all $length digits.';
    if (RegExp(r'\D').hasMatch(trimmed)) return 'The code is digits only.';
    return null;
  }

  static String? addressLabel(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return 'Give this address a name.';
    if (trimmed.length > 40) return 'Use 40 characters or fewer.';
    return null;
  }

  /// Phone normalisation matching `backend/src/utils/phone.js`, so the number
  /// the customer typed and the number stored on the account always agree.
  static String normalizePhone(String raw, {String countryCode = '+91'}) {
    final trimmed = raw.trim().replaceAll(RegExp(r'[\s()\-.]'), '');
    final hasPlus = trimmed.startsWith('+');
    final digits = trimmed.replaceAll(_digitsOnly, '');

    if (digits.isEmpty) return raw.trim();
    if (hasPlus) return '+$digits';
    if (digits.length == 10) return '$countryCode$digits';
    if (digits.length > 10 && digits.startsWith('0')) {
      return '$countryCode${digits.replaceFirst(RegExp(r'^0+'), '')}';
    }
    return '+$digits';
  }

  /// True when the string looks like an email rather than a phone number, used
  /// by the single "mobile number or email" sign-in field.
  static bool looksLikeEmail(String value) => value.contains('@');
}
