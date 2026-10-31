import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/state_views.dart';
import '../../booking_details/models/booking.dart';
import '../../booking_details/providers/booking_detail_providers.dart';

/// Cancellation sheet: pick a reason, see the fee, confirm.
///
/// The fee is re-fetched when the sheet opens rather than reusing whatever the
/// details screen loaded earlier - the figure depends on how long ago a driver
/// was assigned, so a stale number could be wrong by the time it is read.
///
/// The reasons come from the server too, so admin reporting and the app always
/// agree on the vocabulary. Some reasons (a driver asking to cancel, a wrong
/// pickup) waive the fee, which the server decides; this screen just shows the
/// consequence before the customer commits.
class CancelBookingSheet extends ConsumerStatefulWidget {
  const CancelBookingSheet({super.key, required this.booking});

  final Booking booking;

  @override
  ConsumerState<CancelBookingSheet> createState() => _CancelBookingSheetState();
}

class _CancelBookingSheetState extends ConsumerState<CancelBookingSheet> {
  final _remarksController = TextEditingController();

  String? _selectedReason;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Any state from a previous cancellation attempt would confuse this one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cancellationControllerProvider.notifier).reset();
    });
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _selectedReason;
    if (reason == null) {
      AppFeedback.showInfo(context, 'Choose a reason for cancelling.');
      return;
    }

    // "Other" without a note tells the operator nothing, so require one.
    if (reason == 'Other' && _remarksController.text.trim().length < 3) {
      AppFeedback.showInfo(context, 'Tell us a little more about why you are cancelling.');
      return;
    }

    final confirmed = await AppFeedback.confirm(
      context,
      title: 'Cancel this booking?',
      message: 'Booking ${widget.booking.bookingCode} will be cancelled. This cannot be undone.',
      confirmLabel: 'Yes, cancel',
      cancelLabel: 'Keep booking',
      isDestructive: true,
    );

    if (!confirmed || !mounted) return;

    setState(() => _isSubmitting = true);

    final cancelled = await ref.read(cancellationControllerProvider.notifier).cancel(
          bookingId: widget.booking.id,
          reason: reason,
          remarks: _remarksController.text.trim().isEmpty
              ? null
              : _remarksController.text.trim(),
        );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (cancelled != null) {
      Navigator.of(context).pop(cancelled);
      return;
    }

    final error = ref.read(cancellationControllerProvider).error;

    // The booking moved while the sheet was open - the admin assigned a driver,
    // or the trip started. Close so the customer sees the real current state
    // rather than arguing with a sheet about a booking that has moved on.
    if (error is ApiException &&
        (error.code == ApiException.bookingStateChanged ||
            error.code == ApiException.bookingAlreadyCompleted ||
            error.code == ApiException.bookingAlreadyCancelled ||
            error.code == ApiException.bookingNotCancellable)) {
      Navigator.of(context).pop();
      AppFeedback.showError(context, error);
      return;
    }

    if (error != null) AppFeedback.showError(context, error);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final policyState = ref.watch(cancellationPolicyProvider(widget.booking.id));

    final reasons = policyState.maybeWhen(
      data: (policy) => policy.reasons,
      orElse: () => ref.watch(serverCapabilitiesProvider).maybeWhen(
            data: (capabilities) => capabilities.cancellationReasons,
            orElse: () => const <String>[],
          ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageGutter,
            0,
            AppSpacing.pageGutter,
            AppSpacing.xxl,
          ),
          children: [
            Text('Cancel booking', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Booking ${widget.booking.bookingCode} - ${widget.booking.vehicleTypeName} to '
              '${widget.booking.destination.shortAddress}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xl),

            policyState.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (error, _) => ErrorView(
                error: error,
                compact: true,
                onRetry: () =>
                    ref.invalidate(cancellationPolicyProvider(widget.booking.id)),
              ),
              data: (policy) => _FeeNotice(
                fee: policy.estimatedFee,
                currencySymbol: widget.booking.currencySymbol,
                selectedReason: _selectedReason,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            Text('Why are you cancelling?', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.md),

            if (reasons.isEmpty)
              Text(
                'Could not load the reason list. Please try again.',
                style: theme.textTheme.bodySmall,
              )
            else
              ...reasons.map(
                (reason) => _ReasonTile(
                  reason: reason,
                  isSelected: _selectedReason == reason,
                  onTap: () => setState(() => _selectedReason = reason),
                ),
              ),

            const SizedBox(height: AppSpacing.xl),
            Text(
              _selectedReason == 'Other' ? 'Tell us more' : 'Anything to add? (optional)',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _remarksController,
              maxLines: 3,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Your remarks help the operator improve the service',
                counterText: '',
              ),
            ),

            const SizedBox(height: AppSpacing.xxl),
            PrimaryButton(
              label: 'Cancel this booking',
              isLoading: _isSubmitting,
              onPressed: _selectedReason == null ? null : _submit,
            ),
            const SizedBox(height: AppSpacing.sm),
            SecondaryButton(
              label: 'Keep my booking',
              onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// States the fee consequence before the customer commits.
class _FeeNotice extends StatelessWidget {
  const _FeeNotice({
    required this.fee,
    required this.currencySymbol,
    required this.selectedReason,
  });

  final double fee;
  final String currencySymbol;
  final String? selectedReason;

  /// Reasons the backend always waives the fee for. Mirrors `NO_FEE_REASONS`
  /// in the backend's domain constants.
  static const _noFeeReasons = {'Driver asked to cancel', 'Wrong pickup location'};

  @override
  Widget build(BuildContext context) {
    final willBeWaived = selectedReason != null && _noFeeReasons.contains(selectedReason);
    final effectiveFee = willBeWaived ? 0.0 : fee;

    if (effectiveFee <= 0) {
      return AppBanner(
        icon: Icons.check_circle_outline_rounded,
        accent: AppColors.success,
        message: willBeWaived && fee > 0
            ? 'No cancellation fee applies for this reason.'
            : 'You can cancel this booking free of charge.',
      );
    }

    return AppBanner(
      icon: Icons.account_balance_wallet_outlined,
      accent: AppColors.warning,
      message:
          'A cancellation fee of ${Formatters.money(effectiveFee, symbol: currencySymbol)} '
          'applies because a driver has already been dispatched.',
    );
  }
}

class _ReasonTile extends StatelessWidget {
  const _ReasonTile({
    required this.reason,
    required this.isSelected,
    required this.onTap,
  });

  final String reason;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.amber.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.14 : 0.1,
                  )
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: isSelected ? AppColors.amberDark : theme.colorScheme.outline,
              width: isSelected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 20,
                color: isSelected ? AppColors.amberDark : theme.colorScheme.outline,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(reason, style: theme.textTheme.bodyMedium)),
            ],
          ),
        ),
      ),
    );
  }
}
