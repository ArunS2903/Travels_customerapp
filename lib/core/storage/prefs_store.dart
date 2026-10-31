import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/models/place.dart';

/// Non-sensitive local state: whether onboarding has been seen, and the recent
/// destinations shown on the home screen.
///
/// Recent destinations live on the device rather than the server because they
/// are a convenience, not a record - and keeping them local means the app has
/// something useful to show before the first network call completes.
class PrefsStore {
  PrefsStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<PrefsStore> create() async => PrefsStore(await SharedPreferences.getInstance());

  static const _onboardingSeenKey = 'onboarding.seen';
  static const _recentDestinationsKey = 'home.recent_destinations';
  static const _lastPaymentMethodKey = 'booking.last_payment_method';

  static const int maxRecentDestinations = 8;

  bool get hasSeenOnboarding => _prefs.getBool(_onboardingSeenKey) ?? false;

  Future<void> setOnboardingSeen() => _prefs.setBool(_onboardingSeenKey, true);

  /// Remembered so the confirmation screen defaults to what they chose last.
  String? get lastPaymentMethod => _prefs.getString(_lastPaymentMethodKey);

  Future<void> setLastPaymentMethod(String method) =>
      _prefs.setString(_lastPaymentMethodKey, method);

  List<Place> get recentDestinations {
    final raw = _prefs.getStringList(_recentDestinationsKey) ?? const [];
    final places = <Place>[];

    for (final entry in raw) {
      try {
        final decoded = jsonDecode(entry);
        if (decoded is Map<String, dynamic>) places.add(Place.fromJson(decoded));
      } on FormatException {
        // Skip an entry written by an older version rather than losing the lot.
        continue;
      }
    }

    return places;
  }

  /// Adds a destination, moving an existing match to the front rather than
  /// duplicating it, and caps the list.
  Future<void> addRecentDestination(Place place) async {
    final existing = recentDestinations
        .where((p) => !p.isSameLocationAs(place) && p.address != place.address)
        .toList();

    final updated = [place, ...existing].take(maxRecentDestinations).toList();

    await _prefs.setStringList(
      _recentDestinationsKey,
      updated.map((p) => jsonEncode(p.toJson())).toList(),
    );
  }

  Future<void> clearRecentDestinations() => _prefs.remove(_recentDestinationsKey);

  /// Called on sign-out. Onboarding stays seen - it is about the app, not the
  /// account - but anything resembling the customer's history is cleared.
  Future<void> clearPersonalData() async {
    await _prefs.remove(_recentDestinationsKey);
    await _prefs.remove(_lastPaymentMethodKey);
  }
}
