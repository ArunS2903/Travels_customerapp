import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/booking_status.dart';
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
import '../../realtime/socket_service.dart';
import '../../support/presentation/widgets/business_contact_card.dart';
import '../models/booking.dart';
import '../providers/booking_detail_providers.dart';
import 'widgets/booking_route_map.dart';
import 'widgets/status_timeline.dart';

/// Everything about one booking.
///
/// Status comes from the backend and only the backend. It arrives three ways,
/// in increasing order of latency: a Socket.IO push, a push notification that
/// invalidates this provider, and pull-to-refresh. The socket is a convenience
/// - the HTTP read on open is what guarantees correctness.
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
  ConsumerState<BookingDetailsScreen> createState() => _BookingDetailsScreenState();
}

class _BookingDetailsScreenState extends ConsumerState<BookingDetailsScreen> {
  bool _showCreatedBanner = false;

  @override
  void initState() {
    super.initState();
    _showCreatedBanner = widget.justCreated;
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

  Future<void> _callDriver(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        AppFeedback.showError(context, 'No phone app available on this device.');
      }
    } on Object {
      if (mounted) AppFeedback.showError(context, 'Could not start a call.');
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
                          Text('Booking reference', style: theme.textTheme.labelSmall),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(booking.bookingCode, style: theme.textTheme.titleLarge),
                              const SizedBox(width: AppSpacing.sm),
                              IconButton(
                                onPressed: () => _copyReference(booking.bookingCode),
                                icon: const Icon(Icons.copy_rounded, size: 17),
                                tooltip: 'Copy reference',
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minHeight: 32, minWidth: 32),
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
                Text(booking.status.description, style: theme.textTheme.bodySmall),
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
            _CancellationCard(cancellation: booking.cancellation!, booking: booking),
          const SizedBox(height: AppSpacing.lg),

          // --- Driver -------------------------------------------------------
          if (booking.driver != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: _DriverCard(
                driver: booking.driver!,
                onCall: booking.driver!.phone == null
                    ? null
                    : () => _callDriver(booking.driver!.phone!),
              ),
            ),

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
                      label: booking.vehicleTypeName,
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
                InfoRow(label: 'Booked on', value: Formatters.dateTime(booking.createdAt)),
                if (booking.isScheduled)
                  InfoRow(
                    label: 'Scheduled pickup',
                    value: Formatters.scheduledAt(booking.scheduledAt),
                  ),
                if (booking.completedAt != null)
                  InfoRow(
                    label: 'Completed',
                    value: Formatters.dateTime(booking.completedAt),
                  ),
                InfoRow(label: 'Name', value: booking.customerName),
                if ((booking.customerPhone ?? '').isNotEmpty)
                  InfoRow(label: 'Mobile', value: Formatters.phone(booking.customerPhone)),
                if ((booking.customerEmail ?? '').isNotEmpty)
                  InfoRow(label: 'Email', value: booking.customerEmail!),
                if ((booking.specialInstructions ?? '').isNotEmpty)
                  InfoRow(label: 'Note for driver', value: booking.specialInstructions!),
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

    // Nothing actionable on a finished booking.
    if (!detail.cancellation.canCancel) {
      if (booking.status != BookingStatus.completed) return null;

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
        child: SecondaryButton(
          label: 'Book this trip again',
          icon: Icons.replay_rounded,
          onPressed: () => context.go(AppRoutes.home),
        ),
      );
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
          if (fee > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                'Cancelling now costs '
                '${Formatters.money(fee, symbol: booking.currencySymbol)}.',
                style: theme.textTheme.labelSmall?.copyWith(color: AppColors.warning),
              ),
            ),
          SecondaryButton(
            label: 'Cancel booking',
            icon: Icons.close_rounded,
            isDestructive: true,
            onPressed: () => _openCancelSheet(booking),
          ),
        ],
      ),
    );
  }
}

class _DriverCard extends StatelessWidget {
  const _DriverCard({required this.driver, this.onCall});

  final BookingDriver driver;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SectionCard(
      title: 'Your driver',
      icon: Icons.person_pin_circle_rounded,
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            backgroundImage: (driver.photoUrl ?? '').isEmpty
                ? null
                : NetworkImage(driver.photoUrl!),
            child: (driver.photoUrl ?? '').isEmpty
                ? Text(
                    Formatters.initials(driver.name),
                    style: theme.textTheme.titleMedium,
                  )
                : null,
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(driver.name ?? 'Driver assigned', style: theme.textTheme.titleSmall),
                if ((driver.vehicleNumber ?? '').isNotEmpty ||
                    (driver.vehicleModel ?? '').isNotEmpty)
                  Text(
                    [driver.vehicleModel, driver.vehicleNumber]
                        .where((part) => (part ?? '').isNotEmpty)
                        .join('  |  '),
                    style: theme.textTheme.bodySmall,
                  ),
                if (driver.rating != null)
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, size: 14, color: AppColors.amberDark),
                      const SizedBox(width: 3),
                      Text(
                        driver.rating!.toStringAsFixed(1),
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (onCall != null)
            IconButton(
              onPressed: onCall,
              tooltip: 'Call driver',
              icon: const Icon(Icons.call_rounded),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.success.withValues(alpha: 0.14),
                foregroundColor: AppColors.success,
              ),
            ),
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
            InfoRow(label: 'When', value: Formatters.dateTime(cancellation.cancelledAt)),
          if ((cancellation.reason ?? '').isNotEmpty)
            InfoRow(label: 'Reason', value: cancellation.reason!),
          if ((cancellation.remarks ?? '').isNotEmpty)
            InfoRow(label: 'Remarks', value: cancellation.remarks!),
          InfoRow(
            label: 'Cancellation fee',
            value: cancellation.fee > 0
                ? Formatters.money(cancellation.fee, symbol: booking.currencySymbol)
                : 'None',
            valueColor: cancellation.fee > 0 ? AppColors.warning : AppColors.success,
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
