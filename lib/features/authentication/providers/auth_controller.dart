import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/notifications/push_service.dart';
import '../../../core/providers/app_providers.dart';
import '../data/auth_repository.dart';
import '../models/auth_session.dart';
import '../models/customer.dart';

enum AuthStatus {
  /// Before the keystore has been consulted. The splash screen waits on this.
  unknown,
  authenticated,
  unauthenticated,
}

class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.customer,
    this.isBusy = false,
    this.message,
  });

  final AuthStatus status;
  final Customer? customer;

  /// True while a sign-in, registration or sign-out is in flight.
  final bool isBusy;

  /// One-shot message to surface after a redirect, e.g. "you were signed out".
  final String? message;

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isResolved => status != AuthStatus.unknown;

  AuthState copyWith({
    AuthStatus? status,
    Customer? customer,
    bool? isBusy,
    String? message,
    bool clearCustomer = false,
    bool clearMessage = false,
  }) =>
      AuthState(
        status: status ?? this.status,
        customer: clearCustomer ? null : (customer ?? this.customer),
        isBusy: isBusy ?? this.isBusy,
        message: clearMessage ? null : (message ?? this.message),
      );
}

/// Owns the session: who is signed in, and the transitions in and out.
///
/// Every screen that needs the customer reads this rather than re-fetching, and
/// the router redirects off [AuthState.status]. Nothing else writes tokens.
class AuthController extends StateNotifier<AuthState> {
  AuthController(this._ref) : super(const AuthState()) {
    // The networking layer signals an unrecoverable 401 through this stream.
    _expirySubscription = _ref.read(sessionEventsProvider).onExpired.listen((_) {
      _handleSessionExpired();
    });
  }

  final Ref _ref;
  late final StreamSubscription<void> _expirySubscription;

  AuthRepository get _repository => _ref.read(authRepositoryProvider);

