import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/models/place.dart';

/// Non-interactive map on the home screen.
///
/// Gestures are disabled on purpose. It sits inside a scrolling page, so a pan
/// gesture would be ambiguous — and the real map interactions belong on the
/// picker screen. Tapping it opens that screen.
///
/// Why the map is built before there is a pickup
/// ---------------------------------------------
/// This widget used to render a "Finding your location" placeholder whenever
/// `pickup` was null, and only build a [GoogleMap] once a fix arrived. That
/// made the map's existence conditional on something that routinely never
/// happens: permission denied, location services off, an emulator with no
/// position set, or simply a slow first fix. The result was a home screen with
/// no map at all and nothing to say why.
///
/// So the map is built immediately, centred on [AppConfig.defaultLatitude] /
/// [AppConfig.defaultLongitude], and the camera moves to the real position when
/// one arrives. A map of roughly the right city is useful; a grey box is not.
/// The "finding your location" message becomes a chip *over* the map rather
/// than a replacement for it.
///
/// The Maps SDK key is configured natively, in `android/local.properties`. It
/// is separate from the Places key passed by `--dart-define`, and must not
/// determine whether this map is shown — a build with no Places key still has
/// a perfectly good map.
class HomeMapPreview extends StatefulWidget {
  const HomeMapPreview({
    super.key,
    required this.pickup,
    required this.destination,
    this.onTap,
    this.height = 170,
    this.isLocating = false,
  });

  final Place? pickup;
  final Place? destination;
  final VoidCallback? onTap;
  final double height;

  /// True while a location fix is still being sought, so the overlay can say so
  /// without the map having to disappear.
  final bool isLocating;

  @override
  State<HomeMapPreview> createState() => _HomeMapPreviewState();
}

class _HomeMapPreviewState extends State<HomeMapPreview> {
  GoogleMapController? _controller;

  /// Set once the platform view reports itself ready. Camera moves before this
  /// throw on Android, which is what the old `Future.delayed` was guessing at.
  bool _isMapReady = false;

  @override
  void didUpdateWidget(HomeMapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.pickup != widget.pickup ||
        oldWidget.destination != widget.destination) {
      _fitToPoints();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Where the map opens, before any fix: the customer's pickup if it is
  /// already known, otherwise the operator's own city.
  CameraPosition get _initialCamera {
    final pickup = widget.pickup;
    return CameraPosition(
      target: pickup == null
          ? const LatLng(AppConfig.defaultLatitude, AppConfig.defaultLongitude)
          : LatLng(pickup.latitude, pickup.longitude),
      zoom: pickup == null ? 11 : 15,
    );
  }

  /// Frames whichever points exist: both ends when a journey is set up,
  /// otherwise just the pickup.
  ///
  /// Awaits [_isMapReady] rather than a fixed delay. A timer long enough to be
  /// safe on a slow device is long enough to be visible on a fast one, and one
  /// short enough to feel instant throws on Android.
  Future<void> _fitToPoints() async {
    final controller = _controller;
    if (controller == null || !_isMapReady) return;

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
        infoWindow: const InfoWindow(title: 'Drop'),
      ));
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final showLocating = widget.pickup == null && widget.isLocating;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GoogleMap(
              initialCameraPosition: _initialCamera,
              onMapCreated: (controller) {
                _controller = controller;
                _isMapReady = true;
                _fitToPoints();
              },
              markers: _buildMarkers(),
              // A preview, not a map: no gestures, no controls.
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              myLocationButtonEnabled: false,
              myLocationEnabled: false,
              compassEnabled: false,
              scrollGesturesEnabled: false,
              zoomGesturesEnabled: false,
              tiltGesturesEnabled: false,
              rotateGesturesEnabled: false,
              /// Lite mode is deliberately off.
              ///
              /// It renders a static snapshot and is Android-only, and in that
              /// mode a map that fails to snapshot shows as a flat grey panel
              /// with no error — indistinguishable from a missing API key. A
              /// full map with every gesture disabled behaves the same for the
              /// customer and actually draws.
              liteModeEnabled: false,
            ),

            // An overlay captures the tap, since the map itself is inert.
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                child: const SizedBox.expand(),
              ),
            ),

            if (showLocating)
              const Positioned(
                left: AppSpacing.sm,
                top: AppSpacing.sm,
                child: _MapChip(
                  icon: Icons.my_location_rounded,
                  label: 'Finding your location',
                  showSpinner: true,
                ),
              ),

            if (widget.onTap != null)
              Positioned(
                right: AppSpacing.sm,
                bottom: AppSpacing.sm,
                child: _MapChip(
                  icon: Icons.edit_location_alt_outlined,
                  label: widget.pickup == null ? 'Set pickup' : 'Adjust pickup',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A small label floating over the map. Opaque enough to stay legible on
/// satellite-dark or road-light tiles alike.
class _MapChip extends StatelessWidget {
  const _MapChip({
    required this.icon,
    required this.label,
    this.showSpinner = false,
  });

  final IconData icon;
  final String label;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm - 2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
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
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSpinner)
            const SizedBox(
              height: 12,
              width: 12,
              child: CircularProgressIndicator(strokeWidth: 1.8),
            )
          else
            Icon(icon, size: 15, color: AppColors.amberDark),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
