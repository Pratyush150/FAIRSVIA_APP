import 'dart:async';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show TileProvider;
import 'package:shared_models/shared_models.dart';

import 'location_service.dart';

/// "Set location on the map" — pan the map under a fixed centre pin to drop a
/// point anywhere, then confirm. The dropped point is reverse-geocoded to an
/// address (via the self-hosted Nominatim proxy), which is ideal where text
/// search is thin (e.g. rural Bhukum): any spot is selectable, named or not.
///
/// Returns the chosen [PlaceDetails] (the *dropped* point as the location, with
/// the reverse-geocoded address as its label), or null if cancelled.
class MapPickerPage extends StatefulWidget {
  const MapPickerPage({
    super.key,
    required this.initial,
    this.title,
    this.tileProvider,
  });

  /// Where the map opens — usually the rider's current pickup so they start
  /// near themselves.
  final GeoPoint initial;
  final String? title;

  /// Test seam: injects an offline tile source so widget tests touch no network.
  final TileProvider? tileProvider;

  @override
  State<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage> {
  final _repo = sl<TripRepository>();
  final _location = LocationService();
  late LatLng _center = LatLng(widget.initial.lat, widget.initial.lng);

  Timer? _debounce;
  String? _address; // live label under the pin (null while resolving)
  bool _confirming = false;
  bool _locating = false;

  // Drives the map back to the rider's live position when "locate me" is tapped.
  LatLng? _recenter;
  int _recenterTick = 0;

  /// Centre the map on the rider's current GPS position.
  Future<void> _locateMe() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      if (!await _location.hasPermission()) {
        await _location.requestPermission();
      }
      final loc = await _location.currentOrFallback();
      if (!mounted) return;
      setState(() {
        _recenter = LatLng(loc.lat, loc.lng);
        _recenterTick++;
      });
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _resolve(_center); // seed the label for the opening position
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onCenterChanged(LatLng c) {
    _center = c;
    setState(() => _address = null); // "Locating…" until the debounce resolves
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _resolve(c));
  }

  Future<void> _resolve(LatLng c) async {
    try {
      final details = await _repo.reverseGeocode(c.latitude, c.longitude);
      if (!mounted || c != _center) return; // moved again — ignore stale result
      setState(() => _address = details.address);
    } on ApiException {
      if (!mounted || c != _center) return;
      setState(() => _address = 'Dropped pin');
    }
  }

  Future<void> _confirm() async {
    setState(() => _confirming = true);
    // Resolve the *current* centre fresh so the returned address matches the pin
    // exactly. Keep the dropped point as the location (don't let geocoding snap
    // it away — the rider chose this spot).
    String address;
    String placeId = '';
    try {
      final d = await _repo.reverseGeocode(_center.latitude, _center.longitude);
      address = d.address;
      placeId = d.placeId;
    } on ApiException {
      address = _address ?? 'Dropped pin';
    }
    if (!mounted) return;
    Navigator.of(context).pop(PlaceDetails(
      placeId: placeId,
      address: address,
      location: GeoPoint(_center.latitude, _center.longitude),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Set location on map'),
        titleTextStyle: theme.textTheme.titleLarge,
      ),
      body: Stack(
        children: [
          AppMap(
            initialCenter: _center,
            initialZoom: 16,
            onCenterChanged: _onCenterChanged,
            recenter: _recenter,
            recenterTrigger: _recenterTick,
            recenterZoom: 16.5,
            tileProvider: widget.tileProvider,
          ),
          // Fixed centre pin — its tip sits on the exact map centre. IgnorePointer
          // so drags pass through to the map beneath.
          const IgnorePointer(child: Center(child: _CenterPin())),
          // "Locate me" — recentres the pin on the rider's live position.
          Positioned(
            right: AppSpacing.md,
            bottom: 180,
            child: SafeArea(
              child: AppCircleButton(
                icon: _locating
                    ? Icons.hourglass_bottom_rounded
                    : Icons.my_location_rounded,
                tooltip: 'My location',
                onPressed: _locateMe,
              ),
            ),
          ),
          // Bottom sheet: live address + confirm.
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.location_on_rounded,
                              size: 20, color: AppColors.accent),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: _address == null
                                ? Row(children: [
                                    const SizedBox(
                                      height: 14,
                                      width: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Text('Locating…',
                                        style: theme.textTheme.bodyMedium),
                                  ])
                                : Text(_address!,
                                    style: theme.textTheme.titleSmall,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      PrimaryButton(
                        label: 'Confirm location',
                        loading: _confirming,
                        onPressed: _confirming ? null : _confirm,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A teardrop pin whose tip points at the map centre. Nudged up by half its
/// height so the tip — not the centre of the glyph — rests on the coordinate.
class _CenterPin extends StatelessWidget {
  const _CenterPin();

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -20),
      child: const Icon(Icons.location_on, size: 44, color: AppColors.accent),
    );
  }
}
