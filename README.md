# Customer App

Flutter taxi-booking application for customers. Android first, with nothing
platform-specific in the Dart layer.

Riverpod for state, Dio for HTTP, go_router for navigation, Google Maps for
location, Socket.IO for live booking status, FCM for push.

API reference: [`../docs/API.md`](../docs/API.md).

## Run it

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000/api/v1
```

`10.0.2.2` is the Android emulator's alias for the host machine's `localhost`.
A physical device needs your machine's LAN address instead.

It runs with no Maps key and no Firebase project. Without the native Maps SDK
key, map tiles are blank; push is off; and address search falls back to the
on-device geocoder. Booking works end to end regardless.

### Talking to an http:// dev server

Android blocks cleartext HTTP from API 28 onwards, so a debug build would
otherwise fail every request with `CLEARTEXT communication to 10.0.2.2 not
permitted by network security policy`.

`android/app/src/debug/res/xml/network_security_config.xml` permits it, and is
referenced from `android/app/src/debug/AndroidManifest.xml`. Both live in the
**debug source set only** — release and profile builds keep Android's default
and will refuse a plain-http server, which is what you want. Point release
builds at an HTTPS URL.

## Configuration

Nothing environment-specific is committed. Dart configuration comes from
`--dart-define`, read in `lib/core/config/app_config.dart`. The Android Maps SDK
key is read separately from the ignored `android/local.properties`.

| Define | Default | Effect when unset |
|---|---|---|
| `API_BASE_URL` | `http://10.0.2.2:5000/api/v1` | — |
| `SOCKET_URL` | derived from `API_BASE_URL` | — |
| `GOOGLE_MAPS_API_KEY` | empty | Places autocomplete falls back to the device geocoder, which needs fuller addresses; does not control map tiles |
| `FIREBASE_PROJECT_ID` | empty | push disabled |
| `FIREBASE_API_KEY` | empty | push disabled |
| `FIREBASE_APP_ID` | empty | push disabled |
| `FIREBASE_MESSAGING_SENDER_ID` | empty | push disabled |
| `DEBUG_LOGGING` | `true` | network logging; forced off in release builds |

`AppConfig.missingConfiguration` turns the above into a plain-language list,
which the profile screen shows under "Build configuration". A tester can see at
a glance why something is missing instead of assuming it is broken.

### The Android Maps SDK key is separate

The native Maps SDK reads its key from the manifest, not from `--dart-define`.
The map preview, map picker, and booking route use this native key. Put it in
`android/local.properties` (gitignored):

```ini
MAPS_API_KEY=AIza...
```

Gradle substitutes it into `AndroidManifest.xml` as a manifest placeholder, so
no key is committed. With it unset the placeholder is empty and the build still
succeeds.

Use **three distinct, restricted keys**: the Android SDK key restricted to this
package name and signing SHA-1, a Places key for the HTTP autocomplete calls,
and a server-side key (IP-restricted) in the backend's `.env`. One unrestricted
key shipped in an APK is extractable in minutes.

### Firebase

Credentials are passed explicitly as `FirebaseOptions` rather than through
`google-services.json`, so the project builds and runs without a Firebase
project at all. `PushService.initialize()` reports failure instead of throwing,
and `unavailableReason` explains why — a missing config, a denied permission, or
no Play Services.

Push is never load-bearing: the backend persists every notification before
attempting delivery, and the in-app notification screen reads them over HTTP.

Full run:

```bash
flutter run \
  --dart-define=API_BASE_URL=https://api.example.com/api/v1 \
  --dart-define=GOOGLE_MAPS_API_KEY=AIza... \
  --dart-define=FIREBASE_PROJECT_ID=my-project \
  --dart-define=FIREBASE_API_KEY=... \
  --dart-define=FIREBASE_APP_ID=1:123:android:abc \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=123456789
```

## Layout

```
lib/
├── main.dart                 storage init before first frame, then runApp
├── app.dart                  MaterialApp.router; wires socket + push to session
├── core/
│   ├── config/               build-time values
│   ├── constants/            api_endpoints, booking_status (mirrors the backend enums)
│   ├── network/              dio_client, auth_interceptor, retry_interceptor,
│   │                         api_client (unwraps the envelope), api_exception
│   ├── storage/              token_store (keystore), prefs_store
│   ├── theme/                app_colors, app_spacing, app_theme
│   ├── routing/              app_routes, app_router (one redirect rule set)
│   ├── utils/                validators, formatters, polyline_decoder
│   ├── providers/            app_providers — the whole DI graph
│   └── notifications/        push_service
├── shared/
│   ├── widgets/              primary_button, app_text_field, state_views,
│   │                         section_card, status_chip, feedback, app_logo
│   └── models/               place, paginated_result
└── features/<feature>/
    ├── data/                 repositories and services
    ├── models/               parsing
    ├── providers/            controllers
    └── presentation/         screens and their widgets
```

Features: `authentication`, `onboarding`, `home`, `location`,
`vehicle_selection`, `booking_confirmation`, `booking_details`,
`booking_cancellation`, `booking_history`, `notifications`, `profile`,
`support`, `realtime`.

