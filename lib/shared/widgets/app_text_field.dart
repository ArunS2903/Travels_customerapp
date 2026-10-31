import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_spacing.dart';

/// The app's text field.
///
/// Wraps [TextFormField] to add the two things every form here needs: a
/// show/hide toggle for passwords, and a `serverError` that takes precedence
/// over the local validator. The second matters because the backend knows
/// things the client cannot - "that number is already registered" - and that
/// message should appear under the offending field, not in a snackbar.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.helperText,
    this.validator,
    this.serverError,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.prefixIcon,
    this.suffix,
    this.maxLength,
    this.maxLines = 1,
    this.enabled = true,
    this.autofocus = false,
    this.inputFormatters,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helperText;
  final String? Function(String?)? validator;

  /// A field error returned by the API. Shown until the customer edits the
  /// field, at which point the caller clears it.
  final String? serverError;

  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final IconData? prefixIcon;
  final Widget? suffix;
  final int? maxLength;
  final int maxLines;
  final bool enabled;
  final bool autofocus;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextCapitalization textCapitalization;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final isPassword = widget.obscureText;

    return TextFormField(
      controller: widget.controller,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      obscureText: isPassword && _obscured,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      maxLength: widget.maxLength,
      maxLines: isPassword ? 1 : widget.maxLines,
      inputFormatters: widget.inputFormatters,
      autofillHints: widget.autofillHints,
      textCapitalization: widget.textCapitalization,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      // A server error wins: it is the more informed of the two.
      validator: (value) => widget.serverError ?? widget.validator?.call(value),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        helperText: widget.helperText,
        // Reserve the helper line so the field does not grow when an error
        // appears and push the rest of the form down.
        helperMaxLines: 2,
        errorText: widget.serverError,
        prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon, size: 20),
        counterText: '',
        suffixIcon: isPassword
            ? IconButton(
                onPressed: () => setState(() => _obscured = !_obscured),
                icon: Icon(
                  _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 20,
                ),
                tooltip: _obscured ? 'Show password' : 'Hide password',
              )
            : widget.suffix,
      ),
    );
  }
}

/// A read-only field that behaves like a button, for "tap to choose" inputs
/// such as a pickup address or a scheduled time.
class AppPickerField extends StatelessWidget {
  const AppPickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.placeholder = 'Tap to choose',
    this.prefixIcon,
    this.trailingIcon = Icons.chevron_right_rounded,
    this.isEmpty = false,
    this.enabled = true,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final String placeholder;
  final IconData? prefixIcon;
  final IconData? trailingIcon;

  /// When true the [placeholder] styling is used instead of the value styling.
  final bool isEmpty;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        constraints: const BoxConstraints(minHeight: 64),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: colorScheme.outline),
        ),
        child: Row(
          children: [
            if (prefixIcon != null) ...[
              Icon(prefixIcon, size: 20, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label, style: theme.textTheme.labelSmall),
                  const SizedBox(height: 2),
                  Text(
                    isEmpty ? placeholder : value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isEmpty ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
                      fontWeight: isEmpty ? FontWeight.w400 : FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (trailingIcon != null)
              Icon(trailingIcon, size: 22, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
