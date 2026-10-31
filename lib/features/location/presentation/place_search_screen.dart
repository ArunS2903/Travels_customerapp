import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/models/place.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../../authentication/models/customer.dart';
import '../../authentication/providers/auth_controller.dart';
import '../data/places_service.dart';
import '../providers/location_providers.dart';
import 'map_picker_screen.dart';

/// Whether the search is choosing a pickup or a destination.
enum PlaceSearchTarget { pickup, destination }

class PlaceSearchArgs {
  const PlaceSearchArgs({
    this.target = PlaceSearchTarget.destination,
    this.nearLatitude,
    this.nearLongitude,
  });

  final PlaceSearchTarget target;

  /// Biases results toward the customer, so "airport" means the nearest one.
  final double? nearLatitude;
  final double? nearLongitude;

  String get title =>
      target == PlaceSearchTarget.pickup ? 'Set pickup' : 'Where to?';
}

/// Address search, with saved addresses and recent destinations as shortcuts.
///
/// Returns the chosen [Place] through `context.pop`, so the caller decides what
/// to do with it. That keeps this screen reusable for both ends of the trip.
class PlaceSearchScreen extends ConsumerStatefulWidget {
  const PlaceSearchScreen({super.key, required this.args});

  final PlaceSearchArgs args;

  @override
  ConsumerState<PlaceSearchScreen> createState() => _PlaceSearchScreenState();
}

class _PlaceSearchScreenState extends ConsumerState<PlaceSearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    ref.read(placeSearchProvider.notifier).search(
          query,
          nearLatitude: widget.args.nearLatitude,
          nearLongitude: widget.args.nearLongitude,
        );
  }

  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    final place = await ref.read(placeSearchProvider.notifier).resolve(suggestion);

    if (!mounted) return;

    if (place == null) {
      AppFeedback.showError(
        context,
        // A resolve failure is usually a Places key without the Details API.
        'We could not pin down that address. Try another result, or drop a pin on the map.',
      );
      return;
    }

    _returnPlace(place);
  }

  void _returnPlace(Place place) {
    // Recents are only meaningful for destinations.
    if (widget.args.target == PlaceSearchTarget.destination) {
      ref.read(prefsStoreProvider).addRecentDestination(place);
    }
    context.pop(place);
  }

  Future<void> _openMapPicker() async {
    final result = await context.push<Place>(
      AppRoutes.mapPicker,
      extra: MapPickerArgs(
        target: widget.args.target,
        initialLatitude: widget.args.nearLatitude,
        initialLongitude: widget.args.nearLongitude,
      ),
    );

    if (!mounted || result == null) return;
    _returnPlace(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searchState = ref.watch(placeSearchProvider);
    final customer = ref.watch(currentCustomerProvider);
    final recents = ref.watch(prefsStoreProvider).recentDestinations;
    final usingFallback = ref.watch(placesServiceProvider).isUsingFallback;

    return Scaffold(
      appBar: AppBar(title: Text(widget.args.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageGutter,
              AppSpacing.sm,
              AppSpacing.pageGutter,
              AppSpacing.md,
            ),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              textInputAction: TextInputAction.search,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                hintText: 'Search for a place or address',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: searchState.isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _controller.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            tooltip: 'Clear',
                            onPressed: () {
                              _controller.clear();
                              ref.read(placeSearchProvider.notifier).clear();
                              setState(() {});
                            },
                          ),
              ),
            ),
          ),

          // Honest about the degraded search path rather than letting the
          // customer conclude the search is just bad.
          if (usingFallback)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageGutter),
              child: AppBanner(
                icon: Icons.travel_explore_rounded,
                message:
                    'Place suggestions are limited in this build (no Google Places key). '
                    'Enter a fuller address, or drop a pin on the map.',
              ),
            ),

          ListTile(
            onTap: _openMapPicker,
            leading: Container(
              height: 38,
              width: 38,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                Icons.map_outlined,
                size: 19,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            title: const Text('Choose on the map'),
            subtitle: const Text('Drop a pin exactly where you want'),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
          const Divider(),

          Expanded(
            child: searchState.hasQuery
                ? _buildResults(searchState)
                : _buildShortcuts(customer?.savedAddresses ?? const [], recents),
          ),

          if (searchState.isResolving)
            const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }

  Widget _buildResults(PlaceSearchState state) {
    if (state.error != null && state.suggestions.isEmpty) {
      return ErrorView(
        error: state.error!,
        onRetry: () => _onQueryChanged(_controller.text),
      );
    }

    if (state.isEmpty) {
      return EmptyView(
        icon: Icons.search_off_rounded,
        title: 'No matches',
        message: 'Try a different spelling, add the city name, or drop a pin on the map.',
        actionLabel: 'Open map',
        onAction: _openMapPicker,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      itemCount: state.suggestions.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final suggestion = state.suggestions[index];
        return ListTile(
          onTap: state.isResolving ? null : () => _selectSuggestion(suggestion),
          leading: const Icon(Icons.place_outlined, size: 20),
          title: Text(suggestion.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: suggestion.subtitle.isEmpty
              ? null
              : Text(suggestion.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        );
      },
    );
  }

  Widget _buildShortcuts(List<SavedAddress> savedAddresses, List<Place> recents) {
    final theme = Theme.of(context);

    if (savedAddresses.isEmpty && recents.isEmpty) {
      return EmptyView(
        icon: Icons.history_rounded,
        title: 'Start typing',
        message: 'Search for an address, or drop a pin on the map. '
            'Places you use will show up here next time.',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      children: [
        if (savedAddresses.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageGutter,
              AppSpacing.lg,
              AppSpacing.pageGutter,
              AppSpacing.sm,
            ),
            child: Text('Saved places', style: theme.textTheme.labelMedium),
          ),
          ...savedAddresses.map((address) {
            final place = address.toPlace();
            return ListTile(
              onTap: () => _returnPlace(place),
              leading: Icon(
                address.isHome
                    ? Icons.home_outlined
                    : address.isOffice
                        ? Icons.work_outline_rounded
                        : Icons.bookmark_outline_rounded,
                size: 20,
              ),
              title: Text(address.label),
              subtitle: Text(
                address.address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }),
        ],
        if (recents.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageGutter,
              AppSpacing.xl,
              AppSpacing.pageGutter,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(child: Text('Recent destinations', style: theme.textTheme.labelMedium)),
                TextButton(
                  onPressed: () async {
                    await ref.read(prefsStoreProvider).clearRecentDestinations();
                    if (mounted) setState(() {});
                  },
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          ...recents.map(
            (place) => ListTile(
              onTap: () => _returnPlace(place),
              leading: const Icon(Icons.history_rounded, size: 20),
              title: Text(place.shortAddress, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: place.addressDetail.isEmpty
                  ? null
                  : Text(
                      place.addressDetail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ),
        ],
      ],
    );
  }
}
