import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../booking_confirmation/providers/booking_draft_controller.dart';
import '../../home/presentation/widgets/vehicle_category_strip.dart';
import '../models/vehicle_estimate.dart';
import '../providers/vehicle_providers.dart';

/// Choose a vehicle for the route in the draft.
///
/// All prices here come from `POST /fares/estimate` - the server measures the
/// route and applies the admin's fare rules. Nothing on this screen is computed
/// locally, which is why the fares shown can be trusted to match what the
/// booking will be created with.
class VehicleSelectionScreen extends ConsumerStatefulWidget {
  const VehicleSelectionScreen({super.key});

  @override
  ConsumerState<VehicleSelectionScreen> createState() => _VehicleSelectionScreenState();
}

class _VehicleSelectionScreenState extends ConsumerState<VehicleSelectionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestQuote());
  }

  void _requestQuote() {
    final draft = ref.read(bookingDraftProvider);
    if (!draft.isReadyToQuote) return;

    ref.read(fareQuoteProvider.notifier).quote(
          pickup: draft.pickup!,
          destination: draft.destination!,
        );
  }

  void _continue() {
    final draft = ref.read(bookingDraftProvider);

    if (!draft.isReadyToConfirm) {
      AppFeedback.showInfo(context, 'Choose a vehicle to continue.');
      return;
    }

    context.push(AppRoutes.bookingConfirmation);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = ref.watch(bookingDraftProvider);
    final quote = ref.watch(fareQuoteProvider);

    // Arriving here without a route means a deep link or a restart.
    if (!draft.isReadyToQuote) {
      return Scaffold(
        appBar: AppBar(title: const Text('Choose a vehicle')),
        body: EmptyView(
          icon: Icons.wrong_location_outlined,
          title: 'No trip set up',
          message: 'Set a pickup and destination first, then come back to pick a vehicle.',
          actionLabel: 'Go to home',
          onAction: () => context.go(AppRoutes.home),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Choose a vehicle')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageGutter,
              0,
              AppSpacing.pageGutter,
              AppSpacing.md,
            ),
            child: SectionCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  RouteSummary(
                    dense: true,
                    pickupAddress: draft.pickup!.address,
                    destinationAddress: draft.destination!.address,
                    onTapPickup: () => context.pop(),
                    onTapDestination: () => context.pop(),
                  ),
                  if (quote.result != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    const Divider(height: 1),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        InfoPill(
                          icon: Icons.straighten_rounded,
                          label: Formatters.distance(quote.result!.route.distanceKm),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        InfoPill(
                          icon: Icons.schedule_rounded,
                          label: Formatters.duration(quote.result!.route.durationMinutes),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _requestQuote,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Refresh'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Said plainly rather than buried: when the server has no Maps key,
          // the distance is a straight-line estimate and so is the fare.
          if (quote.result?.route.isApproximate ?? false)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageGutter,
                0,
                AppSpacing.pageGutter,
                AppSpacing.md,
              ),
              child: AppBanner(
                icon: Icons.straighten_rounded,
                accent: AppColors.warning,
                message:
                    'Distances are approximate in this environment, so fares are rough. '
                    'The server needs a Google Maps key for real road distances.',
              ),
            ),

          Expanded(child: _buildList(quote)),

          if (quote.hasResult) _buildFooter(theme, draft, quote),
        ],
      ),
    );
  }

  Widget _buildList(FareQuoteState quote) {
    if (quote.isLoading && !quote.hasResult) {
      return const LoadingView(message: 'Working out your fare');
    }

    if (quote.error != null && !quote.hasResult) {
      return ErrorView(error: quote.error!, onRetry: _requestQuote);
    }

    final estimates = quote.result?.estimates ?? const <VehicleEstimate>[];

    if (estimates.isEmpty) {
      return EmptyView(
        icon: Icons.no_transfer_rounded,
        title: 'No vehicles available',
        message: 'There are no vehicle categories for this trip right now. Please try again later.',
        actionLabel: 'Try again',
        onAction: _requestQuote,
      );
    }

    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageGutter,
            0,
            AppSpacing.pageGutter,
            AppSpacing.xxl,
          ),
          itemCount: estimates.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) {
            final estimate = estimates[index];
            final isCheapest = quote.result?.cheapest?.id == estimate.id;

            return _VehicleCard(
              estimate: estimate,
              isSelected: quote.selectedVehicleTypeId == estimate.id,
              isCheapest: isCheapest && estimates.length > 1,
              onTap: () => ref.read(fareQuoteProvider.notifier).select(estimate),
            );
          },
        ),
        // A re-quote keeps the old prices visible under a thin progress bar,
        // rather than blanking the list the customer was reading.
        if (quote.isLoading) const LinearProgressIndicator(minHeight: 2),
      ],
    );
  }

  Widget _buildFooter(ThemeData theme, BookingDraft draft, FareQuoteState quote) {
    final selected = quote.selected;
    final fare = selected?.fare;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.pageGutter,
        AppSpacing.lg,
        AppSpacing.pageGutter,
        AppSpacing.lg + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (quote.result != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      quote.result!.disclaimer,
                      style: theme.textTheme.labelSmall,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),
          PrimaryButton(
            label: selected == null ? 'Choose a vehicle' : 'Continue with ${selected.vehicleType.name}',
            onPressed: selected == null ? null : _continue,
            trailing: fare == null
                ? null
                : Text(
                    Formatters.money(fare.total, symbol: fare.currencySymbol),
                    style: theme.textTheme.titleMedium?.copyWith(color: AppColors.ink),
                  ),
          ),
        ],
      ),
    );
  }
}

