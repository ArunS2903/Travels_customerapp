import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/primary_button.dart';
import '../models/auth_session.dart';
import 'otp_screen.dart';

/// Starts a password reset.
///
/// The backend answers identically whether or not the account exists, so this
/// screen cannot be used to find out who has an account - and it must not
/// pretend otherwise. We therefore always advance to the OTP screen, and the
/// customer discovers a wrong number by never receiving a code.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();

  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _identifierController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    final identifier = _identifierController.text.trim();

    try {
      final challenge = await ref.read(authRepositoryProvider).forgotPassword(
            identifier: identifier,
          );

      if (!mounted) return;

      context.push(
        AppRoutes.otp,
        extra: OtpScreenArgs(
          identifier: identifier,
          purpose: OtpPurpose.resetPassword,
          challenge: challenge,
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;

      if (error.code == ApiException.validation) {
        setState(() => _error = error.fieldErrors.values.firstOrNull ?? error.message);
      } else {
        AppFeedback.showError(context, error);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.pageGutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_reset_rounded,
                    size: 28,
                    color: AppColors.amberDark,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('Reset your password', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Enter the mobile number or email address on your account and we will send '
                  'you a code to set a new password.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),

                AppTextField(
                  controller: _identifierController,
                  label: 'Mobile number or email',
                  hint: '9876543210 or you@example.com',
                  prefixIcon: Icons.person_outline_rounded,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  autofocus: true,
                  serverError: _error,
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return 'Enter your mobile number or email address.';
                    return Validators.looksLikeEmail(text)
                        ? Validators.email(text)
                        : Validators.phone(text);
                  },
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: AppSpacing.xxl),

                PrimaryButton(
                  label: 'Send reset code',
                  isLoading: _isSubmitting,
                  onPressed: _submit,
                ),
                const SizedBox(height: AppSpacing.xl),

                AppBanner(
                  icon: Icons.privacy_tip_outlined,
                  message:
                      'For your privacy we do not reveal whether an account exists. If you do '
                      'not receive a code, check the number or email and try again.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
