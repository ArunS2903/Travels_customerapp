import 'package:customer_app/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('money', () {
    test('omits decimals for whole amounts', () {
      expect(Formatters.money(320, symbol: '₹'), '₹320');
    });

    test('shows two decimals when there are fractions', () {
      expect(Formatters.money(320.5, symbol: '₹'), '₹320.50');
    });

    test('groups thousands', () {
      expect(Formatters.money(12500, symbol: '₹'), '₹12,500');
    });

    test('renders a placeholder for a missing amount', () {
      expect(Formatters.money(null), '--');
    });

    test('works with no symbol, for an operator we have no currency for', () {
      expect(Formatters.money(99), '99');
    });
  });

  group('distance', () {
    test('uses metres below a kilometre', () {
      expect(Formatters.distance(0.85), '850 m');
    });

    test('uses one decimal kilometre above that', () {
      expect(Formatters.distance(12.54), '12.5 km');
    });

    test('handles a missing distance', () {
      expect(Formatters.distance(null), '--');
    });
  });

  group('duration', () {
    test('renders minutes under an hour', () {
      expect(Formatters.duration(25), '25 min');
    });

    test('renders hours and minutes', () {
      expect(Formatters.duration(65), '1 hr 5 min');
    });

    test('drops the minutes on a whole hour', () {
      expect(Formatters.duration(120), '2 hr');
    });
  });

  group('eta', () {
    test('never says "0 min away"', () {
      expect(Formatters.eta(0), '1 min away');
      expect(Formatters.eta(1), '1 min away');
    });

    test('rounds to whole minutes', () {
      expect(Formatters.eta(4.4), '4 min away');
    });

    test('reports an unknown ETA honestly', () {
      expect(Formatters.eta(null), 'Checking');
    });
  });

  group('countdown', () {
    test('renders seconds under a minute', () {
      expect(Formatters.countdown(45), '45s');
    });

    test('pads the seconds past a minute', () {
      expect(Formatters.countdown(125), '2m 05s');
    });

    test('clamps at zero', () {
      expect(Formatters.countdown(0), '0s');
      expect(Formatters.countdown(-5), '0s');
    });
  });

  group('phone', () {
    test('formats an E.164 Indian number for display', () {
      expect(Formatters.phone('+919876543210'), '+91 98765 43210');
    });

    test('leaves an unexpected shape alone rather than mangling it', () {
      expect(Formatters.phone('12345'), '12345');
      expect(Formatters.phone('+1555'), '+1555');
    });

    test('handles a missing number', () {
      expect(Formatters.phone(null), '--');
    });
  });

  group('firstName and initials', () {
    test('takes the first word', () {
      expect(Formatters.firstName('Asha Babu'), 'Asha');
      expect(Formatters.firstName('Asha'), 'Asha');
    });

    test('falls back politely on an empty name', () {
      expect(Formatters.firstName(null), 'there');
      expect(Formatters.firstName('   '), 'there');
    });

    test('builds initials from the first and last words', () {
      expect(Formatters.initials('Asha Babu'), 'AB');
      expect(Formatters.initials('Asha Rani Babu'), 'AB');
      expect(Formatters.initials('Asha'), 'A');
      expect(Formatters.initials(null), '?');
    });
  });

  group('relativeDateTime', () {
    test('labels today and yesterday', () {
      final now = DateTime.now();
      expect(Formatters.relativeDateTime(now), startsWith('Today, '));
      expect(
        Formatters.relativeDateTime(now.subtract(const Duration(days: 1))),
        startsWith('Yesterday, '),
      );
    });

    test('labels tomorrow, for a scheduled pickup', () {
      expect(
        Formatters.relativeDateTime(DateTime.now().add(const Duration(days: 1))),
        startsWith('Tomorrow, '),
      );
    });

    test('includes the year for an older trip', () {
      expect(Formatters.relativeDateTime(DateTime(2021, 3, 14, 9, 15)), contains('2021'));
    });
  });
}
