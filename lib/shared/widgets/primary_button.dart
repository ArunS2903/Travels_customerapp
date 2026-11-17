import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// The main call-to-action, painted in the brand gradient.
///
/// Owns its own busy state so no screen reinvents "disable the button, swap the
/// label for a spinner, keep the height from jumping". The height is fixed
/// across both states, which is what stops the layout shifting on tap.
///
/// The gradient lives here rather than in `AppTheme` because `ThemeData` has
/// nowhere to put one: `ElevatedButton.styleFrom` takes flat colours. So the
/// button is an [Ink] gradient with a transparent [ElevatedButton] over it,
/// which keeps the ripple, the focus ring and the disabled state that
/// Material gives for free - a hand-rolled [GestureDetector] would lose all
/// three. When disabled the gradient is dropped entirely and the theme's flat
/// disabled colour shows through, because a greyed gradient still reads as an
/// available button.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.trailing,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;

  /// While true the button shows a spinner and ignores taps - the guard against
  /// the double-submit that would otherwise create two bookings.
  final bool isLoading;

  final IconData? icon;

  /// Shown at the trailing edge, e.g. the fare on "Confirm booking".
  final Widget? trailing;

  final bool expand;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null && !isLoading;

    final content = isLoading
        ? const SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: AppSpacing.sm),
              ],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.md),
                trailing!,
              ],
            ],
          );

    // A loading button keeps the gradient: it is still the live action, just
    // busy, and draining the colour would read as "this has been disabled".
    final showsGradient = isEnabled || isLoading;

    final button = ElevatedButton(
      onPressed: isEnabled ? onPressed : null,
      style: showsGradient
          ? ElevatedButton.styleFrom(
              // Transparent so the Ink gradient underneath is what is seen;
              // the shadow goes with it, because a gradient surface with a
              // Material elevation shadow reads as two overlapping shapes.
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.transparent,
              disabledForegroundColor: Colors.white70,
              shadowColor: Colors.transparent,
            )
          : null,
      child: content,
    );

    final shape = BorderRadius.circular(AppRadius.md);

    final decorated = showsGradient
        ? Ink(
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: shape,
            ),
            child: button,
          )
        : button;

    return expand ? SizedBox(width: double.infinity, child: decorated) : decorated;
  }
}

/// Secondary action, same ergonomics as [PrimaryButton].
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.isDestructive = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  /// Colours the label and border red, for "Cancel booking" and similar.
  final bool isDestructive;

  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEnabled = onPressed != null && !isLoading;

    final button = OutlinedButton(
      onPressed: isEnabled ? onPressed : null,
      style: isDestructive
          ? OutlinedButton.styleFrom(
              foregroundColor: colorScheme.error,
              side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
            )
          : null,
      child: isLoading
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ],
            ),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
