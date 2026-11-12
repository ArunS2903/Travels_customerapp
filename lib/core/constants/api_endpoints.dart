/// Every API path in one place, relative to `AppConfig.apiBaseUrl`.
///
/// Keeping them here rather than inline in the repositories means a backend
/// route change is a one-line edit, and it is easy to audit what the app talks
/// to. These mirror backend/src/routes/index.js.
class ApiEndpoints {
  const ApiEndpoints._();

  // --- Authentication -------------------------------------------------------
  static const String register = '/auth/register';
  static const String sendOtp = '/auth/send-otp';
  static const String verifyOtp = '/auth/verify-otp';
  static const String login = '/auth/login';
  static const String refreshToken = '/auth/refresh-token';
  static const String logout = '/auth/logout';
  static const String forgotPassword = '/auth/forgot-password';
  static const String resetPassword = '/auth/reset-password';

  // --- Customer -------------------------------------------------------------
  static const String me = '/customers/me';
  static const String myPassword = '/customers/me/password';
  static const String myBookings = '/customers/me/bookings';
  static const String myAddresses = '/customers/me/addresses';
  static String address(String addressId) =>
      '/customers/me/addresses/$addressId';
  static const String notificationPreferences =
      '/customers/me/notification-preferences';
  static const String devices = '/customers/me/devices';

  // --- Vehicles and fares ---------------------------------------------------
  static const String vehicleTypes = '/vehicles/types';
  static const String fareEstimate = '/fares/estimate';

  /// The fleet: individual vehicles with their photographs and daily rates.
  ///
  /// Declared after `/vehicles/types` on the server so "types" is never matched
  /// as an id; the order matters there, not here.
  static const String vehicles = '/vehicles';
  static String vehicle(String vehicleId) => '/vehicles/$vehicleId';

  /// Which days a vehicle is already held, for the date picker.
  static String vehicleAvailability(String vehicleId) =>
      '/vehicles/$vehicleId/availability';

  // --- Bookings -------------------------------------------------------------
  static const String bookings = '/bookings';

  /// What a hire would cost, before committing to it. Creates nothing.
  static const String hireQuote = '/bookings/quote';

  static String booking(String bookingId) => '/bookings/$bookingId';
  static String bookingPaymentOrder(String bookingId) =>
      '/bookings/$bookingId/payment/order';
  static String verifyBookingPayment(String bookingId) =>
      '/bookings/$bookingId/payment/verify';
  static String confirmCashPayment(String bookingId) =>
      '/bookings/$bookingId/payment/confirm-cash';
  static String cancelBooking(String bookingId) =>
      '/bookings/$bookingId/cancel';
  static String cancellationPolicy(String bookingId) =>
      '/bookings/$bookingId/cancellation-policy';

  // --- Notifications --------------------------------------------------------
  static const String notifications = '/notifications';
  static const String unreadCount = '/notifications/unread-count';
  static const String readAllNotifications = '/notifications/read-all';
  static String readNotification(String id) => '/notifications/$id/read';

  // --- Public ---------------------------------------------------------------
  static const String businessContact = '/public/business-contact';
  static const String appConfig = '/public/app-config';
  static const String health = '/public/health';
}
