import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/primary_button.dart';
import '../models/auth_session.dart';
import '../providers/auth_controller.dart';
import 'reset_password_screen.dart';

/// Arguments for [OtpScreen].
///
/// Carries the challenge from the screen that requested the code, so this
/// screen knows the masked destination and the resend cooldown without
/// re-requesting - and so it never sends a second SMS just by being opened.
class OtpScreenArgs {
  const OtpScreenArgs({
    required this.identifier,
    required this.purpose,
    required this.challenge,
    this.registrationDraft,
  });

  /// The raw identifier the customer typed. Normalised inside the repository.
  final String identifier;

  final OtpPurpose purpose;
  final OtpChallenge challenge;

  /// For a registration, the details to submit once the code is verified. The
  /// account is only created after verification, so an unverified number can
  /// never end up attached to one.
  final RegistrationDraft? registrationDraft;
}

/// The signup details held between "send code" and "create account".
class RegistrationDraft {
  const RegistrationDraft({
    required this.fullName,
    required this.phone,
    required this.password,
    this.email,
  });

  final String fullName;
  final String phone;
  final String password;
  final String? email;
}

/// Enters and verifies a one-time code.
///
/// What happens on success depends on [OtpScreenArgs.purpose]:
///   - `login`          -> signs in directly
///   - `register`       -> creates the account with the held draft
///   - `resetPassword`  -> moves on to choose a new password
///   - `verifyPhone/Email` -> returns the verification token to the caller
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.args});

  final OtpScreenArgs args;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  Timer? _ticker;
  int _resendIn = 0;
  int _expiresIn = 0;

  bool _isVerifying = false;
  bool _isResending = false;
  String? _error;

  int get _codeLength => ref.read(serverCapabilitiesProvider).maybeWhen(
        data: (capabilities) => capabilities.otpLength,
        orElse: () => 6,
      );

  @override
  void initState() {
    super.initState();
    _startTimers(
      resendIn: widget.args.challenge.resendInSeconds,
      expiresIn: widget.args.challenge.expiresInSeconds,
    );

    // Autofocus after the route transition settles, so the keyboard animates
    // in rather than fighting the page transition.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _startTimers({required int resendIn, required int expiresIn}) {
    _ticker?.cancel();
    setState(() {
      _resendIn = resendIn;
      _expiresIn = expiresIn;
    });

    if (resendIn <= 0 && expiresIn <= 0) return;

    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_resendIn > 0) _resendIn--;
        if (_expiresIn > 0) _expiresIn--;
      });

      if (_resendIn <= 0 && _expiresIn <= 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();

    if (code.length != _codeLength) {
      setState(() => _error = 'Enter all $_codeLength digits.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isVerifying = true;
      _error = null;
    });

    try {
      switch (widget.args.purpose) {
        case OtpPurpose.login:
          await _completeLogin(code);
        case OtpPurpose.register:
          await _completeRegistration(code);
        case OtpPurpose.resetPassword:
          await _continueToPasswordReset(code);
        case OtpPurpose.verifyPhone:
        case OtpPurpose.verifyEmail:
          await _returnVerificationToken(code);
      }
    } on ApiException catch (error) {
      if (!mounted) return;

      // An exhausted or expired code needs a new one, so say so plainly and
      // open the resend immediately rather than leaving them re-tapping Verify.
      if (error.code == ApiException.otpExpired ||
          error.code == ApiException.otpAttemptsExceeded) {
        setState(() {
          _error = error.message;
          _resendIn = 0;
          _expiresIn = 0;
        });
        _controller.clear();
      } else {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _completeLogin(String code) async {
    await ref.read(authControllerProvider.notifier).loginWithOtp(
          identifier: widget.args.identifier,
          code: code,
        );
    // The router redirect handles navigation on success.
  }

  Future<void> _completeRegistration(String code) async {
    final draft = widget.args.registrationDraft;
    if (draft == null) {
      setState(() => _error = 'Something went wrong. Please start again.');
      return;
    }

    final verification = await ref.read(authRepositoryProvider).verifyOtp(
          identifier: widget.args.identifier,
          purpose: OtpPurpose.register,
          code: code,
        );

    await ref.read(authControllerProvider.notifier).registerWithPhone(
          fullName: draft.fullName,
          phone: draft.phone,
          email: draft.email,
          password: draft.password,
          verificationToken: verification.verificationToken,
        );

    if (mounted) {
      AppFeedback.showSuccess(context, 'Welcome aboard. Your account is ready.');
    }
  }

  Future<void> _continueToPasswordReset(String code) async {
    final verification = await ref.read(authRepositoryProvider).verifyOtp(
          identifier: widget.args.identifier,
          purpose: OtpPurpose.resetPassword,
          code: code,
        );

    if (!mounted) return;

    context.pushReplacement(
      AppRoutes.resetPassword,
      extra: ResetPasswordArgs(
        identifier: widget.args.identifier,
        verificationToken: verification.verificationToken,
      ),
    );
  }

  Future<void> _returnVerificationToken(String code) async {
    final verification = await ref.read(authRepositoryProvider).verifyOtp(
          identifier: widget.args.identifier,
          purpose: widget.args.purpose,
          code: code,
        );

    if (!mounted) return;
    // The caller (profile edit) awaits this token to complete its own update.
    context.pop(verification.verificationToken);
  }

  Future<void> _resend() async {
    setState(() {
      _isResending = true;
      _error = null;
    });

    try {
      final challenge = await ref.read(authRepositoryProvider).sendOtp(
            identifier: widget.args.identifier,
            purpose: widget.args.purpose,
          );

      _controller.clear();
      _startTimers(
        resendIn: challenge.resendInSeconds,
        expiresIn: challenge.expiresInSeconds,
      );

      if (!mounted) return;
      _focusNode.requestFocus();

      AppFeedback.showSuccess(
        context,
        challenge.isDevelopmentCode
            ? 'New development code: ${challenge.devOtp}'
            : 'A new code is on its way.',
      );
    } on ApiException catch (error) {
      if (!mounted) return;

      // The server's cooldown is authoritative; adopt whatever it tells us.
      final retryAfter = error.details?['retryAfterSeconds'];
      if (retryAfter is num) {
        setState(() => _resendIn = retryAfter.toInt());
        _startTimers(resendIn: retryAfter.toInt(), expiresIn: _expiresIn);
      }
      AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final args = widget.args;
    final isBusy = _isVerifying || ref.watch(authControllerProvider).isBusy;

    return Scaffold(
      appBar: AppBar(title: Text(args.purpose.screenTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.pageGutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  args.purpose == OtpPurpose.verifyEmail
                      ? Icons.mark_email_unread_outlined
                      : Icons.sms_outlined,
                  size: 28,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Enter the $_codeLength-digit code', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text.rich(
                TextSpan(
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  children: [
                    const TextSpan(text: 'We sent it to '),
                    TextSpan(
                      text: args.challenge.maskedDestination,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Development affordance: the backend only returns `devOtp` when
              // its SMS provider is mocked and it is not in production. Without
              // this, the OTP flow would be untestable without an SMS gateway.
              if (args.challenge.isDevelopmentCode) ...[
                AppBanner(
                  icon: Icons.construction_rounded,
                  accent: AppColors.warning,
                  message:
                      'Development mode: SMS delivery is mocked on the server, so the code is '
                      'shown here instead of being texted. Code: ${args.challenge.devOtp}',
                  actionLabel: 'Fill it in',
                  onAction: () {
                    _controller.text = args.challenge.devOtp!;
                    setState(() => _error = null);
                  },
                ),
                const SizedBox(height: AppSpacing.xl),
              ],

              _OtpInput(
                controller: _controller,
                focusNode: _focusNode,
                length: _codeLength,
                hasError: _error != null,
                enabled: !isBusy,
                onChanged: (value) {
                  if (_error != null) setState(() => _error = null);
                  // Verify as soon as the last digit lands - nobody wants to
                  // reach for a button after typing a code.
                  if (value.length == _codeLength) _submit();
                },
              ),

              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Icon(Icons.error_outline_rounded, size: 16, color: theme.colorScheme.error),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: AppSpacing.xl),

              if (_expiresIn > 0)
                Text(
                  'This code expires in ${Formatters.countdown(_expiresIn)}.',
                  style: theme.textTheme.bodySmall,
                )
              else
                Text(
                  'This code has expired. Request a new one.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),

              const SizedBox(height: AppSpacing.xxl),

              // Always enabled: `_submit` validates the length and explains
              // what is missing, which beats a dead button with no reason.
              PrimaryButton(label: 'Verify', isLoading: isBusy, onPressed: _submit),

              const SizedBox(height: AppSpacing.md),

              Center(
                child: _resendIn > 0
                    ? Text(
                        'Resend available in ${Formatters.countdown(_resendIn)}',
                        style: theme.textTheme.bodySmall,
                      )
                    : TextButton.icon(
                        onPressed: _isResending ? null : _resend,
                        icon: _isResending
                            ? const SizedBox(
                                height: 15,
                                width: 15,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(_isResending ? 'Sending' : 'Resend code'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Segmented code entry.
///
/// A single hidden [TextField] drives the boxes rather than one field per
/// digit. That means SMS autofill, paste and the backspace key all behave the
/// way the platform expects, which per-digit fields famously break.
class _OtpInput extends StatefulWidget {
  const _OtpInput({
    required this.controller,
    required this.focusNode,
    required this.length,
    required this.onChanged,
    this.hasError = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int length;
  final ValueChanged<String> onChanged;
  final bool hasError;
  final bool enabled;

  @override
  State<_OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<_OtpInput> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = widget.controller.text;

    return Stack(
      children: [
        // The real input, invisible but focusable and fully functional.
        Opacity(
          opacity: 0,
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            enabled: widget.enabled,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(widget.length),
            ],
            onChanged: widget.onChanged,
          ),
        ),
        GestureDetector(
          onTap: widget.enabled ? widget.focusNode.requestFocus : null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(widget.length, (index) {
              final hasDigit = index < value.length;
              final isNext = index == value.length && widget.focusNode.hasFocus;

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: index == widget.length - 1 ? 0 : AppSpacing.sm),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 60,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: widget.hasError
                            ? theme.colorScheme.error
                            : isNext
                                ? AppColors.amberDark
                                : theme.colorScheme.outline,
                        width: isNext || widget.hasError ? 1.8 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      hasDigit ? value[index] : '',
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}
