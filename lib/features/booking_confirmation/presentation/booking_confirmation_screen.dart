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
import '../../fleet/presentation/widgets/vehicle_photo_gallery.dart';
import '../../support/presentation/widgets/business_contact_card.dart';
import '../providers/booking_creation_controller.dart';
import '../providers/booking_draft_controller.dart';
import 'widgets/payment_method_selector.dart';

/// The final review before a booking exists.
///
/// Everything the brief asks to be confirmed is here: the booking dates, the
/// vehicle with its photographs, where it is going, the itemised total, the
/// payment method, the customer's own details, any instructions - and the
/// operator's contact details, fetched from the backend rather than hardcoded.
///
/// The quote is re-fetched on open and whenever it goes stale. That is not
/// cosmetic: between choosing a vehicle and confirming, another customer may
/// have booked it, and the re-quote is how this screen finds that out before
/// taking a payment method and submitting.
class BookingConfirmationScreen extends ConsumerStatefulWidget {
  const BookingConfirmationScreen({super.key});

  @override
  ConsumerState<BookingConfirmationScreen> createState() =>
      _BookingConfirmationScreenState();
}

class _BookingConfirmationScreenState
    extends ConsumerState<BookingConfirmationScreen> {
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

  /// Restores the method the customer used last time, if it is still one they
  /// may choose - a remembered `Card` from an older build must not be restored
  /// into a form that can only submit GPay or Cash.
  void _restoreLastPaymentMethod() {
    final remembered = ref.read(prefsStoreProvider).lastPaymentMethod;
    if (remembered == null) return;

    final method = PaymentMethod.fromApi(remembered);
    if (!method.isOfferedForHire) return;

    ref.read(bookingDraftProvider.notifier).setPaymentMethod(method);
  }

  @override
  void dispose() {
    _instructionsController.dispose();
    super.dispose();
  }

  /// Re-prices the hire, and checks the vehicle is still free for the dates.
  Future<void> _refreshQuote() async {
    final draft = ref.read(bookingDraftProvider);
    final period = draft.period;
    final vehicle = draft.vehicle;
    if (period == null || vehicle == null) return;

    setState(() => _isRefreshingQuote = true);

    try {
      final refreshed = await ref
          .read(fleetRepositoryProvider)
          .quoteHire(vehicleId: vehicle.id, period: period);

      if (!mounted) return;

      final previousTotal = draft.quote?.amountDue;
      ref.read(bookingDraftProvider.notifier).refreshQuote(refreshed);

      if (!refreshed.isAvailable) {
        AppFeedback.showError(
          context,
          refreshed.conflictingDays.isEmpty
              ? '${vehicle.name} has just been booked for these dates.'
              : '${vehicle.name} is now booked on ${refreshed.conflictingDays.join(', ')}.',
        );
        return;
      }

      if (previousTotal != null && refreshed.amountDue != previousTotal) {
        AppFeedback.showInfo(
          context,
          'The total changed to '
          '${Formatters.money(refreshed.amountDue, symbol: refreshed.currencySymbol)}.',
        );
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isRefreshingQuote = false);
    }
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
    // the same hire, keeping the pickup for convenience.
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

    final vehicle = draft.vehicle;
    final quote = draft.quote;
    final period = draft.period;

    if (vehicle == null ||
        quote == null ||
        period == null ||
        !draft.isReadyToSearch) {
      return Scaffold(
        appBar: AppBar(title: const Text('Confirm booking')),
        body: EmptyView(
          icon: Icons.assignment_late_outlined,
          title: 'Booking details are incomplete',
          message:
              'Choose your booking dates, pickup and drop locations, and a vehicle before confirming.',
          actionLabel: 'Complete booking',
          onAction: () => context.go(AppRoutes.home),
        ),
      );
    }

    final symbol = quote.currencySymbol;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm booking'),
        actions: [
          IconButton(
            onPressed: _isRefreshingQuote ? null : _refreshQuote,
            tooltip: 'Check availability and price again',
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
          AppSpacing.lg,
          AppSpacing.pageGutter,
          AppSpacing.xxl,
        ),
        children: [
          if (!quote.isAvailable)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: AppBanner(
                icon: Icons.event_busy_rounded,
                accent: AppColors.danger,
                message: quote.conflictingDays.isEmpty
                    ? 'This vehicle is no longer free for these dates.'
                    : 'This vehicle is now booked on ${quote.conflictingDays.join(', ')}.',
                actionLabel: 'Choose another',
                onAction: () => context.go(AppRoutes.availableVehicles),
              ),
            )
          else if (draft.isQuoteStale)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: AppBanner(
                icon: Icons.update_rounded,
                accent: AppColors.warning,
                message:
                    'This was checked a few minutes ago. Refresh to confirm the vehicle '
                    'is still free.',
                actionLabel: 'Refresh',
                onAction: _refreshQuote,
              ),
            ),

          // --- Booking dates ------------------------------------------------
          SectionCard(
            title: 'Booking information',
            icon: Icons.event_note_rounded,
            trailing: TextButton(
              onPressed: () => context.go(AppRoutes.home),
              child: const Text('Change'),
            ),
            child: Column(
              children: [
                InfoRow(
                  label: 'Booking date',
                  value: Formatters.date(quote.startAt),
                  icon: Icons.event_rounded,
                  emphasised: true,
                ),
                InfoRow(
                  label: 'Return date',
                  value: Formatters.date(quote.endAt),
                  icon: Icons.event_repeat_rounded,
                ),
                InfoRow(
                  label: 'Duration',
                  value: quote.days == 1 ? '1 day' : '${quote.days} days',
                  icon: Icons.schedule_rounded,
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
              onPressed: () =>
                  context.push(AppRoutes.vehicleDetailsFor(vehicle.id)),
              child: const Text('Details'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (vehicle.hasPhotos) ...[
                  VehiclePhotoGallery(
                    photoUrls: vehicle.photoUrls,
                    heroTitle: vehicle.name,
                    height: 170,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                Text(vehicle.name, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(vehicle.makeAndModel, style: theme.textTheme.bodySmall),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    InfoPill(
                      icon: Icons.category_rounded,
                      label: vehicle.categoryLabel,
                    ),
                    InfoPill(
                      icon: Icons.airline_seat_recline_normal_rounded,
                      label: '${vehicle.seatingCapacity} seats',
                    ),
                    InfoPill(
                      icon: Icons.local_gas_station_rounded,
                      label: vehicle.fuelLabel,
                    ),
                    InfoPill(
                      icon: Icons.settings_rounded,
                      label: vehicle.transmissionLabel,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Where it is going --------------------------------------------
          SectionCard(
            title: 'Pickup and drop',
            icon: Icons.route_rounded,
            child: RouteSummary(
              pickupAddress: draft.pickup!.address,
              destinationAddress: draft.destination!.address,
              destinationLabel: 'Drop location',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- What it costs ------------------------------------------------
          SectionCard(
            title: 'Total',
            icon: Icons.receipt_long_rounded,
            child: Column(
              children: [
                InfoRow(
                  label: 'Daily rate',
                  value: Formatters.money(quote.dailyRate, symbol: symbol),
                ),
                InfoRow(
                  label: quote.days == 1
                      ? 'Hire charge (1 day)'
                      : 'Hire charge (${quote.days} days)',
                  value: Formatters.money(quote.hireCharge, symbol: symbol),
                ),
                if (quote.securityDeposit > 0)
                  InfoRow(
                    label: 'Security deposit',
                    value: Formatters.money(
                      quote.securityDeposit,
                      symbol: symbol,
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.sm),
                InfoRow(
                  label: 'Amount due',
                  value: Formatters.money(quote.amountDue, symbol: symbol),
                  emphasised: true,
                ),
                if (quote.securityDeposit > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      'The security deposit of '
                      '${Formatters.money(quote.securityDeposit, symbol: symbol)} is refundable '
                      'when the vehicle comes back.',
                      style: theme.textTheme.labelSmall,
                    ),
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
              // The operator's own list, so GPay never appears when it is not
              // configured on the server.
              offered: quote.paymentMethods,
              onSelected: (method) => ref
                  .read(bookingDraftProvider.notifier)
                  .setPaymentMethod(method),
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
                InfoRow(
                  label: 'Mobile',
                  value: Formatters.phone(customer?.phone),
                ),
                InfoRow(
                  label: 'Email',
                  value: (customer?.email?.isNotEmpty ?? false)
                      ? customer!.email!
                      : 'Not added',
                ),
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    'We text your driver details to this mobile number as soon as the '
                    'operator allocates one.',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Instructions -------------------------------------------------
          SectionCard(
            title: 'Note for the operator',
            icon: Icons.sticky_note_2_outlined,
            child: TextField(
              controller: _instructionsController,
              maxLines: 3,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText:
                    'Collection time, a landmark, or anything else useful (optional)',
                counterText: '',
              ),
              onChanged: (value) => ref
                  .read(bookingDraftProvider.notifier)
                  .setSpecialInstructions(value),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Who you are booking with -------------------------------------
          // Fetched from GET /public/business-contact; never hardcoded here.
          const BusinessContactCard(
            title: 'Booking with',
            subtitle:
                'Keep these details for any questions about your booking.',
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
                      Text('Amount due', style: theme.textTheme.labelSmall),
                      Text(
                        Formatters.money(quote.amountDue, symbol: symbol),
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
              // Disabled while submitting, after success, and while the vehicle
              // is known not to be free. The server-side idempotency key is what
              // actually guarantees one booking; this just avoids the customer
              // wondering whether it worked.
              onPressed:
                  creation.isSubmitting || creation.isDone || !quote.isAvailable
                  ? null
                  : _confirm,
            ),
          ],
        ),
      ),
    );
  }
}
