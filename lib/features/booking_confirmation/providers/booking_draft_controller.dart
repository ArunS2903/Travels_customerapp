import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/booking_status.dart';
import '../../../shared/models/place.dart';
import '../../booking_details/data/booking_repository.dart';
import '../../fleet/models/fleet_vehicle.dart';

/// The booking being composed: the dates, where the car is going, which car,
/// and how it is being paid for.
///
/// Held in one place rather than passed between routes, so the flow survives a
/// rebuild, a back-navigation, or the app being resumed mid-booking - and so
/// `go_router` never has to carry heavy objects in `extra`.
///
/// The order the customer fills it in is the order the screens ask: dates
/// first, then pickup and drop, then the vehicle. That is deliberate - which
/// vehicles exist at all depends on the dates, so asking for a car before a
/// date would mean offering cars that cannot be had.
class BookingDraft {
  const BookingDraft({
    this.pickup,
    this.destination,
    this.startAt,
    this.endAt,
    this.vehicle,
    this.quote,
    this.paymentMethod = PaymentMethod.cash,
    this.specialInstructions,
    this.idempotencyKey,
    this.quotedAt,
  });

  final Place? pickup;
  final Place? destination;

  /// When the customer wants the vehicle. The one field the whole flow hangs
  /// off: availability, the day count and the total all derive from it.
  final DateTime? startAt;

  /// When it comes back. A same-day hire still bills one day, so this is never
  /// equal to [startAt] - the pickers keep it at least a day later.
  final DateTime? endAt;

  /// The chosen vehicle, as the fleet listing returned it.
  final FleetVehicle? vehicle;

  /// The server's price for [vehicle] over this period, and its word that the
  /// car is free for it. The app never computes a total of its own.
  final HireQuote? quote;

  final PaymentMethod paymentMethod;
  final String? specialInstructions;

  /// Generated once per booking attempt and reused across every retry, so a
  /// double tap or a network retry cannot create a second booking.
  final String? idempotencyKey;

  /// When [quote] was fetched, so a long-idle quote can be refreshed before the
  /// booking is submitted.
  final DateTime? quotedAt;

  /// The period, when both ends are set and make sense.
  HirePeriod? get period {
    final start = startAt;
    final end = endAt;
    if (start == null || end == null) return null;
    if (!end.isAfter(start)) return null;
    return HirePeriod(startAt: start, endAt: end);
  }

  bool get hasPeriod => period != null;

  bool get hasRoute =>
      pickup != null &&
      destination != null &&
      pickup!.hasValidCoordinates &&
      destination!.hasValidCoordinates;

  /// Whether enough is set to go and look for vehicles: dates, and both ends
  /// of the journey the car is being taken on.
  bool get isReadyToSearch =>
      hasPeriod && hasRoute && !pickup!.isSameLocationAs(destination!);

  /// Whether the confirmation screen has everything it needs. The quote must
  /// say the vehicle is still free - a stale "available" is not enough.
  bool get isReadyToConfirm =>
      isReadyToSearch && vehicle != null && quote != null && quote!.isAvailable;

  /// Billable days, from the period. Shown while the customer picks dates,
  /// before any quote exists; the charged figure is always `quote.days`.
  int get days => quote?.days ?? period?.days ?? 0;

  /// A quote older than this is refreshed before the booking is submitted, so
  /// the customer is not shown a price for a car somebody else has since taken.
  static const Duration quoteFreshness = Duration(minutes: 3);

  bool get isQuoteStale {
    final at = quotedAt;
    if (at == null) return true;
    return DateTime.now().difference(at) > quoteFreshness;
  }

  BookingDraft copyWith({
    Place? pickup,
    Place? destination,
    DateTime? startAt,
    DateTime? endAt,
    FleetVehicle? vehicle,
    HireQuote? quote,
    PaymentMethod? paymentMethod,
    String? specialInstructions,
    String? idempotencyKey,
    DateTime? quotedAt,
    bool clearDestination = false,
    bool clearVehicle = false,
    bool clearInstructions = false,
  }) =>
      BookingDraft(
        pickup: pickup ?? this.pickup,
        destination: clearDestination ? null : (destination ?? this.destination),
        startAt: startAt ?? this.startAt,
        endAt: endAt ?? this.endAt,
        vehicle: clearVehicle ? null : (vehicle ?? this.vehicle),
        quote: clearVehicle ? null : (quote ?? this.quote),
        paymentMethod: paymentMethod ?? this.paymentMethod,
        specialInstructions:
            clearInstructions ? null : (specialInstructions ?? this.specialInstructions),
        idempotencyKey: clearVehicle ? null : (idempotencyKey ?? this.idempotencyKey),
        quotedAt: clearVehicle ? null : (quotedAt ?? this.quotedAt),
      );
}

