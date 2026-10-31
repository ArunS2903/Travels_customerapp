import 'package:customer_app/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phone normalisation is the one piece of client-side logic that can silently
/// break an account: if the app normalises differently from the backend, the
/// customer registers one number and signs in against another. These tests pin
/// the behaviour to match `backend/src/utils/phone.js`.
void main() {
  group('normalizePhone', () {
    test('prefixes a bare 10-digit national number', () {
      expect(Validators.normalizePhone('9876543210'), '+919876543210');
    });

    test('keeps an existing country code', () {
      expect(Validators.normalizePhone('+919876543210'), '+919876543210');
    });

    test('strips spaces, dashes, dots and brackets', () {
      expect(Validators.normalizePhone('+91 98765-43210'), '+919876543210');
      expect(Validators.normalizePhone('(098765) 43210'), '+919876543210');
      expect(Validators.normalizePhone('98765.43210'), '+919876543210');
    });

    test('drops a national trunk prefix', () {
      expect(Validators.normalizePhone('09876543210'), '+919876543210');
    });

    test('honours a non-default country code', () {
      expect(
        Validators.normalizePhone('7700900123', countryCode: '+44'),
        '+447700900123',
      );
    });

    test('is idempotent', () {
      const raw = '9876543210';
      final once = Validators.normalizePhone(raw);
      expect(Validators.normalizePhone(once), once);
    });
  });

  group('phone validation', () {
    test('accepts a 10-digit number', () {
      expect(Validators.phone('9876543210'), isNull);
    });

    test('accepts an international number', () {
      expect(Validators.phone('+919876543210'), isNull);
    });

    test('rejects an empty value', () {
      expect(Validators.phone(''), isNotNull);
      expect(Validators.phone(null), isNotNull);
    });

    test('rejects too few digits', () {
      expect(Validators.phone('98765'), isNotNull);
    });

    test('rejects absurdly long input', () {
      expect(Validators.phone('+9198765432109876543'), isNotNull);
    });
  });

  group('email validation', () {
    test('accepts ordinary addresses', () {
      expect(Validators.email('customer@example.com'), isNull);
      expect(Validators.email('first.last+tag@sub.example.co.uk'), isNull);
    });

    test('rejects malformed addresses', () {
      for (final bad in ['no-at-sign', 'missing@tld', '@example.com', 'spaces in@x.com']) {
        expect(Validators.email(bad), isNotNull, reason: 'should reject "$bad"');
      }
    });

    test('allows an empty value only when optional', () {
      expect(Validators.email('', optional: true), isNull);
      expect(Validators.email(''), isNotNull);
    });
  });

  group('password validation', () {
    test('accepts a password meeting the backend policy', () {
      expect(Validators.password('Password123'), isNull);
    });

    test('rejects passwords under 8 characters', () {
      expect(Validators.password('Pass1'), isNotNull);
    });

    test('requires a letter and a digit', () {
      expect(Validators.password('12345678'), isNotNull);
      expect(Validators.password('abcdefgh'), isNotNull);
    });

    test('rejects an over-long password', () {
      expect(Validators.password('${'a' * 130}1'), isNotNull);
    });
  });

  group('confirmPassword', () {
    test('passes when both match', () {
      expect(Validators.confirmPassword('Password123', 'Password123'), isNull);
    });

    test('fails on mismatch', () {
      expect(Validators.confirmPassword('Password123', 'Password124'), isNotNull);
    });
  });

  group('looksLikeEmail', () {
    test('routes the combined sign-in field correctly', () {
      expect(Validators.looksLikeEmail('customer@example.com'), isTrue);
      expect(Validators.looksLikeEmail('9876543210'), isFalse);
      expect(Validators.looksLikeEmail('+91 98765 43210'), isFalse);
    });
  });

  group('fullName', () {
    test('accepts names with spaces, hyphens and apostrophes', () {
      expect(Validators.fullName('Asha Babu'), isNull);
      expect(Validators.fullName("O'Brien-Smith"), isNull);
    });

    test('rejects digits and symbols', () {
      expect(Validators.fullName('Customer123'), isNotNull);
      expect(Validators.fullName('a@b'), isNotNull);
    });

    test('rejects a single character', () {
      expect(Validators.fullName('A'), isNotNull);
    });
  });

  group('otp', () {
    test('accepts the configured length', () {
      expect(Validators.otp('123456'), isNull);
      expect(Validators.otp('1234', length: 4), isNull);
    });

    test('rejects the wrong length or non-digits', () {
      expect(Validators.otp('12345'), isNotNull);
      expect(Validators.otp('12345a'), isNotNull);
    });
  });
}
