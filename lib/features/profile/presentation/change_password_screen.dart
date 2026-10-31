import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../authentication/providers/auth_controller.dart';

/// Change (or first set) the account password.
///
/// The backend bumps the account's token version on success, which invalidates
/// every session including this one, and returns a fresh session for this
/// device. We adopt that session immediately - without it the app would be
/// holding a token it just invalidated and the next request would sign the
/// customer out.
///
/// An account created through OTP login alone has no password; the current
/// password field is then hidden rather than demanding something that does not
/// exist.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isSaving = false;
  String? _currentError;
  String? _newError;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _currentError = null;
      _newError = null;
    });

    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);

    final hasPassword = ref.read(currentCustomerProvider)?.hasPassword ?? true;

    try {
      final session = await ref.read(customerRepositoryProvider).changePassword(
            currentPassword: hasPassword ? _currentController.text : null,
            newPassword: _newController.text,
          );

      // Replaces the token the server just invalidated.
      await ref.read(authControllerProvider.notifier).adoptSession(session);

      if (!mounted) return;
      AppFeedback.showSuccess(
        context,
        'Password updated. Other devices have been signed out.',
      );
      context.pop();
    } on ApiException catch (error) {
      if (!mounted) return;

      switch (error.code) {
        case 'CURRENT_PASSWORD_INVALID':
        case 'CURRENT_PASSWORD_REQUIRED':
          setState(() => _currentError = error.message);
        case 'WEAK_PASSWORD':
          setState(() => _newError = error.message);
        case ApiException.validation:
          setState(() {
            _currentError = error.fieldErrors['currentPassword'];
            _newError = error.fieldErrors['newPassword'];
          });
          if (_currentError == null && _newError == null) {
            AppFeedback.showError(context, error);
          }
        default:
          AppFeedback.showError(context, error);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPassword = ref.watch(currentCustomerProvider)?.hasPassword ?? true;

    return Scaffold(
      appBar: AppBar(title: Text(hasPassword ? 'Change password' : 'Set a password')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.pageGutter),
          children: [
            Text(
              hasPassword
                  ? 'Choose a new password. You will stay signed in here, and be signed out '
                      'everywhere else.'
                  : 'Set a password so you can sign in without waiting for a one-time code.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),

            if (hasPassword) ...[
              AppTextField(
                controller: _currentController,
                label: 'Current password',
                obscureText: true,
                prefixIcon: Icons.lock_clock_outlined,
                textInputAction: TextInputAction.next,
                serverError: _currentError,
                onChanged: (_) {
                  if (_currentError != null) setState(() => _currentError = null);
                },
                validator: Validators.passwordPresent,
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            AppTextField(
              controller: _newController,
              label: 'New password',
              helperText: 'At least 8 characters, with a letter and a number.',
              obscureText: true,
              prefixIcon: Icons.lock_outline_rounded,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              serverError: _newError,
              onChanged: (_) {
                if (_newError != null) setState(() => _newError = null);
              },
              validator: (value) {
                final strength = Validators.password(value);
                if (strength != null) return strength;
                if (hasPassword && value == _currentController.text) {
                  return 'Choose a password different from your current one.';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.lg),

            AppTextField(
              controller: _confirmController,
              label: 'Confirm new password',
              obscureText: true,
              prefixIcon: Icons.lock_reset_rounded,
              textInputAction: TextInputAction.done,
              validator: (value) => Validators.confirmPassword(value, _newController.text),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: AppSpacing.xxl),

            PrimaryButton(
              label: hasPassword ? 'Change password' : 'Set password',
              isLoading: _isSaving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
