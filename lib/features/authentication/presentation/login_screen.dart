import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/primary_button.dart';
import '../models/auth_session.dart';
import '../providers/auth_controller.dart';
import 'otp_screen.dart';

/// Sign-in, covering the three options the brief calls for:
///
///   A. mobile number + password   -> the Password tab
///   B. mobile number + OTP        -> the "Email a code" tab
///   C. email + password           -> the Password tab
///
/// Option B is mobile-number-based authentication whose code arrives by
/// email: the customer proves the number by proving the inbox registered
/// against it. The server decides that - see OTP_PHONE_DELIVERY - so this
/// screen reads the challenge's `deliveryChannel` rather than assuming.
///
/// A and C share one field because the server accepts either; which one the
/// customer typed is decided by looking for an `@`. That is one less decision
/// to make on a screen people use half-asleep.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);

  final _passwordFormKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();

  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpPhoneController = TextEditingController();

  bool _isSubmitting = false;
  bool _isRequestingOtp = false;

  /// Field errors returned by the API, cleared as soon as the field is edited.
  String? _identifierError;
  String? _passwordError;
  String? _otpPhoneError;

  @override
  void initState() {
    super.initState();

    // An expired session redirects here with a message to explain why.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final message = ref.read(authControllerProvider).message;
      if (message != null && mounted) {
        AppFeedback.showInfo(context, message);
        ref.read(authControllerProvider.notifier).consumeMessage();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _identifierController.dispose();
    _passwordController.dispose();
    _otpPhoneController.dispose();
    super.dispose();
  }

  void _applyFieldErrors(ApiException error) {
    final fields = error.fieldErrors;
    setState(() {
      _identifierError = fields['phone'] ?? fields['email'];
      _passwordError = fields['password'];
      _otpPhoneError = fields['phone'];
    });
  }

  Future<void> _signInWithPassword() async {
    setState(() {
      _identifierError = null;
      _passwordError = null;
    });

    if (!(_passwordFormKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    try {
      await ref.read(authControllerProvider.notifier).loginWithPassword(
            identifier: _identifierController.text,
            password: _passwordController.text,
          );
      // The router's redirect takes over from here; no explicit navigation.
    } on ApiException catch (error) {
      if (!mounted) return;

      if (error.code == ApiException.validation) {
        _applyFieldErrors(error);
      } else if (error.code == ApiException.invalidCredentials) {
        // Deliberately shown against the password field rather than as a
        // snackbar, because that is where the customer is looking.
        setState(() => _passwordError = error.message);
      } else {
        AppFeedback.showError(context, error);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Requests a login code and hands off to the OTP screen, which does the
  /// verification and the sign-in.
  Future<void> _requestLoginCode() async {
    setState(() => _otpPhoneError = null);
    if (!(_otpFormKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() => _isRequestingOtp = true);

    final identifier = _otpPhoneController.text.trim();

    try {
      final challenge = await ref.read(authRepositoryProvider).sendOtp(
            identifier: identifier,
            purpose: OtpPurpose.login,
          );

      if (!mounted) return;

      context.push(
        AppRoutes.otp,
        extra: OtpScreenArgs(
          identifier: identifier,
          purpose: OtpPurpose.login,
          challenge: challenge,
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;

      if (error.code == ApiException.accountNotFound) {
        setState(() => _otpPhoneError = error.message);
      } else if (error.code == ApiException.validation) {
        setState(() => _otpPhoneError = error.fieldErrors['phone'] ?? error.message);
      } else {
        AppFeedback.showError(context, error);
      }
    } finally {
      if (mounted) setState(() => _isRequestingOtp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final businessName = ref.watch(businessContactProvider).maybeWhen(
          data: (contact) => contact.businessName,
          orElse: () => null,
        );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                // Keeps the submit button reachable above the keyboard.
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.pageGutter,
                  AppSpacing.xxl,
                  AppSpacing.pageGutter,
                  AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom * 0.1,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppLogo(size: 58),
                    const SizedBox(height: AppSpacing.xl),
                    Text('Welcome back', style: theme.textTheme.headlineMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      businessName == null
                          ? 'Sign in to book your ride.'
                          : 'Sign in to book with $businessName.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),

                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        dividerColor: Colors.transparent,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: theme.colorScheme.outline),
                        ),
                        tabs: const [
                          Tab(text: 'Password'),
                          Tab(text: 'Email a code'),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),

                    // AnimatedSize keeps the card from jumping as the two tabs
                    // have different heights.
                    AnimatedBuilder(
                      animation: _tabController,
                      builder: (context, _) => AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        alignment: Alignment.topCenter,
                        child: _tabController.index == 0
                            ? _buildPasswordForm()
                            : _buildOtpForm(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageGutter,
                0,
                AppSpacing.pageGutter,
                AppSpacing.md,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'New here?',
                    style: theme.textTheme.bodySmall,
                  ),
                  TextButton(
                    onPressed: () => context.push(AppRoutes.register),
                    child: const Text('Create an account'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordForm() {
    return Form(
      key: _passwordFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            controller: _identifierController,
            label: 'Mobile number or email',
            hint: '9876543210 or you@example.com',
            prefixIcon: Icons.person_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username],
            serverError: _identifierError,
            onChanged: (_) {
              if (_identifierError != null) setState(() => _identifierError = null);
            },
            validator: (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty) return 'Enter your mobile number or email address.';
              return Validators.looksLikeEmail(text)
                  ? Validators.email(text)
                  : Validators.phone(text);
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _passwordController,
            label: 'Password',
            obscureText: true,
            prefixIcon: Icons.lock_outline_rounded,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            serverError: _passwordError,
            onChanged: (_) {
              if (_passwordError != null) setState(() => _passwordError = null);
            },
            validator: Validators.passwordPresent,
            onSubmitted: (_) => _signInWithPassword(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.push(AppRoutes.forgotPassword),
              child: const Text('Forgot password?'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          PrimaryButton(
            label: 'Sign in',
            isLoading: _isSubmitting,
            onPressed: _signInWithPassword,
          ),
        ],
      ),
    );
  }

  Widget _buildOtpForm() {
    final theme = Theme.of(context);

    return Form(
      key: _otpFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            controller: _otpPhoneController,
            label: 'Mobile number',
            hint: '9876543210',
            prefixIcon: Icons.smartphone_rounded,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.telephoneNumber],
            inputFormatters: [
              // Digits and a leading plus only, so the number cannot arrive at
              // the normaliser full of punctuation.
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s]')),
              LengthLimitingTextInputFormatter(16),
            ],
            serverError: _otpPhoneError,
            onChanged: (_) {
              if (_otpPhoneError != null) setState(() => _otpPhoneError = null);
            },
            validator: Validators.phone,
            onSubmitted: (_) => _requestLoginCode(),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Enter your mobile number and we will email a one-time code to the '
            'address registered against it. No password needed.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: 'Email me a code',
            icon: Icons.mark_email_unread_outlined,
            isLoading: _isRequestingOtp,
            onPressed: _requestLoginCode,
          ),
        ],
      ),
    );
  }
}
