import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/booking_status.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../authentication/providers/auth_controller.dart';
import '../../support/presentation/widgets/business_contact_card.dart';
import '../providers/booking_creation_controller.dart';
import '../providers/booking_draft_controller.dart';
import 'widgets/fare_breakdown_view.dart';
import 'widgets/payment_method_selector.dart';

/// The final review before a booking exists.
///
/// Everything the brief asks to be confirmed is here: the customer's own
/// details, both addresses, the vehicle, distance, duration, the itemised fare,
/// the payment method, the pickup time, any instructions - and the official
/// business contact details, fetched from the backend rather than hardcoded.
class BookingConfirmationScreen extends ConsumerStatefulWidget {
  const BookingConfirmationScreen({super.key});

  @override
  ConsumerState<BookingConfirmationScreen> createState() =>
      _BookingConfirmationScreenState();
}

class _BookingConfirmationScreenState extends ConsumerState<BookingConfirmationScreen> {
  final _instructionsController = TextEditingController();
  bool _isRefreshingQuote = false;

  @override
  void initState() {
    super.initState();

    final draft = ref.read(bookingDraftProvider);
    _instructionsController.text = draft.specialInstructions ?? '';

    // Any leftover state from a previous booking would otherwise make this
    // screen think it had already submitted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(bookingCreationProvider.notifier).reset();
      _restoreLastPaymentMethod();
      if (draft.isQuoteStale) _refreshQuote();
    });
  }

  void _restoreLastPaymentMethod() {
    final remembered = ref.read(prefsStoreProvider).lastPaymentMethod;
    if (remembered == null) return;

    final method = PaymentMethod.fromApi(remembered);
    ref.read(bookingDraftProvider.notifier).setPaymentMethod(method);
  }

  @override
  void dispose() {
    _instructionsController.dispose();
    super.dispose();
  }

  /// Re-prices the chosen vehicle.
  ///
  /// A quote can go stale while this screen sits open - a surge multiplier may
  /// change - so we refresh rather than submit a figure the customer would be
  /// surprised by. The server recomputes the fare on creation regardless; this
  /// is about showing the right number *before* they commit.
  Future<void> _refreshQuote() async {
    final draft = ref.read(bookingDraftProvider);
    if (!draft.isReadyToConfirm) return;

    setState(() => _isRefreshingQuote = true);

    try {
      final refreshed = await ref.read(vehicleRepositoryProvider).estimateOne(
            vehicleTypeId: draft.selectedEstimate!.id,
            pickup: draft.pickup!,
            destination: draft.destination!,
          );

      if (!mounted) return;

      final previousTotal = draft.selectedEstimate!.fare?.total;
      ref.read(bookingDraftProvider.notifier).refreshSelection(refreshed);

      final newTotal = refreshed.fare?.total;
      if (previousTotal != null && newTotal != null && newTotal != previousTotal) {
        AppFeedback.showInfo(
          context,
          'The fare estimate changed to '
          '${Formatters.money(newTotal, symbol: refreshed.fare!.currencySymbol)}.',
        );
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isRefreshingQuote = false);
    }
  }

  Future<void> _pickScheduledTime() async {
    final now = DateTime.now();
    final draft = ref.read(bookingDraftProvider);

    final date = await showDatePicker(
      context: context,
      initialDate: draft.scheduledAt ?? now.add(const Duration(minutes: 30)),
      firstDate: now,
      // A month is as far ahead as dispatch can sensibly plan.
      lastDate: now.add(const Duration(days: 30)),
    );

    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        draft.scheduledAt ?? now.add(const Duration(minutes: 30)),
      ),
    );

    if (time == null || !mounted) return;

    final scheduled = DateTime(date.year, date.month, date.day, time.hour, time.minute);

    if (scheduled.isBefore(now.add(const Duration(minutes: 10)))) {
      AppFeedback.showInfo(
        context,
        'Schedule a pickup at least 10 minutes from now, or book for right away.',
      );
      return;
    }

    ref.read(bookingDraftProvider.notifier).setScheduledAt(scheduled);
  }

  Future<void> _confirm() async {
    // Persist whatever is in the instructions field before submitting.
    ref
        .read(bookingDraftProvider.notifier)
        .setSpecialInstructions(_instructionsController.text);

    FocusScope.of(context).unfocus();

    final booking = await ref.read(bookingCreationProvider.notifier).submit();

    if (!mounted) return;

    if (booking == null) {
      final error = ref.read(bookingCreationProvider).error;
      if (error != null) AppFeedback.showError(context, error);
      return;
    }

    final wasDeduplicated = ref.read(bookingCreationProvider).wasDeduplicated;

    // Clear the draft so the back button cannot lead to a second submission of
    // the same trip, keeping the pickup for convenience.
    ref.read(bookingDraftProvider.notifier).reset();

    // `go` rather than `push`: the confirmation flow is finished, and the
    // customer should not be able to swipe back into it.
    context.go(AppRoutes.bookingDetailsFor(booking.id), extra: 'created');

    if (wasDeduplicated) {
      AppFeedback.showInfo(context, 'This booking was already created.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = ref.watch(bookingDraftProvider);
    final creation = ref.watch(bookingCreationProvider);
    final customer = ref.watch(currentCustomerProvider);

    if (!draft.isReadyToConfirm) {
      return Scaffold(
        appBar: AppBar(title: const Text('Confirm booking')),
        body: EmptyView(
          icon: Icons.assignment_late_outlined,
          title: 'Nothing to confirm',
          message: 'Start a booking from the home screen to see its summary here.',
          actionLabel: 'Go to home',
          onAction: () => context.go(AppRoutes.home),
        ),
      );
    }

    final estimate = draft.selectedEstimate!;
    final fare = estimate.fare!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm booking'),
        actions: [
          IconButton(
            onPressed: _isRefreshingQuote ? null : _refreshQuote,
            tooltip: 'Refresh fare',
            icon: _isRefreshingQuote
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageGutter,
          0,
          AppSpacing.pageGutter,
          AppSpacing.xxl,
        ),
        children: [
          if (draft.isQuoteStale)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: AppBanner(
                icon: Icons.update_rounded,
                accent: AppColors.warning,
                message:
                    'This fare was quoted a few minutes ago and may have changed.',
                actionLabel: 'Refresh the fare',
                onAction: _refreshQuote,
              ),
            ),

          // --- Trip ---------------------------------------------------------
          SectionCard(
            title: 'Your trip',
            icon: Icons.route_rounded,
            child: Column(
              children: [
                RouteSummary(
                  pickupAddress: draft.pickup!.address,
                  destinationAddress: draft.destination!.address,
                ),
                const SizedBox(height: AppSpacing.lg),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    InfoPill(
                      icon: Icons.straighten_rounded,
                      label: Formatters.distance(draft.route?.distanceKm),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    InfoPill(
                      icon: Icons.schedule_rounded,
                      label: Formatters.duration(draft.route?.durationMinutes),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Vehicle ------------------------------------------------------
          SectionCard(
            title: 'Vehicle',
            icon: Icons.directions_car_filled_rounded,
            trailing: TextButton(
              onPressed: () => context.pop(),
              child: const Text('Change'),
            ),
            child: Row(
              children: [
                Container(
                  height: 46,
                  width: 46,
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Icon(
                    Icons.local_taxi_rounded,
                    size: 23,
                    color: AppColors.amberDark,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(estimate.vehicleType.name, style: theme.textTheme.titleSmall),
                      Text(
                        '${estimate.vehicleType.passengerCapacity} seats'
                        '${estimate.etaMinutes != null ? '  |  ${Formatters.eta(estimate.etaMinutes)}' : ''}',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Fare ---------------------------------------------------------
          SectionCard(
            title: 'Estimated fare',
            icon: Icons.receipt_long_rounded,
            child: FareBreakdownView(fare: fare),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Pickup time --------------------------------------------------
          SectionCard(
            title: 'Pickup time',
            icon: Icons.access_time_rounded,
            child: Column(
              children: [
                _ChoiceTile(
                  isSelected: draft.scheduledAt == null,
                  title: 'Right away',
                  subtitle: 'We look for a driver immediately',
                  icon: Icons.bolt_rounded,
                  onTap: () => ref.read(bookingDraftProvider.notifier).setScheduledAt(null),
                ),
                const SizedBox(height: AppSpacing.sm),
                _ChoiceTile(
                  isSelected: draft.scheduledAt != null,
                  title: 'Schedule for later',
                  subtitle: draft.scheduledAt == null
                      ? 'Choose a date and time'
                      : Formatters.scheduledAt(draft.scheduledAt),
                  icon: Icons.event_rounded,
                  onTap: _pickScheduledTime,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Payment ------------------------------------------------------
          SectionCard(
            title: 'Payment method',
            icon: Icons.payments_outlined,
            child: PaymentMethodSelector(
              selected: draft.paymentMethod,
              onSelected: (method) =>
                  ref.read(bookingDraftProvider.notifier).setPaymentMethod(method),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Your details -------------------------------------------------
          SectionCard(
            title: 'Your details',
            icon: Icons.person_outline_rounded,
            child: Column(
              children: [
                InfoRow(label: 'Name', value: customer?.fullName ?? '--'),
                InfoRow(label: 'Mobile', value: Formatters.phone(customer?.phone)),
                InfoRow(
                  label: 'Email',
                  value: (customer?.email?.isNotEmpty ?? false) ? customer!.email! : 'Not added',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Instructions -------------------------------------------------
          SectionCard(
            title: 'Note for the driver',
            icon: Icons.sticky_note_2_outlined,
            child: TextField(
              controller: _instructionsController,
              maxLines: 3,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Landmark, gate number, or anything else useful (optional)',
                counterText: '',
              ),
              onChanged: (value) =>
                  ref.read(bookingDraftProvider.notifier).setSpecialInstructions(value),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Who you are booking with -------------------------------------
          // Fetched from GET /public/business-contact; never hardcoded here.
          const BusinessContactCard(
            title: 'Booking with',
            subtitle: 'Keep these details for any questions about your trip.',
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.pageGutter,
          AppSpacing.lg,
          AppSpacing.pageGutter,
          AppSpacing.lg + MediaQuery.paddingOf(context).bottom,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: theme.colorScheme.outline)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Estimated total', style: theme.textTheme.labelSmall),
                      Text(
                        Formatters.money(fare.total, symbol: fare.currencySymbol),
                        style: theme.textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  draft.paymentMethod.apiValue,
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(draft.paymentMethod.icon, size: 18),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              label: creation.isDone ? 'Booking created' : 'Confirm booking',
              icon: creation.isDone ? Icons.check_rounded : null,
              isLoading: creation.isSubmitting,
              // Disabled while submitting and after success. The server-side
              // idempotency key is what actually guarantees one booking; this
              // just avoids the customer wondering whether it worked.
              onPressed: creation.isSubmitting || creation.isDone ? null : _confirm,
            ),
          ],
        ),
      ),
    );
  }
}

/// A selectable option row.
///
/// Used instead of [RadioListTile], whose `groupValue`/`onChanged` are
/// deprecated in current Flutter in favour of a `RadioGroup` ancestor; a plain
/// tile is simpler than threading that through for two options.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.isSelected,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final bool isSelected;
  final String title;
  final String subtitle;
  final IconData icon;
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
              icon,
              size: 20,
              color: isSelected ? AppColors.amberDark : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(subtitle, style: theme.textTheme.bodySmall),
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
