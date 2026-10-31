import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../realtime/socket_service.dart';
import '../models/booking.dart';

/// One booking's detail, keyed by id.
///
/// `family` rather than a single provider so two bookings can be open (list
/// behind, detail in front) without fighting over one slot, and so invalidating
/// one does not refetch the other.
final bookingDetailProvider = FutureProvider.family<BookingDetail, String>((ref, bookingId) async {
  final socket = ref.watch(socketServiceProvider);

  // Join this booking's room while the screen is alive, and leave on dispose,
  // so the server is not fanning out updates nobody is watching.
  socket.subscribeToBooking(bookingId);
  ref.onDispose(() => socket.unsubscribeFromBooking(bookingId));

  return ref.watch(bookingRepositoryProvider).fetchBooking(bookingId);
});

/// The current cancellation fee for a booking, fetched when the cancel sheet
/// opens so the figure shown is live rather than whatever the detail call said.
final cancellationPolicyProvider =
    FutureProvider.family<CancellationInfo, String>((ref, bookingId) {
  return ref.watch(bookingRepositoryProvider).fetchCancellationPolicy(bookingId);
});

/// Cancels a booking and reports progress to the sheet.
class CancellationState {
  const CancellationState({this.isSubmitting = false, this.error, this.cancelled});

  final bool isSubmitting;
  final Object? error;

  /// Set once the booking has been cancelled, so the sheet can close and the
  /// detail screen can show the new status without another round trip.
  final Booking? cancelled;

  CancellationState copyWith({
    bool? isSubmitting,
    Object? error,
    Booking? cancelled,
    bool clearError = false,
  }) =>
      CancellationState(
        isSubmitting: isSubmitting ?? this.isSubmitting,
        error: clearError ? null : (error ?? this.error),
        cancelled: cancelled ?? this.cancelled,
      );
}

class CancellationController extends StateNotifier<CancellationState> {
  CancellationController(this._ref) : super(const CancellationState());

  final Ref _ref;

  Future<Booking?> cancel({
    required String bookingId,
    required String reason,
    String? remarks,
  }) async {
    if (state.isSubmitting) return null;
    state = state.copyWith(isSubmitting: true, clearError: true);

    try {
      final booking = await _ref.read(bookingRepositoryProvider).cancelBooking(
            bookingId: bookingId,
            reason: reason,
            remarks: remarks,
          );

      state = CancellationState(cancelled: booking);

      // The detail screen and every list that might show this booking are now
      // out of date.
      _ref.invalidate(bookingDetailProvider(bookingId));
      return booking;
    } on Object catch (error) {
      state = state.copyWith(isSubmitting: false, error: error);
      return null;
    }
  }

  void reset() => state = const CancellationState();
}

final cancellationControllerProvider =
    StateNotifierProvider<CancellationController, CancellationState>(
  (ref) => CancellationController(ref),
);
