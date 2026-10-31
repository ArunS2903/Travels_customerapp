import 'package:intl/intl.dart';

/// Display formatting for money, distance, duration and dates.
///
/// Currency symbols always come from the backend's fare breakdown rather than
/// being assumed, so an operator in a different country gets the right symbol
/// without an app change.
class Formatters {
  const Formatters._();

  static final NumberFormat _wholeNumber = NumberFormat('#,##0');
  static final NumberFormat _oneDecimal = NumberFormat('#,##0.0');
  static final NumberFormat _twoDecimals = NumberFormat('#,##0.00');

  /// `₹320` for a whole amount, `₹320.50` when there are paise to show.
  static String money(num? amount, {String symbol = ''}) {
    if (amount == null) return '--';
    final isWhole = amount == amount.roundToDouble();
    return '$symbol${isWhole ? _wholeNumber.format(amount) : _twoDecimals.format(amount)}';
  }

  /// `12.5 km`, or `850 m` below a kilometre where metres read better.
  static String distance(num? km) {
    if (km == null) return '--';
    if (km < 1) return '${(km * 1000).round()} m';
    return '${_oneDecimal.format(km)} km';
  }

  /// `25 min`, `1 hr 5 min`.
  static String duration(num? minutes) {
    if (minutes == null) return '--';
    final total = minutes.round();
    if (total < 60) return '$total min';
    final hours = total ~/ 60;
    final remainder = total % 60;
    if (remainder == 0) return '$hours hr';
    return '$hours hr $remainder min';
  }

  /// `4 min away` for a pickup ETA.
  static String eta(num? minutes) {
    if (minutes == null) return 'Checking';
    final rounded = minutes.round();
    if (rounded <= 1) return '1 min away';
    return '$rounded min away';
  }

  static final DateFormat _dayMonth = DateFormat('d MMM');
  static final DateFormat _dayMonthYear = DateFormat('d MMM yyyy');
  static final DateFormat _time = DateFormat('h:mm a');
  static final DateFormat _full = DateFormat('d MMM yyyy, h:mm a');
  static final DateFormat _weekdayTime = DateFormat('EEE, d MMM, h:mm a');

  static String dateTime(DateTime? value) => value == null ? '--' : _full.format(value.toLocal());

  static String time(DateTime? value) => value == null ? '--' : _time.format(value.toLocal());

  static String date(DateTime? value) => value == null ? '--' : _dayMonthYear.format(value.toLocal());

  static String scheduledAt(DateTime? value) =>
      value == null ? 'Now' : _weekdayTime.format(value.toLocal());

  /// `Today, 3:40 pm` / `Yesterday, 9:15 am` / `14 Mar, 9:15 am`, which is what
  /// a booking list wants - the exact year is noise for recent trips.
  static String relativeDateTime(DateTime? value) {
    if (value == null) return '--';
    final local = value.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(local.year, local.month, local.day);
    final dayDifference = today.difference(that).inDays;

    if (dayDifference == 0) return 'Today, ${_time.format(local)}';
    if (dayDifference == 1) return 'Yesterday, ${_time.format(local)}';
    if (dayDifference == -1) return 'Tomorrow, ${_time.format(local)}';
    if (local.year == now.year) return '${_dayMonth.format(local)}, ${_time.format(local)}';
    return '${_dayMonthYear.format(local)}, ${_time.format(local)}';
  }

  /// `2 min 05 s` countdown label for the OTP resend timer.
  static String countdown(int seconds) {
    if (seconds <= 0) return '0s';
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '${minutes}m ${remainder.toString().padLeft(2, '0')}s';
  }

  /// `+91 98765 43210` from E.164, for read-only display.
  static String phone(String? e164) {
    if (e164 == null || e164.isEmpty) return '--';
    if (!e164.startsWith('+')) return e164;

    final digits = e164.substring(1);
    if (digits.length < 11) return e164;

    final national = digits.substring(digits.length - 10);
    final countryCode = digits.substring(0, digits.length - 10);
    return '+$countryCode ${national.substring(0, 5)} ${national.substring(5)}';
  }

  /// First name, for greetings. Falls back to the whole string.
  static String firstName(String? fullName) {
    final trimmed = (fullName ?? '').trim();
    if (trimmed.isEmpty) return 'there';
    final space = trimmed.indexOf(' ');
    return space > 0 ? trimmed.substring(0, space) : trimmed;
  }

  /// `AB` from "Asha Babu", for the avatar.
  static String initials(String? fullName) {
    final parts = (fullName ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}