## Design notes

**No prices are defined in this app.** Every rate, multiplier and total is
parsed from the backend. The home screen's category strip shows the admin's
*rate card* ("from ₹16/km") because there is no route yet; a trip total only
appears once `POST /fares/estimate` has measured one.

**Duplicate bookings are prevented by the server, with the UI as a courtesy.**
`BookingDraftController.selectVehicle` mints an `idempotencyKey` when the
customer commits to a vehicle, and it is reused across every retry of that
attempt — including a Dio retry after a timeout. The disabled Confirm button
helps, but it is local state and would not survive a process restart; the key
would.

**One in-flight token refresh, shared.** `AuthInterceptor` stores the refresh
`Future` and has concurrent 401s await it. Without that, three parallel requests
would each rotate a one-use refresh token, and the second and third would
present a revoked one — tripping the backend's reuse alarm and signing out a
customer who did nothing wrong.

**Retries only where they are provably safe.** `RetryInterceptor` retries GETs
and anything that opts in with `extra: {'retryable': true}`. Booking creation
opts in precisely because it carries an idempotency key. Backoff is exponential
with jitter, so a fleet of clients does not retry in lockstep after a blip.

**Being offline is not being logged out.** `AuthController.bootstrap` treats a
network failure during the profile fetch as "stay signed in with the cached
profile", and only signs out on an error that actually says the session is
finished.

**Stale fare quotes are refreshed, not silently submitted.** The confirmation
screen re-prices a quote older than three minutes and tells the customer if the
figure moved. The server recomputes on creation regardless; this is about not
surprising them.

**Degradation is always stated.** An approximate distance, a blank map, missing
Places autocomplete, disabled push — each has a visible explanation naming the
missing configuration, rather than looking like a defect.

**Accessibility.** Status is never colour alone: every chip carries an icon and
its text. Text scaling is honoured up to 1.3x (beyond that the fare breakdown
and map panel clip). Tap targets are at least 48dp. Light and dark themes both
meet WCAG AA at body size.

## Testing

```bash
flutter analyze      # clean
flutter test         # 95 tests
```

Unit tests cover the parsing and formatting that screens depend on:

- phone normalisation, pinned to match `backend/src/utils/phone.js` — a mismatch
  there means registering one number and signing in against another
- the validators, mirroring the backend's rules
- money, distance, duration and relative-date formatting, including the cases
  that read badly if naive (`850 m` not `0.9 km`, `1 min away` not `0 min away`)
- `Place.hasValidCoordinates` rejecting the uninitialised `(0,0)` pair
- `BookingStatus.fromApi` degrading to `unknown` for a status the admin adds
  after this build shipped, rather than throwing
- `FareBreakdown` omitting zero lines, and surviving a response with fields
  missing
- `PolylineDecoder` against Google's documented reference string, and not
  throwing on a truncated one
- `FareEstimateResult.cheapest` picking the right option and ignoring
  unavailable ones

Widget tests cover the shared components whose behaviour is load-bearing: that
`PrimaryButton` ignores taps while loading, and that `StatusChip` renders text
alongside colour.

## Release build

```bash
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://api.example.com/api/v1 \
  --dart-define=GOOGLE_MAPS_API_KEY=... \
  --dart-define=FIREBASE_PROJECT_ID=... --dart-define=FIREBASE_API_KEY=... \
  --dart-define=FIREBASE_APP_ID=... --dart-define=FIREBASE_MESSAGING_SENDER_ID=...
```

Signing reads `android/key.properties` if it exists:

```ini
storeFile=../upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA \
  -keysize 2048 -validity 10000 -alias upload
```

Without `key.properties`, release builds use the debug key so `--release` can be
tested; that artifact cannot be published.

R8 and resource shrinking are on for release. `android/app/proguard-rules.pro`
keeps the Maps, Firebase and `flutter_local_notifications` classes that are
resolved reflectively, and preserves line numbers so a field crash report is
readable.

`minSdk` is 23 — `flutter_secure_storage`'s `EncryptedSharedPreferences` needs
it, and that is what keeps tokens out of a device backup.

### Permissions

Declared in `AndroidManifest.xml`, each with a reason in a comment:
`INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_COARSE_LOCATION`,
`ACCESS_FINE_LOCATION`, `POST_NOTIFICATIONS`.

Deliberately **not** requested: background location, contacts, storage, camera.
Location hardware is marked `required="false"`, so the app installs on a device
without GPS — the customer can always type an address or drop a pin.

## Known build issue in this environment

`flutter build apk` currently fails here with a Gradle TLS error
(`PKIX path building failed`) because AVG antivirus intercepts HTTPS and its
root CA is not in the JDK truststore. It is a machine configuration problem, not
a code one. See **Known environment issue** in the [root README](../README.md)
for the diagnosis and three ways to fix it.

## iOS

The Dart code is platform-agnostic and the Xcode project exists, but iOS is not
configured: `Info.plist` needs the location and notification usage strings, the
Maps SDK key must be set in `AppDelegate`, and APNs certificates must be
uploaded to Firebase.
