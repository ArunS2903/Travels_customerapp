import 'package:flutter/material.dart';

import '../../../../core/constants/booking_status.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../models/booking.dart';

/// Vertical progress tracker through the booking lifecycle.
///
/// The steps are the fixed happy path (Pending through Completed); the
/// timestamps come from the booking's own `statusHistory`, so a step that was
/// skipped server-side simply has no time against it rather than inventing one.
///
/// A cancelled booking has no place on this path, so the details screen shows
/// a cancellation card instead of this widget.
class StatusTimeline extends StatelessWidget {
  const StatusTimeline({
    super.key,
    required this.currentStatus,
    required this.history,
  });

  final BookingStatus currentStatus;
  final List<BookingStatusEvent> history;

  /// When each status was reached, by status. Later events win, so a booking
  /// that bounced back to a status shows the most recent time.
  Map<BookingStatus, DateTime> get _timestamps {
    final map = <BookingStatus, DateTime>{};
    for (final event in history) {
      map[event.status] = event.at;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = BookingStatus.progressSequence;
    final currentStep = currentStatus.progressStep ?? 0;
    final times = _timestamps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(steps.length, (index) {
        final step = steps[index];
        final isDone = index < currentStep;
        final isCurrent = index == currentStep;
        final isFuture = index > currentStep;
        final isLast = index == steps.length - 1;
        final reachedAt = times[step];

        final color = isFuture
            ? theme.colorScheme.outline
            : isCurrent
                ? AppColors.brand
                : AppColors.success;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  height: 26,
                  width: 26,
                  decoration: BoxDecoration(
                    color: isFuture ? Colors.transparent : color.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: isCurrent ? 2.2 : 1.6),
                  ),
                  child: Center(
                    child: isDone
                        ? Icon(Icons.check_rounded, size: 14, color: color)
                        : isCurrent
                            // A filled dot on the current step reads as "here",
                            // where a tick would read as "finished".
                            ? Container(
                                height: 9,
                                width: 9,
                                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                              )
                            : null,
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 34,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: isDone ? AppColors.success : theme.colorScheme.outline,
                  ),
              ],
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.apiValue,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: isFuture ? theme.colorScheme.onSurfaceVariant : null,
                        fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      reachedAt != null
                          ? Formatters.relativeDateTime(reachedAt)
                          : isCurrent
                              ? 'In progress'
                              : 'Pending',
                      style: theme.textTheme.labelSmall,
                    ),
                    if (isCurrent) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(step.description, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}
