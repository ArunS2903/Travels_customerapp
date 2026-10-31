import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/place.dart';
import '../data/location_service.dart';
import '../data/places_service.dart';

final locationServiceProvider = Provider<LocationService>((ref) => const LocationService());

final placesServiceProvider = Provider<PlacesService>((ref) => PlacesService());

/// The device's current location as a [Place].
///
/// Deliberately *not* auto-refreshing: the home screen reads it once, and a
/// moving customer should not have their pickup pin wander while they type a
/// destination. Pulling to refresh invalidates it explicitly.
final currentPlaceProvider = FutureProvider<Place>((ref) {
  return ref.watch(locationServiceProvider).getCurrentPlace();
});

/// State of an address search.
class PlaceSearchState {
  const PlaceSearchState({
    this.query = '',
    this.suggestions = const [],
    this.isSearching = false,
    this.isResolving = false,
    this.error,
  });

  final String query;
  final List<PlaceSuggestion> suggestions;
  final bool isSearching;

  /// True while a tapped suggestion's coordinates are being fetched.
  final bool isResolving;

  final Object? error;

  bool get hasQuery => query.trim().length >= 3;
  bool get isEmpty => suggestions.isEmpty && hasQuery && !isSearching;

  PlaceSearchState copyWith({
    String? query,
    List<PlaceSuggestion>? suggestions,
    bool? isSearching,
    bool? isResolving,
    Object? error,
    bool clearError = false,
  }) =>
      PlaceSearchState(
        query: query ?? this.query,
        suggestions: suggestions ?? this.suggestions,
        isSearching: isSearching ?? this.isSearching,
        isResolving: isResolving ?? this.isResolving,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Debounced address search.
///
/// Two things matter here. The debounce stops a request per keystroke, which
/// both costs money on the Places API and produces flickering results. The
/// [CancelToken] discards a slower earlier request, so results can never
/// arrive out of order and show suggestions for a query the customer has
/// already finished editing.
class PlaceSearchController extends StateNotifier<PlaceSearchState> {
  PlaceSearchController(this._ref) : super(const PlaceSearchState()) {
    _ref.read(placesServiceProvider).newSession();
  }

  final Ref _ref;

  Timer? _debounce;
  CancelToken? _inFlight;

  static const _debounceDuration = Duration(milliseconds: 350);

  void search(String query, {double? nearLatitude, double? nearLongitude}) {
    state = state.copyWith(query: query, clearError: true);

    _debounce?.cancel();
    _inFlight?.cancel('superseded');

    if (query.trim().length < 3) {
      state = state.copyWith(suggestions: const [], isSearching: false);
      return;
    }

    state = state.copyWith(isSearching: true);

    _debounce = Timer(_debounceDuration, () async {
      final cancelToken = CancelToken();
      _inFlight = cancelToken;

      try {
        final suggestions = await _ref.read(placesServiceProvider).autocomplete(
              query,
              latitude: nearLatitude,
              longitude: nearLongitude,
              cancelToken: cancelToken,
            );

        // A newer search started while we were waiting; drop this result.
        if (cancelToken.isCancelled || !mounted) return;
        if (state.query != query) return;

        state = state.copyWith(suggestions: suggestions, isSearching: false);
      } on Object catch (error) {
        if (!mounted || cancelToken.isCancelled) return;
        state = state.copyWith(isSearching: false, error: error);
      }
    });
  }

  /// Resolves a tapped suggestion to coordinates.
  Future<Place?> resolve(PlaceSuggestion suggestion) async {
    state = state.copyWith(isResolving: true, clearError: true);

    try {
      final place = await _ref.read(placesServiceProvider).resolve(suggestion);
      if (!mounted) return place;

      state = state.copyWith(isResolving: false);
      return place;
    } on Object catch (error) {
      if (mounted) state = state.copyWith(isResolving: false, error: error);
      return null;
    }
  }

  void clear() {
    _debounce?.cancel();
    _inFlight?.cancel('cleared');
    state = const PlaceSearchState();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _inFlight?.cancel('disposed');
    super.dispose();
  }
}

final placeSearchProvider =
    StateNotifierProvider.autoDispose<PlaceSearchController, PlaceSearchState>(
  (ref) => PlaceSearchController(ref),
);
