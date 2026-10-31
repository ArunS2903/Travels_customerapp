import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/paginated_result.dart';
import '../models/app_notification.dart';

/// In-app notification history.
class NotificationRepository {
  const NotificationRepository(this._client);

  final ApiClient _client;

  Future<NotificationPage> fetchNotifications({
    int page = 1,
    int limit = 20,
    bool unreadOnly = false,
  }) async {
    final data = await _client.get(
      ApiEndpoints.notifications,
      query: {
        'page': page,
        'limit': limit,
        if (unreadOnly) 'unreadOnly': 'true',
      },
    );

    return NotificationPage(
      result: PaginatedResult.fromJson(data, AppNotification.fromJson),
      unreadCount: (data['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }

  Future<int> fetchUnreadCount() async {
    final data = await _client.get(ApiEndpoints.unreadCount);
    return (data['unreadCount'] as num?)?.toInt() ?? 0;
  }

  Future<void> markRead(String notificationId) async {
    await _client.post(ApiEndpoints.readNotification(notificationId));
  }

  Future<int> markAllRead() async {
    final data = await _client.post(ApiEndpoints.readAllNotifications);
    return (data['markedCount'] as num?)?.toInt() ?? 0;
  }
}

/// A page of notifications plus the account-wide unread count, which the badge
/// needs and which does not follow from the page itself.
class NotificationPage {
  const NotificationPage({required this.result, required this.unreadCount});

  final PaginatedResult<AppNotification> result;
  final int unreadCount;
}
