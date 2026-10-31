import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/primary_button.dart';
import '../providers/auth_controller.dart';

/// Arguments for [ResetPasswordScreen], produced by verifying a
/// `reset_password` OTP.
class ResetPasswordArgs {
  const ResetPasswordArgs({required this.identifier, required this.verificationToken});

  final String identifier;

  /// One-use token from `POST /auth/verify-otp`. Authorises exactly this reset
  /// and nothing else, and expires on its own.
  final String verificationToken;
}

/// Sets a new password after the code has been verified.
///
/// On success the backend bumps the account's token version, which invalidates
/// every session that existed before - the point of a reset is to lock out
/// whoever prompted it. It hands back a fresh session for this device, so the
/// customer lands in the app rather than back at sign-in.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.args});

  final ResetPasswordArgs args;

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isSubmitting = false;
  String? _passwordError;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _passwordError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    try {
      await ref.read(authControllerProvider.notifier).completePasswordReset(
            identifier: widget.args.identifier,
            verificationToken: widget.args.verificationToken,
            password: _passwordController.text,
          );

      if (!mounted) return;
      AppFeedback.showSuccess(
        context,
        'Password changed. You have been signed out of other devices.',
      );
      // The router redirect sends us home now that a session exists.
    } on ApiException catch (error) {
      if (!mounted) return;

      if (error.code == 'WEAK_PASSWORD' || error.code == ApiException.validation) {
        setState(() {
          _passwordError = error.fieldErrors['password'] ?? error.message;
        });
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
      appBar: AppBar(title: const Text('New password')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.pageGutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Choose a new password', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Pick something you have not used here before. Signing in on your other '
                  'devices will need the new password.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),

                AppTextField(
                  controller: _passwordController,
                  label: 'New password',
                  helperText: 'At least 8 characters, with a letter and a number.',
                  obscureText: true,
                  prefixIcon: Icons.lock_outline_rounded,
                  textInputAction: TextInputAction.next,
                  autofocus: true,
                  autofillHints: const [AutofillHints.newPassword],
                  serverError: _passwordError,
                  onChanged: (_) {
                    if (_passwordError != null) setState(() => _passwordError = null);
                  },
                  validator: Validators.password,
                ),
                const SizedBox(height: AppSpacing.lg),

                AppTextField(
                  controller: _confirmController,
                  label: 'Confirm new password',
                  obscureText: true,
                  prefixIcon: Icons.lock_reset_rounded,
                  textInputAction: TextInputAction.done,
                  validator: (value) =>
                      Validators.confirmPassword(value, _passwordController.text),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: AppSpacing.xxl),

                PrimaryButton(
                  label: 'Save new password',
                  isLoading: _isSubmitting || ref.watch(authControllerProvider).isBusy,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
