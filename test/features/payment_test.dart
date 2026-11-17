import 'package:customer_app/core/constants/booking_status.dart';
import 'package:customer_app/features/booking_details/data/booking_repository.dart';
import 'package:customer_app/features/booking_details/models/booking.dart';
import 'package:customer_app/features/support/data/support_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// The payment half of a booking, on the client side.
///
/// The thing under test throughout is the distinction between a payment being
/// *marked* paid and being *proved* paid. The app shows the Completed and
/// Confirm Paid actions on the strength of the proof, so a bug that conflated
/// the two would offer them on an unverified claim.
void main() {
  group('BookingPayment', () {
    test('reads the verification flag rather than inferring it from status', () {
      final payment = BookingPayment.fromJson(const {
        'status': 'Awaiting Verification',
        'amount': 3200,
        'isPaid': false,
        'isTruePayment': false,
        'awaitingVerification': true,
        'transactionId': '432199887766',
      });

      expect(payment.isPaid, isFalse);
      expect(payment.isTruePayment, isFalse);
      expect(payment.awaitingVerification, isTrue);
      expect(payment.transactionId, '432199887766');
    });

    test('a verified payment carries who proved it and when', () {
      final payment = BookingPayment.fromJson(const {
        'status': 'Paid',
        'isPaid': true,
        'isTruePayment': true,
        'verifiedBy': 'admin',
        'verifiedAt': '2026-11-15T13:37:00.000Z',
      });

      expect(payment.isTruePayment, isTrue);
      expect(payment.verifiedBy, 'admin');
      expect(payment.verifiedAt, DateTime.parse('2026-11-15T13:37:00.000Z'));
    });

    /// A booking written before the flag existed was never gateway-verified,
    /// so false is the honest default rather than a missing value the UI would
    /// have to treat as true.
    test('defaults to unverified when the server did not say', () {
      final payment = BookingPayment.fromJson(const {'status': 'Paid', 'isPaid': true});
      expect(payment.isTruePayment, isFalse);
      expect(payment.verifiedBy, isNull);
    });

    test('tracks the two customer acknowledgements separately', () {
      final none = BookingPayment.fromJson(const {'isTruePayment': true});
      expect(none.hasConfirmedPaid, isFalse);
      expect(none.hasConfirmedCompleted, isFalse);

      final both = BookingPayment.fromJson(const {
        'isTruePayment': true,
        'customerConfirmedPaidAt': '2026-11-15T13:38:06.000Z',
        'customerCompletedAt': '2026-11-15T13:38:07.000Z',
      });
      expect(both.hasConfirmedPaid, isTrue);
      expect(both.hasConfirmedCompleted, isTrue);
    });

    test('reports a rejected reference so the card can explain it', () {
      final rejected = BookingPayment.fromJson(const {
        'status': 'Pending',
        'rejectionReason': 'No matching credit on that date.',
      });
      expect(rejected.wasRejected, isTrue);
      expect(rejected.rejectionReason, 'No matching credit on that date.');

      expect(BookingPayment.fromJson(const {}).wasRejected, isFalse);
    });
  });

  group('payment method labels', () {
    /// The stored values stay `GPay` and `Cash` - they are on every historical
    /// booking - while the customer sees the spec's wording.
    test('GPay reads as Online Payment and Cash as Cash on Pay', () {
      expect(PaymentMethod.gpay.apiValue, 'GPay');
      expect(PaymentMethod.gpay.label, 'Online Payment');
      expect(PaymentMethod.cash.apiValue, 'Cash');
      expect(PaymentMethod.cash.label, 'Cash on Pay');
    });

    test('only those two are offered for a new hire', () {
      expect(PaymentMethod.offeredForHire, [PaymentMethod.gpay, PaymentMethod.cash]);
      expect(PaymentMethod.upi.isOfferedForHire, isFalse);
      expect(PaymentMethod.card.isOfferedForHire, isFalse);
    });

    test('an unknown method from the server falls back to cash, not a crash', () {
      expect(PaymentMethod.fromApi('Bitcoin'), PaymentMethod.cash);
      expect(PaymentMethod.fromApi(null), PaymentMethod.cash);
    });
  });

  group('ServerCapabilities', () {
    test('reads the online payment mode and the UPI payee', () {
      final capabilities = ServerCapabilities.fromJson(const {
        'appName': 'PP Travels & Cab',
        'paymentMethods': ['GPay', 'Cash'],
        'paymentMethodLabels': {'GPay': 'Online Payment', 'Cash': 'Cash on Pay'},
        'upi': {'vpa': 'arun4315d29-2@okhdfcbank', 'name': 'PP Travels & Cab'},
        'features': {
          'onlinePaymentMode': 'upi',
          'paymentNeedsVerification': true,
        },
      });

      expect(capabilities.appName, 'PP Travels & Cab');
      expect(capabilities.hasOnlinePayments, isTrue);
      expect(capabilities.usesDirectUpi, isTrue);
      expect(capabilities.paymentNeedsVerification, isTrue);
      expect(capabilities.upiPayeeVpa, 'arun4315d29-2@okhdfcbank');
      expect(capabilities.labelForPaymentMethod('GPay'), 'Online Payment');
    });

    /// A gateway confirms its own payments, so the app must not ask for a
    /// reference afterwards - the branch in the booking screen turns on this.
    test('a gateway deployment does not use the direct-UPI flow', () {
      final capabilities = ServerCapabilities.fromJson(const {
        'features': {'onlinePaymentMode': 'razorpay', 'paymentNeedsVerification': false},
      });

      expect(capabilities.hasOnlinePayments, isTrue);
      expect(capabilities.usesDirectUpi, isFalse);
      expect(capabilities.paymentNeedsVerification, isFalse);
    });

    test('with no online route configured, nothing online is offered', () {
      final capabilities = ServerCapabilities.fromJson(const {'features': {}});
      expect(capabilities.hasOnlinePayments, isFalse);
      expect(capabilities.usesDirectUpi, isFalse);
    });

    test('an unmapped method falls back to its stored name', () {
      final capabilities = ServerCapabilities.fromJson(const {'features': {}});
      expect(capabilities.labelForPaymentMethod('Wallet'), 'Wallet');
    });
  });

  group('UpiPaymentIntent', () {
    test('reads the links, the payee and what to do next', () {
      final intent = UpiPaymentIntent.fromJson(const {
        'bookingCode': 'TX-000042',
        'payment': {
          'intentUrl': 'upi://pay?pa=arun4315d29-2%40okhdfcbank&am=3200.00',
          'gpayUrl': 'tez://upi/pay?pa=arun4315d29-2%40okhdfcbank&am=3200.00',
          'payeeVpa': 'arun4315d29-2@okhdfcbank',
          'payeeName': 'PP Travels & Cab',
          'amount': 3200,
          'currencySymbol': '₹',
          'reference': 'TX000042',
          'referenceLabel': 'UPI transaction ID (UTR)',
          'referenceHint': 'Usually a 12-digit number on your payment receipt.',
        },
        'verification': {
          'required': true,
          'instructions': 'Pay the full amount, then submit the UTR.',
        },
      });

      expect(intent.intentUrl, startsWith('upi://pay?'));
      expect(intent.payeeVpa, 'arun4315d29-2@okhdfcbank');
      expect(intent.amount, 3200);
      expect(intent.reference, 'TX000042');
      expect(intent.requiresReference, isTrue);
      expect(intent.instructions, 'Pay the full amount, then submit the UTR.');
    });

    test('a gateway intent that needs no reference says so', () {
      final intent = UpiPaymentIntent.fromJson(const {
        'payment': {'intentUrl': 'upi://pay?pa=x', 'amount': 10},
        'verification': {'required': false},
      });
      expect(intent.requiresReference, isFalse);
    });
  });
}
