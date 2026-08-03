import 'dart:async';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import 'location_service.dart';
import 'map_picker_page.dart';

/// The pickup + destination the rider chose on the search page.
class RouteChoice {
  const RouteChoice({
    required this.pickup,
    required this.pickupAddr,
    required this.dropoff,
    required this.dropoffAddr,
  });

  final GeoPoint pickup;
  final String pickupAddr;
  final GeoPoint dropoff;
  final String dropoffAddr;
}

/// Full-screen route search with an editable **pickup** and **destination**
/// (Uber-style). The active field drives debounced Places autocomplete via the
/// backend proxy. Selecting a place fills the active field; once both ends are
/// set it returns a [RouteChoice]. Pickup defaults to the rider's current
/// location, so searching only a destination still works in one tap.
class DestinationSearchPage extends StatefulWidget {
  const DestinationSearchPage({
    super.key,
    this.initialPickup,
    this.initialPickupLabel = 'Current location',
    this.singleDestination = false,
  });

  final GeoPoint? initialPickup;
  final String initialPickupLabel;

  /// When true, only a single location field is shown and the chosen
  /// [PlaceDetails] is returned (used for "add a stop"). Otherwise the page is
  /// a pickup+destination route search that returns a [RouteChoice].
  final bool singleDestination;

  @override
  State<DestinationSearchPage> createState() => _DestinationSearchPageState();
}

enum _Field { pickup, dropoff }

class _DestinationSearchPageState extends State<DestinationSearchPage> {
  final _pickupCtrl = TextEditingController();
  final _dropoffCtrl = TextEditingController();
  final _pickupFocus = FocusNode();
  final _dropoffFocus = FocusNode();
  final _repo = sl<TripRepository>();

  Timer? _debounce;
  List<PlacePrediction> _predictions = [];
  bool _loading = false;
  bool _resolving = false;
  String? _error;

  // Chosen ends. Pickup starts at the rider's current location; dropoff empty.
  late GeoPoint _pickup =
      widget.initialPickup ?? const GeoPoint(0, 0); // unused in single mode
  late String _pickupLabel = widget.initialPickupLabel;
  GeoPoint? _dropoff;
  String? _dropoffLabel;

  _Field get _active =>
      _pickupFocus.hasFocus ? _Field.pickup : _Field.dropoff;

