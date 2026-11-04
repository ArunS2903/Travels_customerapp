import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/authentication/data/auth_repository.dart';
import '../../features/booking_details/data/booking_repository.dart';
import '../../features/fleet/data/fleet_repository.dart';
import '../../features/notifications/data/notification_repository.dart';
import '../../features/profile/data/customer_repository.dart';
import '../../features/support/data/support_repository.dart';
import '../../features/vehicle_selection/data/vehicle_repository.dart';
import '../network/api_client.dart';
import '../network/dio_client.dart';
import '../storage/prefs_store.dart';
import '../storage/token_store.dart';

/// Broadcasts "your session is over" from the networking layer to the auth
/// controller.
///
/// The Dio interceptor discovers an unrecoverable 401 deep inside a request,
/// and the auth controller needs to react to it - but the interceptor is built
/// before the controller exists, and the controller depends on the client. This
/// one-way stream breaks that cycle without either side holding the other.
class SessionEvents {
  SessionEvents();

  final _controller = StreamController<void>.broadcast();

  Stream<void> get onExpired => _controller.stream;

  void notifyExpired() {
    if (!_controller.isClosed) _controller.add(null);
  }

  void dispose() => _controller.close();
}

/// Holds the tokens. Overridden in `main()` with an instance whose keystore
/// read has already completed, so the router can decide where to start without
/// awaiting anything.
final tokenStoreProvider = Provider<TokenStore>((ref) {
  throw StateError(
    'tokenStoreProvider must be overridden in main() with a loaded TokenStore.',
  );
});

/// Local preferences. Also overridden in `main()`.
final prefsStoreProvider = Provider<PrefsStore>((ref) {
  throw StateError(
    'prefsStoreProvider must be overridden in main() with an initialised PrefsStore.',
  );
});

final sessionEventsProvider = Provider<SessionEvents>((ref) {
  final events = SessionEvents();
  ref.onDispose(events.dispose);
  return events;
});

final dioClientProvider = Provider<DioClient>((ref) {
  final tokenStore = ref.watch(tokenStoreProvider);
  final sessionEvents = ref.watch(sessionEventsProvider);

  return DioClient(
    tokenStore: tokenStore,
    onSessionExpired: () async {
      await tokenStore.clear();
      sessionEvents.notifyExpired();
    },
  );
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(dioClientProvider).dio);
});

// --- Repositories -----------------------------------------------------------

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);

final customerRepositoryProvider = Provider<CustomerRepository>(
  (ref) => CustomerRepository(ref.watch(apiClientProvider)),
);

final vehicleRepositoryProvider = Provider<VehicleRepository>(
  (ref) => VehicleRepository(ref.watch(apiClientProvider)),
);

/// The fleet: individual vehicles, their photographs, and hire quotes.
final fleetRepositoryProvider = Provider<FleetRepository>(
  (ref) => FleetRepository(ref.watch(apiClientProvider)),
);

final bookingRepositoryProvider = Provider<BookingRepository>(
  (ref) => BookingRepository(ref.watch(apiClientProvider)),
);

final supportRepositoryProvider = Provider<SupportRepository>(
  (ref) => SupportRepository(ref.watch(apiClientProvider)),
);

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(apiClientProvider)),
);

/// Server capabilities, fetched once and cached for the session. Screens read
/// this to decide whether to offer scheduled bookings, show the approximate
/// distance note, and so on.
final serverCapabilitiesProvider = FutureProvider((ref) async {
  try {
    return await ref.watch(supportRepositoryProvider).fetchAppConfig();
  } on Object {
    // A missing config endpoint must not stop the app working.
    return ServerCapabilitiesFallback.value;
  }
});

/// Indirection so the fallback can live next to the model while staying
/// reachable from the provider above.
class ServerCapabilitiesFallback {
  const ServerCapabilitiesFallback._();
  static final value = ServerCapabilities.fallback;
}

/// The business contact details. Cached for the session; the support screen
/// can force a refresh by invalidating it.
final businessContactProvider = FutureProvider(
  (ref) => ref.watch(supportRepositoryProvider).fetchBusinessContact(),
);
