import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/validators.dart';
import '../../authentication/models/auth_session.dart';
import '../../authentication/models/customer.dart';
import '../../../shared/models/place.dart';

/// Profile, saved addresses, preferences and account deletion.
class CustomerRepository {
  const CustomerRepository(this._client);

  final ApiClient _client;

  Future<Customer> fetchProfile() async {
    final data = await _client.get(ApiEndpoints.me);
    return Customer.fromJson(Map<String, dynamic>.from(data['customer'] as Map));
  }

  /// Updates the name, and optionally an identifier.
  ///
  /// Changing a verified phone or email needs [verificationToken] from an OTP
  /// sent to the *new* value - proof the customer controls it. The backend
  /// enforces this; passing nothing gets a `VERIFICATION_TOKEN_MISSING` error
  /// that the profile screen turns into a "verify first" prompt.
  Future<Customer> updateProfile({
    String? fullName,
    String? phone,
    String? email,
    String? verificationToken,
  }) async {
    final data = await _client.put(
      ApiEndpoints.me,
      body: {
        if (fullName != null) 'fullName': fullName.trim(),
        if (phone != null) 'phone': Validators.normalizePhone(phone),
        if (email != null) 'email': email.trim().toLowerCase(),
        if (verificationToken != null) 'verificationToken': verificationToken,
      },
    );
    return Customer.fromJson(Map<String, dynamic>.from(data['customer'] as Map));
  }

  /// Changes the password. The backend signs out every other device and issues
  /// a new session for this one, which is returned so the caller can store it -
  /// without that, the app would be holding a token it just invalidated.
  Future<AuthSession> changePassword({
    String? currentPassword,
    required String newPassword,
  }) async {
    final data = await _client.put(
      ApiEndpoints.myPassword,
      body: {
        if (currentPassword != null && currentPassword.isNotEmpty)
          'currentPassword': currentPassword,
        'newPassword': newPassword,
        'confirmPassword': newPassword,
      },
    );
    return AuthSession.fromJson(data);
  }

  Future<List<SavedAddress>> fetchAddresses() async {
    final data = await _client.get(ApiEndpoints.myAddresses);
    return _parseAddresses(data['items']);
  }

  /// Saves an address. Saving a `Home` or `Office` replaces the existing one of
  /// that name rather than adding a second.
  Future<List<SavedAddress>> saveAddress({required String label, required Place place}) async {
    final data = await _client.post(
      ApiEndpoints.myAddresses,
      body: {
        'label': label.trim(),
        'address': place.address,
        'latitude': place.latitude,
        'longitude': place.longitude,
        if (place.placeId != null) 'placeId': place.placeId,
      },
    );
    return _parseAddresses(data['savedAddresses']);
  }

  Future<List<SavedAddress>> deleteAddress(String addressId) async {
    final data = await _client.delete(ApiEndpoints.address(addressId));
    return _parseAddresses(data['savedAddresses']);
  }

  Future<NotificationPreferences> updateNotificationPreferences({
    bool? push,
    bool? email,
    bool? sms,
    bool? promotions,
  }) async {
    final data = await _client.put(
      ApiEndpoints.notificationPreferences,
      body: {
        if (push != null) 'push': push,
        if (email != null) 'email': email,
        if (sms != null) 'sms': sms,
        if (promotions != null) 'promotions': promotions,
      },
    );
    return NotificationPreferences.fromJson(
      Map<String, dynamic>.from(data['notificationPrefs'] as Map),
    );
  }

  /// Registers this device's FCM token so booking updates can be pushed.
  Future<void> registerDevice({required String fcmToken, String platform = 'android'}) async {
    await _client.post(
      ApiEndpoints.devices,
      body: {'fcmToken': fcmToken, 'platform': platform},
    );
  }

  /// Requests account deletion. The backend flags the account rather than
  /// deleting rows, and refuses while a trip is in progress.
  Future<void> requestAccountDeletion({String? reason}) async {
    await _client.delete(
      ApiEndpoints.me,
      body: {'confirm': true, if (reason != null && reason.isNotEmpty) 'reason': reason},
    );
  }

  static List<SavedAddress> _parseAddresses(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => SavedAddress.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }
}
