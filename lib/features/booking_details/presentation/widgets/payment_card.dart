import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/booking_status.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/feedback.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../../shared/widgets/section_card.dart';
import '../../../support/data/support_repository.dart';
import '../../models/booking.dart';
import '../../providers/booking_detail_providers.dart';

/// The payment on a booking: what is owed, what has happened to it, and what
/// the customer can do next.
///
/// The ordering rule this card follows
/// -----------------------------------
/// The Completed and Confirm Paid actions appear only once the payment has
/// been *verified* - `payment.isTruePayment`, which is the backend's record
/// that money actually arrived, not that somebody said it had. That is the
/// difference between this card and a naive one: a customer who has submitted
/// a transaction reference sees "we are checking", not a pair of buttons that
/// imply the matter is closed.
///
/// Everything here is driven by server state. The card never infers that a
/// payment succeeded from the fact that a UPI app opened, because that is
/// exactly the inference that cannot be made.
class PaymentCard extends ConsumerStatefulWidget {
  const PaymentCard({
    super.key,
    required this.booking,
    required this.onPayOnline,
    required this.onConfirmCash,
    this.isBusy = false,
  });

  final Booking booking;

  /// Starts the online payment flow - a UPI intent or a gateway checkout,
  /// depending on what the server is configured for. Owned by the screen
  /// because the gateway path needs the Razorpay instance that lives there.
  final VoidCallback onPayOnline;

  /// Settles a cash booking after the travel is complete.
  final VoidCallback onConfirmCash;

  final bool isBusy;

  @override
  ConsumerState<PaymentCard> createState() => _PaymentCardState();
}

class _PaymentCardState extends ConsumerState<PaymentCard> {
  /// Which acknowledgement is in flight, so only the tapped button spins.
  String? _pendingAction;

