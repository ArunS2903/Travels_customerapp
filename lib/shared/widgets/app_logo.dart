import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// The PP Travels & Cab mark.
///
/// The asset is the real logo rather than a drawn approximation, because the
/// mark is two interlocking Ps on a gradient ring and nothing built from an
/// [Icon] would be recognisable as it.
///
/// It falls back to a gradient badge if the asset cannot be decoded. That is
/// not defensive padding: an app whose splash screen is a grey error box
/// because someone moved a file is worse than one that shows a plain brand
/// badge, and the fallback costs four lines.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 56,
    this.showWordmark = false,
    this.wordmark,
    this.wordmarkStyle,
  });

  final double size;
  final bool showWordmark;

  /// Business name, when known. Falls back to the product name so the splash
  /// screen renders before the business-contact call returns.
  final String? wordmark;

  final TextStyle? wordmarkStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final mark = SizedBox(
      height: size,
      width: size,
      child: Image.asset(
        'assets/images/logo_mark.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _FallbackBadge(size: size),
      ),
    );

    if (!showWordmark) return mark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(height: AppSpacing.lg),
        Text(
          wordmark ?? 'PP Travels & Cab',
          style: wordmarkStyle ?? theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// The full lock-up: the mark above the wordmark, as the logo file draws it.
/// Used on the splash and the sign-in screens, where there is room for it.
class AppLogoLockup extends StatelessWidget {
  const AppLogoLockup({super.key, this.width = 220});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Image.asset(
        'assets/images/logo.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => AppLogo(size: width * 0.5, showWordmark: true),
      ),
    );
  }
}

/// Shown only if the logo asset is missing or undecodable.
class _FallbackBadge extends StatelessWidget {
  const _FallbackBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        'PP',
        style: TextStyle(
          fontSize: size * 0.38,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}

/// Paints its child in the brand gradient.
///
/// Used for headline text on the sign-in and splash screens, where the mark's
/// sweep running through the words ties the two together. Restricted to large,
/// bold text by convention - a gradient on body copy is unreadable, and the
/// shader makes contrast impossible to reason about.
class BrandGradientText extends StatelessWidget {
  const BrandGradientText(this.text, {super.key, this.style, this.textAlign});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      // srcIn keeps the gradient only where the glyphs are, so the surrounding
      // box stays transparent rather than becoming a coloured rectangle.
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => AppColors.brandGradientHorizontal.createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      child: Text(
        text,
        textAlign: textAlign,
        // The colour here is irrelevant to the result but must be opaque, or
        // the mask has nothing to tint.
        style: (style ?? const TextStyle()).copyWith(color: Colors.white),
      ),
    );
  }
}
