import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../models/app_notification.dart';
import '../providers/notification_providers.dart';

/// In-app notification history.
///
/// Served over HTTP from the backend, which persists every notification before
/// it tries to push one. That is why this screen is complete even when FCM is
/// not configured at all - push is the delivery mechanism, not the record.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      ref.read(notificationListProvider.notifier).loadMore();
    }
  }

  Future<void> _markAllRead() async {
    try {
      await ref.read(notificationListProvider.notifier).markAllRead();
      if (mounted) AppFeedback.showSuccess(context, 'All notifications marked as read.');
    } on Object catch (error) {
      if (mounted) AppFeedback.showError(context, error);
    }
  }

  void _openNotification(AppNotification notification) {
    ref.read(notificationListProvider.notifier).markRead(notification.id);

    if (notification.isAboutBooking) {
      context.push(AppRoutes.bookingDetailsFor(notification.bookingId!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationListProvider);
    final controller = ref.read(notificationListProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (state.unreadCount > 0)
            TextButton(onPressed: _markAllRead, child: const Text('Mark all read')),
        ],
      ),
      body: _buildBody(state, controller),
    );
  }

  Widget _buildBody(NotificationListState state, NotificationListController controller) {
    if (state.isLoading && state.items.isEmpty) {
      return const LoadingView();
    }

    if (state.error != null && state.items.isEmpty) {
      return ErrorView(error: state.error!, onRetry: controller.load);
    }

    if (state.isEmpty) {
      return RefreshIndicator(
        onRefresh: controller.load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.65,
            child: const EmptyView(
              icon: Icons.notifications_none_rounded,
              title: 'No notifications yet',
              message:
                  'Booking confirmations, driver updates and trip receipts will appear here.',
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: controller.load,
      child: ListView.separated(
        controller: _scrollController,
        itemCount: state.items.length + (state.hasMore || state.isLoadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index >= state.items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }

          return _NotificationTile(
            notification: state.items[index],
            onTap: () => _openNotification(state.items[index]),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnread = !notification.isRead;

    return InkWell(
      onTap: onTap,
      child: Container(
        // A tinted background, not just bold text, so unread items are
        // scannable at a glance down the list.
        color: isUnread
            ? notification.accentColor.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.08 : 0.05,
              )
            : null,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pageGutter,
          vertical: AppSpacing.lg,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 38,
              width: 38,
              decoration: BoxDecoration(
                color: notification.accentColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(notification.icon, size: 19, color: notification.accentColor),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (isUnread)
                        Container(
                          height: 8,
                          width: 8,
                          margin: const EdgeInsets.only(left: AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: notification.accentColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(notification.body, style: theme.textTheme.bodySmall),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Text(
                        Formatters.relativeDateTime(notification.createdAt),
                        style: theme.textTheme.labelSmall,
                      ),
                      if (notification.isAboutBooking) ...[
                        const Spacer(),
                        Text(
                          'View booking',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: notification.accentColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 15,
                          color: notification.accentColor,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
