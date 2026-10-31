/// Build-time configuration.
///
/// Every value comes from `--dart-define`, so nothing environment-specific or
/// secret is committed. Running without defines gives you the local-development
/// defaults, and [missingConfiguration] reports what is unset so the UI can say
/// so plainly instead of failing in a confusing way.
///
/// Example:
/// ```
/// flutter run \
///   --dart-define=API_BASE_URL=http://10.0.2.2:5000/api/v1 \
///   --dart-define=GOOGLE_MAPS_API_KEY=AIza... \
///   --dart-define=FIREBASE_PROJECT_ID=my-project \
///   --dart-define=FIREBASE_API_KEY=... \
///   --dart-define=FIREBASE_APP_ID=... \
///   --dart-define=FIREBASE_MESSAGING_SENDER_ID=...
/// ```
class AppConfig {
  const AppConfig._();

  /// Base URL of the Node.js API, including the `/api/v1` prefix.
  ///
  /// `10.0.2.2` is the Android emulator's alias for the host machine's
  /// `localhost`; a physical device needs your machine's LAN address instead.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5000/api/v1',
  );

  /// Origin used for the Socket.IO connection. Defaults to [apiBaseUrl] with
  /// the API prefix stripped, which is right for the standard deployment.
  static const String socketUrlOverride = String.fromEnvironment('SOCKET_URL');

  static String get socketUrl {
    if (socketUrlOverride.isNotEmpty) return socketUrlOverride;
    final index = apiBaseUrl.indexOf('/api/');
    return index == -1 ? apiBaseUrl : apiBaseUrl.substring(0, index);
  }

  /// Android/iOS Maps SDK key. Also used for the Places and Geocoding web
  /// services when [enablePlacesAutocomplete] is true.
  ///
  /// On Android the SDK reads its key from the manifest (supplied by the
  /// `MAPS_API_KEY` Gradle property), so this value is only needed for the
  /// HTTP Places calls. Without it, address search falls back to the on-device
  /// geocoder, which is less precise but needs no key.
  static const String googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  static bool get enablePlacesAutocomplete => googleMapsApiKey.isNotEmpty;

  // --- Firebase Cloud Messaging ---------------------------------------------
  // Supplied explicitly rather than through google-services.json so the app
  // builds and runs without a Firebase project. When any of these is empty,
  // push notifications are disabled and the profile screen explains why.

  static const String firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String firebaseMessagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');

  static bool get isFirebaseConfigured =>
      firebaseProjectId.isNotEmpty &&
      firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseMessagingSenderId.isNotEmpty;

  /// Shows network logs and the development OTP banner. Off in release builds
  /// regardless of what is passed in.
  static const bool _debugLoggingRequested = bool.fromEnvironment(
    'DEBUG_LOGGING',
    defaultValue: true,
  );

  static bool get debugLogging {
    const inRelease = bool.fromEnvironment('dart.vm.product');
    return _debugLoggingRequested && !inRelease;
  }

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
  static const Duration sendTimeout = Duration(seconds: 20);

  /// Fallback map centre, used only before the first location fix arrives.
  static const double defaultLatitude = 11.0168;
  static const double defaultLongitude = 76.9558;

  /// Human-readable list of integrations that are not configured in this build.
  /// Surfaced on the profile screen so a tester knows why something is missing
  /// rather than assuming it is broken.
  static List<String> get missingConfiguration {
    return [
      if (googleMapsApiKey.isEmpty)
        'GOOGLE_MAPS_API_KEY - address autocomplete falls back to the on-device geocoder',
      if (!isFirebaseConfigured)
        'Firebase (FIREBASE_PROJECT_ID, FIREBASE_API_KEY, FIREBASE_APP_ID, FIREBASE_MESSAGING_SENDER_ID) - push notifications are off; in-app notifications still work',
    ];
  }

  static bool get isFullyConfigured => missingConfiguration.isEmpty;
}
