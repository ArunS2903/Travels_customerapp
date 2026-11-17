import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// An in-app notification record, from `GET /notifications`.
///
/// The backend persists every notification before attempting push delivery, so
/// this history is complete even when FCM is not configured or a push failed.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.bookingId,
    this.data = const {},
    this.readAt,
  });

  final String id;

  /// Matches the backend's NOTIFICATION_TYPE enum, e.g. `booking_status`.
  final String type;

  final String title;
  final String body;
  final bool isRead;
  final DateTime createdAt;

  /// Set for anything about a booking; used to deep-link on tap.
  final String? bookingId;

  final Map<String, dynamic> data;
  final DateTime? readAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        type: (json['type'] ?? 'account') as String,
        title: (json['title'] ?? '') as String,
        body: (json['body'] ?? '') as String,
        isRead: json['isRead'] as bool? ?? false,
        createdAt: DateTime.tryParse((json['createdAt'] ?? '') as String) ?? DateTime.now(),
        bookingId: json['bookingId'] as String?,
        data: json['data'] is Map ? Map<String, dynamic>.from(json['data'] as Map) : const {},
        readAt: json['readAt'] is String ? DateTime.tryParse(json['readAt'] as String) : null,
      );

  AppNotification copyWith({bool? isRead, DateTime? readAt}) => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
        bookingId: bookingId,
        data: data,
        readAt: readAt ?? this.readAt,
      );

  bool get isAboutBooking => bookingId != null && bookingId!.isNotEmpty;

  IconData get icon {
    switch (type) {
      case 'booking_created':
        return Icons.bookmark_added_outlined;
      case 'booking_status':
        return Icons.update_rounded;
      case 'driver_assigned':
        return Icons.directions_car_filled_rounded;
      case 'driver_arrived':
        return Icons.where_to_vote_rounded;
      case 'trip_completed':
        return Icons.task_alt_rounded;
      case 'booking_cancelled':
        return Icons.cancel_outlined;
      case 'payment':
        return Icons.receipt_long_rounded;
      case 'promotion':
        return Icons.local_offer_outlined;
      case 'account':
      default:
        return Icons.person_outline_rounded;
    }
  }

  Color get accentColor {
    switch (type) {
      case 'trip_completed':
        return AppColors.success;
      case 'booking_cancelled':
        return AppColors.danger;
      case 'driver_assigned':
      case 'driver_arrived':
      case 'booking_status':
        return AppColors.info;
      case 'payment':
        return AppColors.brand;
      case 'promotion':
        return AppColors.brand;
      case 'booking_created':
        return AppColors.success;
      case 'account':
      default:
        return AppColors.inkMuted;
    }
  }
}
