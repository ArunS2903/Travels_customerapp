import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/routing/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'features/authentication/providers/auth_controller.dart';
import 'features/booking_details/providers/booking_detail_providers.dart';
import 'features/notifications/providers/notification_providers.dart';
import 'features/realtime/socket_service.dart';

/// Root widget.
///
/// Also the place where app-wide, cross-feature reactions are wired: the
/// realtime socket follows the session, and a tapped push notification
/// navigates. Doing this here rather than in a screen means it keeps working
/// regardless of which screen happens to be open.
class CustomerApp extends ConsumerStatefulWidget {
  const CustomerApp({super.key});

  @override
  ConsumerState<CustomerApp> createState() => _CustomerAppState();
}

class _CustomerAppState extends ConsumerState<CustomerApp> {
  StreamSubscription<String>? _pushTapSubscription;
  StreamSubscription<Map<String, dynamic>>? _pushMessageSubscription;

  @override
  void initState() {
    super.initState();

    // Deferred to after the first frame so the router exists before we could
    // be asked to navigate.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _wirePushNavigation();
      // `ref.listen` in build only fires on *changes*, so if bootstrap resolved
      // to "signed in" before this widget mounted, nothing would open the
      // socket. Cover that first case here.
      if (ref.read(authControllerProvider).isAuthenticated) {
        ref.read(socketServiceProvider).connect();
      }
    });
  }

  void _wirePushNavigation() {
    final push = ref.read(pushServiceProvider);

    _pushTapSubscription = push.onBookingTapped.listen((bookingId) {
      if (!mounted || bookingId.isEmpty) return;
      // Only navigate for a signed-in customer; a tap on a stale notification
      // after signing out should not open someone's booking.
      if (!ref.read(authControllerProvider).isAuthenticated) return;
      ref.read(routerProvider).push(AppRoutes.bookingDetailsFor(bookingId));
    });

    // A foreground push about a booking means our cached copy is stale.
    _pushMessageSubscription = push.onForegroundMessage.listen((data) {
      if (!mounted) return;
      ref.invalidate(unreadNotificationCountProvider);

      final bookingId = data['bookingId'];
      if (bookingId is String && bookingId.isNotEmpty) {
        ref.invalidate(bookingDetailProvider(bookingId));
      }
    });
  }

  @override
  void dispose() {
    _pushTapSubscription?.cancel();
    _pushMessageSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    // Opening and closing the socket is a side effect of the session, not of
    // any one screen, so it is driven from here.
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (previous?.status == next.status) return;

      final socket = ref.read(socketServiceProvider);
      if (next.isAuthenticated) {
        socket.connect();
      } else {
        socket.disconnect();
      }
    });

    return MaterialApp.router(
      title: 'Taxi Booking',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
      builder: (context, child) {
        // Cap text scaling. Beyond ~1.3 the fare breakdown and map panel start
        // clipping; honouring the customer's preference up to that point is the
        // right balance between accessibility and a usable layout.
        final mediaQuery = MediaQuery.of(context);
        final scale = mediaQuery.textScaler.clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.3,
        );

        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: scale),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