  /// Decides the starting screen.
  ///
  /// A stored refresh token is treated as "probably signed in", and we try to
  /// load the profile. A network failure is deliberately *not* a sign-out: the
  /// customer keeps their session and sees cached details, because being
  /// offline is not the same as being logged out.
  Future<void> bootstrap() async {
    final tokenStore = _ref.read(tokenStoreProvider);
    await tokenStore.load();

    if (!tokenStore.hasSession) {
      state = state.copyWith(status: AuthStatus.unauthenticated, clearCustomer: true);
      return;
    }

    // Show something immediately from the cached profile.
    final cached = await tokenStore.readCustomer();
    if (cached != null) {
      try {
        state = state.copyWith(
          status: AuthStatus.authenticated,
          customer: Customer.fromJson(cached),
        );
      } on Object {
        // A cache written by an older version; ignore and rely on the network.
      }
    }

    try {
      final customer = await _repository.fetchProfile();
      await tokenStore.saveCustomer(customer.toJson());
      state = state.copyWith(status: AuthStatus.authenticated, customer: customer);
      await _registerPushToken();
    } on ApiException catch (error) {
      if (error.requiresReauthentication) {
        await _clearSession();
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          clearCustomer: true,
          message: 'Please sign in again.',
        );
        return;
      }

      if (cached != null) {
        // Offline with a cached profile: stay signed in.
        state = state.copyWith(status: AuthStatus.authenticated);
      } else {
        // Offline with nothing cached. The token may be fine, but we have no
        // profile to render, so send them to sign-in rather than an empty home.
        state = state.copyWith(status: AuthStatus.unauthenticated, clearCustomer: true);
      }
    }
  }

  Future<AuthSession> registerWithPhone({
    required String fullName,
    required String phone,
    String? email,
    required String password,
    required String verificationToken,
  }) =>
      _runSessionCall(() => _repository.register(
            fullName: fullName,
            phone: phone,
            email: email,
            password: password,
            verificationToken: verificationToken,
            fcmToken: _pushToken,
          ));

  Future<AuthSession> registerWithEmail({
    required String fullName,
    required String email,
    required String password,
  }) =>
      _runSessionCall(() => _repository.register(
            fullName: fullName,
            email: email,
            password: password,
            fcmToken: _pushToken,
          ));

  Future<AuthSession> loginWithPassword({
    required String identifier,
    required String password,
  }) =>
      _runSessionCall(() => _repository.loginWithPassword(
            identifier: identifier,
            password: password,
            fcmToken: _pushToken,
          ));

  Future<AuthSession> loginWithOtp({required String identifier, required String code}) =>
      _runSessionCall(() => _repository.verifyOtpAndSignIn(
            identifier: identifier,
            code: code,
            fcmToken: _pushToken,
          ));

  Future<AuthSession> completePasswordReset({
    required String identifier,
    required String verificationToken,
    required String password,
  }) =>
      _runSessionCall(() => _repository.resetPassword(
            identifier: identifier,
            verificationToken: verificationToken,
            password: password,
          ));

  /// Stores a session returned by an endpoint outside this controller, such as
  /// the change-password call, which rotates tokens as a side effect.
  Future<void> adoptSession(AuthSession session) async {
    await _persistSession(session);
    state = state.copyWith(status: AuthStatus.authenticated, customer: session.customer);
  }

  /// Runs a call that returns a session, handling the busy flag and persistence
  /// in one place so each caller is a one-liner.
  Future<AuthSession> _runSessionCall(Future<AuthSession> Function() call) async {
    state = state.copyWith(isBusy: true, clearMessage: true);
    try {
      final session = await call();
      await _persistSession(session);
      state = state.copyWith(
        status: AuthStatus.authenticated,
        customer: session.customer,
        isBusy: false,
      );
      await _registerPushToken();
      return session;
    } on Object {
      state = state.copyWith(isBusy: false);
      rethrow;
    }
  }

  Future<void> _persistSession(AuthSession session) async {
    final tokenStore = _ref.read(tokenStoreProvider);
    await tokenStore.saveTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );
    await tokenStore.saveCustomer(session.customer.toJson());
  }

  /// Replaces the cached customer after a profile edit.
  Future<void> updateCustomer(Customer customer) async {
    await _ref.read(tokenStoreProvider).saveCustomer(customer.toJson());
    state = state.copyWith(customer: customer);
  }

  /// Re-reads the profile, e.g. after saving an address elsewhere.
  Future<void> refreshProfile() async {
    if (!state.isAuthenticated) return;
    try {
      final customer = await _repository.fetchProfile();
      await _ref.read(tokenStoreProvider).saveCustomer(customer.toJson());
      state = state.copyWith(customer: customer);
    } on ApiException {
      // A failed refresh leaves the existing profile in place.
    }
  }

  Future<void> logout({bool allDevices = false}) async {
    state = state.copyWith(isBusy: true);
    final tokenStore = _ref.read(tokenStoreProvider);
    final refreshToken = tokenStore.refreshToken;

    try {
      await _repository.logout(
        refreshToken: refreshToken,
        fcmToken: _pushToken,
        allDevices: allDevices,
      );
    } on ApiException {
      // Telling the server is best-effort. Signing out locally must always
      // succeed, or a customer with a dead network could not sign out at all.
    }

    await _clearSession();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> _clearSession() async {
    await _ref.read(tokenStoreProvider).clear();
    await _ref.read(prefsStoreProvider).clearPersonalData();
  }

  Future<void> _handleSessionExpired() async {
    if (state.status == AuthStatus.unauthenticated) return;
    await _clearSession();
    state = const AuthState(
      status: AuthStatus.unauthenticated,
      message: 'Your session expired. Please sign in again.',
    );
  }

  void consumeMessage() {
    if (state.message != null) state = state.copyWith(clearMessage: true);
  }

  String? get _pushToken {
    final push = _ref.read(pushServiceProvider);
    return push.isAvailable ? push.token : null;
  }

  /// Sends this device's FCM token to the backend after sign-in. Failure is
  /// logged and ignored - push is an enhancement, not a requirement.
  Future<void> _registerPushToken() async {
    final push = _ref.read(pushServiceProvider);
    final token = push.token;
    if (!push.isAvailable || token == null || token.isEmpty) return;

    try {
      await _ref.read(customerRepositoryProvider).registerDevice(fcmToken: token);
    } on ApiException catch (error) {
      if (AppConfig.debugLogging) {
        // ignore: avoid_print
        print('[push] device registration failed: ${error.code}');
      }
    }
  }

  @override
  void dispose() {
    _expirySubscription.cancel();
    super.dispose();
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(ref),
);

/// The signed-in customer, or null. Convenience for widgets that only need this.
final currentCustomerProvider = Provider<Customer?>(
  (ref) => ref.watch(authControllerProvider).customer,
);

/// Push notifications. Initialised in `main()`; see [PushService.initialize].
final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService();
  ref.onDispose(service.dispose);
  return service;
});
