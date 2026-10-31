import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/state_views.dart';
import '../../authentication/providers/auth_controller.dart';

/// Notification preferences.
///
/// Each toggle is applied optimistically and reverted if the call fails, so a
/// switch never sits in a state the server disagrees with.
///
/// Transactional updates about a live booking are not switchable: a customer
/// who turned those off would be left waiting at the kerb with no idea their
/// driver had arrived. Only the channel and marketing choices are offered.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  String? _pendingKey;

  Future<void> _update({
    required String key,
    bool? push,
    bool? email,
    bool? sms,
    bool? promotions,
  }) async {
    final controller = ref.read(authControllerProvider.notifier);
    final customer = ref.read(currentCustomerProvider);
    if (customer == null) return;

    final previous = customer.notificationPrefs;

    // Optimistic update.
    setState(() => _pendingKey = key);
    await controller.updateCustomer(
      customer.copyWith(
        notificationPrefs: previous.copyWith(
          push: push,
          email: email,
          sms: sms,
          promotions: promotions,
        ),
      ),
    );

    try {
      final saved = await ref.read(customerRepositoryProvider).updateNotificationPreferences(
            push: push,
            email: email,
            sms: sms,
            promotions: promotions,
          );

      final current = ref.read(currentCustomerProvider);
      if (current != null) {
        await controller.updateCustomer(current.copyWith(notificationPrefs: saved));
      }
    } on ApiException catch (error) {
      // Put the switch back where it was.
      final current = ref.read(currentCustomerProvider);
      if (current != null) {
        await controller.updateCustomer(current.copyWith(notificationPrefs: previous));
      }
      if (mounted) AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _pendingKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customer = ref.watch(currentCustomerProvider);
    final pushService = ref.watch(pushServiceProvider);

    if (customer == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: const LoadingView(),
      );
    }

    final prefs = customer.notificationPrefs;

    return Scaffold(
      appBar: AppBar(title: const Text('Notification preferences')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.pageGutter),
        children: [
          if (!pushService.isAvailable)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: AppBanner(
                icon: Icons.notifications_off_outlined,
                accent: AppColors.warning,
                message: pushService.unavailableReason ??
                    'Push notifications are unavailable on this device. You can still see '
                        'everything in the in-app notifications list.',
              ),
            ),

          SectionCard(
            title: 'How we reach you',
            icon: Icons.campaign_outlined,
            child: Column(
              children: [
                _PreferenceSwitch(
                  label: 'Push notifications',
                  subtitle: 'Driver assignment, arrival and trip updates',
                  value: prefs.push,
                  isBusy: _pendingKey == 'push',
                  // A disabled switch would be a lie if the toggle still works
                  // server-side, so keep it live and explain above instead.
                  onChanged: (value) => _update(key: 'push', push: value),
                ),
                const Divider(height: 1),
                _PreferenceSwitch(
                  label: 'SMS',
                  subtitle: 'Text messages for important booking updates',
                  value: prefs.sms,
                  isBusy: _pendingKey == 'sms',
                  onChanged: (value) => _update(key: 'sms', sms: value),
                ),
                const Divider(height: 1),
                _PreferenceSwitch(
                  label: 'Email',
                  subtitle: 'Trip receipts and account notices',
                  value: prefs.email,
                  isBusy: _pendingKey == 'email',
                  onChanged: (value) => _update(key: 'email', email: value),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          SectionCard(
            title: 'Offers',
            icon: Icons.local_offer_outlined,
            child: _PreferenceSwitch(
              label: 'Promotions and offers',
              subtitle: 'Discounts and news from the operator. Off by default.',
              value: prefs.promotions,
              isBusy: _pendingKey == 'promotions',
              onChanged: (value) => _update(key: 'promotions', promotions: value),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          Text(
            'Updates about a trip in progress are always delivered in the app, so you never '
            'miss your driver arriving.',
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _PreferenceSwitch extends StatelessWidget {
  const _PreferenceSwitch({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.isBusy = false,
  });

  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 1),
                Text(subtitle, style: theme.textTheme.labelSmall),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          if (isBusy)
            const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
