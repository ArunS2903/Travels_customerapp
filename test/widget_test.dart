import 'package:customer_app/core/constants/booking_status.dart';
import 'package:customer_app/core/theme/app_theme.dart';
import 'package:customer_app/shared/widgets/primary_button.dart';
import 'package:customer_app/shared/widgets/state_views.dart';
import 'package:customer_app/shared/widgets/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the shared components every screen leans on.
///
/// These are the pieces whose behaviour is load-bearing rather than cosmetic:
/// a PrimaryButton that still fires while loading would create duplicate
/// bookings, and a StatusChip that renders colour without text would be
/// unreadable for a colour-blind customer.
void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
      );

  group('PrimaryButton', () {
    testWidgets('invokes onPressed when enabled', (tester) async {
      var taps = 0;

      await tester.pumpWidget(wrap(
        PrimaryButton(label: 'Confirm booking', onPressed: () => taps++),
      ));

      await tester.tap(find.text('Confirm booking'));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('ignores taps while loading, and hides the label', (tester) async {
      var taps = 0;

      await tester.pumpWidget(wrap(
        PrimaryButton(
          label: 'Confirm booking',
          isLoading: true,
          onPressed: () => taps++,
        ),
      ));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Confirm booking'), findsNothing);

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      // This is the guard against a double-tap creating two bookings.
      expect(taps, 0);
    });

    testWidgets('is disabled when onPressed is null', (tester) async {
      await tester.pumpWidget(wrap(const PrimaryButton(label: 'Continue')));

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
    });
  });

  group('StatusChip', () {
    testWidgets('shows the status text alongside its icon', (tester) async {
      await tester.pumpWidget(wrap(
        const StatusChip(status: BookingStatus.driverAssigned),
      ));

      // Never colour alone: the label has to be there too.
      expect(find.text('Driver Assigned'), findsOneWidget);
      expect(find.byIcon(Icons.directions_car_filled_rounded), findsOneWidget);
    });

    testWidgets('renders an unrecognised status without crashing', (tester) async {
      await tester.pumpWidget(wrap(
        StatusChip(status: BookingStatus.fromApi('Something New')),
      ));

      expect(find.text('Unknown'), findsOneWidget);
    });
  });

  group('EmptyView', () {
    testWidgets('shows the action only when both label and callback are given',
        (tester) async {
      await tester.pumpWidget(wrap(
        const EmptyView(title: 'No trips', message: 'Nothing here yet.'),
      ));
      expect(find.byType(PrimaryButton), findsNothing);

      await tester.pumpWidget(wrap(
        EmptyView(
          title: 'No trips',
          message: 'Nothing here yet.',
          actionLabel: 'Book a ride',
          onAction: () {},
        ),
      ));
      expect(find.text('Book a ride'), findsOneWidget);
    });
  });
}
