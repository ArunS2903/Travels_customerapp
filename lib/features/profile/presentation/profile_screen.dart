import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/state_views.dart';
import '../../authentication/providers/auth_controller.dart';

/// The account hub.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _isDeleting = false;

  Future<void> _logout() async {
    final confirmed = await AppFeedback.confirm(
      context,
      title: 'Sign out?',
      message: 'You will need your password or a one-time code to sign back in.',
      confirmLabel: 'Sign out',
      isDestructive: true,
    );

    if (!confirmed) return;
    await ref.read(authControllerProvider.notifier).logout();
    // The router redirect takes it from here.
  }

  /// Account deletion is a request, not an immediate wipe: bookings have to
  /// survive for the operator's records. The backend flags the account and
  /// signing back in cancels the request, which this dialog says plainly.
  Future<void> _requestDeletion() async {
    final confirmed = await AppFeedback.confirm(
      context,
      title: 'Request account deletion?',
      message:
          'Your account will be deactivated and you will be signed out. Your past bookings are '
          'kept for the operator\'s records as required. Signing in again cancels the request.',
      confirmLabel: 'Request deletion',
      isDestructive: true,
    );

    if (!confirmed) return;

    setState(() => _isDeleting = true);

    try {
      await ref.read(customerRepositoryProvider).requestAccountDeletion();
      if (!mounted) return;

      AppFeedback.showSuccess(context, 'Your deletion request has been received.');
      await ref.read(authControllerProvider.notifier).logout();
    } on ApiException catch (error) {
      if (!mounted) return;

      if (error.code == 'ACTIVE_BOOKING_EXISTS') {
        AppFeedback.showError(context, error);
        context.push(AppRoutes.bookings);
      } else {
        AppFeedback.showError(context, error);
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customer = ref.watch(currentCustomerProvider);
    final authState = ref.watch(authControllerProvider);

    if (customer == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const LoadingView(),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(authControllerProvider.notifier).refreshProfile(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageGutter,
            AppSpacing.md,
            AppSpacing.pageGutter,
            AppSpacing.xxl,
          ),
          children: [
            // --- Identity ---------------------------------------------------
            SectionCard(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: theme.colorScheme.secondaryContainer,
                    child: Text(
                      Formatters.initials(customer.fullName),
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(customer.fullName, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        if ((customer.phone ?? '').isNotEmpty)
                          Row(
                            children: [
                              Text(
                                Formatters.phone(customer.phone),
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              _VerifiedMark(isVerified: customer.phoneVerified),
                            ],
                          ),
                        if ((customer.email ?? '').isNotEmpty)
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  customer.email!,
                                  style: theme.textTheme.bodySmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              _VerifiedMark(isVerified: customer.emailVerified),
                            ],
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => context.push(AppRoutes.editProfile),
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit profile',
                  ),
                ],
              ),
            ),

            if (customer.hasPendingDeletion) ...[
              const SizedBox(height: AppSpacing.lg),
              AppBanner(
                icon: Icons.warning_amber_rounded,
                accent: AppColors.warning,
                message:
                    'Your account is pending deletion since '
                    '${Formatters.date(customer.deletionRequestedAt)}. Contact support if this '
                    'was not intended.',
                actionLabel: 'Contact support',
                onAction: () => context.push(AppRoutes.support),
              ),
            ],

            if ((customer.email ?? '').isNotEmpty && !customer.emailVerified) ...[
              const SizedBox(height: AppSpacing.lg),
              AppBanner(
                icon: Icons.mark_email_unread_outlined,
                message:
                    'Your email address is not verified yet. Verify it to receive trip '
                    'receipts by email.',
                actionLabel: 'Verify email',
                onAction: () => context.push(AppRoutes.editProfile),
              ),
            ],

            const SizedBox(height: AppSpacing.lg),

            // --- Account ----------------------------------------------------
            _MenuGroup(
              title: 'Account',
              items: [
                _MenuItem(
                  icon: Icons.person_outline_rounded,
                  label: 'Personal details',
                  subtitle: 'Name, mobile number and email',
                  onTap: () => context.push(AppRoutes.editProfile),
                ),
                _MenuItem(
                  icon: Icons.lock_outline_rounded,
                  label: customer.hasPassword ? 'Change password' : 'Set a password',
                  subtitle: customer.hasPassword
                      ? 'Signs you out of other devices'
                      : 'Sign in without a one-time code',
                  onTap: () => context.push(AppRoutes.changePassword),
                ),
                _MenuItem(
                  icon: Icons.bookmark_outline_rounded,
                  label: 'Saved addresses',
                  subtitle: customer.savedAddresses.isEmpty
                      ? 'Add your home and office'
                      : '${customer.savedAddresses.length} saved',
                  onTap: () => context.push(AppRoutes.savedAddresses),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // --- Activity ---------------------------------------------------
            _MenuGroup(
              title: 'Activity',
              items: [
                _MenuItem(
                  icon: Icons.receipt_long_outlined,
                  label: 'My bookings',
                  subtitle: 'Trip history, fares and receipts',
                  onTap: () => context.push(AppRoutes.bookings),
                ),
                _MenuItem(
                  icon: Icons.notifications_none_rounded,
                  label: 'Notifications',
                  subtitle: 'Your booking and account updates',
                  onTap: () => context.push(AppRoutes.notifications),
                ),
                _MenuItem(
                  icon: Icons.tune_rounded,
                  label: 'Notification preferences',
                  subtitle: 'Choose what you want to hear about',
                  onTap: () => context.push(AppRoutes.notificationSettings),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // --- Help -------------------------------------------------------
            _MenuGroup(
              title: 'Help and legal',
              items: [
                _MenuItem(
                  icon: Icons.support_agent_rounded,
                  label: 'Contact support',
                  subtitle: 'Call or email the operator',
                  onTap: () => context.push(AppRoutes.support),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xxl),

            OutlinedButton.icon(
              onPressed: authState.isBusy ? null : _logout,
              icon: const Icon(Icons.logout_rounded, size: 19),
              label: const Text('Sign out'),
            ),
            const SizedBox(height: AppSpacing.md),

            TextButton(
              onPressed: _isDeleting ? null : _requestDeletion,
              style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
              child: Text(_isDeleting ? 'Submitting request' : 'Request account deletion'),
            ),

            const SizedBox(height: AppSpacing.lg),
            Center(
              child: Text(
                'Member since ${Formatters.date(customer.createdAt)}',
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerifiedMark extends StatelessWidget {
  const _VerifiedMark({required this.isVerified});

  final bool isVerified;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          isVerified ? Icons.verified_rounded : Icons.error_outline_rounded,
          size: 13,
          color: isVerified ? AppColors.success : AppColors.warning,
        ),
        const SizedBox(width: 2),
        Text(
          isVerified ? 'Verified' : 'Unverified',
          style: theme.textTheme.labelSmall?.copyWith(
            color: isVerified ? AppColors.success : AppColors.warning,
          ),
        ),
      ],
    );
  }
}

class _MenuItem {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
}

class _MenuGroup extends StatelessWidget {
  const _MenuGroup({required this.title, required this.items});

  final String title;
  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.sm),
          child: Text(title, style: theme.textTheme.labelMedium),
        ),
        Card(
          child: Column(
            children: [
              for (var index = 0; index < items.length; index++) ...[
                InkWell(
                  onTap: items[index].onTap,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(index == 0 ? AppRadius.lg : 0),
                    bottom: Radius.circular(index == items.length - 1 ? AppRadius.lg : 0),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.lg,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          items[index].icon,
                          size: 21,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(items[index].label, style: theme.textTheme.bodyLarge),
                              if (items[index].subtitle != null) ...[
                                const SizedBox(height: 1),
                                Text(
                                  items[index].subtitle!,
                                  style: theme.textTheme.labelSmall,
                                ),
                              ],
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 21,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                if (index != items.length - 1)
                  const Divider(height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
