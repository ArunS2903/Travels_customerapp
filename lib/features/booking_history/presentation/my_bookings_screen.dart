import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/booking_status.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../booking_details/models/booking.dart';
import '../../realtime/socket_service.dart';
import '../providers/booking_history_providers.dart';

/// My Bookings: Upcoming, Active, Completed, Cancelled.
///
/// Each tab is filtered server-side (`?tab=`) rather than by downloading
/// everything and filtering locally, so a customer with hundreds of trips pays
/// for one page.
class MyBookingsScreen extends ConsumerStatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  ConsumerState<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends ConsumerState<MyBookingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: BookingTab.values.length, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A status change can move a booking between tabs, so refresh them all
    // rather than guessing which pair is affected.
    ref.listen(bookingUpdateStreamProvider, (previous, next) {
      if (next.value == null) return;
      for (final tab in BookingTab.values) {
        ref.read(bookingListProvider(tab).notifier).refresh();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('My bookings'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: BookingTab.values.map((tab) => Tab(text: tab.label)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: BookingTab.values.map((tab) => _BookingTabView(tab: tab)).toList(),
      ),
    );
  }
}

class _BookingTabView extends ConsumerStatefulWidget {
  const _BookingTabView({required this.tab});

  final BookingTab tab;

  @override
  ConsumerState<_BookingTabView> createState() => _BookingTabViewState();
}

class _BookingTabViewState extends ConsumerState<_BookingTabView> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Loads the next page when the customer is within one screen of the end, so
  /// the list feels continuous rather than making them wait at the bottom.
  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      ref.read(bookingListProvider(widget.tab).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookingListProvider(widget.tab));
    final controller = ref.read(bookingListProvider(widget.tab).notifier);

    if (state.isLoading && state.items.isEmpty) {
      return const LoadingView();
    }

    if (state.error != null && state.items.isEmpty) {
      return ErrorView(error: state.error!, onRetry: controller.refresh);
    }

    if (state.isEmpty) {
      return RefreshIndicator(
        onRefresh: controller.refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: EmptyView(
              icon: Icons.receipt_long_outlined,
              title: widget.tab.emptyTitle,
              message: widget.tab.emptyMessage,
              actionLabel: widget.tab == BookingTab.upcoming ? 'Book a ride' : null,
              onAction: widget.tab == BookingTab.upcoming
                  ? () => context.go(AppRoutes.home)
                  : null,
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.all(AppSpacing.pageGutter),
        // One extra row for the footer.
        itemCount: state.items.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) {
          if (index == state.items.length) {
            return _ListFooter(
              isLoadingMore: state.isLoadingMore,
              hasMore: state.hasMore,
              total: state.total,
              onLoadMore: controller.loadMore,
            );
          }

          final booking = state.items[index];
          return _BookingCard(
            booking: booking,
            onTap: () => context.push(AppRoutes.bookingDetailsFor(booking.id)),
          );
        },
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, required this.onTap});

  final BookingSummary booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(booking.bookingCode, style: theme.textTheme.titleSmall),
                      Text(
                        Formatters.relativeDateTime(booking.scheduledAt ?? booking.createdAt),
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                StatusChip(status: booking.status, compact: true),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            RouteSummary(
              dense: true,
              pickupAddress: booking.pickupAddress,
              destinationAddress: booking.destinationAddress,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                InfoPill(
                  icon: Icons.directions_car_filled_rounded,
                  label: booking.vehicleTypeName,
                ),
                if (booking.distanceKm > 0) ...[
                  const SizedBox(width: AppSpacing.sm),
                  InfoPill(
                    icon: Icons.straighten_rounded,
                    label: Formatters.distance(booking.distanceKm),
                  ),
                ],
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Formatters.money(booking.displayFare, symbol: booking.currencySymbol),
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      // "Estimated" is only honest until the operator sets the
                      // real fare; after that it is the final figure.
                      booking.isFareFinal ? 'final' : 'estimated',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({
    required this.isLoadingMore,
    required this.hasMore,
    required this.total,
    required this.onLoadMore,
  });

  final bool isLoadingMore;
  final bool hasMore;
  final int total;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        ),
      );
    }

    if (hasMore) {
      // Scrolling triggers this automatically; the button is the fallback for
      // when the list is short enough that the scroll threshold never fires.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: TextButton.icon(
            onPressed: onLoadMore,
            icon: const Icon(Icons.expand_more_rounded, size: 18),
            label: const Text('Load more'),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Center(
        child: Text(
          total == 1 ? '1 booking' : '$total bookings',
          style: theme.textTheme.labelSmall,
        ),
      ),
    );
  }
}