/// One category row: icon, name, capacity, ETA and the fare for this route.
class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.estimate,
    required this.isSelected,
    required this.isCheapest,
    required this.onTap,
  });

  final VehicleEstimate estimate;
  final bool isSelected;
  final bool isCheapest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vehicle = estimate.vehicleType;
    final fare = estimate.fare;
    final isAvailable = estimate.isAvailable && fare != null;

    return Opacity(
      // Unavailable categories stay listed but visibly inert, so the customer
      // can see the option exists and why it is not offered.
      opacity: isAvailable ? 1 : 0.55,
      child: InkWell(
        onTap: isAvailable ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.amber.withValues(alpha: theme.brightness == Brightness.dark ? 0.14 : 0.1)
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isSelected ? AppColors.amberDark : theme.colorScheme.outline,
              width: isSelected ? 1.8 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                height: 52,
                width: 52,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  vehicleIconFor(vehicle),
                  size: 26,
                  color: isSelected ? AppColors.amberDark : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            vehicle.name,
                            style: theme.textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCheapest) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Text(
                              'Cheapest',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.success,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 3),
                        Text('${vehicle.passengerCapacity}', style: theme.textTheme.labelSmall),
                        if (vehicle.luggageCapacity > 0) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Icon(
                            Icons.luggage_outlined,
                            size: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 3),
                          Text('${vehicle.luggageCapacity}', style: theme.textTheme.labelSmall),
                        ],
                        if (isAvailable && estimate.etaMinutes != null) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Text('|', style: theme.textTheme.labelSmall),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            Formatters.eta(estimate.etaMinutes),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (!isAvailable) ...[
                      const SizedBox(height: 3),
                      Text(
                        estimate.unavailableReason ?? 'Not available for this trip',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ] else if (vehicle.description != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        vehicle.description!,
                        style: theme.textTheme.labelSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (fare != null)
                    Text(
                      Formatters.money(fare.total, symbol: fare.currencySymbol),
                      style: theme.textTheme.titleMedium,
                    )
                  else
                    Text('--', style: theme.textTheme.titleMedium),
                  if (fare?.hasSurge ?? false)
                    Text(
                      '${fare!.surgeMultiplier}x busy',
                      style: theme.textTheme.labelSmall?.copyWith(color: AppColors.warning),
                    )
                  else
                    Text('estimated', style: theme.textTheme.labelSmall),
                ],
              ),
              if (isSelected)
                const Padding(
                  padding: EdgeInsets.only(left: AppSpacing.sm),
                  child: Icon(Icons.check_circle_rounded, size: 21, color: AppColors.amberDark),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
