import 'dart:async';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

/// What the driver chose on the destination picker.
class DestinationPick {
  const DestinationPick({
    required this.lat,
    required this.lng,
    required this.label,
    this.saveAsHome = false,
  });

  final double lat;
  final double lng;
  final String label;
  final bool saveAsHome;
}

/// Destination ("go home") mode on the online sheet: a "Destination" button
/// while off, or the chip "Heading to Home · 1 of 2 today" with a cancel.
///
/// While it is on, dispatch only offers trips whose drop-off brings the driver
/// meaningfully closer (drop-off→destination ≤ 70 % of driver→destination).
/// It ends itself within 500 m of the destination or after 2 h; the next
/// refresh (every minute, or on `driver:destination_off`) shows that.
class DestinationModeBar extends StatefulWidget {
  const DestinationModeBar({
    super.key,
    required this.api,
    required this.onPick,
    this.refreshEvery = const Duration(minutes: 1),
  });

  final DestinationModeRemoteDataSource api;

  /// Opens the picker; returns null when the driver backs out.
  final Future<DestinationPick?> Function(DestinationModeStatus status) onPick;

  final Duration refreshEvery;

  @override
  State<DestinationModeBar> createState() => _DestinationModeBarState();
}

class _DestinationModeBarState extends State<DestinationModeBar> {
  DestinationModeStatus? _status;
  bool _busy = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _refresh();
    _tick = Timer.periodic(widget.refreshEvery, (_) => _refresh());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final s = await widget.api.get();
      if (!mounted) return;
      final wasActive = _status?.active ?? false;
      setState(() => _status = s);
      if (wasActive && !s.active && s.endedReason != null) {
        _toast(
          s.endedReason == 'arrived'
              ? "You've reached your destination. Destination mode is off."
              : 'Destination mode ended after 2 hours.',
        );
      }
    } catch (_) {
      // Best-effort: the bar just keeps its last state.
    }
  }

  void _toast(String msg) => ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _start() async {
    final status = _status;
    if (status == null || _busy) return;
    if (status.limitReached) {
      _toast(
        'Destination mode can be used ${status.usesPerDay} times a day. '
        'Try again tomorrow.',
      );
      return;
    }
    final pick = await widget.onPick(status);
    if (pick == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final s = await widget.api.set(
        lat: pick.lat,
        lng: pick.lng,
        label: pick.label,
        saveAsHome: pick.saveAsHome,
      );
      if (mounted) setState(() => _status = s);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast("Couldn't set the destination. Try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final s = await widget.api.clear();
      if (mounted) setState(() => _status = s);
    } catch (_) {
      _toast("Couldn't turn off destination mode. Try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    if (s == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    if (!s.active) {
      return SecondaryButton(
        label: 'Destination',
        icon: PhosphorIconsRegular.flag,
        onPressed: _busy ? null : _start,
      );
    }
    final label = s.destination?.label ?? 'Destination';
    final text = 'Heading to $label · ${s.usesToday} of ${s.usesPerDay} today';
    return Semantics(
      container: true,
      label: '$text. Only trips toward your destination are offered.',
      child: Container(
        padding: const EdgeInsets.only(left: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Row(
          children: [
            Icon(PhosphorIconsRegular.flag, size: 20, color: AppColors.accent),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ExcludeSemantics(
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Cancel destination',
              icon: const Icon(PhosphorIconsRegular.x),
              onPressed: _busy ? null : _cancel,
            ),
          ],
        ),
      ),
    );
  }
}

/// Picks where the driver is heading: the saved Home, a places search, or a
/// point dropped on the map.
class DestinationPickerPage extends StatefulWidget {
  const DestinationPickerPage({
    super.key,
    required this.places,
    this.home,
    this.near,
  });

  final PlacesRemoteDataSource places;
  final DestinationPoint? home;
  final GeoPoint? near;

  @override
  State<DestinationPickerPage> createState() => _DestinationPickerPageState();
}

class _DestinationPickerPageState extends State<DestinationPickerPage> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<PlacePrediction> _results = const [];
  bool _saveAsHome = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (q.trim().length < 2) {
        if (mounted) setState(() => _results = const []);
        return;
      }
      try {
        final r = await widget.places.autocomplete(q.trim(), near: widget.near);
        if (!mounted) return;
        setState(() {
          _results = r;
          _error = null;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _error = "Search isn't available right now.");
      }
    });
  }

  Future<void> _choose(PlacePrediction p) async {
    try {
      final d = await widget.places.details(p.placeId);
      if (!mounted) return;
      Navigator.of(context).pop(
        DestinationPick(
          lat: d.location.lat,
          lng: d.location.lng,
          label: _saveAsHome ? 'Home' : p.primaryText,
          saveAsHome: _saveAsHome,
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't load that place.");
    }
  }

  Future<void> _pickOnMap() async {
    final home = widget.home;
    final start =
        widget.near ?? (home == null ? null : GeoPoint(home.lat, home.lng));
    final at = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => _DestinationMapPick(
          initial: start == null
              ? const LatLng(41.3111, 69.2797)
              : LatLng(start.lat, start.lng),
        ),
      ),
    );
    if (at == null || !mounted) return;
    Navigator.of(context).pop(
      DestinationPick(
        lat: at.latitude,
        lng: at.longitude,
        label: _saveAsHome ? 'Home' : 'Pinned spot',
        saveAsHome: _saveAsHome,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final home = widget.home;
    return Scaffold(
      appBar: AppBar(title: const Text('Where are you heading?')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(
            "You'll only get trips that end closer to your destination. "
            'It turns off when you arrive or after 2 hours.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _query,
            onChanged: _onChanged,
            decoration: const InputDecoration(
              hintText: 'Search a place',
              prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (home != null)
            ListTile(
              leading: const Icon(PhosphorIconsRegular.house),
              title: Text(home.label),
              subtitle: const Text('Saved home'),
              onTap: () => Navigator.of(context).pop(
                DestinationPick(
                  lat: home.lat,
                  lng: home.lng,
                  label: home.label,
                ),
              ),
            ),
          ListTile(
            leading: const Icon(PhosphorIconsRegular.mapPin),
            title: const Text('Choose on map'),
            onTap: _pickOnMap,
          ),
          SwitchListTile(
            value: _saveAsHome,
            onChanged: (v) => setState(() => _saveAsHome = v),
            title: const Text('Save as Home'),
          ),
          for (final p in _results)
            ListTile(
              leading: const Icon(PhosphorIconsRegular.mapPin),
              title: Text(p.primaryText),
              subtitle: p.secondaryText.isEmpty ? null : Text(p.secondaryText),
              onTap: () => _choose(p),
            ),
        ],
      ),
    );
  }
}

/// Pan the map under a fixed pin, then confirm.
class _DestinationMapPick extends StatefulWidget {
  const _DestinationMapPick({required this.initial});

  final LatLng initial;

  @override
  State<_DestinationMapPick> createState() => _DestinationMapPickState();
}

class _DestinationMapPickState extends State<_DestinationMapPick> {
  late LatLng _center = widget.initial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose on map')),
      body: Stack(
        children: [
          AppMap(
            initialCenter: widget.initial,
            initialZoom: 14,
            onCenterChanged: (c) => _center = c,
          ),
          IgnorePointer(
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, -22),
                child: Icon(
                  PhosphorIconsRegular.mapPin,
                  size: 48,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: PrimaryButton(
                  label: 'Head here',
                  onPressed: () => Navigator.of(context).pop(_center),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
