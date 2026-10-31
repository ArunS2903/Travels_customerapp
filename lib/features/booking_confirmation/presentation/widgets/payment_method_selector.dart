import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/booking_status.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Payment method chooser.
///
/// The list of methods comes from `GET /public/app-config`, so an operator that
/// only takes cash does not show a UPI option the driver cannot accept. Cash is
/// the fallback if the config call has not resolved - it is the one method that
/// needs no integration and therefore always works.
///
/// Only methods settled with the driver are offered; nothing here captures card
/// details or takes a payment, which would need a payment gateway and a PCI
/// story this app does not have.
class PaymentMethodSelector extends ConsumerWidget {
  const PaymentMethodSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final PaymentMethod selected;
  final ValueChanged<PaymentMethod> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final available = ref.watch(serverCapabilitiesProvider).maybeWhen(
          data: (capabilities) => capabilities.paymentMethods
              .map(PaymentMethod.fromApi)
              .toSet()
              .toList(),
          orElse: () => [PaymentMethod.cash],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: available.map((method) {
            final isSelected = method == selected;

            return InkWell(
              onTap: () => onSelected(method),
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.amber.withValues(
                          alpha: theme.brightness == Brightness.dark ? 0.16 : 0.12,
                        )
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: isSelected ? AppColors.amberDark : theme.colorScheme.outline,
                    width: isSelected ? 1.6 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      method.icon,
                      size: 18,
                      color: isSelected
                          ? AppColors.amberDark
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      method.apiValue,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          selected == PaymentMethod.cash
              ? 'Pay the driver in cash at the end of the trip.'
              : 'Settle with the driver by ${selected.apiValue} at the end of the trip.',
          style: theme.textTheme.labelSmall,
        ),
      ],
    );
  }
}