  @override
  void initState() {
    super.initState();
    _pickupFocus.addListener(_onFocusChange);
    _dropoffFocus.addListener(_onFocusChange);
    // Start by editing the destination — the common case.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _dropoffFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pickupCtrl.dispose();
    _dropoffCtrl.dispose();
    _pickupFocus.dispose();
    _dropoffFocus.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!mounted) return;
    // Re-run suggestions for whichever field is now active.
    setState(() {
      _predictions = [];
      _error = null;
    });
    final text = (_active == _Field.pickup ? _pickupCtrl : _dropoffCtrl).text;
    _onChanged(text);
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      setState(() {
        _predictions = [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    try {
      final results = await _repo.autocomplete(q);
      if (!mounted) return;
      setState(() {
        _predictions = results;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _select(PlacePrediction prediction) async {
    setState(() => _resolving = true);
    try {
      final details = await _repo.placeDetails(prediction.placeId);
      if (!mounted) return;
      // Single-location mode (add-a-stop): return the raw place.
      if (widget.singleDestination) {
        Navigator.of(context).pop(details);
        return;
      }
      final field = _active;
      setState(() {
        _resolving = false;
        _predictions = [];
        if (field == _Field.pickup) {
          _pickup = details.location;
          _pickupLabel = details.address;
          _pickupCtrl.text = prediction.primaryText;
        } else {
          _dropoff = details.location;
          _dropoffLabel = details.address;
          _dropoffCtrl.text = prediction.primaryText;
        }
      });
      // Both ends known → return; otherwise move focus to the missing one.
      if (_dropoff != null) {
        Navigator.of(context).pop(RouteChoice(
          pickup: _pickup,
          pickupAddr: _pickupLabel,
          dropoff: _dropoff!,
          dropoffAddr: _dropoffLabel ?? 'Destination',
        ));
      } else {
        _dropoffFocus.requestFocus();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _error = e.message;
      });
    }
  }

  /// Where the map picker should open for the field being edited. Prefer that
  /// field's current point, then the pickup, then the configured city fallback
  /// (Bhukum in this build) — never the unset (0,0) sentinel.
  GeoPoint _mapStart() {
    final p = _active == _Field.pickup ? _pickup : (_dropoff ?? _pickup);
    final isSet = p.lat != 0 || p.lng != 0;
    return isSet ? p : LocationService.fallback;
  }

  /// Open the "set location on the map" picker for the active field, then apply
  /// the dropped point exactly like a picked prediction.
  Future<void> _pickOnMap() async {
    final field = _active;
    final result = await Navigator.of(context).push<PlaceDetails>(
      MaterialPageRoute(
        builder: (_) => MapPickerPage(
          initial: _mapStart(),
          title: field == _Field.pickup
              ? 'Set pickup on map'
              : 'Set destination on map',
        ),
      ),
    );
    if (result == null || !mounted) return;
    if (widget.singleDestination) {
      Navigator.of(context).pop(result); // add-a-stop: return the raw place
      return;
    }
    setState(() {
      _predictions = [];
      _error = null;
      if (field == _Field.pickup) {
        _pickup = result.location;
        _pickupLabel = result.address;
        _pickupCtrl.text = result.address;
      } else {
        _dropoff = result.location;
        _dropoffLabel = result.address;
        _dropoffCtrl.text = result.address;
      }
    });
    if (_dropoff != null) {
      Navigator.of(context).pop(RouteChoice(
        pickup: _pickup,
        pickupAddr: _pickupLabel,
        dropoff: _dropoff!,
        dropoffAddr: _dropoffLabel ?? 'Destination',
      ));
    } else {
      _dropoffFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.singleDestination ? 'Add a stop' : 'Plan your ride'),
        titleTextStyle: theme.textTheme.titleLarge,
      ),
      body: Column(
        children: [
          _RouteFields(
            pickupCtrl: _pickupCtrl,
            dropoffCtrl: _dropoffCtrl,
            pickupFocus: _pickupFocus,
            dropoffFocus: _dropoffFocus,
            pickupHint: _pickupLabel,
            showPickup: !widget.singleDestination,
            onChanged: (v) {
              _onChanged(v);
              setState(() {});
            },
            loading: _loading,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 18, color: AppColors.error),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(_error!,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppColors.error)),
                  ),
                ],
              ),
            ),
          // Always-available fallback to text search: drop a pin anywhere on the
          // map. Essential where OSM place data is thin (e.g. rural Bhukum).
          InkWell(
            onTap: _resolving ? null : _pickOnMap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg, vertical: AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.map_rounded,
                        size: 20, color: AppColors.accent),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text('Set location on the map',
                        style: theme.textTheme.titleSmall),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: theme.colorScheme.outline),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          Expanded(
            child: Stack(
              children: [
                if (_predictions.isEmpty && !_loading && _error == null)
                  EmptyState(
                    icon: Icons.explore_outlined,
                    title: _active == _Field.pickup
                        ? 'Set your pickup'
                        : 'Search for a destination',
                    message:
                        'Type an address, landmark, or place to see suggestions.',
                  )
                else
                  ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    itemCount: _predictions.length,
                    separatorBuilder: (_, _) => Divider(
                        height: 1,
                        indent: 72,
                        endIndent: AppSpacing.lg,
                        color: theme.dividerColor),
                    itemBuilder: (context, i) {
                      final p = _predictions[i];
                      return InkWell(
                        onTap: _resolving ? null : () => _select(p),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.md,
                          ),
                          child: Row(
                            children: [
                              Container(
                                height: 40,
                                width: 40,
                                decoration: BoxDecoration(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.location_on_rounded,
                                    size: 20,
                                    color: theme.colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.primaryText,
                                        style: theme.textTheme.titleSmall,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    if (p.secondaryText.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(p.secondaryText,
                                          style: theme.textTheme.bodyMedium,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                    ],
                                  ],
                                ),
                              ),
                              Icon(Icons.north_east_rounded,
                                  size: 18,
                                  color: theme.colorScheme.outline),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                if (_resolving)
                  Container(
                    color: AppColors.scrim,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The stacked pickup (origin dot) + destination (square) fields with the
/// connecting rail, mirroring Uber's route header.
class _RouteFields extends StatelessWidget {
  const _RouteFields({
    required this.pickupCtrl,
    required this.dropoffCtrl,
    required this.pickupFocus,
    required this.dropoffFocus,
    required this.pickupHint,
    required this.showPickup,
    required this.onChanged,
    required this.loading,
  });

  final TextEditingController pickupCtrl;
  final TextEditingController dropoffCtrl;
  final FocusNode pickupFocus;
  final FocusNode dropoffFocus;
  final String pickupHint;
  final bool showPickup;
  final ValueChanged<String> onChanged;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dropoffField = _FieldBox(
      controller: dropoffCtrl,
      focusNode: dropoffFocus,
      hint: showPickup ? 'Where to?' : 'Search a place',
      onChanged: onChanged,
      trailing: loading
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            )
          : null,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
      child: showPickup
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Origin dot → rail → destination square.
                Column(
                  children: [
                    const Icon(Icons.trip_origin,
                        size: 14, color: AppColors.accent),
                    Container(
                      width: 2,
                      height: 26,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: theme.dividerColor,
                    ),
                    const Icon(Icons.square, size: 12, color: AppColors.error),
                  ],
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    children: [
                      _FieldBox(
                        controller: pickupCtrl,
                        focusNode: pickupFocus,
                        hint: pickupHint,
                        onChanged: onChanged,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      dropoffField,
                    ],
                  ),
                ),
              ],
            )
          : dropoffField,
    );
  }
}

class _FieldBox extends StatelessWidget {
  const _FieldBox({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onChanged,
    this.trailing,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String> onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      focusNode: focusNode,
      style: theme.textTheme.bodyLarge,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest,
        suffixIcon: trailing,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: onChanged,
    );
  }
}
