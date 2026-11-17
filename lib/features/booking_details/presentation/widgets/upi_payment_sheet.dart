import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/feedback.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../data/booking_repository.dart';
import '../../models/booking.dart';
import '../../providers/booking_detail_providers.dart';

/// Paying a booking by UPI, in two steps on one sheet.
///
/// Why two steps, and why the second one cannot be skipped
/// -------------------------------------------------------
/// The money goes directly into the operator's UPI ID. That is the whole
/// appeal - no gateway, no percentage - and it is also the whole problem: a
/// transfer into a personal or sole-proprietor VPA has no status anybody can
/// query. The app cannot know the payment succeeded, and neither can the
/// server. So the customer brings back the UTR from their own receipt, and an
/// administrator matches it against the bank credit.
///
/// The sheet is honest about that rather than showing a success tick and
/// hoping. Step two says, in as many words, that we are checking.
///
/// The amount is never editable here. It is fetched from the server with the
/// intent, and the "pay the full amount" rule is enforced by there being
/// nothing to type.
class UpiPaymentSheet extends ConsumerStatefulWidget {
  const UpiPaymentSheet({super.key, required this.booking});

  final Booking booking;

  @override
  ConsumerState<UpiPaymentSheet> createState() => _UpiPaymentSheetState();
}

class _UpiPaymentSheetState extends ConsumerState<UpiPaymentSheet> {
  final _referenceController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  UpiPaymentIntent? _intent;
  Object? _loadError;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _referenceError;

  /// Flips once the customer has actually been sent to a UPI app. Until then
  /// the reference field is hidden: asking for a transaction ID before there
  /// has been a transaction invites people to invent one.
  bool _hasOpenedUpiApp = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final intent = await ref
          .read(bookingRepositoryProvider)
          .fetchUpiIntent(widget.booking.id);
      if (!mounted) return;
      setState(() {
        _intent = intent;
        _isLoading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _openUpiApp() async {
    final intent = _intent;
    if (intent == null) return;

    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(intent.intentUrl),
        mode: LaunchMode.externalApplication,
      );
    } on Object {
      launched = false;
    }

    if (!mounted) return;

    if (!launched) {
      // Nothing answered `upi:`. The VPA and the amount are both on screen, so
      // the customer can still pay by hand - which is a far better outcome
      // than a dead button and a shrug.
      AppFeedback.showError(
        context,
        'We could not open a UPI app on this device. Pay the amount shown to '
        '${intent.payeeVpa} from any UPI app, then enter the transaction ID below.',
      );
    }

    // Set either way: the customer has been told how to pay, so the reference
    // field should be there when they come back.
    setState(() => _hasOpenedUpiApp = true);
  }

  Future<void> _copyVpa(String vpa) async {
    await Clipboard.setData(ClipboardData(text: vpa));
    if (!mounted) return;
    AppFeedback.showSuccess(context, 'UPI ID copied.');
  }

  Future<void> _submitReference() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _referenceError = null;
    });

    try {
      await ref.read(bookingRepositoryProvider).submitPaymentReference(
            bookingId: widget.booking.id,
            transactionId: _referenceController.text.trim(),
          );

      if (!mounted) return;
      ref.invalidate(bookingDetailProvider(widget.booking.id));
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _referenceError = AppFeedback.messageFor(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);

    return Padding(
      // Lifts the sheet clear of the keyboard, which otherwise covers the
      // field the customer is being asked to type in.
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: mediaQuery.size.height * 0.88),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageGutter,
              0,
              AppSpacing.pageGutter,
              AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Online payment', style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  'Booking ${widget.booking.bookingCode}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),

                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_intent == null)
                  _LoadFailure(error: _loadError, onRetry: _load)
                else
                  ..._buildPaymentSteps(theme, _intent!),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPaymentSteps(ThemeData theme, UpiPaymentIntent intent) {
    return [
      // --- The amount, large and not editable ------------------------------
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Amount to pay',
              style: TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
            const SizedBox(height: 4),
            Text(
              Formatters.money(intent.amount, symbol: intent.currencySymbol),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Pay the full amount in one transaction. Part payments cannot be '
              'matched to this booking.',
              style: TextStyle(color: Colors.white, fontSize: 12.5, height: 1.4),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.lg),

      // --- Who it goes to --------------------------------------------------
      _DetailRow(
        label: 'Paying to',
        value: intent.payeeName,
      ),
      _DetailRow(
        label: 'UPI ID',
        value: intent.payeeVpa,
        onCopy: () => _copyVpa(intent.payeeVpa),
      ),
      if (intent.reference.isNotEmpty)
        _DetailRow(label: 'Our reference', value: intent.reference),

      const SizedBox(height: AppSpacing.lg),

      PrimaryButton(
        label: _hasOpenedUpiApp ? 'Open UPI app again' : 'Pay with UPI',
        icon: Icons.account_balance_wallet_rounded,
        onPressed: _openUpiApp,
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        'Your phone will offer every UPI app you have installed - Google Pay, '
        'PhonePe, Paytm, your bank app. Any of them works.',
        style: theme.textTheme.labelSmall,
      ),

      // --- The reference, once they have been sent to pay -------------------
      if (_hasOpenedUpiApp && intent.requiresReference) ...[
        const SizedBox(height: AppSpacing.xl),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.lg),

        Text('After you have paid', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Text(
          intent.instructions.isNotEmpty
              ? intent.instructions
              : 'Copy the transaction ID from your payment receipt and enter it '
                  'below. We check it against our account and confirm your payment.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.lg),

        Form(
          key: _formKey,
          child: AppTextField(
            controller: _referenceController,
            label: intent.referenceLabel,
            hint: intent.referenceHint.isNotEmpty
                ? intent.referenceHint
                : 'Usually a 12-digit number on your receipt',
            prefixIcon: Icons.receipt_long_rounded,
            // Not `number`: a UPI UTR is twelve digits, but several bank apps
            // print their own reference with letters in it, and a numeric
            // keypad on an alphanumeric reference leaves the customer unable
            // to type what is on their receipt.
            keyboardType: TextInputType.visiblePassword,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              LengthLimitingTextInputFormatter(30),
            ],
            serverError: _referenceError,
            onChanged: (_) {
              if (_referenceError != null) {
                setState(() => _referenceError = null);
              }
            },
            validator: (value) {
              final trimmed = (value ?? '').trim();
              if (trimmed.isEmpty) {
                return 'Enter the transaction ID from your receipt.';
              }
              // Only long enough not to be a slip. The server applies the
              // deployment's own rule, and an administrator checks the
              // reference against the bank credit either way - so a strict
              // client-side length here would only stop a real payment being
              // recorded.
              if (trimmed.length < 6) {
                return 'That looks too short. Copy it exactly as it appears on your receipt.';
              }
              return null;
            },
            onSubmitted: (_) => _submitReference(),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        PrimaryButton(
          label: 'Submit transaction ID',
          icon: Icons.check_rounded,
          isLoading: _isSubmitting,
          onPressed: _isSubmitting ? null : _submitReference,
        ),
        const SizedBox(height: AppSpacing.md),

        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.infoSoft,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.info),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Your booking stays as it is until we have confirmed the '
                  'payment against our account. You will see it marked paid, '
                  'usually within a few hours.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    ];
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.onCopy});

  final String label;
  final String value;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onCopy != null)
            IconButton(
              onPressed: onCopy,
              tooltip: 'Copy',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_rounded, size: 17),
            ),
        ],
      ),
    );
  }
}

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppFeedback.messageFor(error ?? 'Could not prepare the payment.'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          SecondaryButton(
            label: 'Try again',
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
