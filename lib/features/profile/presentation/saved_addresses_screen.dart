import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/models/place.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/state_views.dart';
import '../../authentication/models/customer.dart';
import '../../authentication/providers/auth_controller.dart';
import '../../location/presentation/place_search_screen.dart';

/// Manage saved addresses.
///
/// Home and Office are singletons server-side: saving a new Home replaces the
/// old one rather than leaving two, which is what the home screen's shortcut
/// tiles assume.
class SavedAddressesScreen extends ConsumerStatefulWidget {
  const SavedAddressesScreen({super.key});

  @override
  ConsumerState<SavedAddressesScreen> createState() => _SavedAddressesScreenState();
}

class _SavedAddressesScreenState extends ConsumerState<SavedAddressesScreen> {
  bool _isBusy = false;

  Future<void> _addAddress({String? presetLabel}) async {
    final place = await context.push<Place>(
      AppRoutes.placeSearch,
      extra: const PlaceSearchArgs(target: PlaceSearchTarget.destination),
    );

    if (!mounted || place == null) return;

    final label = presetLabel ?? await _askForLabel(place);
    if (label == null || !mounted) return;

    await _save(label: label, place: place);
  }

  /// Asks what to call this address. Pre-filled with Home/Office chips because
  /// those are what most people save.
  Future<String?> _askForLabel(Place place) async {
    final controller = TextEditingController();

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);

        return Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.pageGutter,
            0,
            AppSpacing.pageGutter,
            AppSpacing.pageGutter + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Name this address', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                place.address,
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final preset in ['Home', 'Office', 'Gym', 'Airport'])
                    ActionChip(
                      label: Text(preset),
                      onPressed: () => Navigator.of(sheetContext).pop(preset),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: 'Or type a name',
                  counterText: '',
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    Navigator.of(sheetContext).pop(value.trim());
                  }
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: 'Save address',
                onPressed: () {
                  final value = controller.text.trim();
                  if (value.isEmpty) return;
                  Navigator.of(sheetContext).pop(value);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _save({required String label, required Place place}) async {
    setState(() => _isBusy = true);

    try {
      await ref.read(customerRepositoryProvider).saveAddress(label: label, place: place);
      // The profile carries the authoritative list, so re-read it rather than
      // patching local state and risking drift.
      await ref.read(authControllerProvider.notifier).refreshProfile();

      if (!mounted) return;
      AppFeedback.showSuccess(context, 'Saved as $label.');
    } on ApiException catch (error) {
      if (mounted) AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _delete(SavedAddress address) async {
    final confirmed = await AppFeedback.confirm(
      context,
      title: 'Remove ${address.label}?',
      message: address.address,
      confirmLabel: 'Remove',
      isDestructive: true,
    );

    if (!confirmed || !mounted) return;

    setState(() => _isBusy = true);

    try {
      await ref.read(customerRepositoryProvider).deleteAddress(address.id);
      await ref.read(authControllerProvider.notifier).refreshProfile();

      if (!mounted) return;
      AppFeedback.showSuccess(context, '${address.label} removed.');
    } on ApiException catch (error) {
      if (mounted) AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customer = ref.watch(currentCustomerProvider);
    final addresses = customer?.savedAddresses ?? const <SavedAddress>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Saved addresses')),
      body: Stack(
        children: [
          if (addresses.isEmpty)
            Column(
              children: [
                Expanded(
                  child: EmptyView(
                    icon: Icons.bookmark_border_rounded,
                    title: 'No saved addresses',
                    message:
                        'Save the places you travel to often and book them from the home '
                        'screen in one tap.',
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.pageGutter,
                    0,
                    AppSpacing.pageGutter,
                    AppSpacing.pageGutter + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Column(
                    children: [
                      PrimaryButton(
                        label: 'Add your home',
                        icon: Icons.home_outlined,
                        onPressed: _isBusy ? null : () => _addAddress(presetLabel: 'Home'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SecondaryButton(
                        label: 'Add your office',
                        icon: Icons.work_outline_rounded,
                        onPressed: _isBusy ? null : () => _addAddress(presetLabel: 'Office'),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            ListView.separated(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.pageGutter,
                AppSpacing.md,
                AppSpacing.pageGutter,
                AppSpacing.huge + MediaQuery.paddingOf(context).bottom,
              ),
              itemCount: addresses.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) {
                final address = addresses[index];

                return Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: theme.colorScheme.outline),
                  ),
                  child: Row(
                    children: [
                      Container(
                        height: 40,
                        width: 40,
                        decoration: BoxDecoration(
                          color: AppColors.amber.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Icon(
                          address.isHome
                              ? Icons.home_rounded
                              : address.isOffice
                                  ? Icons.work_rounded
                                  : Icons.bookmark_rounded,
                          size: 20,
                          color: AppColors.amberDark,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(address.label, style: theme.textTheme.titleSmall),
                            const SizedBox(height: 2),
                            Text(
                              address.address,
                              style: theme.textTheme.bodySmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _isBusy ? null : () => _delete(address),
                        icon: const Icon(Icons.delete_outline_rounded),
                        tooltip: 'Remove ${address.label}',
                        color: theme.colorScheme.error,
                      ),
                    ],
                  ),
                );
              },
            ),
          if (_isBusy) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
      floatingActionButton: addresses.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _isBusy ? null : () => _addAddress(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add address'),
            ),
    );
  }
}
