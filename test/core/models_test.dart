import 'package:customer_app/core/constants/booking_status.dart';
import 'package:customer_app/core/utils/polyline_decoder.dart';
import 'package:customer_app/features/booking_details/models/booking.dart';
import 'package:customer_app/features/vehicle_selection/models/vehicle_estimate.dart';
import 'package:customer_app/shared/models/paginated_result.dart';
import 'package:customer_app/shared/models/place.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parsing tests.
///
/// The app parses JSON it did not write, so these cover the shapes that would
/// otherwise crash a screen: absent optional fields, numbers arriving as `int`
/// where `double` is expected, and enum values the app has never heard of.
void main() {
  group('Place', () {
    test('rejects the uninitialised (0, 0) coordinate pair', () {
      const place = Place(address: 'Nowhere', latitude: 0, longitude: 0);
      expect(place.hasValidCoordinates, isFalse);
    });

    test('accepts real coordinates', () {
      const place = Place(address: 'Coimbatore', latitude: 11.0183, longitude: 76.9725);
      expect(place.hasValidCoordinates, isTrue);
    });

    test('rejects out-of-range coordinates', () {
      const place = Place(address: 'Broken', latitude: 91, longitude: 0);
      expect(place.hasValidCoordinates, isFalse);
    });

    test('treats nearby points as the same location', () {
      const a = Place(address: 'A', latitude: 11.0183, longitude: 76.9725);
      // Roughly 11 m away.
      const b = Place(address: 'B', latitude: 11.01840, longitude: 76.97255);
      expect(a.isSameLocationAs(b), isTrue);
    });

    test('treats distant points as different', () {
      const a = Place(address: 'A', latitude: 11.0183, longitude: 76.9725);
      const b = Place(address: 'B', latitude: 11.0300, longitude: 77.0434);
      expect(a.isSameLocationAs(b), isFalse);
    });

    test('splits an address into a headline and detail', () {
      const place = Place(
        address: '12 Gandhipuram, Coimbatore, Tamil Nadu',
        latitude: 11.0183,
        longitude: 76.9725,
      );
      expect(place.shortAddress, '12 Gandhipuram');
      expect(place.addressDetail, 'Coimbatore, Tamil Nadu');
    });

    test('round-trips through JSON', () {
      const place = Place(
        address: 'Tidel Park',
        latitude: 11.03,
        longitude: 77.0434,
        placeId: 'abc123',
      );
      final restored = Place.fromJson(place.toJson());

      expect(restored.address, place.address);
      expect(restored.latitude, place.latitude);
      expect(restored.placeId, 'abc123');
    });

    test('parses integer coordinates sent as JSON numbers', () {
      final place = Place.fromJson({'address': 'X', 'latitude': 11, 'longitude': 77});
      expect(place.latitude, 11.0);
      expect(place.longitude, 77.0);
    });
  });

  group('BookingStatus', () {
    test('maps every API value', () {
      expect(BookingStatus.fromApi('Pending'), BookingStatus.pending);
      expect(BookingStatus.fromApi('Driver Assigned'), BookingStatus.driverAssigned);
      expect(BookingStatus.fromApi('In Progress'), BookingStatus.inProgress);
      expect(BookingStatus.fromApi('Completed'), BookingStatus.completed);
      expect(BookingStatus.fromApi('Cancelled'), BookingStatus.cancelled);
    });

    test('is case-insensitive', () {
      expect(BookingStatus.fromApi('driver assigned'), BookingStatus.driverAssigned);
    });

    test('degrades to unknown rather than throwing on a new status', () {
      expect(BookingStatus.fromApi('Awaiting Payment'), BookingStatus.unknown);
      expect(BookingStatus.fromApi(null), BookingStatus.unknown);
    });

    test('classifies statuses for the My Bookings tabs', () {
      expect(BookingStatus.pending.isUpcoming, isTrue);
      expect(BookingStatus.inProgress.isActive, isTrue);
      expect(BookingStatus.completed.isTerminal, isTrue);
      expect(BookingStatus.cancelled.isTerminal, isTrue);
    });

    test('allows cancelling only up to the trip starting', () {
      expect(BookingStatus.pending.isCancellable, isTrue);
      expect(BookingStatus.driverArrived.isCancellable, isTrue);
      expect(BookingStatus.inProgress.isCancellable, isFalse);
      expect(BookingStatus.completed.isCancellable, isFalse);
    });

    test('has no progress step for a cancelled booking', () {
      expect(BookingStatus.cancelled.progressStep, isNull);
      expect(BookingStatus.pending.progressStep, 0);
      expect(BookingStatus.completed.progressStep, 5);
    });
  });

  group('PaymentMethod and PaymentStatus', () {
    test('parse their API values', () {
      expect(PaymentMethod.fromApi('UPI'), PaymentMethod.upi);
      expect(PaymentStatus.fromApi('Paid'), PaymentStatus.paid);
    });

    test('fall back safely on an unknown value', () {
      expect(PaymentMethod.fromApi('Crypto'), PaymentMethod.cash);
      expect(PaymentStatus.fromApi('Disputed'), PaymentStatus.pending);
    });
  });

  group('FareBreakdown', () {
    final json = {
      'currency': 'INR',
      'currencySymbol': '₹',
      'baseFare': 55,
      'distanceFare': 168,
      'timeFare': 0,
      'waitingCharge': 0,
      'nightSurcharge': 0,
      'platformFee': 10,
      'additionalCharges': [
        {'label': 'Airport levy', 'amount': 25},
      ],
      'surgeMultiplier': 1,
      'subtotal': 258,
      'minimumFareApplied': false,
      'taxPercent': 5,
      'taxAmount': 12.9,
      'total': 271,
    };

    test('parses every component', () {
      final fare = FareBreakdown.fromJson(json);

      expect(fare.baseFare, 55);
      expect(fare.distanceFare, 168);
      expect(fare.additionalCharges.single.label, 'Airport levy');
      expect(fare.total, 271);
    });

    test('omits zero-value lines from the display', () {
      final fare = FareBreakdown.fromJson(json);
      final labels = fare.visibleLines.map((line) => line.label).toList();

      expect(labels, contains('Base fare'));
      expect(labels, contains('Distance'));
      expect(labels, contains('Airport levy'));
      // Zeroes would just be noise in the breakdown.
      expect(labels, isNot(contains('Time')));
      expect(labels, isNot(contains('Waiting charge')));
    });

    test('flags a surge', () {
      expect(FareBreakdown.fromJson({...json, 'surgeMultiplier': 1.5}).hasSurge, isTrue);
      expect(FareBreakdown.fromJson(json).hasSurge, isFalse);
    });

    test('survives a response with fields missing', () {
      final fare = FareBreakdown.fromJson({'total': 100});
      expect(fare.total, 100);
      expect(fare.baseFare, 0);
      expect(fare.additionalCharges, isEmpty);
    });
  });

  group('Booking', () {
    final json = {
      'id': '507f1f77bcf86cd799439011',
      'bookingCode': 'TX-000042',
      'customer': {'id': 'c1', 'name': 'Asha Babu', 'phone': '+919876543210'},
      'vehicleType': {'id': 'v1', 'name': 'Sedan', 'code': 'SEDAN'},
      'pickup': {'address': 'A', 'latitude': 11.0183, 'longitude': 76.9725},
      'destination': {'address': 'B', 'latitude': 11.03, 'longitude': 77.0434},
      'distanceKm': 12.5,
      'durationMinutes': 29,
      'estimatedFare': 320,
      'finalFare': null,
      'bookingStatus': 'Pending',
      'paymentMethod': 'Cash',
      'paymentStatus': 'Pending',
      'createdAt': '2026-03-14T09:15:00.000Z',
    };

    test('parses the core fields', () {
      final booking = Booking.fromJson(json);

      expect(booking.bookingCode, 'TX-000042');
      expect(booking.customerName, 'Asha Babu');
      expect(booking.vehicleTypeName, 'Sedan');
      expect(booking.status, BookingStatus.pending);
      expect(booking.distanceKm, 12.5);
    });

    test('shows the estimate until a final fare exists', () {
      final booking = Booking.fromJson(json);
      expect(booking.isFareFinal, isFalse);
      expect(booking.displayFare, 320);

      final completed = Booking.fromJson({...json, 'finalFare': 345});
      expect(completed.isFareFinal, isTrue);
      expect(completed.displayFare, 345);
    });

    test('tolerates every optional field being absent', () {
      final booking = Booking.fromJson(json);

      expect(booking.driver, isNull);
      expect(booking.cancellation, isNull);
      expect(booking.businessContact, isNull);
      expect(booking.fareBreakdown, isNull);
      expect(booking.statusHistory, isEmpty);
      expect(booking.isScheduled, isFalse);
    });

    test('parses a cancellation and its fee', () {
      final booking = Booking.fromJson({
        ...json,
        'bookingStatus': 'Cancelled',
        'cancellation': {
          'reason': 'Plans changed',
          'cancelledByRole': 'customer',
          'fee': 30,
          'feeWaived': false,
          'cancelledAt': '2026-03-14T09:20:00.000Z',
        },
      });

      expect(booking.status, BookingStatus.cancelled);
      expect(booking.cancellation!.fee, 30);
      expect(booking.cancellation!.wasCancelledByCustomer, isTrue);
    });

    test('exposes the contact snapshot captured on the booking', () {
      final booking = Booking.fromJson({
        ...json,
        'businessContact': {
          'businessName': 'Your Taxi Service',
          'supportPhone': '+919000000001',
          'adminPhone': '+919000000000',
        },
      });

      // Support line is preferred over the general admin number.
      expect(booking.businessContact!.callNumber, '+919000000001');
      expect(booking.businessContact!.hasAnyContact, isTrue);
    });
  });

  group('BookingSummary', () {
    test('falls back to estimatedFare when displayFare is absent', () {
      final summary = BookingSummary.fromJson({
        'id': 'b1',
        'bookingCode': 'TX-000001',
        'pickupAddress': 'A',
        'destinationAddress': 'B',
        'vehicleTypeName': 'Mini',
        'bookingStatus': 'Pending',
        'paymentStatus': 'Pending',
        'createdAt': '2026-03-14T09:15:00.000Z',
        'estimatedFare': 120,
      });

      expect(summary.displayFare, 120);
      expect(summary.isFareFinal, isFalse);
    });
  });

  group('PaginatedResult', () {
    test('parses the envelope and computes hasMore when absent', () {
      final page = PaginatedResult.fromJson(
        {
          'items': [
            {'value': 1},
          ],
          'page': 1,
          'limit': 10,
          'total': 25,
        },
        (json) => json['value'] as int,
      );

      expect(page.items, [1]);
      expect(page.hasMore, isTrue);
    });

    test('trusts the server over its own arithmetic', () {
      final page = PaginatedResult.fromJson(
        {'items': <dynamic>[], 'page': 1, 'limit': 10, 'total': 25, 'hasMore': false},
        (json) => json,
      );
      expect(page.hasMore, isFalse);
    });

    test('merges pages in order', () {
      const first = PaginatedResult<int>(
        items: [1, 2],
        page: 1,
        limit: 2,
        total: 4,
        hasMore: true,
      );
      const second = PaginatedResult<int>(
        items: [3, 4],
        page: 2,
        limit: 2,
        total: 4,
        hasMore: false,
      );

      final merged = first.merge(second);
      expect(merged.items, [1, 2, 3, 4]);
      expect(merged.hasMore, isFalse);
      expect(merged.page, 2);
    });

    test('handles a malformed items field', () {
      final page = PaginatedResult.fromJson({'items': 'not a list'}, (json) => json);
      expect(page.items, isEmpty);
    });
  });

  group('PolylineDecoder', () {
    test('decodes the reference example from Google docs', () {
      // `_p~iF~ps|U_ulLnnqC_mqNvxq`@` is the documented sample.
      final points = PolylineDecoder.decode(r'_p~iF~ps|U_ulLnnqC_mqNvxq`@');

      expect(points, hasLength(3));
      expect(points[0].latitude, closeTo(38.5, 0.0001));
      expect(points[0].longitude, closeTo(-120.2, 0.0001));
      expect(points[2].latitude, closeTo(43.252, 0.0001));
      expect(points[2].longitude, closeTo(-126.453, 0.0001));
    });

    test('returns nothing for empty or null input', () {
      expect(PolylineDecoder.decode(null), isEmpty);
      expect(PolylineDecoder.decode(''), isEmpty);
    });

    test('does not throw on a truncated string', () {
      expect(() => PolylineDecoder.decode('_p~iF~ps|U_ul'), returnsNormally);
    });

    test('computes padded bounds around the points', () {
      final points = PolylineDecoder.decode(r'_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      final bounds = PolylineDecoder.boundsFor(points);

      expect(bounds, isNotNull);
      expect(bounds!.southwest.latitude, lessThan(38.5));
      expect(bounds.northeast.latitude, greaterThan(43.252));
    });

    test('has no bounds for no points', () {
      expect(PolylineDecoder.boundsFor(const []), isNull);
    });
  });

  group('FareEstimateResult', () {
    test('picks the cheapest available option', () {
      final result = FareEstimateResult.fromJson({
        'route': {'distanceKm': 12.5, 'durationMinutes': 29, 'isApproximate': false},
        'estimates': [
          {
            'id': 'v1',
            'name': 'Sedan',
            'code': 'SEDAN',
            'passengerCapacity': 4,
            'isAvailable': true,
            'fare': {
              'total': 320,
              'breakdown': {'total': 320, 'currencySymbol': '₹'},
            },
          },
          {
            'id': 'v2',
            'name': 'Mini',
            'code': 'MINI',
            'passengerCapacity': 4,
            'isAvailable': true,
            'fare': {
              'total': 210,
              'breakdown': {'total': 210, 'currencySymbol': '₹'},
            },
          },
          {
            'id': 'v3',
            'name': 'SUV',
            'code': 'SUV',
            'passengerCapacity': 6,
            'isAvailable': false,
            'unavailableReason': 'Pricing not configured',
          },
        ],
        'disclaimer': 'Fares are estimates.',
      });

      expect(result.estimates, hasLength(3));
      expect(result.available, hasLength(2));
      expect(result.cheapest!.vehicleType.name, 'Mini');
      // An unpriced category is listed but not bookable, not hidden.
      expect(result.estimates.last.isAvailable, isFalse);
      expect(result.estimates.last.unavailableReason, 'Pricing not configured');
    });

    test('has no cheapest option when nothing is available', () {
      final result = FareEstimateResult.fromJson({
        'route': {'distanceKm': 1, 'durationMinutes': 5, 'isApproximate': true},
        'estimates': [
          {
            'id': 'v1',
            'name': 'Sedan',
            'code': 'SEDAN',
            'passengerCapacity': 4,
            'isAvailable': false,
          },
        ],
        'disclaimer': 'x',
      });

      expect(result.cheapest, isNull);
    });
  });
}
