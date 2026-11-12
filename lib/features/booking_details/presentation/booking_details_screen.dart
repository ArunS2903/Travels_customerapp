import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/booking_status.dart';
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
import '../../booking_cancellation/presentation/cancel_booking_sheet.dart';
import '../../booking_confirmation/presentation/widgets/fare_breakdown_view.dart';
import '../../fleet/presentation/widgets/vehicle_photo_gallery.dart';
import '../../realtime/socket_service.dart';
import '../../support/presentation/widgets/business_contact_card.dart';
import '../models/booking.dart';
import '../providers/booking_detail_providers.dart';
import 'widgets/booking_route_map.dart';
import 'widgets/driver_allocation_card.dart';
import 'widgets/status_timeline.dart';

/// Everything about one booking: the Booked Details screen.
///
/// It is laid out to answer the questions in the order a customer asks them:
/// which booking is this, what is its status, has a driver been allocated and
/// who are they, which vehicle is it and what does it look like, where is it
/// going, what does it cost.
///
/// Status and driver details come from the backend and only the backend. They
/// arrive three ways, in increasing order of latency: a Socket.IO push, a push
/// notification that invalidates this provider, and pull-to-refresh. The socket
/// is a convenience - the HTTP read on open is what guarantees correctness.
class BookingDetailsScreen extends ConsumerStatefulWidget {
  const BookingDetailsScreen({
    super.key,
    required this.bookingId,
    this.justCreated = false,
  });

  final String bookingId;

  /// True when arriving straight from a successful booking, which earns the
  /// confirmation banner and the "save this reference" nudge.
  final bool justCreated;

  @override
  ConsumerState<BookingDetailsScreen> createState() =>
      _BookingDetailsScreenState();
}

class _BookingDetailsScreenState extends ConsumerState<BookingDetailsScreen> {
  bool _showCreatedBanner = false;
  bool _isProcessingPayment = false;
  late final Razorpay _razorpay;

