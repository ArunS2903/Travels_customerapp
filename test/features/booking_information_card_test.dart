import 'package:customer_app/features/home/presentation/widgets/booking_information_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BookingInformationCard.pickupDateTimeForTime', () {
    test('changes the time while preserving the selected local date', () {
      final date = DateTime(2026, 11, 5, 9);
      const time = TimeOfDay(hour: 14, minute: 45);

      expect(
        BookingInformationCard.pickupDateTimeForTime(date, time),
        DateTime(2026, 11, 5, 14, 45),
      );
    });
  });

  group('BookingInformationCard.pickupStartAtForDate', () {
    test('keeps 09:00 for today when it is still safely ahead', () {
      final now = DateTime(2026, 11, 4, 8);

      expect(
        BookingInformationCard.pickupStartAtForDate(now, now: now),
        DateTime(2026, 11, 4, 9),
      );
    });

    test('moves today pickup to the near future after 09:00 has passed', () {
      final now = DateTime(2026, 11, 4, 14);

      expect(
        BookingInformationCard.pickupStartAtForDate(now, now: now),
        DateTime(2026, 11, 4, 14, 30),
      );
    });

    test('keeps future dates anchored at 09:00', () {
      final now = DateTime(2026, 11, 4, 14);
      final tomorrow = DateTime(2026, 11, 5);

      expect(
        BookingInformationCard.pickupStartAtForDate(tomorrow, now: now),
        DateTime(2026, 11, 5, 9),
      );
    });
  });
}
