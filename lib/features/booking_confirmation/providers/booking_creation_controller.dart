import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/app_providers.dart';
import '../../booking_details/data/booking_repository.dart';
import '../../booking_details/models/booking.dart';
import 'booking_draft_controller.dart';

class BookingCreationState {
  const BookingCreationState({
    this.isSubmitting = false,
    this.booking,
    this.error,
    this.wasDeduplicated = false,
  });

  final bool isSubmitting;
  final Booking? booking;
  final Object? error;

  /// True when the submission matched an idempotency key we had already used,
  /// i.e. the booking already existed. The UI then skips the celebration.
  final bool wasDeduplicated;

  bool get isDone => booking != null;

  BookingCreationState copyWith({
    bool? isSubmitting,
    Booking? booking,
    Object? error,
    bool? wasDeduplicated,
    bool clearError = false,
  }) =>
      BookingCreationState(
        isSubmitting: isSubmitting ?? this.isSubmitting,
        booking: booking ?? this.booking,
        error: clearError ? null : (error ?? this.error),
        wasDeduplicated: wasDeduplicated ?? this.wasDeduplicated,
      );
}

/// Submits the booking.
///
/// Duplicate prevention has three layers, because a repeat tap creating a
/// second taxi is the worst bug this screen could have:
///
///   1. the Confirm button is disabled while [BookingCreationState.isSubmitting]
///   2. this controller refuses to start a second submission, and refuses
///      outright once one has succeeded
///   3. every attempt carries the draft's `idempotencyKey`, so even a retry
///      from the Dio layer or a resubmission after a timeout returns the
///      original booking rather than creating another
///
/// Layer 3 is the only one that is actually sufficient - the first two are
/// local and cannot survive a process restart - which is why the key is minted
/// when the vehicle is chosen and kept in the draft.
class BookingCreationController extends StateNotifier<BookingCreationState> {
  BookingCreationController(this._ref) : super(const BookingCreationState());

  final Ref _ref;

  Future<Booking?> submit() async {
    if (state.isSubmitting) return null;

    // Already created. Hand back what we have instead of booking again.
    if (state.booking != null) return state.booking;

    final draft = _ref.read(bookingDraftProvider);

    final period = draft.period;
    final vehicle = draft.vehicle;

    if (!draft.isReadyToConfirm || period == null || vehicle == null) {
      state = state.copyWith(
        error: const ApiException(
          message: 'Something is missing from this booking. Please check and try again.',
          code: 'DRAFT_INCOMPLETE',
        ),
      );
      return null;
    }

    // Reuse the key from the draft, or mint one if the draft somehow lacks it.
    final idempotencyKey = draft.idempotencyKey ?? BookingRepository.newIdempotencyKey();

    state = state.copyWith(isSubmitting: true, clearError: true);

    try {
      final result = await _ref.read(bookingRepositoryProvider).createBooking(
            vehicleId: vehicle.id,
            startAt: period.startAt,
            endAt: period.endAt,
            pickup: draft.pickup!,
            destination: draft.destination!,
            paymentMethod: draft.paymentMethod,
            idempotencyKey: idempotencyKey,
            specialInstructions: draft.specialInstructions,
          );

      state = BookingCreationState(
        booking: result.booking,
        wasDeduplicated: result.wasDeduplicated,
      );

      // Remember the payment choice for next time.
      await _ref
          .read(prefsStoreProvider)
          .setLastPaymentMethod(draft.paymentMethod.apiValue);

      return result.booking;
    } on Object catch (error) {
      state = state.copyWith(isSubmitting: false, error: error);
      return null;
    }
  }

  /// Clears state so the screen can be used for a new booking.
  void reset() => state = const BookingCreationState();
}

final bookingCreationProvider =
    StateNotifierProvider<BookingCreationController, BookingCreationState>(
  (ref) => BookingCreationController(ref),
);
