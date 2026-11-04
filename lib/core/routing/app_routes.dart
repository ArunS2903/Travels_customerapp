/// Route paths and names in one place, so navigation calls never contain a
/// string literal that can drift out of sync with the router.
class AppRoutes {
  const AppRoutes._();

  static const String splash = '/splash';
  static const String onboarding = '/onboarding';

  static const String login = '/login';
  static const String register = '/register';
  static const String otp = '/otp';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';

  static const String home = '/';
  static const String placeSearch = '/place-search';
  static const String mapPicker = '/map-picker';

  /// The vehicles free for the dates in the draft.
  static const String availableVehicles = '/vehicles';

  /// One vehicle, in full. A path parameter rather than an object in `extra`,
  /// so the screen works from a deep link and after a process restart.
  static const String vehicleDetails = '/vehicles/:vehicleId';
  static String vehicleDetailsFor(String vehicleId) => '/vehicles/$vehicleId';

  static const String bookingConfirmation = '/booking-confirmation';

  static const String bookings = '/bookings';
  static const String bookingDetails = '/bookings/:bookingId';
  static String bookingDetailsFor(String bookingId) => '/bookings/$bookingId';

  static const String notifications = '/notifications';

  static const String profile = '/profile';
  static const String editProfile = '/profile/edit';
  static const String savedAddresses = '/profile/addresses';
  static const String changePassword = '/profile/change-password';
  static const String notificationSettings = '/profile/notifications';
  static const String deleteAccount = '/profile/delete-account';

  static const String support = '/support';

  /// Screens reachable without a session. Everything else redirects to [login].
  static const Set<String> publicPaths = {
    splash,
    onboarding,
    login,
    register,
    otp,
    forgotPassword,
    resetPassword,
    support,
  };
}
