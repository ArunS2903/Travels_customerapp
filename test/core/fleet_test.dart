import 'package:customer_app/core/constants/booking_status.dart';
import 'package:customer_app/features/booking_confirmation/providers/booking_draft_controller.dart';
import 'package:customer_app/features/booking_details/models/booking.dart';
import 'package:customer_app/features/fleet/models/fleet_vehicle.dart';
import 'package:customer_app/shared/models/place.dart';
import 'package:flutter_test/flutter_test.dart';

/// The hire flow: the fleet, the period, the draft, and the driver-allocation
/// status.
///
/// These are the pieces that decide what the customer is shown and what is
/// submitted, so the cases covered are the ones that would otherwise be wrong
/// silently: a day count that bills an extra day, a vehicle selection that
/// survives a date change it should not, and an allocation status read from a
/// field the server did not send.
void main() {
  const pickup = Place(
    address: 'Gandhipuram',
    latitude: 11.0183,
    longitude: 76.9725,
  );
  const drop = Place(address: 'Ooty', latitude: 11.4102, longitude: 76.6950);

  group('HirePeriod', () {
    test('a same-day hire still bills one day', () {
      final period = HirePeriod(
        startAt: DateTime(2026, 11, 12, 9),
        endAt: DateTime(2026, 11, 12, 18),
      );

      expect(period.days, 1);
    });

    test('counts whole days between the two dates', () {
      final period = HirePeriod(
        startAt: DateTime(2026, 11, 12, 9),
        endAt: DateTime(2026, 11, 15, 9),
      );

      expect(period.days, 3);
    });

    test(
      'forgives a few minutes of overshoot rather than billing a whole day',
      () {
        // The case this exists for: a client computing "three days from now"
        // evaluates its two ends milliseconds apart, and a customer handing the
        // keys back slightly late should not be charged a fourth day. Matches the
        // 15-minute grace in the backend's hire service.
        final period = HirePeriod(
          startAt: DateTime(2026, 11, 12, 9),
          endAt: DateTime(2026, 11, 15, 9, 10),
        );

        expect(period.days, 3);
      },
    );

    test('bills the extra day once the overshoot is real', () {
      final period = HirePeriod(
        startAt: DateTime(2026, 11, 12, 9),
        endAt: DateTime(2026, 11, 15, 12),
      );

      expect(period.days, 4);
    });

    test('is a value type, so the provider family caches by dates', () {
      final a = HirePeriod(
        startAt: DateTime(2026, 11, 12, 9),
        endAt: DateTime(2026, 11, 13, 9),
      );
      final b = HirePeriod(
        startAt: DateTime(2026, 11, 12, 9),
        endAt: DateTime(2026, 11, 13, 9),
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test(
      'sends both ends of the window, which the backend requires together',
      () {
        final period = HirePeriod(
          startAt: DateTime.utc(2026, 11, 12, 9),
          endAt: DateTime.utc(2026, 11, 13, 9),
        );

        expect(
          period.toQuery().keys,
          containsAll(['availableFrom', 'availableTo']),
        );
        expect(period.toQuery()['availableFrom'], '2026-11-12T09:00:00.000Z');
      },
    );

    test('preserves the local pickup instant when serializing it as UTC', () {
      final localStart = DateTime(2026, 11, 12, 9);
      final period = HirePeriod(
        startAt: localStart,
        endAt: localStart.add(const Duration(days: 1)),
      );
      final serializedStart = DateTime.parse(
        period.toQuery()['availableFrom']!,
      );

      expect(serializedStart.isUtc, isTrue);
      expect(serializedStart.isAtSameMomentAs(localStart), isTrue);
    });

    test('a backwards period is not valid', () {
      final period = HirePeriod(
        startAt: DateTime(2026, 11, 15),
        endAt: DateTime(2026, 11, 12),
      );

      expect(period.isValid, isFalse);
    });
  });

  group('FleetVehicle', () {
    Map<String, dynamic> json({Object? images, Object? primary}) => {
      'id': 'v1',
      'name': 'Swift Dzire',
      'brand': 'Maruti',
      'model': 'Dzire',
      'year': 2022,
      'category': 'car',
      'seatingCapacity': 5,
      'fuelType': 'petrol',
      'transmission': 'manual',
      // An int where a double is expected, which is what Mongo sends for a
      // whole-number rate.
      'pricePerDay': 2000,
      'securityDeposit': 3000,
      'currencySymbol': '₹',
      'availabilityStatus': 'available',
      'isAvailable': true,
      'features': ['Air conditioning', 'Bluetooth'],
      if (images != null) 'images': images,
      if (primary != null) 'primaryImageUrl': primary,
    };

    test('parses whole-number rates as doubles', () {
      final vehicle = FleetVehicle.fromJson(json());

      expect(vehicle.pricePerDay, 2000.0);
      expect(vehicle.securityDeposit, 3000.0);
      expect(vehicle.pricePerKm, isNull);
    });

    test('puts the cover photo first, whatever order the server sent', () {
      final vehicle = FleetVehicle.fromJson(
        json(
          images: [
            {'url': 'side.jpg', 'isPrimary': false, 'sortOrder': 1},
            {'url': 'cover.jpg', 'isPrimary': true, 'sortOrder': 2},
            {'url': 'rear.jpg', 'isPrimary': false, 'sortOrder': 0},
          ],
        ),
      );

      expect(vehicle.photoUrls, ['cover.jpg', 'rear.jpg', 'side.jpg']);
      expect(vehicle.coverUrl, 'cover.jpg');
    });

    test('still shows one photo when only the cover url came through', () {
      final vehicle = FleetVehicle.fromJson(json(primary: 'cover.jpg'));

      expect(vehicle.hasPhotos, isTrue);
      expect(vehicle.photoUrls, ['cover.jpg']);
    });

    test('renders a vehicle with no photographs rather than crashing', () {
      final vehicle = FleetVehicle.fromJson(json());

      expect(vehicle.hasPhotos, isFalse);
      expect(vehicle.photoUrls, isEmpty);
      expect(vehicle.coverUrl, isNull);
    });

    test('labels categories rather than capitalising them', () {
      // 'suv' is 'SUV' and 'car' is 'Car', and both are three letters, so no
      // rule derives one from the other.
      expect(
        FleetVehicle.fromJson({...json(), 'category': 'suv'}).categoryLabel,
        'SUV',
      );
      expect(
        FleetVehicle.fromJson({...json(), 'category': 'car'}).categoryLabel,
        'Car',
      );
      expect(
        FleetVehicle.fromJson({...json(), 'category': 'tempo'}).categoryLabel,
        'Tempo',
      );
    });

    test('keeps an unrecognised category usable', () {
      expect(
        FleetVehicle.fromJson({...json(), 'category': 'tractor'}).categoryLabel,
        'Tractor',
      );
    });

    test('reports a vehicle in the workshop', () {
      final vehicle = FleetVehicle.fromJson({
        ...json(),
        'availabilityStatus': 'under_maintenance',
      });

      expect(vehicle.isUnderMaintenance, isTrue);
    });
  });

  group('HireQuote', () {
    Map<String, dynamic> quoteJson({
      bool isAvailable = true,
      List<String> clashes = const [],
    }) => {
      'vehicle': {
        'id': 'v1',
        'name': 'Swift Dzire',
        'brand': 'Maruti',
        'model': 'Dzire',
        'year': 2022,
        'category': 'car',
        'seatingCapacity': 5,
        'fuelType': 'petrol',
        'transmission': 'manual',
        'pricePerDay': 2000,
      },
      'hire': {
        'startAt': '2026-11-12T09:00:00.000Z',
        'endAt': '2026-11-15T09:00:00.000Z',
        'days': 3,
        'dailyRate': 2000,
        'hireCharge': 6000,
        'securityDeposit': 3000,
        'amountDue': 9000,
        'currency': 'INR',
        'currencySymbol': '₹',
      },
      'isAvailable': isAvailable,
      'conflictingDays': clashes,
      'paymentMethods': ['GPay', 'Cash'],
    };

    test(
      'takes the day count and the total from the server, not arithmetic',
      () {
        final quote = HireQuote.fromJson(quoteJson());

        expect(quote.days, 3);
        expect(quote.hireCharge, 6000);
        expect(quote.amountDue, 9000);
        expect(quote.vehicle.name, 'Swift Dzire');
      },
    );

    test('an unavailable vehicle is an answer with dates, not an error', () {
      final quote = HireQuote.fromJson(
        quoteJson(isAvailable: false, clashes: ['2026-11-13', '2026-11-14']),
      );

      expect(quote.isAvailable, isFalse);
      expect(quote.conflictingDays, ['2026-11-13', '2026-11-14']);
    });

    test('carries the methods the operator can actually take', () {
      expect(HireQuote.fromJson(quoteJson()).paymentMethods, ['GPay', 'Cash']);
    });
  });

  group('VehicleAvailability', () {
    test('builds a day key from local parts, not from a UTC ISO string', () {
      // `toIso8601String().substring(0, 10)` would shift the date by the UTC
      // offset and grey out the wrong day in the picker.
      final key = VehicleAvailability.dayKey(DateTime(2026, 11, 12, 23, 30));
      expect(key, '2026-11-12');
    });

    test('pads single-digit months and days', () {
      expect(VehicleAvailability.dayKey(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('reports a day the server has held', () {
      final availability = VehicleAvailability.fromJson({
        'vehicleId': 'v1',
        'takenDays': ['2026-11-13'],
      });

      expect(availability.isTaken(DateTime(2026, 11, 13, 14)), isTrue);
      expect(availability.isTaken(DateTime(2026, 11, 14)), isFalse);
    });
  });

  group('BookingDraftController', () {
    late BookingDraftController controller;

    setUp(() => controller = BookingDraftController());

    test('is not ready to search until the dates and both ends are set', () {
      expect(controller.state.isReadyToSearch, isFalse);

      controller.setPeriod(
        startAt: DateTime(2026, 11, 12, 9),
        endAt: DateTime(2026, 11, 13, 9),
      );
      expect(controller.state.hasPeriod, isTrue);
      expect(controller.state.isReadyToSearch, isFalse);

      controller.setPickup(pickup);
      controller.setDestination(drop);
      expect(controller.state.isReadyToSearch, isTrue);
    });

    test('refuses a pickup and drop that are the same place', () {
      controller.setPeriod(
        startAt: DateTime(2026, 11, 12, 9),
        endAt: DateTime(2026, 11, 13, 9),
      );
      controller.setPickup(pickup);
      controller.setDestination(pickup);

      expect(controller.state.isReadyToSearch, isFalse);
    });

    test('changing the dates drops the chosen vehicle', () {
      // The rule that matters: a car free on the 12th is not necessarily free
      // on the 19th, so carrying the selection across a date change would let
      // the customer reach the confirmation screen holding a booking the server
      // will refuse.
      controller.setPeriod(
        startAt: DateTime(2026, 11, 12, 9),
        endAt: DateTime(2026, 11, 13, 9),
      );
      controller.setPickup(pickup);
      controller.setDestination(drop);
      controller.selectVehicle(_vehicle());

      expect(controller.state.vehicle, isNotNull);
      expect(controller.state.idempotencyKey, isNotNull);

      controller.setPeriod(
        startAt: DateTime(2026, 11, 19, 9),
        endAt: DateTime(2026, 11, 20, 9),
      );

      expect(controller.state.vehicle, isNull);
      expect(controller.state.quote, isNull);
      expect(controller.state.idempotencyKey, isNull);
      // The locations survive: they do not affect availability.
      expect(controller.state.pickup, isNotNull);
      expect(controller.state.destination, isNotNull);
    });

    test('setting the same dates again keeps the chosen vehicle', () {
      // A rebuild that re-sets the same dates must not silently deselect the
      // car the customer just chose.
      final start = DateTime(2026, 11, 12, 9);
      final end = DateTime(2026, 11, 13, 9);

      controller.setPeriod(startAt: start, endAt: end);
      controller.selectVehicle(_vehicle());
      controller.setPeriod(startAt: start, endAt: end);

      expect(controller.state.vehicle, isNotNull);
    });

    test('moving the start date keeps the hire the same length', () {
      controller.setPeriod(
        startAt: DateTime(2026, 11, 12, 9),
        endAt: DateTime(2026, 11, 15, 9),
      );
      controller.setStartDate(DateTime(2026, 11, 20, 9));

      expect(controller.state.startAt, DateTime(2026, 11, 20, 9));
      expect(controller.state.endAt, DateTime(2026, 11, 23, 9));
      expect(controller.state.days, 3);
    });

    test(
      'changing the pickup keeps the chosen vehicle, because price is by the day',
      () {
        controller.setPeriod(
          startAt: DateTime(2026, 11, 12, 9),
          endAt: DateTime(2026, 11, 13, 9),
        );
        controller.selectVehicle(_vehicle());
        controller.setPickup(drop);

        expect(controller.state.vehicle, isNotNull);
      },
    );

    test('is not ready to confirm on a quote that says the car is taken', () {
      controller.setPeriod(
        startAt: DateTime(2026, 11, 12, 9),
        endAt: DateTime(2026, 11, 13, 9),
      );
      controller.setPickup(pickup);
      controller.setDestination(drop);
      controller.selectVehicle(_vehicle(), quote: _quote(isAvailable: false));

      expect(controller.state.isReadyToConfirm, isFalse);
    });

    test('is not ready to confirm without pickup and drop locations', () {
      controller.setPeriod(
        startAt: DateTime(2026, 11, 12, 9),
        endAt: DateTime(2026, 11, 13, 9),
      );
      controller.selectVehicle(_vehicle(), quote: _quote());

      expect(controller.state.isReadyToConfirm, isFalse);
    });

    test('is ready to confirm once the quote says it is free', () {
      controller.setPeriod(
        startAt: DateTime(2026, 11, 12, 9),
        endAt: DateTime(2026, 11, 13, 9),
      );
      controller.setPickup(pickup);
      controller.setDestination(drop);
      controller.selectVehicle(_vehicle(), quote: _quote());

      expect(controller.state.isReadyToConfirm, isTrue);
    });

    test(
      'keeps the idempotency key across a re-quote, because it is one attempt',
      () {
        controller.setPeriod(
          startAt: DateTime(2026, 11, 12, 9),
          endAt: DateTime(2026, 11, 13, 9),
        );
        controller.selectVehicle(_vehicle(), quote: _quote());
        final key = controller.state.idempotencyKey;

        controller.refreshQuote(_quote());

        expect(controller.state.idempotencyKey, key);
      },
    );

    test('mints a new key when the customer chooses a different vehicle', () {
      controller.setPeriod(
        startAt: DateTime(2026, 11, 12, 9),
        endAt: DateTime(2026, 11, 13, 9),
      );
      controller.selectVehicle(_vehicle());
      final first = controller.state.idempotencyKey;

      controller.selectVehicle(_vehicle(id: 'v2'));

      expect(controller.state.idempotencyKey, isNot(first));
    });

    test('a reset keeps the pickup and nothing else', () {
      controller.setPeriod(
        startAt: DateTime(2026, 11, 12, 9),
        endAt: DateTime(2026, 11, 13, 9),
      );
      controller.setPickup(pickup);
      controller.setDestination(drop);
      controller.selectVehicle(_vehicle(), quote: _quote());

      controller.reset();

      expect(controller.state.pickup, isNotNull);
      expect(controller.state.destination, isNull);
      expect(controller.state.startAt, isNull);
      expect(controller.state.vehicle, isNull);
    });
  });

  group('DriverAllocationStatus', () {
    test('parses the two values the backend sends', () {
      expect(
        DriverAllocationStatus.fromApi('Allocated'),
        DriverAllocationStatus.allocated,
      );
      expect(
        DriverAllocationStatus.fromApi('Not Allocated'),
        DriverAllocationStatus.notAllocated,
      );
    });

    test('treats anything it does not recognise as not allocated', () {
      // Erring towards "not allocated" is the safe direction: claiming a driver
      // exists when the app cannot name one is the worse failure.
      expect(
        DriverAllocationStatus.fromApi(null),
        DriverAllocationStatus.notAllocated,
      );
      expect(
        DriverAllocationStatus.fromApi(''),
        DriverAllocationStatus.notAllocated,
      );
      expect(
        DriverAllocationStatus.fromApi('Maybe'),
        DriverAllocationStatus.notAllocated,
      );
    });
  });

  group('Booking driver allocation', () {
    Map<String, dynamic> bookingJson({
      Map<String, dynamic>? driver,
      Map<String, dynamic>? allocation,
    }) => {
      'id': 'b1',
      'bookingCode': 'TX-000042',
      'customer': {'id': 'c1', 'name': 'Asha Babu', 'phone': '+919876543210'},
      'vehicleType': {'id': 't1', 'name': 'Car', 'code': 'CAR'},
      'vehicle': {
        'id': 'v1',
        'name': 'Swift Dzire',
        'brand': 'Maruti',
        'model': 'Dzire',
        'year': 2022,
        'registrationNumber': 'TN01AB1234',
        'seatingCapacity': 5,
        'imageUrl': 'cover.jpg',
        'imageUrls': ['cover.jpg', 'side.jpg'],
      },
      'hire': {
        'startAt': '2026-11-12T09:00:00.000Z',
        'endAt': '2026-11-15T09:00:00.000Z',
        'days': 3,
        'dailyRate': 2000,
        'hireCharge': 6000,
        'securityDeposit': 3000,
        'amountDue': 9000,
        'currencySymbol': '₹',
      },
      'pickup': {
        'address': 'Gandhipuram',
        'latitude': 11.0183,
        'longitude': 76.9725,
      },
      'destination': {
        'address': 'Ooty',
        'latitude': 11.4102,
        'longitude': 76.6950,
      },
      'distanceKm': 86,
      'durationMinutes': 150,
      'estimatedFare': 9000,
      'bookingStatus': 'Confirmed',
      'paymentMethod': 'Cash',
      'paymentStatus': 'Pending',
      'createdAt': '2026-11-03T10:00:00.000Z',
      if (driver != null) 'driver': driver,
      if (allocation != null) 'driverAllocation': allocation,
    };

    test('reads not allocated on a booking with no driver', () {
      final booking = Booking.fromJson(
        bookingJson(
          allocation: {'status': 'Not Allocated', 'isAllocated': false},
        ),
      );

      expect(booking.isDriverAllocated, isFalse);
      expect(booking.allocation.status, DriverAllocationStatus.notAllocated);
      expect(booking.driver, isNull);
    });

    test('reads the driver name and mobile number once allocated', () {
      final booking = Booking.fromJson(
        bookingJson(
          driver: {
            'driverId': 'd1',
            'driverCode': 'DRV-0007',
            'name': 'Rahul Kumar',
            'phone': '+919812345678',
            'vehicleNumber': 'TN01AB1234',
            'assignedAt': '2026-11-04T08:00:00.000Z',
          },
          allocation: {
            'status': 'Allocated',
            'isAllocated': true,
            'driverName': 'Rahul Kumar',
            'driverPhone': '+919812345678',
            'allocatedAt': '2026-11-04T08:00:00.000Z',
          },
        ),
      );

      expect(booking.isDriverAllocated, isTrue);
      expect(booking.driver!.name, 'Rahul Kumar');
      expect(booking.driver!.phone, '+919812345678');
      expect(booking.driver!.driverCode, 'DRV-0007');
      expect(booking.driver!.hasPhone, isTrue);
      expect(booking.allocation.allocatedAt, isNotNull);
    });

    test('derives the status when the server did not send the block', () {
      // The socket payload and older servers send `driver` without
      // `driverAllocation`, and the screen still has to render the field.
      final booking = Booking.fromJson(
        bookingJson(driver: {'name': 'Rahul Kumar', 'phone': '+919812345678'}),
      );

      expect(booking.driverAllocation, isNull);
      expect(booking.allocation.status, DriverAllocationStatus.allocated);
      expect(booking.allocation.driverName, 'Rahul Kumar');
      expect(booking.isDriverAllocated, isTrue);
    });

    test('derives not-allocated from an absent driver', () {
      final booking = Booking.fromJson(bookingJson());

      expect(booking.allocation.status, DriverAllocationStatus.notAllocated);
      expect(booking.isDriverAllocated, isFalse);
    });

    test('exposes the booking date and the vehicle photographs', () {
      final booking = Booking.fromJson(bookingJson());

      expect(booking.isHire, isTrue);
      expect(booking.hire!.days, 3);
      expect(booking.bookingDate, booking.hire!.startAt);
      expect(booking.vehiclePhotos, ['cover.jpg', 'side.jpg']);
    });

    test('falls back to the cover photo for a booking with no gallery', () {
      final json = bookingJson();
      (json['vehicle'] as Map).remove('imageUrls');

      expect(Booking.fromJson(json).vehiclePhotos, ['cover.jpg']);
    });
  });

  group('BookingSummary', () {
    test('carries the allocation status so a list row can badge it', () {
      final summary = BookingSummary.fromJson({
        'id': 'b1',
        'bookingCode': 'TX-000042',
        'pickupAddress': 'Gandhipuram',
        'destinationAddress': 'Ooty',
        'vehicleTypeName': 'Car',
        'vehicleName': 'Swift Dzire',
        'registrationNumber': 'TN01AB1234',
        'hireStartAt': '2026-11-12T09:00:00.000Z',
        'hireEndAt': '2026-11-15T09:00:00.000Z',
        'hireDays': 3,
        'bookingStatus': 'Driver Assigned',
        'paymentStatus': 'Pending',
        'displayFare': 9000,
        'currencySymbol': '₹',
        'createdAt': '2026-11-03T10:00:00.000Z',
        'driverAllocationStatus': 'Allocated',
        'driverName': 'Rahul Kumar',
      });

      expect(summary.isHire, isTrue);
      expect(summary.isDriverAllocated, isTrue);
      expect(summary.driverName, 'Rahul Kumar');
      expect(summary.hireDays, 3);
      expect(summary.bookingDate, summary.hireStartAt);
    });

    test('defaults to not allocated when the field is absent', () {
      final summary = BookingSummary.fromJson({
        'id': 'b1',
        'bookingCode': 'TX-000043',
        'pickupAddress': 'A',
        'destinationAddress': 'B',
        'vehicleTypeName': 'Car',
        'bookingStatus': 'Pending',
        'paymentStatus': 'Pending',
        'displayFare': 1,
        'createdAt': '2026-11-03T10:00:00.000Z',
      });

      expect(summary.allocationStatus, DriverAllocationStatus.notAllocated);
      expect(summary.isHire, isFalse);
    });
  });

  group('PaymentMethod', () {
    test('offers only what the backend accepts for a new hire', () {
      expect(PaymentMethod.offeredForHire, [
        PaymentMethod.gpay,
        PaymentMethod.cash,
      ]);
      expect(PaymentMethod.gpay.isOfferedForHire, isTrue);
      expect(PaymentMethod.card.isOfferedForHire, isFalse);
    });

    test('still parses the methods historical bookings carry', () {
      // `UPI`, `Card` and `Wallet` are valid on old bookings and must render.
      expect(PaymentMethod.fromApi('UPI'), PaymentMethod.upi);
      expect(PaymentMethod.fromApi('Card'), PaymentMethod.card);
      expect(PaymentMethod.fromApi('GPay'), PaymentMethod.gpay);
    });

    test('falls back to cash on an unknown method', () {
      expect(PaymentMethod.fromApi('Bitcoin'), PaymentMethod.cash);
    });
  });

  group('PaymentStatus', () {
    test('parses Awaiting Verification, which only an admin can move on', () {
      expect(
        PaymentStatus.fromApi('Awaiting Verification'),
        PaymentStatus.awaitingVerification,
      );
      expect(PaymentStatus.awaitingVerification.isSettled, isFalse);
      expect(PaymentStatus.paid.isSettled, isTrue);
    });
  });
}

FleetVehicle _vehicle({String id = 'v1'}) => FleetVehicle(
  id: id,
  name: 'Swift Dzire',
  brand: 'Maruti',
  model: 'Dzire',
  year: 2022,
  category: 'car',
  seatingCapacity: 5,
  fuelType: 'petrol',
  transmission: 'manual',
  pricePerDay: 2000,
);

HireQuote _quote({bool isAvailable = true}) => HireQuote(
  vehicle: _vehicle(),
  startAt: DateTime(2026, 11, 12, 9),
  endAt: DateTime(2026, 11, 13, 9),
  days: 1,
  dailyRate: 2000,
  hireCharge: 2000,
  securityDeposit: 3000,
  amountDue: 5000,
  currency: 'INR',
  currencySymbol: '₹',
  isAvailable: isAvailable,
);