  Future<void> _acknowledge(String action) async {
    if (_pendingAction != null) return;
    setState(() => _pendingAction = action);

    try {
      await ref.read(bookingRepositoryProvider).acknowledgePayment(
            bookingId: widget.booking.id,
            action: action,
          );
      if (!mounted) return;
      ref.invalidate(bookingDetailProvider(widget.booking.id));
      AppFeedback.showSuccess(
        context,
        action == 'completed'
            ? 'Thanks for confirming the travel is complete.'
            : 'Thanks for confirming your payment.',
      );
    } on Object catch (error) {
      if (!mounted) return;
      AppFeedback.showError(context, error);
      // The refusal is usually "that is no longer true", so re-read rather
      // than leave the card showing the state that produced it.
      ref.invalidate(bookingDetailProvider(widget.booking.id));
    } finally {
      if (mounted) setState(() => _pendingAction = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final booking = widget.booking;
    final payment = booking.payment;

    final capabilities = ref.watch(serverCapabilitiesProvider).maybeWhen(
          data: (value) => value,
          orElse: () => ServerCapabilities.fallback,
        );

    final methodLabel =
        capabilities.labelForPaymentMethod(booking.paymentMethod.apiValue);

    final isOnline = booking.paymentMethod == PaymentMethod.gpay;
    final isVerified = payment?.isTruePayment ?? false;
    final isAwaiting = payment?.awaitingVerification ?? false;
    final isTravelComplete = booking.status == BookingStatus.completed;

    /// Online payment is offered while money is still owed. Deliberately not
    /// gated on the travel being complete: a customer who wants to settle up
    /// in advance should be able to, and the operator would rather be paid.
    final canPayOnline = isOnline &&
        !isVerified &&
        !isAwaiting &&
        booking.paymentStatus != PaymentStatus.paid &&
        booking.paymentStatus != PaymentStatus.refunded &&
        booking.status != BookingStatus.cancelled;

    /// Cash settles only after the travel, because that is when it changes
    /// hands. Confirming earlier would be confirming something that has not
    /// happened.
    final canConfirmCash = !isOnline &&
        isTravelComplete &&
        booking.paymentStatus != PaymentStatus.paid &&
        booking.paymentStatus != PaymentStatus.refunded;

    return SectionCard(
      title: 'Payment',
      icon: Icons.payments_outlined,
      trailing: _PaymentBadge(
        status: booking.paymentStatus,
        isVerified: isVerified,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoRow(label: 'Method', value: methodLabel),
          InfoRow(
            label: 'Amount',
            value: Formatters.money(
              payment?.amount ?? booking.displayFare,
              symbol: booking.currencySymbol,
            ),
            emphasised: true,
          ),
          if ((payment?.transactionId ?? '').isNotEmpty)
            InfoRow(label: 'Transaction ID', value: payment!.transactionId!),
          if (payment?.verifiedAt != null)
            InfoRow(
              label: 'Confirmed',
              value: Formatters.dateTime(payment!.verifiedAt),
            ),

          // --- What is happening, in words -------------------------------
          if (payment?.wasRejected == true) ...[
            const SizedBox(height: AppSpacing.md),
            _Notice(
              icon: Icons.error_outline_rounded,
              accent: AppColors.danger,
              background: AppColors.dangerSoft,
              message:
                  '${payment!.rejectionReason!} Check the transaction ID on your '
                  'receipt and submit it again.',
            ),
          ] else if (isAwaiting) ...[
            const SizedBox(height: AppSpacing.md),
            _Notice(
              icon: Icons.hourglass_top_rounded,
              accent: AppColors.warning,
              background: AppColors.warningSoft,
              message:
                  'We have your transaction ID and are checking it against our '
                  'account. Your booking will be marked paid once it is '
                  'confirmed - usually within a few hours.',
            ),
          ],

          // --- Pay -------------------------------------------------------
          if (canPayOnline) ...[
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Pay $methodLabel',
              icon: Icons.account_balance_wallet_rounded,
              isLoading: widget.isBusy,
              onPressed: widget.isBusy ? null : widget.onPayOnline,
            ),
            if (capabilities.usesDirectUpi &&
                (capabilities.upiPayeeVpa ?? '').isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Pays the full amount to ${capabilities.upiPayeeVpa} from any '
                'UPI app, in one transaction.',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ],

          if (canConfirmCash) ...[
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Confirm Paid',
              icon: Icons.check_circle_outline_rounded,
              isLoading: widget.isBusy,
              onPressed: widget.isBusy ? null : widget.onConfirmCash,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Confirm once you have handed the cash over.',
              style: theme.textTheme.labelSmall,
            ),
          ],

          /// --- Verified: the two acknowledgements -----------------------
          ///
          /// This is the pair the spec asks for, and the condition is the
          /// whole point of it: they exist only after the payment has been
          /// confirmed as genuinely received.
          if (isVerified) ...[
            const SizedBox(height: AppSpacing.md),
            _Notice(
              icon: Icons.verified_rounded,
              accent: AppColors.success,
              background: AppColors.successSoft,
              message: payment?.verifiedBy == 'gateway'
                  ? 'Payment verified by the payment provider.'
                  : payment?.verifiedBy == 'cash'
                      ? 'Cash payment recorded.'
                      : 'Payment confirmed against our account.',
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: _AckButton(
                    label: 'Completed',
                    icon: Icons.task_alt_rounded,
                    done: payment?.hasConfirmedCompleted ?? false,
                    doneLabel: 'Completed ✓',
                    isLoading: _pendingAction == 'completed',
                    onPressed: (payment?.hasConfirmedCompleted ?? false)
                        ? null
                        : () => _acknowledge('completed'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _AckButton(
                    label: 'Confirm Paid',
                    icon: Icons.check_circle_outline_rounded,
                    done: payment?.hasConfirmedPaid ?? false,
                    doneLabel: 'Confirmed ✓',
                    isLoading: _pendingAction == 'confirm_paid',
                    onPressed: (payment?.hasConfirmedPaid ?? false)
                        ? null
                        : () => _acknowledge('confirm_paid'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A compact status pill in the card's header.
class _PaymentBadge extends StatelessWidget {
  const _PaymentBadge({required this.status, required this.isVerified});

  final PaymentStatus status;
  final bool isVerified;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (label, color) = switch (status) {
      PaymentStatus.paid => (isVerified ? 'Verified' : 'Paid', AppColors.success),
      PaymentStatus.awaitingVerification => ('Checking', AppColors.warning),
      PaymentStatus.failed => ('Failed', AppColors.danger),
      PaymentStatus.refunded => ('Refunded', AppColors.info),
      _ => ('Due', AppColors.warning),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// One of the two post-verification acknowledgements.
///
/// Once tapped it stays on screen as a completed state rather than
/// disappearing: a button that vanishes leaves the customer unsure whether the
/// tap registered, and this one has no other visible effect to reassure them.
class _AckButton extends StatelessWidget {
  const _AckButton({
    required this.label,
    required this.icon,
    required this.done,
    required this.doneLabel,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool done;
  final String doneLabel;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (done) {
      return Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.successSoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
        ),
        child: Text(
          doneLabel,
          style: theme.textTheme.labelLarge?.copyWith(
            color: AppColors.success,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          foregroundColor: AppColors.brand,
          side: const BorderSide(color: AppColors.brandSoftBorder),
        ),
        child: isLoading
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(label, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.accent,
    required this.background,
    required this.message,
  });

  final IconData icon;
  final Color accent;
  final Color background;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
