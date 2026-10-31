import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/booking_status.dart';
import '../../../core/providers/app_providers.dart';
import '../../booking_details/models/booking.dart';

class BookingListState {
  const BookingListState({
    this.items = const [],
    this.page = 1,
    this.hasMore = false,
    this.total = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  final List<BookingSummary> items;
  final int page;
  final bool hasMore;
  final int total;
  final bool isLoading;
  final bool isLoadingMore;
  final Object? error;

  bool get isEmpty => items.isEmpty && !isLoading && error == null;

  BookingListState copyWith({
    List<BookingSummary>? items,
    int? page,
    bool? hasMore,
    int? total,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error,
    bool clearError = false,
  }) =>
      BookingListState(
        items: items ?? this.items,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
        total: total ?? this.total,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        error: clearError ? null : (error ?? this.error),
      );
}

/// One tab of My Bookings, with incremental loading.
///
/// `family` over the tab so each tab keeps its own scroll position and page
/// count - switching tabs should not reset the list you were half way through.
class BookingListController extends StateNotifier<BookingListState> {
  BookingListController(this._ref, this._tab) : super(const BookingListState()) {
    refresh();
  }

  final Ref _ref;
  final BookingTab _tab;

  static const _pageSize = 10;

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final result = await _ref.read(bookingRepositoryProvider).fetchBookings(
            tab: _tab,
            page: 1,
            limit: _pageSize,
          );

      state = BookingListState(
        items: result.items,
        page: 1,
        hasMore: result.hasMore,
        total: result.total,
      );
    } on Object catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.isLoading) return;

    state = state.copyWith(isLoadingMore: true);

    try {
      final result = await _ref.read(bookingRepositoryProvider).fetchBookings(
            tab: _tab,
            page: state.page + 1,
            limit: _pageSize,
          );

      state = state.copyWith(
        items: [...state.items, ...result.items],
        page: state.page + 1,
        hasMore: result.hasMore,
        total: result.total,
        isLoadingMore: false,
      );
    } on Object {
      // Keep what we have; the footer offers another tap.
      state = state.copyWith(isLoadingMore: false);
    }
  }
}

final bookingListProvider =
    StateNotifierProvider.family<BookingListController, BookingListState, BookingTab>(
  (ref, tab) => BookingListController(ref, tab),
);
