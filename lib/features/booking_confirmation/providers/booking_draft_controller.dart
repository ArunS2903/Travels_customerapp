import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/booking_status.dart';
import '../../../shared/models/place.dart';
import '../../booking_details/data/booking_repository.dart';
import '../../vehicle_selection/models/vehicle_estimate.dart';

/// The booking being composed, from picking a destination to confirming.
///
/// Held in one place rather than passed between routes, so the flow survives a
/// rebuild, a back-navigation, or the app being resumed mid-booking - and so
/// `go_router` never has to carry heavy objects in `extra`.
class BookingDraft {
  const BookingDraft({
    this.pickup,
    this.destination,
    this.route,
    this.selectedEstimate,
    this.paymentMethod = PaymentMethod.cash,
    this.specialInstructions,
    this.scheduledAt,
    this.idempotencyKey,
    this.quotedAt,
  });

  final Place? pickup;
  final Place? destination;
  final RouteInfo? route;
  final VehicleEstimate? selectedEstimate;
  final PaymentMethod paymentMethod;
  final String? specialInstructions;
  final DateTime? scheduledAt;

  /// Generated once per booking attempt and reused across every retry, so a
  /// double tap or a network retry cannot create a second booking.
  final String? idempotencyKey;

  /// When the selected fare was quoted. Used to warn that a long-idle quote
  /// may have moved.
  final DateTime? quotedAt;

  bool get hasRoute =>
      pickup != null &&
      destination != null &&
      pickup!.hasValidCoordinates &&
      destination!.hasValidCoordinates;

  bool get isReadyToQuote => hasRoute && !pickup!.isSameLocationAs(destination!);

  bool get isReadyToConfirm =>
      isReadyToQuote && selectedEstimate != null && selectedEstimate!.fare != null;

  /// A quote older than this is refreshed before the booking is submitted, so
  /// the customer is not shown a price that a surge change has invalidated.
  static const Duration quoteFreshness = Duration(minutes: 3);

  bool get isQuoteStale {
    final at = quotedAt;
    if (at == null) return true;
    return DateTime.now().difference(at) > quoteFreshness;
  }

  BookingDraft copyWith({
    Place? pickup,
    Place? destination,
    RouteInfo? route,
    VehicleEstimate? selectedEstimate,
    PaymentMethod? paymentMethod,
    String? specialInstructions,
    DateTime? scheduledAt,
    String? idempotencyKey,
    DateTime? quotedAt,
    bool clearDestination = false,
    bool clearSelection = false,
    bool clearSchedule = false,
    bool clearInstructions = false,
  }) =>
      BookingDraft(
        pickup: pickup ?? this.pickup,
        destination: clearDestination ? null : (destination ?? this.destination),
        route: clearDestination ? null : (route ?? this.route),
        selectedEstimate:
            clearSelection || clearDestination ? null : (selectedEstimate ?? this.selectedEstimate),
        paymentMethod: paymentMethod ?? this.paymentMethod,
        specialInstructions:
            clearInstructions ? null : (specialInstructions ?? this.specialInstructions),
        scheduledAt: clearSchedule ? null : (scheduledAt ?? this.scheduledAt),
        idempotencyKey: idempotencyKey ?? this.idempotencyKey,
        quotedAt: clearSelection || clearDestination ? null : (quotedAt ?? this.quotedAt),
      );
}

class BookingDraftController extends StateNotifier<BookingDraft> {
  BookingDraftController() : super(const BookingDraft());

  void setPickup(Place pickup) {
    // Changing the pickup invalidates the route and every quote built on it.
    state = state.copyWith(pickup: pickup, clearSelection: true, route: null);
  }

  void setDestination(Place destination) {
    state = state.copyWith(destination: destination, clearSelection: true, route: null);
  }

  void clearDestination() => state = state.copyWith(clearDestination: true);

  void swapPickupAndDestination() {
    final pickup = state.pickup;
    final destination = state.destination;
    if (pickup == null || destination == null) return;

    state = BookingDraft(
      pickup: destination,
      destination: pickup,
      paymentMethod: state.paymentMethod,
      specialInstructions: state.specialInstructions,
      scheduledAt: state.scheduledAt,
    );
  }

  void setRoute(RouteInfo route) => state = state.copyWith(route: route);

  /// Selects a vehicle and starts a booking attempt.
  ///
  /// The idempotency key is minted here, at the point the customer commits to a
  /// specific vehicle and price - so every retry of *this* booking shares a key,
  /// while going back and choosing differently starts a new attempt.
  void selectVehicle(VehicleEstimate estimate, {DateTime? quotedAt}) {
    state = state.copyWith(
      selectedEstimate: estimate,
      quotedAt: quotedAt ?? DateTime.now(),
      idempotencyKey: BookingRepository.newIdempotencyKey(),
    );
  }

  void setPaymentMethod(PaymentMethod method) => state = state.copyWith(paymentMethod: method);

  void setSpecialInstructions(String? instructions) {
    final trimmed = instructions?.trim();
    state = trimmed == null || trimmed.isEmpty
        ? state.copyWith(clearInstructions: true)
        : state.copyWith(specialInstructions: trimmed);
  }

  void setScheduledAt(DateTime? when) =>
      state = when == null ? state.copyWith(clearSchedule: true) : state.copyWith(scheduledAt: when);

  /// Refreshes the selected estimate in place after a re-quote, keeping the
  /// same idempotency key because it is still the same booking attempt.
  void refreshSelection(VehicleEstimate estimate) {
    state = state.copyWith(selectedEstimate: estimate, quotedAt: DateTime.now());
  }

  /// Called after a booking is successfully created, so the next booking starts
  /// clean while the pickup (usually the customer's current location) is kept.
  void reset({bool keepPickup = true}) {
    state = BookingDraft(pickup: keepPickup ? state.pickup : null);
  }
}

final bookingDraftProvider = StateNotifierProvider<BookingDraftController, BookingDraft>(
  (ref) => BookingDraftController(),
);
