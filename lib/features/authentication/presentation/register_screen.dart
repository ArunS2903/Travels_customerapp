import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/primary_button.dart';
import '../models/auth_session.dart';
import '../providers/auth_controller.dart';
import 'otp_screen.dart';

/// Create an account.
///
/// Two paths, because they have genuinely different security properties:
///
///   - With a mobile number, the account is created only *after* an SMS code is
///     verified, so a number can never be attached to an account by someone who
///     does not hold the SIM. The details entered here are carried to the OTP
///     screen as a draft and submitted on success.
///
///   - Email-only signup completes immediately, with a verification code sent
///     afterwards. Nothing privileged depends on `emailVerified`, so holding
///     the whole signup hostage to an inbox round trip is not worth it.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isSubmitting = false;
  bool _acceptedTerms = false;

  final Map<String, String?> _fieldErrors = {};

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _clearFieldError(String field) {
    if (_fieldErrors[field] != null) {
      setState(() => _fieldErrors[field] = null);
    }
  }

  Future<void> _submit() async {
    setState(_fieldErrors.clear);

    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (!_acceptedTerms) {
      AppFeedback.showInfo(context, 'Please accept the terms to continue.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();

    try {
      if (phone.isNotEmpty) {
        await _startPhoneVerification(phone, email);
      } else {
        await _registerWithEmailOnly(email);
      }
    } on ApiException catch (error) {
      if (!mounted) return;

      if (error.code == ApiException.validation) {
        setState(() {
          error.fieldErrors.forEach((key, value) => _fieldErrors[key] = value);
        });
        // Re-run validation so the new server errors are rendered.
        _formKey.currentState?.validate();
      } else if (error.code == ApiException.accountExists) {
        final field = error.details?['field'] as String?;
        setState(() => _fieldErrors[field ?? 'phone'] = error.message);
        _formKey.currentState?.validate();
      } else {
        AppFeedback.showError(context, error);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Sends the register OTP and hands the draft to the OTP screen, which
  /// creates the account once the code checks out.
  Future<void> _startPhoneVerification(String phone, String email) async {
    final challenge = await ref.read(authRepositoryProvider).sendOtp(
          identifier: phone,
          purpose: OtpPurpose.register,
        );

    if (!mounted) return;

    context.push(
      AppRoutes.otp,
      extra: OtpScreenArgs(
        identifier: phone,
        purpose: OtpPurpose.register,
        challenge: challenge,
        registrationDraft: RegistrationDraft(
          fullName: _nameController.text.trim(),
          phone: phone,
          password: _passwordController.text,
          email: email.isEmpty ? null : email,
        ),
      ),
    );
  }

  Future<void> _registerWithEmailOnly(String email) async {
    await ref.read(authControllerProvider.notifier).registerWithEmail(
          fullName: _nameController.text.trim(),
          email: email,
          password: _passwordController.text,
        );

    if (!mounted) return;
    AppFeedback.showSuccess(
      context,
      'Account created. Check your email for a verification code.',
    );
    // The router redirect takes it from here.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final termsUrl = ref.watch(businessContactProvider).maybeWhen(
          data: (contact) => contact.termsUrl,
          orElse: () => null,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.pageGutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A few details and you are ready to ride.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),

                AppTextField(
                  controller: _nameController,
                  label: 'Full name',
                  hint: 'As it should appear to your driver',
                  prefixIcon: Icons.badge_outlined,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  serverError: _fieldErrors['fullName'],
                  onChanged: (_) => _clearFieldError('fullName'),
                  validator: Validators.fullName,
                ),
                const SizedBox(height: AppSpacing.lg),

                AppTextField(
                  controller: _phoneController,
                  label: 'Mobile number',
                  hint: '9876543210',
                  helperText: 'We will text a code to confirm this number.',
                  prefixIcon: Icons.smartphone_rounded,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s]')),
                    LengthLimitingTextInputFormatter(16),
                  ],
                  serverError: _fieldErrors['phone'],
                  onChanged: (_) {
                    _clearFieldError('phone');
                    // The email field's requirement depends on this one, so
                    // repaint the labels.
                    setState(() {});
                  },
                  validator: (value) {
                    final phone = (value ?? '').trim();
                    final email = _emailController.text.trim();
                    // One of the two is required; the backend enforces the same.
                    if (phone.isEmpty) {
                      return email.isEmpty
                          ? 'Enter a mobile number or an email address.'
                          : null;
                    }
                    return Validators.phone(phone);
                  },
                ),
                const SizedBox(height: AppSpacing.lg),

                AppTextField(
                  controller: _emailController,
                  label: _phoneController.text.trim().isEmpty
                      ? 'Email address'
                      : 'Email address (optional)',
                  hint: 'you@example.com',
                  prefixIcon: Icons.alternate_email_rounded,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  serverError: _fieldErrors['email'],
                  onChanged: (_) {
                    _clearFieldError('email');
                    setState(() {});
                  },
                  validator: (value) {
                    final email = (value ?? '').trim();
                    final hasPhone = _phoneController.text.trim().isNotEmpty;
                    if (email.isEmpty) {
                      return hasPhone ? null : 'Enter an email address or a mobile number.';
                    }
                    return Validators.email(email);
                  },
                ),
                const SizedBox(height: AppSpacing.lg),

                AppTextField(
                  controller: _passwordController,
                  label: 'Password',
                  helperText: 'At least 8 characters, with a letter and a number.',
                  obscureText: true,
                  prefixIcon: Icons.lock_outline_rounded,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  serverError: _fieldErrors['password'],
                  onChanged: (_) {
                    _clearFieldError('password');
                    setState(() {});
                  },
                  validator: Validators.password,
                ),
                const SizedBox(height: AppSpacing.sm),
                _PasswordStrengthBar(password: _passwordController.text),
                const SizedBox(height: AppSpacing.lg),

                AppTextField(
                  controller: _confirmController,
                  label: 'Confirm password',
                  obscureText: true,
                  prefixIcon: Icons.lock_reset_rounded,
                  textInputAction: TextInputAction.done,
                  serverError: _fieldErrors['confirmPassword'],
                  onChanged: (_) => _clearFieldError('confirmPassword'),
                  validator: (value) =>
                      Validators.confirmPassword(value, _passwordController.text),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: AppSpacing.xl),

                InkWell(
                  onTap: () => setState(() => _acceptedTerms = !_acceptedTerms),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _acceptedTerms,
                          onChanged: (value) => setState(() => _acceptedTerms = value ?? false),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.md),
                            child: Text(
                              termsUrl == null
                                  ? 'I agree to the terms of service and privacy policy.'
                                  : 'I agree to the terms of service and privacy policy, '
                                      'available in the Support section.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                PrimaryButton(
                  label: _phoneController.text.trim().isEmpty
                      ? 'Create account'
                      : 'Continue',
                  isLoading: _isSubmitting || ref.watch(authControllerProvider).isBusy,
                  onPressed: _submit,
                ),
                const SizedBox(height: AppSpacing.lg),

                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Already have an account?', style: theme.textTheme.bodySmall),
                      TextButton(
                        onPressed: () => context.pop(),
                        child: const Text('Sign in'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Live feedback on password strength.
///
/// Scores length and character variety only - deliberately not a dictionary
/// check, which would need a wordlist in the bundle and still be easy to fool.
/// The bar is advisory; the backend's minimum is what is actually enforced.
class _PasswordStrengthBar extends StatelessWidget {
  const _PasswordStrengthBar({required this.password});

  final String password;

  /// 0 = none, 1 = weak, 2 = fair, 3 = strong.
  int get _score {
    if (password.isEmpty) return 0;

    var score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(password) && RegExp(r'[a-z]').hasMatch(password)) score++;
    if (RegExp(r'\d').hasMatch(password)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;

    if (score <= 2) return 1;
    if (score <= 3) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = _score;

    if (score == 0) return const SizedBox.shrink();

    const labels = {1: 'Weak', 2: 'Fair', 3: 'Strong'};
    final colors = {
      1: theme.colorScheme.error,
      2: Colors.orange.shade700,
      3: Colors.green.shade700,
    };

    return Row(
      children: [
        ...List.generate(3, (index) {
          final isFilled = index < score;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: index == 2 ? 0 : 4),
              height: 4,
              decoration: BoxDecoration(
                color: isFilled ? colors[score] : theme.colorScheme.outline,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
          );
        }),
        const SizedBox(width: AppSpacing.md),
        Text(
          labels[score]!,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors[score],
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