class BookingDraftController extends StateNotifier<BookingDraft> {
  BookingDraftController() : super(const BookingDraft());

  void setPickup(Place pickup) {
    // The pickup does not affect availability or price - a hire is billed by
    // the day - so the chosen vehicle survives a change of address.
    state = state.copyWith(pickup: pickup);
  }

  void setDestination(Place destination) {
    state = state.copyWith(destination: destination);
  }

  void clearDestination() => state = state.copyWith(clearDestination: true);

  void swapPickupAndDestination() {
    final pickup = state.pickup;
    final destination = state.destination;
    if (pickup == null || destination == null) return;

    state = state.copyWith(pickup: destination, destination: pickup);
  }

  /// Sets the hire period.
  ///
  /// Any change clears the vehicle and its quote. That is the important rule in
  /// this class: a car chosen for the 12th is not necessarily free on the 19th,
  /// and carrying the selection across a date change would let the customer
  /// reach the confirmation screen holding a booking the server will refuse.
  void setPeriod({required DateTime startAt, required DateTime endAt}) {
    final sameDates = state.startAt == startAt && state.endAt == endAt;
    if (sameDates) return;

    state = BookingDraft(
      pickup: state.pickup,
      destination: state.destination,
      startAt: startAt,
      endAt: endAt,
      paymentMethod: state.paymentMethod,
      specialInstructions: state.specialInstructions,
    );
  }

  /// Moves the start date, keeping the hire the same length.
  ///
  /// Shifting the end with the start is what somebody changing "when do I want
  /// the car" means; leaving the end put would silently lengthen or shorten
  /// their hire, and in the shortening case produce an invalid period.
  void setStartDate(DateTime startAt) {
    final previousStart = state.startAt;
    final previousEnd = state.endAt;

    final length = previousStart != null && previousEnd != null
        ? previousEnd.difference(previousStart)
        : const Duration(days: 1);

    setPeriod(
      startAt: startAt,
      endAt: startAt.add(length < const Duration(days: 1) ? const Duration(days: 1) : length),
    );
  }

  void setEndDate(DateTime endAt) {
    final start = state.startAt;
    if (start == null) return;
    setPeriod(startAt: start, endAt: endAt);
  }

  /// Chooses a vehicle and starts a booking attempt.
  ///
  /// The idempotency key is minted here, at the point the customer commits to a
  /// specific car and price - so every retry of *this* booking shares a key,
  /// while going back and choosing differently starts a new attempt.
  void selectVehicle(FleetVehicle vehicle, {HireQuote? quote}) {
    state = state.copyWith(
      vehicle: vehicle,
      quote: quote,
      quotedAt: quote == null ? null : DateTime.now(),
      idempotencyKey: BookingRepository.newIdempotencyKey(),
    );
  }

  /// Refreshes the quote in place, keeping the same idempotency key because it
  /// is still the same booking attempt.
  void refreshQuote(HireQuote quote) {
    state = state.copyWith(
      quote: quote,
      // The quote carries the vehicle as the server currently has it, which is
      // more current than whatever the list returned.
      vehicle: quote.vehicle,
      quotedAt: DateTime.now(),
    );
  }

  void clearVehicle() => state = state.copyWith(clearVehicle: true);

  void setPaymentMethod(PaymentMethod method) => state = state.copyWith(paymentMethod: method);

  void setSpecialInstructions(String? instructions) {
    final trimmed = instructions?.trim();
    state = trimmed == null || trimmed.isEmpty
        ? state.copyWith(clearInstructions: true)
        : state.copyWith(specialInstructions: trimmed);
  }

  /// Called after a booking is successfully created, so the next one starts
  /// clean while the pickup (usually the customer's current location) is kept.
  void reset({bool keepPickup = true}) {
    state = BookingDraft(pickup: keepPickup ? state.pickup : null);
  }
}

final bookingDraftProvider = StateNotifierProvider<BookingDraftController, BookingDraft>(
  (ref) => BookingDraftController(),
);