  @override
  void initState() {
    super.initState();
    _showCreatedBanner = widget.justCreated;
    _razorpay = Razorpay()
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess)
      ..on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError)
      ..on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(bookingDetailProvider(widget.bookingId));
    await ref.read(bookingDetailProvider(widget.bookingId).future);
  }

  Future<void> _copyReference(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    AppFeedback.showSuccess(context, 'Booking reference $code copied.');
  }

  Future<void> _copyDriverNumber(String phone) async {
    await Clipboard.setData(ClipboardData(text: phone));
    if (!mounted) return;
    AppFeedback.showSuccess(context, 'Driver number copied.');
  }

  Future<void> _callDriver(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        AppFeedback.showError(
          context,
          'No phone app available on this device.',
        );
      }
    } on Object {
      if (mounted) AppFeedback.showError(context, 'Could not start a call.');
    }
  }

  Future<void> _startGpayPayment(Booking booking) async {
    if (_isProcessingPayment) return;
    setState(() => _isProcessingPayment = true);

    try {
      final order = await ref
          .read(bookingRepositoryProvider)
          .createPaymentOrder(booking.id);

      if (!mounted) return;
      _razorpay.open({
        'key': order.keyId,
        'amount': order.amount,
        'currency': order.currency,
        'order_id': order.orderId,
        'name': booking.businessContact?.businessName ?? 'Travel booking',
        'description': 'Booking ${booking.bookingCode}',
        'method': {'upi': true},
        'prefill': {
          if ((booking.customerName).isNotEmpty) 'name': booking.customerName,
          if ((booking.customerEmail ?? '').isNotEmpty)
            'email': booking.customerEmail,
          if ((booking.customerPhone ?? '').isNotEmpty)
            'contact': booking.customerPhone,
        },
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _isProcessingPayment = false);
      AppFeedback.showError(context, error);
    }
  }

  Future<void> _handlePaymentSuccess(PaymentSuccessResponse response) async {
    final orderId = response.orderId;
    final paymentId = response.paymentId;
    final signature = response.signature;

    if (orderId == null || paymentId == null || signature == null) {
      if (mounted) {
        setState(() => _isProcessingPayment = false);
        AppFeedback.showError(
          context,
          'The payment provider returned incomplete verification details. Refresh the booking before retrying.',
        );
      }
      return;
    }

    try {
      await ref
          .read(bookingRepositoryProvider)
          .verifyGatewayPayment(
            bookingId: widget.bookingId,
            orderId: orderId,
            paymentId: paymentId,
            signature: signature,
          );
      if (!mounted) return;
      ref.invalidate(bookingDetailProvider(widget.bookingId));
      AppFeedback.showSuccess(context, 'Payment verified and marked paid.');
    } on Object catch (error) {
      if (!mounted) return;
      AppFeedback.showError(context, error);
      ref.invalidate(bookingDetailProvider(widget.bookingId));
    } finally {
      if (mounted) setState(() => _isProcessingPayment = false);
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() => _isProcessingPayment = false);
    AppFeedback.showError(
      context,
      response.message ?? 'Payment was not completed. You can try again.',
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (!mounted) return;
    AppFeedback.showInfo(
      context,
      '${response.walletName ?? 'External wallet'} selected. Complete the payment to update this booking.',
    );
  }

  Future<void> _confirmCashPaid(Booking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm cash payment'),
        content: const Text(
          'Have you paid the operator in cash for this completed travel?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm Paid'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _isProcessingPayment) return;

    setState(() => _isProcessingPayment = true);
    try {
      await ref.read(bookingRepositoryProvider).confirmCashPayment(booking.id);
      if (!mounted) return;
      ref.invalidate(bookingDetailProvider(widget.bookingId));
      AppFeedback.showSuccess(context, 'Payment marked paid.');
    } on Object catch (error) {
      if (!mounted) return;
      AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isProcessingPayment = false);
    }
  }

  Future<void> _openCancelSheet(Booking booking) async {
    final cancelled = await showModalBottomSheet<Booking>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CancelBookingSheet(booking: booking),
    );

    if (!mounted || cancelled == null) return;

    AppFeedback.showSuccess(
      context,
      (cancelled.cancellation?.fee ?? 0) > 0
          ? 'Booking cancelled. A cancellation fee of '
                '${Formatters.money(cancelled.cancellation!.fee, symbol: cancelled.currencySymbol)} applies.'
          : 'Booking cancelled. No fee was charged.',
    );

    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final detailState = ref.watch(bookingDetailProvider(widget.bookingId));

    // A socket update for this booking refreshes the screen under the
    // customer, so a driver assignment appears without them doing anything.
    ref.listen(bookingUpdateStreamProvider, (previous, next) {
      final updated = next.value;
      if (updated == null || updated.id != widget.bookingId) return;
      ref.invalidate(bookingDetailProvider(widget.bookingId));
    });

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          onPressed: () {
            context.go(AppRoutes.home);
          },
          tooltip: 'Back to Home',
          icon: const Icon(Icons.arrow_back_rounded, size: 24),
        ),
        title: const Text('Booking details'),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: detailState.when(
        loading: () => const LoadingView(message: 'Loading your booking'),
        error: (error, _) => ErrorView(error: error, onRetry: _refresh),
        data: (detail) => _buildBody(detail),
      ),
      bottomNavigationBar: detailState.maybeWhen(
        data: (detail) => _buildBottomBar(detail),
        orElse: () => null,
      ),
    );
  }

  Widget _buildBody(BookingDetail detail) {
    final theme = Theme.of(context);
    final booking = detail.booking;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageGutter,
          AppSpacing.md,
          AppSpacing.pageGutter,
          AppSpacing.xxl,
        ),
        children: [
          if (_showCreatedBanner)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: AppBanner(
                icon: Icons.check_circle_rounded,
                accent: AppColors.success,
                message:
                    'Your booking is confirmed and has been sent to the operator. '
                    'Keep the reference ${booking.bookingCode} for any questions.',
                onDismiss: () => setState(() => _showCreatedBanner = false),
              ),
            ),

          // --- Reference and status ----------------------------------------
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Booking reference',
                            style: theme.textTheme.labelSmall,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                booking.bookingCode,
                                style: theme.textTheme.titleLarge,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              IconButton(
                                onPressed: () =>
                                    _copyReference(booking.bookingCode),
                                icon: const Icon(Icons.copy_rounded, size: 17),
                                tooltip: 'Copy reference',
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minHeight: 32,
                                  minWidth: 32,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    StatusChip(status: booking.status),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  booking.status.description,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    PaymentStatusChip(status: booking.paymentStatus),
                    const SizedBox(width: AppSpacing.sm),
                    InfoPill(
                      icon: booking.paymentMethod.icon,
                      label: booking.paymentMethod.apiValue,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Progress -----------------------------------------------------
          if (booking.status != BookingStatus.cancelled)
            SectionCard(
              title: 'Progress',
              icon: Icons.timeline_rounded,
              child: StatusTimeline(
                currentStatus: booking.status,
                history: booking.statusHistory,
              ),
            )
          else if (booking.cancellation != null)
            _CancellationCard(
              cancellation: booking.cancellation!,
              booking: booking,
            ),
          const SizedBox(height: AppSpacing.lg),

          // --- Driver allocation --------------------------------------------
          // Always shown, allocated or not: "has a driver been assigned?" is
          // the question this screen exists to answer, and a card that appeared
          // only once the answer was yes would leave the customer hunting for
          // something that was not there.
          DriverAllocationCard(
            booking: booking,
            onCall: booking.driver?.hasPhone ?? false
                ? () => _callDriver(booking.driver!.phone!)
                : null,
            onCopyNumber: booking.driver?.hasPhone ?? false
                ? () => _copyDriverNumber(booking.driver!.phone!)
                : null,
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- The vehicle, and its photographs -----------------------------
          if (booking.vehicle != null) ...[
            _VehicleCard(booking: booking),
            const SizedBox(height: AppSpacing.lg),
          ],

          // --- Route --------------------------------------------------------
          SectionCard(
            title: 'Route',
            icon: Icons.route_rounded,
            child: Column(
              children: [
                BookingRouteMap(booking: booking),
                const SizedBox(height: AppSpacing.lg),
                RouteSummary(
                  pickupAddress: booking.pickup.address,
                  destinationAddress: booking.destination.address,
                  destinationLabel: booking.isHire
                      ? 'Drop location'
                      : 'Destination',
                ),
                const SizedBox(height: AppSpacing.lg),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    InfoPill(
                      icon: Icons.straighten_rounded,
                      label: Formatters.distance(booking.distanceKm),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    InfoPill(
                      icon: Icons.schedule_rounded,
                      label: Formatters.duration(booking.durationMinutes),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    InfoPill(
                      icon: Icons.directions_car_filled_rounded,
                      label: booking.vehicle?.name ?? booking.vehicleTypeName,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Fare ---------------------------------------------------------
          SectionCard(
            title: booking.isFareFinal ? 'Final fare' : 'Estimated fare',
            icon: Icons.receipt_long_rounded,
            trailing: booking.isFareFinal
                ? null
                : Text('Estimate', style: theme.textTheme.labelSmall),
            child: booking.fareBreakdown == null
                ? InfoRow(
                    label: booking.isFareFinal ? 'Total' : 'Estimated total',
                    value: Formatters.money(
                      booking.displayFare,
                      symbol: booking.currencySymbol,
                    ),
                    emphasised: true,
                  )
                : Column(
                    children: [
                      FareBreakdownView(
                        fare: booking.fareBreakdown!,
                        showTotal: !booking.isFareFinal,
                      ),
                      if (booking.isFareFinal) ...[
                        const SizedBox(height: AppSpacing.sm),
                        const Divider(height: 1),
                        const SizedBox(height: AppSpacing.md),
                        InfoRow(
                          label: 'Final fare',
                          value: Formatters.money(
                            booking.finalFare,
                            symbol: booking.currencySymbol,
                          ),
                          emphasised: true,
                          valueColor: AppColors.success,
                        ),
                        if (booking.finalFare != booking.estimatedFare)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: Text(
                              'Estimated at '
                              '${Formatters.money(booking.estimatedFare, symbol: booking.currencySymbol)} '
                              'when you booked.',
                              style: theme.textTheme.labelSmall,
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Booking facts ------------------------------------------------
          SectionCard(
            title: 'Booking information',
            icon: Icons.info_outline_rounded,
            child: Column(
              children: [
                // The booking ID first: it is what a customer quotes back on
                // the phone, and what every other field here is about.
                InfoRow(
                  label: 'Booking ID',
                  value: booking.bookingCode,
                  emphasised: true,
                ),
                if (booking.hire != null) ...[
                  InfoRow(
                    label: 'Booking date',
                    value: Formatters.date(booking.hire!.startAt),
                    icon: Icons.event_rounded,
                  ),
                  InfoRow(
                    label: 'Return date',
                    value: Formatters.date(booking.hire!.endAt),
                    icon: Icons.event_repeat_rounded,
                  ),
                  InfoRow(
                    label: 'Duration',
                    value: booking.hire!.days == 1
                        ? '1 day'
                        : '${booking.hire!.days} days',
                  ),
                ] else if (booking.isScheduled)
                  InfoRow(
                    label: 'Scheduled pickup',
                    value: Formatters.scheduledAt(booking.scheduledAt),
                  ),
                InfoRow(
                  label: 'Booked on',
                  value: Formatters.dateTime(booking.createdAt),
                ),
                if (booking.completedAt != null)
                  InfoRow(
                    label: 'Completed',
                    value: Formatters.dateTime(booking.completedAt),
                  ),
                InfoRow(label: 'Name', value: booking.customerName),
                if ((booking.customerPhone ?? '').isNotEmpty)
                  InfoRow(
                    label: 'Mobile',
                    value: Formatters.phone(booking.customerPhone),
                  ),
                if ((booking.customerEmail ?? '').isNotEmpty)
                  InfoRow(label: 'Email', value: booking.customerEmail!),
                if ((booking.specialInstructions ?? '').isNotEmpty)
                  InfoRow(
                    label: 'Note for driver',
                    value: booking.specialInstructions!,
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Operator contact ---------------------------------------------
          // The snapshot captured on this booking, so it stays accurate for the
          // trip even if the operator later changes their support line.
          BusinessContactCard(
            snapshot: booking.businessContact,
            title: 'Questions about this trip',
          ),
        ],
      ),
    );
  }

  Widget? _buildBottomBar(BookingDetail detail) {
    final theme = Theme.of(context);
    final booking = detail.booking;
    final canPayByGpay =
        booking.paymentMethod == PaymentMethod.gpay &&
        (booking.paymentStatus == PaymentStatus.pending ||
            booking.paymentStatus == PaymentStatus.failed);
    final canConfirmCash =
        booking.paymentMethod == PaymentMethod.cash &&
        booking.status == BookingStatus.completed &&
        booking.paymentStatus != PaymentStatus.paid &&
        booking.paymentStatus != PaymentStatus.refunded;
    final canBookAgain = booking.status == BookingStatus.completed;

    if (!detail.cancellation.canCancel &&
        !canPayByGpay &&
        !canConfirmCash &&
        !canBookAgain) {
      return null;
    }

    final fee = detail.cancellation.estimatedFee;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.pageGutter,
        AppSpacing.md,
        AppSpacing.pageGutter,
        AppSpacing.md + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canPayByGpay) ...[
            PrimaryButton(
              label: 'Pay with GPay',
              icon: Icons.account_balance_wallet_rounded,
              isLoading: _isProcessingPayment,
              onPressed: _isProcessingPayment
                  ? null
                  : () => _startGpayPayment(booking),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (canConfirmCash) ...[
            PrimaryButton(
              label: 'Confirm Paid',
              icon: Icons.check_circle_outline_rounded,
              isLoading: _isProcessingPayment,
              onPressed: _isProcessingPayment
                  ? null
                  : () => _confirmCashPaid(booking),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (detail.cancellation.canCancel) ...[
            if (fee > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  'Cancelling now costs '
                  '${Formatters.money(fee, symbol: booking.currencySymbol)}.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.warning,
                  ),
                ),
              ),
            SecondaryButton(
              label: 'Cancel booking',
              icon: Icons.close_rounded,
              isDestructive: true,
              onPressed: () => _openCancelSheet(booking),
            ),
          ],
          if (canBookAgain)
            SecondaryButton(
              label: 'Book this trip again',
              icon: Icons.replay_rounded,
              onPressed: () => context.go(AppRoutes.home),
            ),
        ],
      ),
    );
  }
}

/// The vehicle that was booked, with its photographs.
///
/// Both come from the snapshot stored on the booking, so a hire from last March
/// still shows the car that went out at the rate it went out at - the operator
/// re-prices vehicles, replaces photographs and eventually sells them.
class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vehicle = booking.vehicle!;
    final hire = booking.hire;
    final symbol = booking.currencySymbol;

    return SectionCard(
      title: 'Your vehicle',
      icon: Icons.directions_car_filled_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (vehicle.hasPhotos) ...[
            VehiclePhotoGallery(
              photoUrls: vehicle.photos,
              heroTitle: vehicle.name,
              height: 190,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          Text(
            vehicle.name ?? booking.vehicleTypeName,
            style: theme.textTheme.titleSmall,
          ),
          if (vehicle.makeAndModel.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(vehicle.makeAndModel, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: AppSpacing.md),

          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if ((vehicle.registrationNumber ?? '').isNotEmpty)
                InfoPill(
                  icon: Icons.confirmation_number_rounded,
                  label: vehicle.registrationNumber!,
                ),
              if (vehicle.seatingCapacity != null)
                InfoPill(
                  icon: Icons.airline_seat_recline_normal_rounded,
                  label: '${vehicle.seatingCapacity} seats',
                ),
              if ((vehicle.fuelType ?? '').isNotEmpty)
                InfoPill(
                  icon: Icons.local_gas_station_rounded,
                  label: vehicle.fuelType!,
                ),
              if ((vehicle.transmission ?? '').isNotEmpty)
                InfoPill(
                  icon: Icons.settings_rounded,
                  label: vehicle.transmission!,
                ),
            ],
          ),

          if (hire != null) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            InfoRow(
              label: 'Daily rate',
              value: Formatters.money(hire.dailyRate, symbol: symbol),
            ),
            InfoRow(
              label: hire.days == 1
                  ? 'Hire charge (1 day)'
                  : 'Hire charge (${hire.days} days)',
              value: Formatters.money(hire.hireCharge, symbol: symbol),
            ),
            if (hire.securityDeposit > 0)
              InfoRow(
                label: 'Security deposit',
                value:
                    '${Formatters.money(hire.securityDeposit, symbol: symbol)} (refundable)',
              ),
          ],
        ],
      ),
    );
  }
}

class _CancellationCard extends StatelessWidget {
  const _CancellationCard({required this.cancellation, required this.booking});

  final BookingCancellation cancellation;
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SectionCard(
      title: 'Cancellation',
      icon: Icons.cancel_outlined,
      child: Column(
        children: [
          InfoRow(
            label: 'Cancelled by',
            value: cancellation.wasCancelledByCustomer
                ? 'You'
                : (cancellation.cancelledByRole ?? 'the operator'),
          ),
          if (cancellation.cancelledAt != null)
            InfoRow(
              label: 'When',
              value: Formatters.dateTime(cancellation.cancelledAt),
            ),
          if ((cancellation.reason ?? '').isNotEmpty)
            InfoRow(label: 'Reason', value: cancellation.reason!),
          if ((cancellation.remarks ?? '').isNotEmpty)
            InfoRow(label: 'Remarks', value: cancellation.remarks!),
          InfoRow(
            label: 'Cancellation fee',
            value: cancellation.fee > 0
                ? Formatters.money(
                    cancellation.fee,
                    symbol: booking.currencySymbol,
                  )
                : 'None',
            valueColor: cancellation.fee > 0
                ? AppColors.warning
                : AppColors.success,
          ),
          if (cancellation.feeWaived && cancellation.fee == 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'No fee was charged for this cancellation.',
                style: theme.textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }
}
