import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../vehicle_selection/models/vehicle_estimate.dart';

/// The itemised fare, exactly as the server computed it.
///
/// Every line comes from the API's breakdown - nothing is recomputed here, so
/// the lines always add up to the total the customer is quoted. Zero-value
/// components are omitted rather than shown as "0", which keeps a simple fare
/// looking simple.
class FareBreakdownView extends StatelessWidget {
  const FareBreakdownView({super.key, required this.fare, this.showTotal = true});

  final FareBreakdown fare;
  final bool showTotal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final symbol = fare.currencySymbol;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (fare.hasSurge)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                children: [
                  const Icon(Icons.trending_up_rounded, size: 16, color: AppColors.warning),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Demand is high, so a ${fare.surgeMultiplier}x multiplier applies.',
                      style: theme.textTheme.labelSmall?.copyWith(color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),
          ),

        ...fare.visibleLines.map(
          (line) => _FareLineRow(
            label: line.label,
            amount: Formatters.money(line.amount, symbol: symbol),
          ),
        ),

        if (fare.minimumFareApplied)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'The minimum fare for this vehicle applies to this trip.',
              style: theme.textTheme.labelSmall,
            ),
          ),

        const SizedBox(height: AppSpacing.sm),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sm),

        _FareLineRow(
          label: 'Subtotal',
          amount: Formatters.money(fare.subtotal, symbol: symbol),
        ),
        if (fare.taxAmount > 0)
          _FareLineRow(
            label: 'Taxes (${fare.taxPercent.toStringAsFixed(fare.taxPercent % 1 == 0 ? 0 : 1)}%)',
            amount: Formatters.money(fare.taxAmount, symbol: symbol),
          ),

        if (showTotal) ...[
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text('Estimated total', style: theme.textTheme.titleSmall),
              ),
              Text(
                Formatters.money(fare.total, symbol: symbol),
                style: theme.textTheme.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'This is an estimate. The final fare can change if the route, waiting time '
                  'or tolls differ.',
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _FareLineRow extends StatelessWidget {
  const _FareLineRow({required this.label, required this.amount});

  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            amount,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
