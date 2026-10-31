import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Session tokens, held in the platform keystore.
///
/// Access and refresh tokens go through `flutter_secure_storage` (Android
/// EncryptedSharedPreferences, iOS Keychain) rather than SharedPreferences, so
/// they are not readable from a backup or by another app on a rooted device.
///
/// Reads are cached in memory because the auth interceptor needs the access
/// token on every single request and a keystore round trip per call is wasteful.
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  final FlutterSecureStorage _storage;

  static const _accessTokenKey = 'auth.access_token';
  static const _refreshTokenKey = 'auth.refresh_token';
  static const _customerKey = 'auth.customer';

  String? _cachedAccessToken;
  String? _cachedRefreshToken;
  bool _loaded = false;

  /// Reads the keystore once at startup. Everything after that is served from
  /// memory, and writes update both.
  Future<void> load() async {
    if (_loaded) return;
    try {
      _cachedAccessToken = await _storage.read(key: _accessTokenKey);
      _cachedRefreshToken = await _storage.read(key: _refreshTokenKey);
    } on Exception {
      // A corrupt or unreadable keystore (it happens after some OS upgrades)
      // should land the customer on the login screen, not crash the app.
      _cachedAccessToken = null;
      _cachedRefreshToken = null;
    }
    _loaded = true;
  }

  String? get accessToken => _cachedAccessToken;
  String? get refreshToken => _cachedRefreshToken;

  bool get hasSession => (_cachedRefreshToken ?? '').isNotEmpty;

  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    _cachedAccessToken = accessToken;
    _cachedRefreshToken = refreshToken;
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  /// Used by the refresh flow, which replaces the access token only.
  Future<void> saveAccessToken(String accessToken) async {
    _cachedAccessToken = accessToken;
    await _storage.write(key: _accessTokenKey, value: accessToken);
  }

  /// The last known profile, so the app can show a name on the home screen
  /// before `GET /customers/me` returns.
  Future<void> saveCustomer(Map<String, dynamic> customer) async {
    await _storage.write(key: _customerKey, value: jsonEncode(customer));
  }

  Future<Map<String, dynamic>?> readCustomer() async {
    try {
      final raw = await _storage.read(key: _customerKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on Exception {
      return null;
    }
  }

  Future<void> clear() async {
    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _customerKey);
  }
}
