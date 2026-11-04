import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/feedback.dart';
import '../../../../shared/widgets/section_card.dart';
import '../../../booking_confirmation/providers/booking_draft_controller.dart';

/// Booking Information: when the customer wants the vehicle.
///
/// This is the first thing on the home screen because it is the first thing the
/// rest of the flow depends on. Which vehicles exist at all is a function of
/// the dates - the operator's fleet is held day by day against other bookings -
/// so asking for a vehicle before a date would mean offering cars that cannot
/// be had, and then refusing them at the end.
///
/// Two dates rather than one. A hire is a period, and the server prices it by
/// the day, so "the required booking date" needs a return date to mean
/// anything. The return defaults to the day after, which makes the common case
/// - one day's hire - a single tap, while longer hires are still possible.
class BookingInformationCard extends ConsumerWidget {
  const BookingInformationCard({super.key});

  /// How far ahead a hire may be booked, mirroring `HIRE_LIMITS` on the server.
  ///
  /// Restated here so the picker cannot offer a date the server will reject.
  /// The server remains the authority; this only keeps the two in step.
  static const int maxAdvanceDays = 365;
  static const int maxHireDays = 90;
  static const Duration pickupBuffer = Duration(minutes: 30);

  /// Uses 09:00 for future dates, but never leaves today's pickup in the past.
  static DateTime pickupStartAtForDate(DateTime date, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final start = DateTime(date.year, date.month, date.day, 9);
    final isToday =
        date.year == current.year &&
        date.month == current.month &&
        date.day == current.day;

    if (isToday && !start.isAfter(current.add(pickupBuffer))) {
      return current.add(pickupBuffer);
    }

    return start;
  }

  static DateTime pickupDateTimeForTime(DateTime date, TimeOfDay time) =>
      DateTime(date.year, date.month, date.day, time.hour, time.minute);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final draft = ref.watch(bookingDraftProvider);

