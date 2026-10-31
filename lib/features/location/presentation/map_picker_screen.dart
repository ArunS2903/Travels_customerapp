import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/models/place.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/primary_button.dart';
import '../data/location_service.dart';
import '../providers/location_providers.dart';
import 'place_search_screen.dart';

class MapPickerArgs {
  const MapPickerArgs({
    this.target = PlaceSearchTarget.destination,
    this.initialLatitude,
    this.initialLongitude,
    this.initialAddress,
  });

  final PlaceSearchTarget target;
  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialAddress;

  String get title =>
      target == PlaceSearchTarget.pickup ? 'Set pickup point' : 'Set destination';

  String get confirmLabel =>
      target == PlaceSearchTarget.pickup ? 'Confirm pickup' : 'Confirm destination';
}

/// Drop a pin on the map.
///
/// The pin is fixed in the centre of the viewport and the *map* moves beneath
/// it, which is how every mapping app does this - dragging a marker with a
/// thumb hides the very spot being chosen.
///
/// Reverse geocoding is deferred until the map settles (`onCameraIdle`) rather
/// than run on every frame, so panning stays smooth and we make one lookup
/// instead of hundreds.
class MapPickerScreen extends ConsumerStatefulWidget {
  const MapPickerScreen({super.key, required this.args});

  final MapPickerArgs args;

  @override
  ConsumerState<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends ConsumerState<MapPickerScreen> {
  GoogleMapController? _mapController;

  late LatLng _target;
  String? _address;
  bool _isGeocoding = false;
  bool _isMoving = false;
  bool _isLocating = false;

  /// Guards against an in-flight geocode for a position the customer has
  /// already panned away from overwriting the current address.
  int _geocodeGeneration = 0;

  @override
  void initState() {
    super.initState();

    _target = LatLng(
      widget.args.initialLatitude ?? AppConfig.defaultLatitude,
      widget.args.initialLongitude ?? AppConfig.defaultLongitude,
    );
    _address = widget.args.initialAddress;

    // No coordinates supplied: try the device location so the customer starts
    // somewhere near themselves rather than at the fallback city centre.
    if (widget.args.initialLatitude == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _moveToCurrentLocation(silent: true));
    } else if (_address == null) {
      _resolveAddress();
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _resolveAddress() async {
    final generation = ++_geocodeGeneration;
    setState(() => _isGeocoding = true);

    final address = await ref.read(locationServiceProvider).reverseGeocode(
          latitude: _target.latitude,
          longitude: _target.longitude,
        );

    // A newer pan already started its own lookup; discard this one.
    if (!mounted || generation != _geocodeGeneration) return;

    setState(() {
      _address = address;
      _isGeocoding = false;
    });
  }

  Future<void> _moveToCurrentLocation({bool silent = false}) async {
    setState(() => _isLocating = true);

    try {
      final position = await ref.read(locationServiceProvider).getCurrentPosition();
      if (!mounted) return;

      final latLng = LatLng(position.latitude, position.longitude);
      setState(() => _target = latLng);

      await _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16.5));
      await _resolveAddress();
    } on LocationException catch (error) {
      if (!mounted || silent) return;

      AppFeedback.showError(context, error.message);

      if (error.requiresSettings) {
        await ref.read(locationServiceProvider).openSettings();
      } else if (error.failure == LocationFailure.serviceDisabled) {
        await ref.read(locationServiceProvider).openLocationSettings();
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _confirm() {
    final place = Place(
      address: _address ??
          'Pinned location (${_target.latitude.toStringAsFixed(5)}, '
              '${_target.longitude.toStringAsFixed(5)})',
      latitude: _target.latitude,
      longitude: _target.longitude,
    );

    if (!place.hasValidCoordinates) {
      AppFeedback.showError(context, 'That location is not valid. Move the pin and try again.');
      return;
    }

    context.pop(place);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPickup = widget.args.target == PlaceSearchTarget.pickup;

    return Scaffold(
      appBar: AppBar(title: Text(widget.args.title)),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _target, zoom: 15.5),
            onMapCreated: (controller) => _mapController = controller,
            onCameraMoveStarted: () => setState(() => _isMoving = true),
            onCameraMove: (position) => _target = position.target,
            onCameraIdle: () {
              setState(() => _isMoving = false);
              _resolveAddress();
            },
            // Our own button is placed clear of the bottom panel; the built-in
            // one would sit underneath it.
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            padding: const EdgeInsets.only(bottom: 180),
          ),

          // The centre pin. Lifts while the map moves, the way a dropped pin
          // behaves, so it is obvious the map is what is moving.
          IgnorePointer(
            child: Center(
              child: Padding(
                // Offset by half the pin height so its point, not its middle,
                // marks the chosen spot.
                padding: const EdgeInsets.only(bottom: 44),
                child: AnimatedScale(
                  scale: _isMoving ? 1.12 : 1,
                  duration: const Duration(milliseconds: 160),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.place_rounded,
                        size: 48,
                        color: isPickup ? AppColors.pickupPin : AppColors.destinationPin,
                      ),
                      Container(
                        height: 6,
                        width: 6,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          if (AppConfig.googleMapsApiKey.isEmpty)
            Positioned(
              top: AppSpacing.md,
              left: AppSpacing.pageGutter,
              right: AppSpacing.pageGutter,
              child: AppBanner(
                icon: Icons.map_outlined,
                accent: AppColors.warning,
                message:
                    'The map tiles need a Google Maps key. Pass GOOGLE_MAPS_API_KEY at build '
                    'time (and set MAPS_API_KEY in android/local.properties) to see them. '
                    'Picking a point still works.',
              ),
            ),

          Positioned(
            right: AppSpacing.lg,
            bottom: 200,
            child: FloatingActionButton.small(
              onPressed: _isLocating ? null : _moveToCurrentLocation,
              tooltip: 'Use my location',
              child: _isLocating
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location_rounded, size: 20),
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.pageGutter,
                AppSpacing.xl,
                AppSpacing.pageGutter,
                AppSpacing.pageGutter + MediaQuery.paddingOf(context).bottom,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.sheet),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isPickup ? 'Pickup point' : 'Destination',
                    style: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  // A fixed height stops the button jumping as the address text
                  // reflows between one and two lines.
                  SizedBox(
                    height: 46,
                    child: _isMoving || _isGeocoding
                        ? Row(
                            children: [
                              const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Text(
                                _isMoving ? 'Move the map to adjust' : 'Looking up this address',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          )
                        : Text(
                            _address ??
                                '${_target.latitude.toStringAsFixed(5)}, '
                                    '${_target.longitude.toStringAsFixed(5)}',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  PrimaryButton(
                    label: widget.args.confirmLabel,
                    icon: Icons.check_rounded,
                    // Confirming mid-pan would capture a position the customer
                    // is still moving away from.
                    onPressed: _isMoving ? null : _confirm,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
