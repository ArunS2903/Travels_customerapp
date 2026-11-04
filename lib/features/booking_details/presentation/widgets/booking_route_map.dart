import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/polyline_decoder.dart';
import '../../models/booking.dart';

/// The booking's route, drawn from the polyline the backend stored at booking
/// time.
///
/// Using the stored polyline rather than re-requesting directions means the map
/// shows the route the fare was actually based on, costs no API quota, and
/// works for a trip taken months ago. When no polyline was stored (the server
/// had no Maps key) we fall back to a straight line between the two points and
/// label it, so the picture does not imply a precision it lacks.
class BookingRouteMap extends StatefulWidget {
  const BookingRouteMap({super.key, required this.booking, this.height = 180});

  final Booking booking;
  final double height;

  @override
  State<BookingRouteMap> createState() => _BookingRouteMapState();
}

class _BookingRouteMapState extends State<BookingRouteMap> {
  GoogleMapController? _controller;

  /// Set once the platform view reports itself ready. Fitting bounds before
  /// that throws on Android, which is what the old fixed delay was guessing at.
  bool _isMapReady = false;

  late final List<LatLng> _routePoints;
  late final bool _isStraightLine;

  LatLng get _pickup =>
      LatLng(widget.booking.pickup.latitude, widget.booking.pickup.longitude);

  LatLng get _destination =>
      LatLng(widget.booking.destination.latitude, widget.booking.destination.longitude);

  @override
  void initState() {
    super.initState();

    final decoded = PolylineDecoder.decode(widget.booking.routePolyline);
    _isStraightLine = decoded.length < 2;
    _routePoints = _isStraightLine ? [_pickup, _destination] : decoded;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _fitRoute() async {
    if (!_isMapReady) return;

    final bounds = PolylineDecoder.boundsFor(_routePoints);
    if (bounds == null) return;

    await _controller?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 46));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: _pickup, zoom: 13),
              onMapCreated: (controller) {
                _controller = controller;
                _isMapReady = true;
                _fitRoute();
              },
              markers: {
                Marker(
                  markerId: const MarkerId('pickup'),
                  position: _pickup,
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                  infoWindow: InfoWindow(
                    title: 'Pickup',
                    snippet: widget.booking.pickup.shortAddress,
                  ),
                ),
                Marker(
                  markerId: const MarkerId('destination'),
                  position: _destination,
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                  infoWindow: InfoWindow(
                    title: 'Destination',
                    snippet: widget.booking.destination.shortAddress,
                  ),
                ),
              },
              polylines: {
                Polyline(
                  polylineId: const PolylineId('route'),
                  points: _routePoints,
                  color: AppColors.route,
                  width: 4,
                  // A dashed line signals "not the real road route".
                  patterns: _isStraightLine
                      ? [PatternItem.dash(14), PatternItem.gap(8)]
                      : const [],
                ),
              },
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              myLocationButtonEnabled: false,
              compassEnabled: false,
              scrollGesturesEnabled: false,
              zoomGesturesEnabled: false,
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              myLocationEnabled: false,
              /// Off for the same reason as on the home preview: lite mode is
              /// Android-only and a failed snapshot renders as a featureless
              /// grey panel, which is indistinguishable from a missing API key.
              liteModeEnabled: false,
            ),
            if (_isStraightLine)
              Positioned(
                left: AppSpacing.sm,
                bottom: AppSpacing.sm,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    'Direct line, not the driving route',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
