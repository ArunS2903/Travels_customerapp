import '../../../shared/models/place.dart';

/// A saved address, with the id needed to delete it.
class SavedAddress {
  const SavedAddress({
    required this.id,
    required this.label,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.placeId,
  });

  final String id;
  final String label;
  final String address;
  final double latitude;
  final double longitude;
  final String? placeId;

  factory SavedAddress.fromJson(Map<String, dynamic> json) => SavedAddress(
        id: json['id'] as String,
        label: (json['label'] ?? 'Other') as String,
        address: (json['address'] ?? '') as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        placeId: json['placeId'] as String?,
      );

  Place toPlace() => Place(
        address: address,
        latitude: latitude,
        longitude: longitude,
        placeId: placeId,
        label: label,
      );

  bool get isHome => label.toLowerCase() == 'home';
  bool get isOffice => label.toLowerCase() == 'office';
}

class NotificationPreferences {
  const NotificationPreferences({
    this.push = true,
    this.email = true,
    this.sms = true,
    this.promotions = false,
  });

  final bool push;
  final bool email;
  final bool sms;
  final bool promotions;

  factory NotificationPreferences.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const NotificationPreferences();
    return NotificationPreferences(
      push: json['push'] as bool? ?? true,
      email: json['email'] as bool? ?? true,
      sms: json['sms'] as bool? ?? true,
      promotions: json['promotions'] as bool? ?? false,
    );
  }

  NotificationPreferences copyWith({bool? push, bool? email, bool? sms, bool? promotions}) =>
      NotificationPreferences(
        push: push ?? this.push,
        email: email ?? this.email,
        sms: sms ?? this.sms,
        promotions: promotions ?? this.promotions,
      );
}

/// The signed-in customer's own profile.
class Customer {
  const Customer({
    required this.id,
    required this.fullName,
    this.phone,
    this.email,
    this.phoneVerified = false,
    this.emailVerified = false,
    this.status = 'active',
    this.savedAddresses = const [],
    this.notificationPrefs = const NotificationPreferences(),
    this.hasPassword = true,
    this.deletionRequestedAt,
    this.createdAt,
  });

  final String id;
  final String fullName;
  final String? phone;
  final String? email;
  final bool phoneVerified;
  final bool emailVerified;
  final String status;
  final List<SavedAddress> savedAddresses;
  final NotificationPreferences notificationPrefs;
  final bool hasPassword;
  final DateTime? deletionRequestedAt;
  final DateTime? createdAt;

  factory Customer.fromJson(Map<String, dynamic> json) {
    final rawAddresses = json['savedAddresses'];

    return Customer(
      id: json['id'] as String,
      fullName: (json['fullName'] ?? '') as String,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      phoneVerified: json['phoneVerified'] as bool? ?? false,
      emailVerified: json['emailVerified'] as bool? ?? false,
      status: (json['status'] ?? 'active') as String,
      savedAddresses: rawAddresses is List
          ? rawAddresses
              .whereType<Map>()
              .map((item) => SavedAddress.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : const [],
      notificationPrefs: NotificationPreferences.fromJson(
        json['notificationPrefs'] is Map
            ? Map<String, dynamic>.from(json['notificationPrefs'] as Map)
            : null,
      ),
      hasPassword: json['hasPassword'] as bool? ?? true,
      deletionRequestedAt: _parseDate(json['deletionRequestedAt']),
      createdAt: _parseDate(json['createdAt']),
    );
  }

  /// Cached locally so the home screen can greet the customer before the
  /// profile request returns.
  Map<String, dynamic> toJson() => {
        'id': id,
        'fullName': fullName,
        'phone': phone,
        'email': email,
        'phoneVerified': phoneVerified,
        'emailVerified': emailVerified,
        'status': status,
        'hasPassword': hasPassword,
        'savedAddresses': savedAddresses
            .map((a) => {
                  'id': a.id,
                  'label': a.label,
                  'address': a.address,
                  'latitude': a.latitude,
                  'longitude': a.longitude,
                  'placeId': a.placeId,
                })
            .toList(),
        'notificationPrefs': {
          'push': notificationPrefs.push,
          'email': notificationPrefs.email,
          'sms': notificationPrefs.sms,
          'promotions': notificationPrefs.promotions,
        },
        'createdAt': createdAt?.toIso8601String(),
        'deletionRequestedAt': deletionRequestedAt?.toIso8601String(),
      };

  SavedAddress? get home =>
      savedAddresses.where((a) => a.isHome).firstOrNull;

  SavedAddress? get office =>
      savedAddresses.where((a) => a.isOffice).firstOrNull;

  bool get hasPendingDeletion => deletionRequestedAt != null;

  Customer copyWith({
    String? fullName,
    String? phone,
    String? email,
    bool? phoneVerified,
    bool? emailVerified,
    String? status,
    List<SavedAddress>? savedAddresses,
    NotificationPreferences? notificationPrefs,
  }) =>
      Customer(
        id: id,
        fullName: fullName ?? this.fullName,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        phoneVerified: phoneVerified ?? this.phoneVerified,
        emailVerified: emailVerified ?? this.emailVerified,
        status: status ?? this.status,
        savedAddresses: savedAddresses ?? this.savedAddresses,
        notificationPrefs: notificationPrefs ?? this.notificationPrefs,
        hasPassword: hasPassword,
        deletionRequestedAt: deletionRequestedAt,
        createdAt: createdAt,
      );

  static DateTime? _parseDate(Object? value) {
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
