import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/place.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../authentication/models/customer.dart';
import '../../authentication/providers/auth_controller.dart';
import '../../booking_confirmation/providers/booking_draft_controller.dart';
import '../../location/data/location_service.dart';
import '../../location/presentation/place_search_screen.dart';
import '../../location/providers/location_providers.dart';
import '../../notifications/providers/notification_providers.dart';
import '../../fleet/presentation/available_vehicles_screen.dart';
import '../../vehicle_selection/providers/vehicle_providers.dart';
import 'widgets/booking_information_card.dart';
import 'widgets/home_map_preview.dart';
import 'widgets/vehicle_category_strip.dart';

/// The home screen: where the customer sets a booking up.
///
/// The order of the sections is the order the flow depends on them. The dates
/// come first, because which vehicles exist at all is a function of them - the
/// fleet is held day by day against other bookings - so asking for a vehicle
/// before a date would mean offering cars that cannot be had.
///
/// The pickup is seeded from the device location on first load, so in the
/// common case the only things to do are pick a date and tap "Where to?".
/// Everything else - saved places, recents - is a shortcut past that.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _hasSeededPickup = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _seedPickupFromLocation(),
    );
  }

  /// Fills the pickup from the device location, once, and only if the customer
  /// has not already set one - re-seeding would silently discard their choice.
  Future<void> _seedPickupFromLocation() async {
    if (_hasSeededPickup) return;
    _hasSeededPickup = true;

    if (ref.read(bookingDraftProvider).pickup != null) return;

    try {
      final place = await ref.read(currentPlaceProvider.future);
      if (!mounted) return;
      if (ref.read(bookingDraftProvider).pickup != null) return;
      ref.read(bookingDraftProvider.notifier).setPickup(place);
    } on Object {
      // Handled by the location banner below; nothing to do here.
    }
  }

  Future<void> _chooseDestination() async {
    final draft = ref.read(bookingDraftProvider);

    final result = await context.push<Place>(
      AppRoutes.placeSearch,
      extra: PlaceSearchArgs(
        target: PlaceSearchTarget.destination,
        nearLatitude: draft.pickup?.latitude,
        nearLongitude: draft.pickup?.longitude,
      ),
    );

    if (!mounted || result == null) return;
    ref.read(bookingDraftProvider.notifier).setDestination(result);
    _continueIfReady();
  }

  Future<void> _choosePickup() async {
    final draft = ref.read(bookingDraftProvider);

    final result = await context.push<Place>(
      AppRoutes.placeSearch,
      extra: PlaceSearchArgs(
        target: PlaceSearchTarget.pickup,
        nearLatitude: draft.pickup?.latitude,
        nearLongitude: draft.pickup?.longitude,
      ),
    );

    if (!mounted || result == null) return;
    ref.read(bookingDraftProvider.notifier).setPickup(result);
  }

  /// Moves to the available vehicles once the dates and both ends are set.
  ///
  /// Nothing is navigated to on a half-filled form: the screen it would open
  /// cannot answer "what is free" without a period, and it is kinder to name
  /// the missing piece here than to show an empty screen there.
  ///
  /// `quiet` is what lets the same method serve two callers. Choosing a
  /// destination calls it hoping to move on and should say nothing if it
  /// cannot; the button calls it meaning to move on and must explain itself.
  void _continueIfReady({bool quiet = true}) {
    var draft = ref.read(bookingDraftProvider);

    if (!draft.hasPeriod) {
      if (!quiet) {
        AppFeedback.showInfo(
          context,
          'Choose your booking date to see available vehicles.',
        );
      }
      return;
    }

    final startAt = draft.startAt!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final pickupDate = DateTime(startAt.year, startAt.month, startAt.day);
    if (pickupDate.isBefore(today)) {
      AppFeedback.showInfo(
        context,
        'Your booking date has passed. Choose a new booking date.',
      );
      return;
    }

    if (pickupDate == today &&
        startAt.isBefore(now.add(BookingInformationCard.pickupBuffer))) {
      final updatedStart = now.add(BookingInformationCard.pickupBuffer);
      ref.read(bookingDraftProvider.notifier).setStartDate(updatedStart);
      draft = ref.read(bookingDraftProvider);
      AppFeedback.showInfo(
        context,
        'Today’s pickup time has passed. We updated it to ${Formatters.time(updatedStart)}.',
      );
    }

    if (!draft.hasRoute) {
      if (!quiet) {
        AppFeedback.showInfo(
          context,
          'Set your pickup and drop locations to continue.',
        );
      }
      return;
    }

    if (!draft.isReadyToSearch) {
      AppFeedback.showInfo(
        context,
        'Your pickup and drop are the same place. Choose a different drop location.',
      );
      return;
    }

    context.push(AppRoutes.availableVehicles);
  }

  Future<void> _useSavedAddress(SavedAddress address) async {
    final place = address.toPlace();
    final draft = ref.read(bookingDraftProvider);

    if (draft.pickup != null && draft.pickup!.isSameLocationAs(place)) {
      AppFeedback.showInfo(
        context,
        'You are already at your ${address.label.toLowerCase()}.',
      );
      return;
    }

    ref.read(bookingDraftProvider.notifier).setDestination(place);
    _continueIfReady();
  }

  Future<void> _refresh() async {
    ref.invalidate(currentPlaceProvider);
    ref.invalidate(vehicleTypesProvider);
    ref.invalidate(unreadNotificationCountProvider);
    await ref.read(authControllerProvider.notifier).refreshProfile();

    // Re-seed the pickup only if the refresh produced a location and the
    // customer had not pinned one themselves.
    try {
      final place = await ref.read(currentPlaceProvider.future);
      if (!mounted) return;
      final draft = ref.read(bookingDraftProvider);
      if (draft.pickup == null) {
        ref.read(bookingDraftProvider.notifier).setPickup(place);
      }
    } on Object {
      // Fine - the banner explains.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customer = ref.watch(currentCustomerProvider);
    final draft = ref.watch(bookingDraftProvider);
    final locationState = ref.watch(currentPlaceProvider);
    final recents = ref.watch(prefsStoreProvider).recentDestinations;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(customer)),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pageGutter,
                    AppSpacing.lg,
                    AppSpacing.pageGutter,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Location trouble is reported once, here, rather than in
                      // each place that wants coordinates.
                      locationState.when(
                        loading: () => const SizedBox.shrink(),
                        data: (_) => const SizedBox.shrink(),
                        error: (error, _) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                          child: _LocationErrorBanner(error: error),
                        ),
                      ),

                      // --- 1. When is the vehicle wanted --------------
                      const BookingInformationCard(),
                      const SizedBox(height: AppSpacing.lg),

                      // --- 2. Where is it going -----------------------
                      HomeMapPreview(
                        pickup: draft.pickup,
                        destination: draft.destination,
                        onTap: _choosePickup,
                        // The map draws either way; this only decides whether
                        // it admits it is still looking for the customer.
                        isLocating:
                            locationState.isLoading && draft.pickup == null,
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      _TripInputs(
                        pickup: draft.pickup,
                        destination: draft.destination,
                        isLoadingPickup:
                            locationState.isLoading && draft.pickup == null,
                        onTapPickup: _choosePickup,
                        onTapDestination: _chooseDestination,
                        onSwap: draft.hasRoute
                            ? () {
                                ref
                                    .read(bookingDraftProvider.notifier)
                                    .swapPickupAndDestination();
                              }
                            : null,
                      ),

                      const SizedBox(height: AppSpacing.lg),
                      PrimaryButton(
                        label: 'Find available vehicles',
                        icon: Icons.directions_car_filled_rounded,
                        // Always live, so tapping it on a half-filled form says
                        // what is still needed rather than doing nothing. The
                        // checks live in _continueIfReady.
                        onPressed: () => _continueIfReady(quiet: false),
                      ),

                      // What is actually free for the chosen dates, so the date
                      // the customer just picked visibly did something.
                      if (draft.period != null) ...[
                        const SizedBox(height: AppSpacing.lg),
                        AvailableVehiclesPreview(period: draft.period!),
                      ],

                      const SizedBox(height: AppSpacing.xxl),

                      if (customer != null &&
                          customer.savedAddresses.isNotEmpty) ...[
                        _SavedPlacesRow(
                          addresses: customer.savedAddresses,
                          onSelect: _useSavedAddress,
                          onManage: () =>
                              context.push(AppRoutes.savedAddresses),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                      ] else if (customer != null) ...[
                        _SaveAddressPrompt(
                          onTap: () => context.push(AppRoutes.savedAddresses),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                      ],

                      if (recents.isNotEmpty) ...[
                        Text(
                          'Recent destinations',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ...recents
                            .take(3)
                            .map(
                              (place) => _RecentDestinationTile(
                                place: place,
                                onTap: () {
                                  ref
                                      .read(bookingDraftProvider.notifier)
                                      .setDestination(place);
                                  _continueIfReady();
                                },
                              ),
                            ),
                        const SizedBox(height: AppSpacing.xxl),
                      ],

                      Text('What we have', style: theme.textTheme.titleSmall),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        draft.hasPeriod
                            ? 'The kinds of vehicle in our fleet. Tap "Find available '
                                  'vehicles" to see which ones are free for your dates.'
                            : 'The kinds of vehicle in our fleet. Pick a booking date '
                                  'above to see which ones are free.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const VehicleCategoryStrip(),

                      const SizedBox(height: AppSpacing.xxl),
                      _QuickActions(
                        onBookings: () => context.push(AppRoutes.bookings),
                        onSupport: () => context.push(AppRoutes.support),
                      ),
                      SizedBox(
                        height:
                            AppSpacing.xxxl +
                            MediaQuery.paddingOf(context).bottom,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Customer? customer) {
    final theme = Theme.of(context);
    final unreadCount = ref
        .watch(unreadNotificationCountProvider)
        .maybeWhen(data: (count) => count, orElse: () => 0);
    final businessName = ref
        .watch(businessContactProvider)
        .maybeWhen(data: (contact) => contact.businessName, orElse: () => null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageGutter,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: Row(
        children: [
          const AppLogo(size: 40),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  businessName ?? 'PP Travels',
                  style: theme.textTheme.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Hello, ${Formatters.firstName(customer?.fullName)}',
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => context.push(AppRoutes.notifications),
            tooltip: 'Notifications',
            icon: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          IconButton(
            onPressed: () => context.push(AppRoutes.profile),
            tooltip: 'Profile',
            icon: CircleAvatar(
              radius: 17,
              backgroundColor: theme.colorScheme.secondaryContainer,
              child: Text(
                Formatters.initials(customer?.fullName),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pickup and destination fields, with a swap button between them.
class _TripInputs extends StatelessWidget {
  const _TripInputs({
    required this.pickup,
    required this.destination,
    required this.isLoadingPickup,
    required this.onTapPickup,
    required this.onTapDestination,
    this.onSwap,
  });

  final Place? pickup;
  final Place? destination;
  final bool isLoadingPickup;
  final VoidCallback onTapPickup;
  final VoidCallback onTapDestination;
  final VoidCallback? onSwap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              AppPickerField(
                label: 'Pickup',
                prefixIcon: Icons.my_location_rounded,
                value: isLoadingPickup
                    ? 'Finding your location'
                    : (pickup?.address ?? ''),
                isEmpty: pickup == null && !isLoadingPickup,
                placeholder: 'Set your pickup point',
                onTap: onTapPickup,
              ),
              const SizedBox(height: AppSpacing.sm),
              AppPickerField(
                label: 'Drop location',
                prefixIcon: Icons.place_outlined,
                value: destination?.address ?? '',
                isEmpty: destination == null,
                placeholder: 'Where are you taking it?',
                onTap: onTapDestination,
              ),
            ],
          ),
        ),
        if (onSwap != null)
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.sm),
            child: IconButton(
              onPressed: onSwap,
              tooltip: 'Swap pickup and drop',
              icon: const Icon(Icons.swap_vert_rounded),
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
      ],
    );
  }
}

/// Home and Office shortcuts.
class _SavedPlacesRow extends StatelessWidget {
  const _SavedPlacesRow({
    required this.addresses,
    required this.onSelect,
    required this.onManage,
  });

  final List<SavedAddress> addresses;
  final ValueChanged<SavedAddress> onSelect;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Saved places', style: theme.textTheme.titleSmall),
            ),
            TextButton(onPressed: onManage, child: const Text('Manage')),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: addresses.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) {
              final address = addresses[index];
              return InkWell(
                onTap: () => onSelect(address),
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Container(
                  width: 170,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: theme.colorScheme.outline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            address.isHome
                                ? Icons.home_rounded
                                : address.isOffice
                                ? Icons.work_rounded
                                : Icons.bookmark_rounded,
                            size: 16,
                            color: AppColors.amberDark,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              address.label,
                              style: theme.textTheme.labelLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          address.address,
                          style: theme.textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SaveAddressPrompt extends StatelessWidget {
  const _SaveAddressPrompt({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: Row(
          children: [
            const Icon(Icons.add_location_alt_outlined, size: 22),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Save your home and office',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Book your regular trips in one tap.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _RecentDestinationTile extends StatelessWidget {
  const _RecentDestinationTile({required this.place, required this.onTap});

  final Place place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Icon(
              Icons.history_rounded,
              size: 19,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.shortAddress,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (place.addressDetail.isNotEmpty)
                    Text(
                      place.addressDetail,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Icon(
              Icons.north_east_rounded,
              size: 17,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onBookings, required this.onSupport});

  final VoidCallback onBookings;
  final VoidCallback onSupport;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionTile(
            icon: Icons.receipt_long_rounded,
            label: 'My bookings',
            onTap: onBookings,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _QuickActionTile(
            icon: Icons.support_agent_rounded,
            label: 'Support',
            onTap: onSupport,
          ),
        ),
      ],
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Explains a location failure and offers the one action that can fix it.
class _LocationErrorBanner extends ConsumerWidget {
  const _LocationErrorBanner({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationError = error is LocationException
        ? error as LocationException
        : null;

    final message =
        locationError?.message ??
        'We could not read your location. Set your pickup manually.';

    String? actionLabel;
    VoidCallback? onAction;

    if (locationError?.requiresSettings ?? false) {
      actionLabel = 'Open settings';
      onAction = () => ref.read(locationServiceProvider).openSettings();
    } else if (locationError?.failure == LocationFailure.serviceDisabled) {
      actionLabel = 'Turn on location';
      onAction = () => ref.read(locationServiceProvider).openLocationSettings();
    } else if (locationError?.isRetryable ?? true) {
      actionLabel = 'Try again';
      onAction = () => ref.invalidate(currentPlaceProvider);
    }

    return AppBanner(
      icon: Icons.location_off_rounded,
      accent: AppColors.warning,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}
