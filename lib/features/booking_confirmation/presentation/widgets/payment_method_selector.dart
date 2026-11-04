import 'package:flutter/material.dart';

import '../../../../core/constants/booking_status.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Payment method chooser.
///
/// The list comes from the quote response, which is the operator's own answer
/// about what they can take right now - so a GPay option never appears when
/// GPay is not configured on the server, and the customer is never offered
/// something that would be refused on submission.
///
/// Cash is the fallback when the server sent nothing usable. It is the one
/// method that needs no integration and therefore always works.
///
/// Nothing here captures card details or takes a payment. GPay is a UPI deep
/// link to the operator's own account, and the customer submits the receipt
/// reference afterwards for an admin to confirm - which is why the GPay option
/// says so rather than implying the app knows when money moved.
class PaymentMethodSelector extends StatelessWidget {
  const PaymentMethodSelector({
    super.key,
    required this.selected,
    required this.onSelected,
    this.offered = const [],
  });

  final PaymentMethod selected;
  final ValueChanged<PaymentMethod> onSelected;

  /// Method names as the server sent them, e.g. `['GPay', 'Cash']`.
  final List<String> offered;

  @override
  Widget build(BuildContext context) {
    /// Parsed from the server's list, then narrowed to what a new hire may
    /// actually use. A name the app does not recognise falls through rather
    /// than rendering a button that cannot work.
    final available = offered
        .map(PaymentMethod.fromApi)
        .where((method) => method.isOfferedForHire)
        .toSet()
        .toList();

    if (available.isEmpty) available.add(PaymentMethod.cash);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final method in available) ...[
          _MethodTile(
            method: method,
            isSelected: method == selected,
            onTap: () => onSelected(method),
          ),
          if (method != available.last) const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

/// A selectable option row.
///
/// Used instead of [RadioListTile], whose `groupValue`/`onChanged` are
/// deprecated in current Flutter in favour of a `RadioGroup` ancestor; a plain
/// tile is simpler than threading that through for two options.
class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.method,
    required this.isSelected,
    required this.onTap,
  });

  final PaymentMethod method;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.amber.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.14 : 0.1,
                )
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isSelected ? AppColors.amberDark : theme.colorScheme.outline,
            width: isSelected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              method.icon,
              size: 20,
              color: isSelected ? AppColors.amberDark : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(method.label, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(method.description, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 20,
              color: isSelected ? AppColors.amberDark : theme.colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }
}
