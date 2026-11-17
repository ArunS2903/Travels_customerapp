import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Booking statuses, mirroring `backend/src/constants/domain.js`.
///
/// The authoritative status is always the string the backend sent. This enum
/// exists only to attach display metadata to it, and [fromApi] keeps an
/// unrecognised value usable rather than crashing - if the admin adds a status
/// before the app ships, the customer sees the raw label instead of an error.
enum BookingStatus {
  pending('Pending'),
  confirmed('Confirmed'),
  driverAssigned('Driver Assigned'),
  driverArrived('Driver Arrived'),
  inProgress('In Progress'),
  completed('Completed'),
  cancelled('Cancelled'),
  unknown('Unknown');

  const BookingStatus(this.apiValue);

  /// Exact string used by the API.
  final String apiValue;

  static BookingStatus fromApi(String? value) {
    if (value == null) return BookingStatus.unknown;
    for (final status in BookingStatus.values) {
      if (status.apiValue.toLowerCase() == value.toLowerCase()) return status;
    }
    return BookingStatus.unknown;
  }

  bool get isTerminal => this == completed || this == cancelled;

  bool get isActive =>
      this == driverAssigned || this == driverArrived || this == inProgress;

  bool get isUpcoming => this == pending || this == confirmed;

  /// Whether the cancel button should be offered at all. The backend decides
  /// authoritatively; this only keeps us from showing a button that will 409.
  bool get isCancellable =>
      this == pending ||
      this == confirmed ||
      this == driverAssigned ||
      this == driverArrived;

  /// What the customer is waiting for, in plain language.
  String get description {
    switch (this) {
      case pending:
        return 'We have received your booking and are finding you a driver.';
      case confirmed:
        return 'Your booking is confirmed. A driver will be assigned shortly.';
      case driverAssigned:
        return 'Your driver is on the way to the pickup point.';
      case driverArrived:
        return 'Your driver is waiting at the pickup point.';
      case inProgress:
        return 'You are on your way to the destination.';
      case completed:
        return 'This trip is complete.';
      case cancelled:
        return 'This booking was cancelled.';
      case unknown:
        return 'Status unavailable.';
    }
  }

  Color get color {
    switch (this) {
      case pending:
        return AppColors.warning;
      case confirmed:
        return AppColors.info;
      case driverAssigned:
      case driverArrived:
        return AppColors.info;
      case inProgress:
        return AppColors.brand;
      case completed:
        return AppColors.success;
      case cancelled:
        return AppColors.danger;
      case unknown:
        return AppColors.lightTextTertiary;
    }
  }

  Color get softColor {
    switch (this) {
      case pending:
        return AppColors.warningSoft;
      case confirmed:
      case driverAssigned:
      case driverArrived:
        return AppColors.infoSoft;
      case inProgress:
        return AppColors.brandSoft;
      case completed:
        return AppColors.successSoft;
      case cancelled:
        return AppColors.dangerSoft;
      case unknown:
        return AppColors.lightSurfaceAlt;
    }
  }

  IconData get icon {
    switch (this) {
      case pending:
        return Icons.schedule_rounded;
      case confirmed:
        return Icons.check_circle_outline_rounded;
      case driverAssigned:
        return Icons.directions_car_filled_rounded;
      case driverArrived:
        return Icons.where_to_vote_rounded;
      case inProgress:
        return Icons.navigation_rounded;
      case completed:
        return Icons.task_alt_rounded;
      case cancelled:
        return Icons.cancel_outlined;
      case unknown:
        return Icons.help_outline_rounded;
    }
  }

  /// Zero-based position in the progress tracker on the details screen.
  /// Returns null for statuses that are not part of the happy path.
  int? get progressStep {
    switch (this) {
      case pending:
        return 0;
      case confirmed:
        return 1;
      case driverAssigned:
        return 2;
      case driverArrived:
        return 3;
      case inProgress:
        return 4;
      case completed:
        return 5;
      case cancelled:
      case unknown:
        return null;
    }
  }

  static const List<BookingStatus> progressSequence = [
    pending,
    confirmed,
    driverAssigned,
    driverArrived,
    inProgress,
    completed,
  ];
}

/// Tabs on the My Bookings screen. `apiValue` is the `tab` query parameter.
enum BookingTab {
  upcoming('upcoming', 'Upcoming'),
  active('active', 'Active'),
  completed('completed', 'Completed'),
  cancelled('cancelled', 'Cancelled');

  const BookingTab(this.apiValue, this.label);

  final String apiValue;
  final String label;

  String get emptyTitle {
    switch (this) {
      case upcoming:
        return 'No upcoming trips';
      case active:
        return 'No trip in progress';
      case completed:
        return 'No completed trips yet';
      case cancelled:
        return 'No cancelled bookings';
    }
  }

  String get emptyMessage {
    switch (this) {
      case upcoming:
        return 'Bookings waiting for a driver will appear here.';
      case active:
        return 'Once your driver is on the way, your trip shows up here.';
      case completed:
        return 'Your finished trips and their fares will be listed here.';
      case cancelled:
        return 'Bookings you cancel will be kept here for your records.';
    }
  }
}

