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
import '../../../shared/widgets/section_card.dart';
import '../../authentication/models/auth_session.dart';
import '../../authentication/presentation/otp_screen.dart';
import '../../authentication/providers/auth_controller.dart';

/// Edit the name, mobile number and email address.
///
/// Changing a *verified* identifier requires proving the new one: this screen
/// sends an OTP to the new value, collects it on the OTP screen, and submits
/// the resulting one-use token with the update. Without that, a stolen session
/// could move the account onto an attacker's number and keep it via OTP login.
///
/// The name needs no verification, and an unverified email can be corrected
/// freely - requiring a code sent to an address that never worked would trap
/// the customer.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;

  bool _isSaving = false;
  final Map<String, String?> _fieldErrors = {};

  @override
  void initState() {
    super.initState();
    final customer = ref.read(currentCustomerProvider);

    _nameController = TextEditingController(text: customer?.fullName ?? '');
    _phoneController = TextEditingController(text: customer?.phone ?? '');
    _emailController = TextEditingController(text: customer?.email ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  /// Sends an OTP to [identifier] and returns the verification token once the
  /// customer enters the code, or null if they backed out.
  Future<String?> _verifyNewIdentifier({
    required String identifier,
    required OtpPurpose purpose,
  }) async {
    try {
      final challenge = await ref.read(authRepositoryProvider).sendOtp(
            identifier: identifier,
            purpose: purpose,
          );

      if (!mounted) return null;

      return await context.push<String>(
        AppRoutes.otp,
        extra: OtpScreenArgs(
          identifier: identifier,
          purpose: purpose,
          challenge: challenge,
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return null;
      AppFeedback.showError(context, error);
      return null;
    }
  }

  Future<void> _save() async {
    setState(_fieldErrors.clear);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final customer = ref.read(currentCustomerProvider);
    if (customer == null) return;

    final newName = _nameController.text.trim();
    final newPhoneRaw = _phoneController.text.trim();
    final newEmail = _emailController.text.trim().toLowerCase();

    final newPhone =
        newPhoneRaw.isEmpty ? null : Validators.normalizePhone(newPhoneRaw);

    final nameChanged = newName != customer.fullName;
    final phoneChanged = newPhone != null && newPhone != customer.phone;
    final emailChanged = newEmail.isNotEmpty && newEmail != (customer.email ?? '');

    if (!nameChanged && !phoneChanged && !emailChanged) {
      AppFeedback.showInfo(context, 'Nothing has changed.');
      return;
    }

    // Only one identifier change at a time: each needs its own verification
    // token, and the API takes a single token per request.
    if (phoneChanged && emailChanged) {
      AppFeedback.showInfo(
        context,
        'Change your mobile number and email one at a time, so each can be verified.',
      );
      return;
    }

    FocusScope.of(context).unfocus();

    String? verificationToken;

    if (phoneChanged) {
      final confirmed = await AppFeedback.confirm(
        context,
        title: 'Change your mobile number?',
        message:
            'We will text a code to $newPhone to confirm it is yours before making the change.',
        confirmLabel: 'Send code',
      );
      if (!confirmed || !mounted) return;

      verificationToken = await _verifyNewIdentifier(
        identifier: newPhone,
        purpose: OtpPurpose.verifyPhone,
      );
      if (verificationToken == null || !mounted) return;
    } else if (emailChanged && customer.emailVerified) {
      final confirmed = await AppFeedback.confirm(
        context,
        title: 'Change your email address?',
        message: 'We will email a code to $newEmail to confirm it is yours.',
        confirmLabel: 'Send code',
      );
      if (!confirmed || !mounted) return;

      verificationToken = await _verifyNewIdentifier(
        identifier: newEmail,
        purpose: OtpPurpose.verifyEmail,
      );
      if (verificationToken == null || !mounted) return;
    }

    setState(() => _isSaving = true);

    try {
      final updated = await ref.read(customerRepositoryProvider).updateProfile(
            fullName: nameChanged ? newName : null,
            phone: phoneChanged ? newPhone : null,
            email: emailChanged ? newEmail : null,
            verificationToken: verificationToken,
          );

      await ref.read(authControllerProvider.notifier).updateCustomer(updated);

      if (!mounted) return;
      AppFeedback.showSuccess(context, 'Your details have been updated.');
      context.pop();
    } on ApiException catch (error) {
      if (!mounted) return;

      if (error.code == ApiException.validation ||
          error.code == 'PHONE_TAKEN' ||
          error.code == 'EMAIL_TAKEN') {
        setState(() {
          error.fieldErrors.forEach((key, value) => _fieldErrors[key] = value);
          final field = error.details?['field'] as String?;
          if (field != null) _fieldErrors[field] = error.message;
        });
        _formKey.currentState?.validate();
      } else {
        AppFeedback.showError(context, error);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Sends a verification code for an email that is already on the account.
  Future<void> _verifyExistingEmail() async {
    final customer = ref.read(currentCustomerProvider);
    final email = customer?.email;
    if (email == null || email.isEmpty) return;

    final token = await _verifyNewIdentifier(
      identifier: email,
      purpose: OtpPurpose.verifyEmail,
    );

    if (token == null || !mounted) return;

    // The backend flips `emailVerified` when the OTP is verified, so just
    // re-read the profile.
    await ref.read(authControllerProvider.notifier).refreshProfile();
    if (mounted) AppFeedback.showSuccess(context, 'Your email address is verified.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customer = ref.watch(currentCustomerProvider);

    if (customer == null) {
      return Scaffold(appBar: AppBar(title: const Text('Personal details')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Personal details')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.pageGutter),
          children: [
            AppTextField(
              controller: _nameController,
              label: 'Full name',
              prefixIcon: Icons.badge_outlined,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              serverError: _fieldErrors['fullName'],
              onChanged: (_) {
                if (_fieldErrors['fullName'] != null) {
                  setState(() => _fieldErrors['fullName'] = null);
                }
              },
              validator: Validators.fullName,
            ),
            const SizedBox(height: AppSpacing.lg),

            AppTextField(
              controller: _phoneController,
              label: 'Mobile number',
              helperText: customer.phoneVerified
                  ? 'Changing this needs a code sent to the new number.'
                  : 'We will text a code to confirm this number.',
              prefixIcon: Icons.smartphone_rounded,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s]')),
                LengthLimitingTextInputFormatter(16),
              ],
              serverError: _fieldErrors['phone'],
              onChanged: (_) {
                if (_fieldErrors['phone'] != null) {
                  setState(() => _fieldErrors['phone'] = null);
                }
              },
              validator: (value) {
                final phone = (value ?? '').trim();
                if (phone.isEmpty) {
                  // Removing the only identifier would lock the account out.
                  return (customer.email ?? '').isEmpty
                      ? 'Keep a mobile number on your account.'
                      : null;
                }
                return Validators.phone(phone);
              },
            ),
            const SizedBox(height: AppSpacing.lg),

            AppTextField(
              controller: _emailController,
              label: 'Email address',
              helperText: customer.emailVerified
                  ? 'Changing this needs a code sent to the new address.'
                  : 'Not verified yet.',
              prefixIcon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              serverError: _fieldErrors['email'],
              onChanged: (_) {
                if (_fieldErrors['email'] != null) {
                  setState(() => _fieldErrors['email'] = null);
                }
              },
              validator: (value) {
                final email = (value ?? '').trim();
                if (email.isEmpty) {
                  return (customer.phone ?? '').isEmpty
                      ? 'Keep an email address on your account.'
                      : null;
                }
                return Validators.email(email);
              },
            ),

            if ((customer.email ?? '').isNotEmpty && !customer.emailVerified) ...[
              const SizedBox(height: AppSpacing.md),
              SecondaryButton(
                label: 'Verify my email address',
                icon: Icons.mark_email_read_outlined,
                onPressed: _verifyExistingEmail,
              ),
            ],

            const SizedBox(height: AppSpacing.xxl),
            PrimaryButton(
              label: 'Save changes',
              isLoading: _isSaving,
              onPressed: _save,
            ),

            const SizedBox(height: AppSpacing.xxl),
            SectionCard(
              title: 'Why we ask for a code',
              icon: Icons.shield_outlined,
              child: Text(
                'Your mobile number and email can be used to sign in, so we confirm a new one '
                'belongs to you before changing it. This keeps someone who gets hold of your '
                'phone from taking over the account.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
