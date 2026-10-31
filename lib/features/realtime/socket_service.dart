import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../core/config/app_config.dart';
import '../../core/providers/app_providers.dart';
import '../booking_details/models/booking.dart';

/// Live booking updates over Socket.IO.
///
/// Explicitly an optimisation, never the source of truth. The screens that care
/// also re-fetch over HTTP when they open and when the app resumes, so a
/// dropped socket costs immediacy and nothing else. That is why every failure
/// path here is silent: there is no error state for the customer to act on.
class SocketService {
  SocketService(this._ref);

  final Ref _ref;

  io.Socket? _socket;

  final _bookingController = StreamController<Booking>.broadcast();

  /// Emits whenever the server reports a change to one of this customer's
  /// bookings, whatever screen is open.
  Stream<Booking> get bookingUpdates => _bookingController.stream;

  bool get isConnected => _socket?.connected ?? false;

  void connect() {
    final token = _ref.read(tokenStoreProvider).accessToken;
    if (token == null || token.isEmpty) return;

    // Reconnect with a fresh token rather than reusing a socket whose
    // handshake credential may have expired.
    disconnect();

    final socket = io.io(
      AppConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableReconnection()
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(15000)
          // Unlimited attempts: a rider on a train will drop in and out all
          // trip, and giving up would leave the details screen stale.
          .setReconnectionAttempts(0)
          .disableAutoConnect()
          .build(),
    );

    socket
      ..onConnect((_) => _log('connected'))
      ..onDisconnect((reason) => _log('disconnected ($reason)'))
      ..onConnectError((error) => _log('connect error: $error'))
      ..on('booking:created', _handleBookingEvent)
      ..on('booking:updated', _handleBookingEvent)
      ..on('booking:cancelled', _handleBookingEvent)
      ..on('notification:new', (_) => _log('notification received'));

    socket.connect();
    _socket = socket;
  }

  /// Joins a booking's room, so updates arrive even if the per-customer room
  /// missed them.
  void subscribeToBooking(String bookingId) {
    _socket?.emit('booking:subscribe', bookingId);
  }

  void unsubscribeFromBooking(String bookingId) {
    _socket?.emit('booking:unsubscribe', bookingId);
  }

  void _handleBookingEvent(dynamic payload) {
    if (payload is! Map) return;
    final raw = payload['booking'];
    if (raw is! Map) return;

    try {
      _bookingController.add(Booking.fromJson(Map<String, dynamic>.from(raw)));
    } on Object catch (error) {
      // A payload we cannot parse must not take down the socket; the screen
      // will still pick up the change on its next refresh.
      _log('could not parse booking payload: $error');
    }
  }

  void disconnect() {
    final socket = _socket;
    if (socket == null) return;

    socket.clearListeners();
    socket.dispose();
    _socket = null;
  }

  void _log(String message) {
    if (AppConfig.debugLogging) {
      // ignore: avoid_print
      print('[socket] $message');
    }
  }

  void dispose() {
    disconnect();
    _bookingController.close();
  }
}

final socketServiceProvider = Provider<SocketService>((ref) {
  final service = SocketService(ref);
  ref.onDispose(service.dispose);
  return service;
});

/// Live booking updates as a stream provider, so a screen can simply watch it.
final bookingUpdateStreamProvider = StreamProvider<Booking>(
  (ref) => ref.watch(socketServiceProvider).bookingUpdates,
);
