import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/authentication/presentation/forgot_password_screen.dart';
import '../../features/authentication/presentation/login_screen.dart';
import '../../features/authentication/presentation/otp_screen.dart';
import '../../features/authentication/presentation/register_screen.dart';
import '../../features/authentication/presentation/reset_password_screen.dart';
import '../../features/authentication/presentation/splash_screen.dart';
import '../../features/authentication/providers/auth_controller.dart';
import '../../features/booking_confirmation/presentation/booking_confirmation_screen.dart';
import '../../features/booking_details/presentation/booking_details_screen.dart';
import '../../features/booking_details/presentation/booking_vehicle_screen.dart';
import '../../features/booking_history/presentation/my_bookings_screen.dart';
import '../../features/fleet/presentation/available_vehicles_screen.dart';
import '../../features/fleet/presentation/vehicle_details_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/location/presentation/map_picker_screen.dart';
import '../../features/location/presentation/place_search_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/profile/presentation/change_password_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/notification_settings_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/saved_addresses_screen.dart';
import '../../features/support/presentation/support_screen.dart';
import '../providers/app_providers.dart';
import 'app_routes.dart';

/// Bridges a Riverpod provider to `go_router`'s `refreshListenable`, so the
/// router re-evaluates its redirect when the auth state changes.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(this._ref) {
    _ref.listen<AuthState>(
      authControllerProvider,
      (previous, next) {
        // Only a status change can affect routing; ignore busy-flag churn and
        // profile edits, which would otherwise rebuild the whole tree.
        if (previous?.status != next.status) notifyListeners();
      },
    );
  }

  final Ref _ref;
}

/// The root navigator.
///
/// Exposed so code that lives *above* the navigator in the widget tree - the
/// `MaterialApp.router` builder, where app-wide wrappers go - can still show a
/// dialogue or a sheet. `showModalBottomSheet` needs a context with a
/// Navigator in it, and a builder's own context is by definition outside the
/// one the router creates. See LocationPermissionGate.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    debugLogDiagnostics: false,

    /// The single place that decides whether a destination is allowed.
    ///
    /// Three rules, in order:
    ///   1. while the session is still being resolved, hold on the splash
    ///   2. a signed-out customer may only see public screens
    ///   3. a signed-in customer has no business on the auth screens
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;
      final isPublic = AppRoutes.publicPaths.contains(location);

      if (!auth.isResolved) {
        return location == AppRoutes.splash ? null : AppRoutes.splash;
      }

      if (!auth.isAuthenticated) {
        if (isPublic && location != AppRoutes.splash) return null;

        // First run shows onboarding before the login screen.
        final prefs = ref.read(prefsStoreProvider);
        return prefs.hasSeenOnboarding ? AppRoutes.login : AppRoutes.onboarding;
      }

      // Signed in. Bounce off the splash and the auth screens.
      const authOnly = {
        AppRoutes.splash,
        AppRoutes.onboarding,
        AppRoutes.login,
        AppRoutes.register,
        AppRoutes.otp,
        AppRoutes.forgotPassword,
        AppRoutes.resetPassword,
      };

      if (authOnly.contains(location)) return AppRoutes.home;
      return null;
    },

    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, __) => const SplashScreen()),
      GoRoute(path: AppRoutes.onboarding, builder: (_, __) => const OnboardingScreen()),

      // --- Authentication ---------------------------------------------------
      GoRoute(path: AppRoutes.login, builder: (_, __) => const LoginScreen()),
      GoRoute(path: AppRoutes.register, builder: (_, __) => const RegisterScreen()),
      GoRoute(
        path: AppRoutes.otp,
        builder: (context, state) {
          final args = state.extra;
          // Reaching the OTP screen without arguments means a deep link or a
          // process restart; send the customer somewhere coherent instead of
          // rendering a screen that cannot work.
          if (args is! OtpScreenArgs) return const LoginScreen();
          return OtpScreen(args: args);
        },
      ),
      GoRoute(path: AppRoutes.forgotPassword, builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (context, state) {
          final args = state.extra;
          if (args is! ResetPasswordArgs) return const ForgotPasswordScreen();
          return ResetPasswordScreen(args: args);
        },
      ),

      // --- Booking flow -----------------------------------------------------
      GoRoute(path: AppRoutes.home, builder: (_, __) => const HomeScreen()),
      GoRoute(
        path: AppRoutes.placeSearch,
        builder: (context, state) {
          final args = state.extra;
          return PlaceSearchScreen(
            args: args is PlaceSearchArgs ? args : const PlaceSearchArgs(),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.mapPicker,
        builder: (context, state) {
          final args = state.extra;
          return MapPickerScreen(args: args is MapPickerArgs ? args : const MapPickerArgs());
        },
      ),
      // The fleet. `/vehicles` is declared before `/vehicles/:vehicleId` so the
      // list is not matched as an id, mirroring the backend's own route order.
      GoRoute(
        path: AppRoutes.availableVehicles,
        builder: (_, __) => const AvailableVehiclesScreen(),
      ),
      GoRoute(
        path: AppRoutes.vehicleDetails,
        builder: (context, state) {
          final vehicleId = state.pathParameters['vehicleId'] ?? '';
          return VehicleDetailsScreen(vehicleId: vehicleId);
        },
      ),
      GoRoute(
        path: AppRoutes.bookingConfirmation,
        builder: (_, __) => const BookingConfirmationScreen(),
      ),

      // --- Bookings ---------------------------------------------------------
      GoRoute(path: AppRoutes.bookings, builder: (_, __) => const MyBookingsScreen()),
      GoRoute(
        path: AppRoutes.bookingDetails,
        builder: (context, state) {
          final bookingId = state.pathParameters['bookingId'] ?? '';
          return BookingDetailsScreen(
            bookingId: bookingId,
            // Set when arriving straight from a successful booking, so the
            // screen can show the confirmation banner.
            justCreated: state.extra == 'created',
          );
        },
      ),

      // Declared after /bookings/:bookingId, which it extends rather than
      // competes with: go_router matches whole paths, so the order is for the
      // reader's benefit, not the matcher's.
      GoRoute(
        path: AppRoutes.bookingVehicle,
        builder: (context, state) =>
            BookingVehicleScreen(bookingId: state.pathParameters['bookingId'] ?? ''),
      ),

      GoRoute(path: AppRoutes.notifications, builder: (_, __) => const NotificationsScreen()),

      // --- Profile ----------------------------------------------------------
      GoRoute(path: AppRoutes.profile, builder: (_, __) => const ProfileScreen()),
      GoRoute(path: AppRoutes.editProfile, builder: (_, __) => const EditProfileScreen()),
      GoRoute(path: AppRoutes.savedAddresses, builder: (_, __) => const SavedAddressesScreen()),
      GoRoute(path: AppRoutes.changePassword, builder: (_, __) => const ChangePasswordScreen()),
      GoRoute(
        path: AppRoutes.notificationSettings,
        builder: (_, __) => const NotificationSettingsScreen(),
      ),

      GoRoute(path: AppRoutes.support, builder: (_, __) => const SupportScreen()),
    ],

    errorBuilder: (context, state) => _RouteNotFound(location: state.uri.toString()),
  );
});

class _RouteNotFound extends StatelessWidget {
  const _RouteNotFound({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.explore_off_rounded, size: 56),
            const SizedBox(height: 16),
            Text(
              'We could not open that screen',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              location,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go(AppRoutes.home),
              child: const Text('Go to home'),
            ),
          ],
        ),
      ),
    );
  }
}