/// Payment methods, mirroring the backend enum.
///
/// The list is longer than what a new booking may use. `UPI`, `Card` and
/// `Wallet` are still valid values on historical bookings and must parse, but
/// only [offeredForHire] may be chosen - nothing in this system can take or
/// verify the others. See `HIRE_PAYMENT_METHODS` in the backend.
enum PaymentMethod {
  gpay('GPay', Icons.account_balance_wallet_rounded),
  cash('Cash', Icons.payments_outlined),
  upi('UPI', Icons.qr_code_rounded),
  card('Card', Icons.credit_card_rounded),
  wallet('Wallet', Icons.account_balance_wallet_outlined);

  const PaymentMethod(this.apiValue, this.icon);

  final String apiValue;
  final IconData icon;

  /// What a customer may pick for a new hire: pay online now, or pay on
  /// completion. The server refuses anything else.
  static const List<PaymentMethod> offeredForHire = [gpay, cash];

  bool get isOfferedForHire => offeredForHire.contains(this);

  /// The label on the chooser.
  ///
  /// `gpay` is stored as "GPay" and shown as "Online Payment". The stored
  /// value is on every historical booking and renaming it would mean a
  /// migration, so the database keeps its vocabulary and the customer gets
  /// ours. The server sends the same labels in `GET /public/app-config`
  /// (`paymentMethodLabels`), which is what a screen should prefer when it has
  /// them - these are the fallback for before that call returns.
  String get label {
    switch (this) {
      case gpay:
        return 'Online Payment';
      case cash:
        return 'Cash on Pay';
      case upi:
        return 'UPI';
      case card:
        return 'Card';
      case wallet:
        return 'Wallet';
    }
  }

  String get description {
    switch (this) {
      case gpay:
        return 'Pay the full amount now from any UPI app. '
            'Your booking is marked paid once the payment is confirmed.';
      case cash:
        return 'Pay the operator when your travel is complete, '
            'then confirm it here.';
      case upi:
      case card:
      case wallet:
        return 'Recorded on this booking.';
    }
  }

  static PaymentMethod fromApi(String? value) =>
      PaymentMethod.values.firstWhere(
        (method) =>
            method.apiValue.toLowerCase() == (value ?? '').toLowerCase(),
        orElse: () => PaymentMethod.cash,
      );
}

/// Payment statuses, mirroring the backend enum.
enum PaymentStatus {
  pending('Pending'),

  /// A legacy direct-UPI claim awaiting manual verification. New GPay
  /// transactions are verified by the backend and do not enter this state.
  awaitingVerification('Awaiting Verification'),

  paid('Paid'),
  failed('Failed'),
  refunded('Refunded');

  const PaymentStatus(this.apiValue);

  final String apiValue;

  bool get isSettled => this == paid;

  static PaymentStatus fromApi(String? value) =>
      PaymentStatus.values.firstWhere(
        (status) =>
            status.apiValue.toLowerCase() == (value ?? '').toLowerCase(),
        orElse: () => PaymentStatus.pending,
      );

  Color get color {
    switch (this) {
      case paid:
        return AppColors.success;
      case failed:
        return AppColors.danger;
      case refunded:
        return AppColors.info;
      case awaitingVerification:
        return AppColors.info;
      case pending:
        return AppColors.warning;
    }
  }
}

/// Whether a driver has been put on a booking, mirroring
/// `DRIVER_ALLOCATION_STATUS` in the backend.
///
/// This exists so the app can say "Driver not allocated yet" as a *state*
/// rather than as the absence of one. The backend sends the string; this enum
/// attaches the colour, the icon and the sentence that explains it, and
/// [fromApi] keeps an unrecognised value usable rather than crashing.
enum DriverAllocationStatus {
  notAllocated('Not Allocated'),
  allocated('Allocated');

  const DriverAllocationStatus(this.apiValue);

  final String apiValue;

  bool get isAllocated => this == allocated;

  static DriverAllocationStatus fromApi(String? value) {
    for (final status in DriverAllocationStatus.values) {
      if (status.apiValue.toLowerCase() == (value ?? '').toLowerCase()) {
        return status;
      }
    }
    return DriverAllocationStatus.notAllocated;
  }

  /// What the customer sees as the field's value.
  String get label =>
      this == allocated ? 'Driver allocated' : 'Driver not allocated yet';

  /// What it means for them, in plain language.
  String get description => this == allocated
      ? 'Your driver has been assigned. Their name and mobile number are below, '
            'and we have texted them to your registered number.'
      : 'The operator has not assigned a driver yet. We will text you their name '
            'and mobile number as soon as they do.';

  Color get color => this == allocated ? AppColors.success : AppColors.warning;

  Color get softColor =>
      this == allocated ? AppColors.successSoft : AppColors.warningSoft;

  IconData get icon => this == allocated
      ? Icons.how_to_reg_rounded
      : Icons.person_search_rounded;
}
