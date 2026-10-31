import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config/app_config.dart';

/// Handles a push that arrives while the app is terminated or backgrounded.
///
/// Must be a top-level function: the OS spins up a fresh isolate to run it, so
/// it cannot close over anything from the app's state. There is nothing to do
/// here beyond letting the system tray notification display - the app re-reads
/// the booking from the API when it next opens.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Intentionally minimal. Do not touch app state from this isolate.
  if (kDebugMode) {
    // ignore: avoid_print
    print('[push] background message ${message.messageId}');
  }
}

/// Push notifications, with graceful degradation when Firebase is not set up.
///
/// The app is fully usable without Firebase: the backend persists every
/// notification and the in-app history screen reads them over HTTP. So
/// [initialize] reports failure rather than throwing, [isAvailable] stays
/// false, and the profile screen explains that push is off. That is what keeps
/// a developer without a Firebase project from being blocked.
class PushService {
  PushService();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  /// Android needs an explicit channel for heads-up notifications; without it
  /// a foreground push is silently dropped into the shade.
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'booking_updates',
    'Booking updates',
    description: 'Driver assignment, arrival, trip progress and payment updates.',
    importance: Importance.high,
  );

  bool _initialized = false;
  bool _available = false;
  String? _token;

  /// Emits the booking id when the customer taps a booking notification, so the
  /// app can navigate to it.
  final _tapController = StreamController<String>.broadcast();
  Stream<String> get onBookingTapped => _tapController.stream;

  /// Emits whenever a push arrives in the foreground, so open screens can
  /// refresh. Carries the raw data payload.
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onForegroundMessage => _messageController.stream;

  final _tokenRefreshController = StreamController<String>.broadcast();

  /// Emits a new FCM token when it rotates, so it can be re-registered.
  Stream<String> get onTokenRefresh => _tokenRefreshController.stream;

  bool get isAvailable => _available;
  String? get token => _token;

  /// Reason push is unavailable, for display in settings. Null when it works.
  String? unavailableReason;

  Future<bool> initialize() async {
    if (_initialized) return _available;
    _initialized = true;

    if (!AppConfig.isFirebaseConfigured) {
      unavailableReason =
          'Firebase is not configured in this build. Pass FIREBASE_PROJECT_ID, FIREBASE_API_KEY, '
          'FIREBASE_APP_ID and FIREBASE_MESSAGING_SENDER_ID with --dart-define to enable push '
          'notifications. In-app notifications work either way.';
      return false;
    }

    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: AppConfig.firebaseApiKey,
          appId: AppConfig.firebaseAppId,
          messagingSenderId: AppConfig.firebaseMessagingSenderId,
          projectId: AppConfig.firebaseProjectId,
        ),
      );

      await _setUpLocalNotifications();

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        unavailableReason =
            'Notifications are turned off for this app. Enable them in your device settings to '
            'get booking updates.';
        return false;
      }

      _token = await messaging.getToken();

      // A token can rotate at any time; the caller re-registers it.
      messaging.onTokenRefresh.listen((refreshed) {
        _token = refreshed;
        _tokenRefreshController.add(refreshed);
      });

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // The app may have been launched *by* a notification tap.
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        // Defer so the router is mounted before we try to navigate.
        Future<void>.delayed(
          const Duration(milliseconds: 600),
          () => _handleNotificationTap(initialMessage),
        );
      }

      _available = true;
      unavailableReason = null;
      return true;
    } on Object catch (error) {
      // Bad credentials, no Play Services, no network at startup - none of
      // which should stop the app.
      unavailableReason = 'Push notifications could not be set up: $error';
      if (AppConfig.debugLogging) {
        // ignore: avoid_print
        print('[push] initialisation failed: $error');
      }
      return false;
    }
  }

  Future<void> _setUpLocalNotifications() async {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final bookingId = response.payload;
        if (bookingId != null && bookingId.isNotEmpty) _tapController.add(bookingId);
      },
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  /// FCM does not draw a notification while the app is in the foreground, so we
  /// draw it with the local plugin - otherwise a driver-arrived push would be
  /// invisible to someone staring at the app.
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final data = Map<String, dynamic>.from(message.data);
    _messageController.add(data);

    final notification = message.notification;
    if (notification == null) return;

    await _localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: data['bookingId'] as String?,
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    final bookingId = message.data['bookingId'];
    if (bookingId is String && bookingId.isNotEmpty) {
      _tapController.add(bookingId);
    }
  }

  void dispose() {
    _tapController.close();
    _messageController.close();
    _tokenRefreshController.close();
  }
}
