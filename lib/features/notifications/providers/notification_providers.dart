import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/app_providers.dart';
import '../../authentication/providers/auth_controller.dart';
import '../models/app_notification.dart';

/// Badge count for the bell icon. Kept separate from the list so the home
/// screen can show a badge without loading a page of notifications.
final unreadNotificationCountProvider = FutureProvider<int>((ref) async {
  // Depending on the auth state means the count refetches on sign-in and
  // resolves to 0 rather than erroring when signed out.
  if (!ref.watch(authControllerProvider).isAuthenticated) return 0;

  try {
    return await ref.watch(notificationRepositoryProvider).fetchUnreadCount();
  } on ApiException {
    // A badge is not worth an error state.
    return 0;
  }
});

class NotificationListState {
  const NotificationListState({
    this.items = const [],
    this.unreadCount = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.error,
    this.page = 1,
  });

  final List<AppNotification> items;
  final int unreadCount;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final Object? error;
  final int page;

  bool get isEmpty => items.isEmpty && !isLoading && error == null;

  NotificationListState copyWith({
    List<AppNotification>? items,
    int? unreadCount,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    Object? error,
    int? page,
    bool clearError = false,
  }) =>
      NotificationListState(
        items: items ?? this.items,
        unreadCount: unreadCount ?? this.unreadCount,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        error: clearError ? null : (error ?? this.error),
        page: page ?? this.page,
      );
}

/// Paginated notification history with optimistic read marking.
class NotificationListController extends StateNotifier<NotificationListState> {
  NotificationListController(this._ref) : super(const NotificationListState()) {
    load();
  }

  final Ref _ref;

  static const _pageSize = 20;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final page = await _ref
          .read(notificationRepositoryProvider)
          .fetchNotifications(page: 1, limit: _pageSize);

      state = NotificationListState(
        items: page.result.items,
        unreadCount: page.unreadCount,
        hasMore: page.result.hasMore,
        page: 1,
      );
    } on Object catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);

    try {
      final next = await _ref
          .read(notificationRepositoryProvider)
          .fetchNotifications(page: state.page + 1, limit: _pageSize);

      state = state.copyWith(
        items: [...state.items, ...next.result.items],
        unreadCount: next.unreadCount,
        hasMore: next.result.hasMore,
        page: state.page + 1,
        isLoadingMore: false,
      );
    } on Object {
      // Leave the list as it is; the footer offers another tap.
      state = state.copyWith(isLoadingMore: false);
    }
  }

  /// Marks one notification read, updating the UI first and reverting if the
  /// call fails - tapping a notification should feel instant.
  Future<void> markRead(String notificationId) async {
    final index = state.items.indexWhere((item) => item.id == notificationId);
    if (index == -1 || state.items[index].isRead) return;

    final original = state.items[index];
    final updated = [...state.items];
    updated[index] = original.copyWith(isRead: true, readAt: DateTime.now());

    state = state.copyWith(
      items: updated,
      unreadCount: (state.unreadCount - 1).clamp(0, 1 << 30),
    );

    try {
      await _ref.read(notificationRepositoryProvider).markRead(notificationId);
      _ref.invalidate(unreadNotificationCountProvider);
    } on ApiException {
      final reverted = [...state.items];
      if (index < reverted.length) reverted[index] = original;
      state = state.copyWith(items: reverted, unreadCount: state.unreadCount + 1);
    }
  }

  Future<void> markAllRead() async {
    if (state.unreadCount == 0) return;

    final original = state.items;
    final now = DateTime.now();

    state = state.copyWith(
      items: state.items.map((item) => item.copyWith(isRead: true, readAt: now)).toList(),
      unreadCount: 0,
    );

    try {
      await _ref.read(notificationRepositoryProvider).markAllRead();
      _ref.invalidate(unreadNotificationCountProvider);
    } on ApiException {
      state = state.copyWith(items: original);
      rethrow;
    }
  }
}

final notificationListProvider =
    StateNotifierProvider<NotificationListController, NotificationListState>(
  (ref) => NotificationListController(ref),
);