    return SectionCard(
      title: 'Booking information',
      icon: Icons.event_note_rounded,
      trailing: draft.hasPeriod
          ? Text(
              draft.days == 1 ? '1 day' : '${draft.days} days',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.amberDark,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            draft.hasPeriod
                ? 'We will only show vehicles that are free on these dates.'
                : 'Choose the date you need a vehicle, and we will show you what is free.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),

          Row(
            children: [
              Expanded(
                child: AppPickerField(
                  label: 'Booking date',
                  prefixIcon: Icons.event_rounded,
                  value: draft.startAt == null
                      ? ''
                      : Formatters.date(draft.startAt),
                  isEmpty: draft.startAt == null,
                  placeholder: 'Select a date',
                  onTap: () => _pickStartDate(context, ref, draft),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppPickerField(
                  label: 'Return date',
                  prefixIcon: Icons.event_repeat_rounded,
                  value: draft.endAt == null
                      ? ''
                      : Formatters.date(draft.endAt),
                  isEmpty: draft.endAt == null,
                  placeholder: draft.startAt == null
                      ? 'Pick a date first'
                      : 'Select a date',
                  onTap: draft.startAt == null
                      ? () => AppFeedback.showInfo(
                          context,
                          'Choose your booking date first.',
                        )
                      : () => _pickEndDate(context, ref, draft),
                ),
              ),
            ],
          ),
          if (draft.startAt != null) ...[
            const SizedBox(height: AppSpacing.sm),
            AppPickerField(
              label: 'Pickup time',
              prefixIcon: Icons.schedule_rounded,
              value: Formatters.time(draft.startAt),
              onTap: () => _pickStartTime(context, ref, draft),
            ),
          ],

          if (draft.startAt == null) ...[
            const SizedBox(height: AppSpacing.md),
            _QuickDateRow(onPick: (date) => _setStart(ref, date)),
          ],
        ],
      ),
    );
  }

  /// Sets the start, and the end a day later if there is none yet.
  ///
  /// Done through the controller's `setStartDate`, which keeps the hire the
  /// same length when the start moves - somebody changing "when do I want the
  /// car" does not mean "and make it shorter".
  void _setStart(WidgetRef ref, DateTime date) {
    final notifier = ref.read(bookingDraftProvider.notifier);
    final draft = ref.read(bookingDraftProvider);
    final start = pickupStartAtForDate(date);

    if (draft.startAt == null) {
      notifier.setPeriod(
        startAt: start,
        endAt: start.add(const Duration(days: 1)),
      );
      return;
    }

    notifier.setStartDate(start);
  }

  Future<void> _pickStartTime(
    BuildContext context,
    WidgetRef ref,
    BookingDraft draft,
  ) async {
    final start = draft.startAt;
    if (start == null) return;

    final picked = await showTimePicker(
      context: context,
      helpText: 'Select pickup time',
      initialTime: TimeOfDay.fromDateTime(start),
    );

    if (picked == null || !context.mounted) return;

    final updatedStart = pickupDateTimeForTime(start, picked);
    final now = DateTime.now();
    final isToday =
        updatedStart.year == now.year &&
        updatedStart.month == now.month &&
        updatedStart.day == now.day;
    if (isToday && !updatedStart.isAfter(now.add(pickupBuffer))) {
      AppFeedback.showInfo(
        context,
        'Choose a pickup time at least 30 minutes from now.',
      );
      return;
    }

    ref.read(bookingDraftProvider.notifier).setStartDate(updatedStart);
  }

  Future<void> _pickStartDate(
    BuildContext context,
    WidgetRef ref,
    BookingDraft draft,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final previousStart = draft.startAt;
    final initialDate =
        previousStart == null ||
            DateUtils.dateOnly(previousStart).isBefore(today)
        ? today
        : DateUtils.dateOnly(previousStart);

    final picked = await showDatePicker(
      context: context,
      helpText: 'Select your booking date',
      initialDate: initialDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: maxAdvanceDays)),
    );

    if (picked == null) return;

    final hadPeriod = draft.hasPeriod;

    _setStart(ref, picked);

    if (!hadPeriod && context.mounted) {
      AppFeedback.showInfo(
        context,
        'Booking date set. Adjust the return date if you need the vehicle longer.',
      );
    }
  }

  Future<void> _pickEndDate(
    BuildContext context,
    WidgetRef ref,
    BookingDraft draft,
  ) async {
    final start = draft.startAt;
    if (start == null) return;

    // A same-day return still bills one day, so the earliest selectable return
    // is the next day - which is also what stops an invalid period reaching the
    // server.
    final earliest = DateTime(
      start.year,
      start.month,
      start.day,
    ).add(const Duration(days: 1));
    final latest = earliest.add(const Duration(days: maxHireDays - 1));

    final initial = draft.endAt != null && !draft.endAt!.isBefore(earliest)
        ? draft.endAt!
        : earliest;

    final picked = await showDatePicker(
      context: context,
      helpText: 'Select your return date',
      initialDate: initial,
      firstDate: earliest,
      lastDate: latest,
    );

    if (picked == null) return;

    // Returned at 09:00 too, so the day count is whole days from the start.
    ref
        .read(bookingDraftProvider.notifier)
        .setEndDate(DateTime(picked.year, picked.month, picked.day, 9));
  }
}

/// Today / tomorrow / this weekend, because most hires start within a few days
/// and a one-tap shortcut beats opening a calendar for them.
class _QuickDateRow extends StatelessWidget {
  const _QuickDateRow({required this.onPick});

  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9);

    /// The coming Saturday. `DateTime.saturday` is 6, so this is 0..6 days out
    /// and lands on today when today is already Saturday.
    final saturday = today.add(
      Duration(days: (DateTime.saturday - today.weekday) % 7),
    );

    final options = <({String label, DateTime date})>[
      (label: 'Today', date: today),
      (label: 'Tomorrow', date: today.add(const Duration(days: 1))),
      (label: 'This weekend', date: saturday),
    ];

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: options
          .map(
            (option) => ActionChip(
              avatar: const Icon(Icons.calendar_today_rounded, size: 15),
              label: Text(option.label),
              onPressed: () => onPick(option.date),
            ),
          )
          .toList(),
    );
  }
}
