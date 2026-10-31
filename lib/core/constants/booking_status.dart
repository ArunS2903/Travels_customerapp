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

  bool get isActive => this == driverAssigned || this == driverArrived || this == inProgress;

  bool get isUpcoming => this == pending || this == confirmed;

  /// Whether the cancel button should be offered at all. The backend decides
  /// authoritatively; this only keeps us from showing a button that will 409.
  bool get isCancellable =>
      this == pending || this == confirmed || this == driverAssigned || this == driverArrived;

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
        return AppColors.amberDark;
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
        return AppColors.amberSoft;
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
enum PaymentMethod {
  cash('Cash', Icons.payments_outlined),
  upi('UPI', Icons.qr_code_rounded),
  card('Card', Icons.credit_card_rounded),
  wallet('Wallet', Icons.account_balance_wallet_outlined);

  const PaymentMethod(this.apiValue, this.icon);

  final String apiValue;
  final IconData icon;

  static PaymentMethod fromApi(String? value) => PaymentMethod.values.firstWhere(
        (method) => method.apiValue.toLowerCase() == (value ?? '').toLowerCase(),
        orElse: () => PaymentMethod.cash,
      );
}

/// Payment statuses, mirroring the backend enum.
enum PaymentStatus {
  pending('Pending'),
  paid('Paid'),
  failed('Failed'),
  refunded('Refunded');

  const PaymentStatus(this.apiValue);

  final String apiValue;

  static PaymentStatus fromApi(String? value) => PaymentStatus.values.firstWhere(
        (status) => status.apiValue.toLowerCase() == (value ?? '').toLowerCase(),
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
      case pending:
        return AppColors.warning;
    }
  }
}
