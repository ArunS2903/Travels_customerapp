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
  static String address(String addressId) => '/customers/me/addresses/$addressId';
  static const String notificationPreferences = '/customers/me/notification-preferences';
  static const String devices = '/customers/me/devices';

  // --- Vehicles and fares ---------------------------------------------------
  static const String vehicleTypes = '/vehicles/types';
  static const String fareEstimate = '/fares/estimate';

  // --- Bookings -------------------------------------------------------------
  static const String bookings = '/bookings';
  static String booking(String bookingId) => '/bookings/$bookingId';
  static String cancelBooking(String bookingId) => '/bookings/$bookingId/cancel';
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
