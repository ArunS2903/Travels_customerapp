import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../shared/models/place.dart';
import '../../booking_confirmation/providers/booking_draft_controller.dart';
import '../models/vehicle_estimate.dart';

/// The catalogue, with no route applied. Used by the home screen's category
/// strip, which has no destination yet.
final vehicleTypesProvider = FutureProvider<List<VehicleType>>(
  (ref) => ref.watch(vehicleRepositoryProvider).fetchVehicleTypes(),
);

class FareQuoteState {
  const FareQuoteState({
    this.result,
    this.isLoading = false,
    this.error,
    this.selectedVehicleTypeId,
  });

  final FareEstimateResult? result;
  final bool isLoading;
  final Object? error;
  final String? selectedVehicleTypeId;

  bool get hasResult => result != null;

  VehicleEstimate? get selected {
    final estimates = result?.estimates;
    if (estimates == null || selectedVehicleTypeId == null) return null;
    for (final estimate in estimates) {
      if (estimate.id == selectedVehicleTypeId) return estimate;
    }
    return null;
  }

  FareQuoteState copyWith({
    FareEstimateResult? result,
    bool? isLoading,
    Object? error,
    String? selectedVehicleTypeId,
    bool clearError = false,
  }) =>
      FareQuoteState(
        result: result ?? this.result,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
        selectedVehicleTypeId: selectedVehicleTypeId ?? this.selectedVehicleTypeId,
      );
}

/// Prices every category for the draft's route.
///
/// Each quote runs under a [CancelToken]: the customer can go back, change the
/// destination and return while a request is still in flight, and a late reply
/// for the old route must not overwrite the new one. We also stamp each request
/// with a generation counter so a cancelled-but-completed response is dropped.
class FareQuoteController extends StateNotifier<FareQuoteState> {
  FareQuoteController(this._ref) : super(const FareQuoteState());

  final Ref _ref;

  CancelToken? _inFlight;
  int _generation = 0;

  Future<void> quote({required Place pickup, required Place destination}) async {
    _inFlight?.cancel('superseded');

    final generation = ++_generation;
    final cancelToken = CancelToken();
    _inFlight = cancelToken;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final result = await _ref.read(vehicleRepositoryProvider).estimateAll(
            pickup: pickup,
            destination: destination,
            cancelToken: cancelToken,
          );

      if (!mounted || generation != _generation) return;

      // Pre-select the cheapest available option: it is what most customers
      // pick, and it means the Confirm button is live immediately.
      final cheapest = result.cheapest;

      state = FareQuoteState(
        result: result,
        selectedVehicleTypeId: cheapest?.id,
      );

      // Share the measured route with the draft so the confirmation screen and
      // the map do not have to ask for it again.
      _ref.read(bookingDraftProvider.notifier).setRoute(result.route);

      if (cheapest != null) {
        _ref.read(bookingDraftProvider.notifier).selectVehicle(
              cheapest,
              quotedAt: result.quotedAt,
            );
      }
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      if (error is DioException && CancelToken.isCancel(error)) return;
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  void select(VehicleEstimate estimate) {
    if (!estimate.isAvailable || estimate.fare == null) return;

    state = state.copyWith(selectedVehicleTypeId: estimate.id);
    _ref.read(bookingDraftProvider.notifier).selectVehicle(
          estimate,
          quotedAt: state.result?.quotedAt,
        );
  }

  @override
  void dispose() {
    _inFlight?.cancel('disposed');
    super.dispose();
  }
}

final fareQuoteProvider =
    StateNotifierProvider.autoDispose<FareQuoteController, FareQuoteState>(
  (ref) => FareQuoteController(ref),
);
