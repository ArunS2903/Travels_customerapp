import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';

/// Every remote image in the app.
///
/// Three things it does that a bare [Image.network] does not, each of which was
/// a real defect on the vehicle screens:
///
/// **It resolves the URL.** The backend serves a locally stored photo as a
/// root-relative path, and rows written before that change still carry an
/// absolute `localhost` URL. Either one is unfetchable from a phone as-is.
/// [AppConfig.resolveMediaUrl] turns both into something on the API's own
/// origin, which the device can reach by definition.
///
/// **It decodes at display size.** A 3000px photograph shown in a 400px-wide
/// card costs about 36MB of RAM decoded at full size and under 1MB at display
/// size. With five photos in a gallery the difference is the whole image cache,
/// and an exhausted cache means every swipe back re-downloads and re-decodes.
/// `cacheWidth` is the single highest-value line in this file.
///
/// **It fails visibly but calmly.** A customer comparing vehicles on a thin
/// connection should see a car-shaped placeholder, not a grid of broken-image
/// icons, and should see *something* immediately rather than a blank box.
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholderIcon = Icons.directions_car_filled_rounded,

    /// The width this image is painted at, in logical pixels. Used to pick the
    /// decode resolution; pass the layout width, not the source width.
    this.displayWidth,
  });

  final String? url;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final IconData placeholderIcon;
  final double? displayWidth;

  @override
  Widget build(BuildContext context) {
    final resolved = AppConfig.resolveMediaUrl(url);

    if (resolved == null) {
      return _wrap(_ImagePlaceholder(icon: placeholderIcon));
    }

    /// Decode width in *device* pixels, which is what `cacheWidth` expects.
    ///
    /// Capped so an unusually wide layout cannot ask for a decode larger than
    /// the source would have been anyway, and left null when the caller does
    /// not know its width — a wrong guess is worse than the default.
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = displayWidth == null
        ? null
        : (displayWidth! * ratio).round().clamp(64, 2048);

    return _wrap(
      Image.network(
        resolved,
        fit: fit,
        cacheWidth: cacheWidth,
        // Fades in rather than popping, which reads better in a carousel.
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: child,
          );
        },
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _ImagePlaceholder(
            icon: placeholderIcon,
            // A determinate bar once the total is known: on a slow connection
            // "43%" is reassurance that a spinner cannot give.
            progress: progress.expectedTotalBytes == null
                ? null
                : progress.cumulativeBytesLoaded / progress.expectedTotalBytes!,
          );
        },
        errorBuilder: (context, error, stack) =>
            const _ImagePlaceholder(icon: Icons.image_not_supported_outlined),
      ),
    );
  }

  Widget _wrap(Widget child) {
    if (borderRadius == null) return child;
    return ClipRRect(borderRadius: borderRadius!, child: child);
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.icon, this.progress});

  final IconData icon;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: progress == null
            ? Icon(icon, size: 32, color: theme.colorScheme.onSurfaceVariant)
            : SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2, value: progress),
              ),
      ),
    );
  }
}
