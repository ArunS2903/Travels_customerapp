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

  /// The product name, in one place.
  ///
  /// The server also reports a name through `GET /public/app-config`, and the
  /// business contact carries the operator's own trading name. Where either is
  /// available the app prefers it - they can be changed without a release -
  /// and this constant is what renders before they have loaded, which is the
  /// splash screen and the first frame of the sign-in screen.
  static const String appName = 'PP Travels & Cab';

  /// The short form, for places where the full name will not fit: the app bar
  /// on a narrow handset, a notification title, the task switcher.
  static const String appShortName = 'PP Travels';

  /// How the business signs its messages to customers.
  static const String serviceName = 'PP Travels Service';

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

  static String get socketUrl => apiOrigin;

  /// [apiBaseUrl] with the `/api/v1` prefix stripped: the server's own origin.
  ///
  /// Cached in a static rather than recomputed, because it is read once per
  /// image in a scrolling gallery.
  static final String apiOrigin = () {
    if (socketUrlOverride.isNotEmpty) return _stripTrailingSlash(socketUrlOverride);
    final index = apiBaseUrl.indexOf('/api/');
    return _stripTrailingSlash(index == -1 ? apiBaseUrl : apiBaseUrl.substring(0, index));
  }();

  static String _stripTrailingSlash(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;

  /// Turns a stored image reference into a URL this device can actually fetch.
  ///
  /// The backend serves a locally stored photo as a root-relative path
  /// (`/uploads/vehicles/ab12.jpg`) precisely so this can happen: a client that
  /// can reach the API can by definition reach a path on the same origin. An
  /// absolute URL cannot make that promise — the one the server used to store
  /// was built from the uploading browser's host, so an admin working at
  /// `localhost:5000` wrote a URL that on a phone means the phone, and every
  /// vehicle photo hung until it timed out.
  ///
  /// A full `http(s)` URL is passed through: that is Cloudinary or a CDN, and
  /// already correct. A `localhost` or `127.0.0.1` URL is *rehosted* onto
  /// [apiOrigin], because rows written before the server was fixed still carry
  /// one and they would otherwise stay broken until somebody re-uploaded every
  /// photograph.
  static String? resolveMediaUrl(String? reference) {
    final value = reference?.trim() ?? '';
    if (value.isEmpty) return null;

    if (value.startsWith('http://') || value.startsWith('https://')) {
      final parsed = Uri.tryParse(value);
      if (parsed == null) return value;

      final isLoopback = parsed.host == 'localhost' ||
          parsed.host == '127.0.0.1' ||
          parsed.host == '0.0.0.0' ||
          // The emulator alias for the host machine, which is only meaningful
          // on an emulator — a physical device cannot route it either.
          parsed.host == '10.0.2.2';

      if (!isLoopback) return value;

      final path = parsed.hasQuery ? '${parsed.path}?${parsed.query}' : parsed.path;
      return '$apiOrigin$path';
    }

    return value.startsWith('/') ? '$apiOrigin$value' : '$apiOrigin/$value';
  }

  /// Places and Geocoding web-service key used by the app's HTTP requests.
  /// The Android Maps SDK key is configured separately in the native manifest.
  /// Without this value, address search falls back to the on-device geocoder.
  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
  );

  static bool get enablePlacesAutocomplete => googleMapsApiKey.isNotEmpty;

  // --- Firebase Cloud Messaging ---------------------------------------------
  // Supplied explicitly rather than through google-services.json so the app
  // builds and runs without a Firebase project. When any of these is empty,
  // push notifications are disabled and the profile screen explains why.

  static const String firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );
  static const String firebaseApiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
  );
  static const String firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String firebaseMessagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );

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

  /// Per-attempt network timeouts.
  ///
  /// These are deliberately short, and the reason is arithmetic. Every timeout
  /// is multiplied by the retry interceptor, so the old 15s/20s pair over three
  /// attempts meant a customer on a dead connection watched a spinner for the
  /// best part of a minute before being told anything. Measured against this
  /// backend the slowest read is well under a second, so eight seconds is
  /// already a generous outlier — anything past it is a broken route, not a slow
  /// one, and saying so quickly is worth more than waiting.
  ///
  /// Two attempts rather than three: see [RetryInterceptor]. Worst case is now
  /// about 18 seconds instead of about 65.
  static const Duration connectTimeout = Duration(seconds: 8);
  static const Duration receiveTimeout = Duration(seconds: 10);
  static const Duration sendTimeout = Duration(seconds: 15);

  /// How many times a safe request is attempted in total, including the first.
  static const int networkAttempts = 2;

  /// Memory budget for decoded images.
  ///
  /// Flutter's default is 100MB, which a gallery of five full-resolution
  /// vehicle photographs can exhaust on a mid-range phone — and an exhausted
  /// cache means every swipe back re-downloads and re-decodes. Raised a little,
  /// but the real saving is decoding at display size rather than at source
  /// size; see `AppNetworkImage`.
  static const int imageCacheBytes = 160 * 1024 * 1024;
  static const int imageCacheCount = 200;

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
