import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/models/place.dart';

/// Non-interactive map on the home screen.
///
/// Gestures are disabled on purpose. It sits inside a scrolling page, so a pan
/// gesture would be ambiguous - and the real map interactions belong on the
/// picker screen. Tapping it opens that screen.
///
/// Without a Maps key the map renders as a blank tile, so we draw a labelled
/// placeholder instead of leaving a grey rectangle that looks like a bug.
class HomeMapPreview extends StatefulWidget {
  const HomeMapPreview({
    super.key,
    required this.pickup,
    required this.destination,
    this.onTap,
    this.height = 170,
  });

  final Place? pickup;
  final Place? destination;
  final VoidCallback? onTap;
  final double height;

  @override
  State<HomeMapPreview> createState() => _HomeMapPreviewState();
}

class _HomeMapPreviewState extends State<HomeMapPreview> {
  GoogleMapController? _controller;

  @override
  void didUpdateWidget(HomeMapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);

    final pickupChanged = oldWidget.pickup != widget.pickup;
    final destinationChanged = oldWidget.destination != widget.destination;
    if (pickupChanged || destinationChanged) _fitToPoints();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Frames whichever points exist: both ends when a trip is set up, otherwise
  /// just the pickup.
  Future<void> _fitToPoints() async {
    final controller = _controller;
    if (controller == null) return;

    final pickup = widget.pickup;
    final destination = widget.destination;
    if (pickup == null) return;

    if (destination == null) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(pickup.latitude, pickup.longitude), 15),
      );
      return;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(
        pickup.latitude < destination.latitude ? pickup.latitude : destination.latitude,
        pickup.longitude < destination.longitude ? pickup.longitude : destination.longitude,
      ),
      northeast: LatLng(
        pickup.latitude > destination.latitude ? pickup.latitude : destination.latitude,
        pickup.longitude > destination.longitude ? pickup.longitude : destination.longitude,
      ),
    );

    // A short delay lets the map finish laying out; fitting bounds before that
    // throws on some Android versions.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 56));
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    final pickup = widget.pickup;
    final destination = widget.destination;

    if (pickup != null) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(pickup.latitude, pickup.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Pickup'),
      ));
    }

    if (destination != null) {
      markers.add(Marker(
        markerId: const MarkerId('destination'),
        position: LatLng(destination.latitude, destination.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Destination'),
      ));
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final pickup = widget.pickup;

    final body = AppConfig.googleMapsApiKey.isEmpty
        ? const _MapPlaceholder()
        : pickup == null
            ? const _MapPlaceholder(message: 'Finding your location')
            : GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(pickup.latitude, pickup.longitude),
                  zoom: 15,
                ),
                onMapCreated: (controller) {
                  _controller = controller;
                  _fitToPoints();
                },
                markers: _buildMarkers(),
                // A preview, not a map: no gestures, no controls.
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                myLocationButtonEnabled: false,
                compassEnabled: false,
                scrollGesturesEnabled: false,
                zoomGesturesEnabled: false,
                tiltGesturesEnabled: false,
                rotateGesturesEnabled: false,
                liteModeEnabled: true,
              );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            body,
            // An overlay captures the tap, since the map itself is inert.
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                child: const SizedBox.expand(),
              ),
            ),
            if (widget.onTap != null)
              Positioned(
                right: AppSpacing.sm,
                bottom: AppSpacing.sm,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm - 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.edit_location_alt_outlined, size: 15),
                      const SizedBox(width: 6),
                      Text(
                        'Adjust pickup',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Stand-in for the map when it cannot render, with the reason stated.
class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMissingKey = AppConfig.googleMapsApiKey.isEmpty;

    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isMissingKey ? Icons.map_outlined : Icons.my_location_rounded,
                size: 30,
                color: AppColors.amberDark,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message ??
                    (isMissingKey
                        ? 'Map preview needs a Google Maps key'
                        : 'Map unavailable'),
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              if (isMissingKey && message == null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Booking still works without it.',
                  style: theme.textTheme.labelSmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
