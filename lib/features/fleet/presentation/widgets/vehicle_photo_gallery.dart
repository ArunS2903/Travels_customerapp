import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_network_image.dart';

/// A swipeable strip of a vehicle's photographs with page dots, which opens a
/// full-screen viewer on tap.
///
/// Used on both the vehicle details screen and the Booked Details screen, so a
/// customer looking at a past hire sees its photographs the same way they saw
/// them when choosing.
class VehiclePhotoGallery extends StatefulWidget {
  const VehiclePhotoGallery({
    super.key,
    required this.photoUrls,
    this.height = 220,
    this.heroTitle,
    this.borderRadius,
  });

  final List<String> photoUrls;
  final double height;

  /// Shown in the full-screen viewer's app bar, so the customer knows which
  /// vehicle they are looking at after swiping through several.
  final String? heroTitle;

  final BorderRadius? borderRadius;

  @override
  State<VehiclePhotoGallery> createState() => _VehiclePhotoGalleryState();
}

class _VehiclePhotoGalleryState extends State<VehiclePhotoGallery> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openViewer(int initialIndex) {
    if (widget.photoUrls.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VehiclePhotoViewer(
          photoUrls: widget.photoUrls,
          initialIndex: initialIndex,
          title: widget.heroTitle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = widget.borderRadius ?? BorderRadius.circular(AppRadius.md);
    final photos = widget.photoUrls;

    if (photos.isEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: const AppNetworkImage(url: null),
        ),
      );
    }

    return Column(
      children: [
        ClipRRect(
          borderRadius: radius,
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: Stack(
              children: [
                PageView.builder(
                  controller: _controller,
                  itemCount: photos.length,
                  onPageChanged: (index) => setState(() => _page = index),
                  itemBuilder: (context, index) => GestureDetector(
                    onTap: () => _openViewer(index),
                    child: AppNetworkImage(
                      url: photos[index],
                      // Decoded for the strip, not for the full-screen viewer:
                      // the gallery is the width of the screen.
                      displayWidth: MediaQuery.sizeOf(context).width,
                    ),
                  ),
                ),

                // The counter is the affordance for "there are more of these",
                // which page dots alone do not convey past about five photos.
                if (photos.length > 1)
                  Positioned(
                    right: AppSpacing.sm,
                    bottom: AppSpacing.sm,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm + 2,
                          vertical: 3,
                        ),
                        child: Text(
                          '${_page + 1} / ${photos.length}',
                          style: theme.textTheme.labelSmall?.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                  ),

                Positioned(
                  left: AppSpacing.sm,
                  bottom: AppSpacing.sm,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm + 2,
                        vertical: 3,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.fullscreen_rounded, size: 13, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            'Tap to enlarge',
                            style: TextStyle(fontSize: 11, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (photos.length > 1) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < photos.length; index++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: 6,
                  width: index == _page ? 18 : 6,
                  decoration: BoxDecoration(
                    color: index == _page
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Every photograph, full screen, swipeable and zoomable.
///
/// Zoom is the point of opening a photo at all: the customer is checking the
/// condition of a car they are about to pay for, and a 220-pixel-high strip
/// cannot answer that question.
class VehiclePhotoViewer extends StatefulWidget {
  const VehiclePhotoViewer({
    super.key,
    required this.photoUrls,
    this.initialIndex = 0,
    this.title,
  });

  final List<String> photoUrls;
  final int initialIndex;
  final String? title;

  @override
  State<VehiclePhotoViewer> createState() => _VehiclePhotoViewerState();
}

class _VehiclePhotoViewerState extends State<VehiclePhotoViewer> {
  late final PageController _controller;
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = widget.initialIndex.clamp(0, widget.photoUrls.length - 1);
    _controller = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.photoUrls.length > 1
              ? '${widget.title ?? 'Photo'}  ${_page + 1}/${widget.photoUrls.length}'
              : (widget.title ?? 'Photo'),
          style: const TextStyle(color: Colors.white, fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.photoUrls.length,
        onPageChanged: (index) => setState(() => _page = index),
        itemBuilder: (context, index) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            // No `displayWidth`: this one is zoomable, so it is the one place
          // that genuinely wants the full-resolution decode.
          child: AppNetworkImage(url: widget.photoUrls[index], fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
