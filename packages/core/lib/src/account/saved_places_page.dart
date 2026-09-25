import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../theme/app_modal_sheet.dart';
import 'package:shared_models/shared_models.dart';

import '../network/api_exception.dart';
import '../trip/places_remote_data_source.dart';
import 'users_remote_data_source.dart';
import 'widgets/async_content.dart';

/// Manage a rider's saved places (Home / Work / custom):
/// list, add, edit, delete. Backed by `/users/me/places`.
class SavedPlacesPage extends StatefulWidget {
  const SavedPlacesPage({
    super.key,
    required this.users,
    required this.places,
  });

  final UsersRemoteDataSource users;
  final PlacesRemoteDataSource places;

  @override
  State<SavedPlacesPage> createState() => _SavedPlacesPageState();
}

class _SavedPlacesPageState extends State<SavedPlacesPage> {
  int _reloadTick = 0;

  // Called after awaited network calls; the page may have been popped meanwhile.
  void _reload() {
    if (!mounted) return;
    setState(() => _reloadTick++);
  }

  Future<void> _addOrEdit([SavedPlace? existing]) async {
    final picked = await showAppModalSheet<_PlaceForm>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PlaceEditorSheet(
        places: widget.places,
        existing: existing,
      ),
    );
    if (picked == null) return;
    try {
      if (existing == null) {
        await widget.users.addPlace(
          label: picked.label,
          lat: picked.location.lat,
          lng: picked.location.lng,
          address: picked.address,
        );
      } else {
        await widget.users.updatePlace(
          existing.id,
          label: picked.label,
          lat: picked.location.lat,
          lng: picked.location.lng,
          address: picked.address,
        );
      }
      _reload();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _delete(SavedPlace place) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete "${place.label}"?'),
        content: const Text('This saved place will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.users.deletePlace(place.id);
      _reload();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved places')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        icon: const Icon(PhosphorIconsRegular.plus),
        label: const Text('Add place'),
      ),
      body: AsyncContent<List<SavedPlace>>(
        key: ValueKey(_reloadTick),
        load: widget.users.listPlaces,
        isEmpty: (list) => list.isEmpty,
        // Saved places are a bookmark everywhere (audit item 11: heart on
        // Home, star here; star means rating, heart means favourite driver).
        emptyIcon: PhosphorIconsRegular.bookmarkSimple,
        emptyTitle: 'No saved places',
        emptyMessage: 'Save Home, Work, or anywhere you go often.',
        builder: (context, list, _) => ListView(
          padding: const EdgeInsets.only(bottom: 80),
          children: [
            for (final p in list)
              ListTile(
                leading: Icon(_iconFor(p.label)),
                title: Text(p.label),
                subtitle: p.address == null ? null : Text(p.address!),
                onTap: () => _addOrEdit(p),
                trailing: IconButton(
                  icon: const Icon(PhosphorIconsRegular.trash),
                  tooltip: 'Delete place',
                  onPressed: () => _delete(p),
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String label) {
    final l = label.toLowerCase();
    if (l == 'home') return PhosphorIconsRegular.house;
    if (l == 'work') return PhosphorIconsRegular.briefcase;
    return PhosphorIconsRegular.mapPin;
  }
}

/// The value returned by the editor sheet.
class _PlaceForm {
  const _PlaceForm({
    required this.label,
    required this.address,
    required this.location,
  });
  final String label;
  final String address;
  final GeoPoint location;
}

class _PlaceEditorSheet extends StatefulWidget {
  const _PlaceEditorSheet({required this.places, this.existing});
  final PlacesRemoteDataSource places;
  final SavedPlace? existing;

  @override
  State<_PlaceEditorSheet> createState() => _PlaceEditorSheetState();
}

class _PlaceEditorSheetState extends State<_PlaceEditorSheet> {
  late final TextEditingController _label =
      TextEditingController(text: widget.existing?.label ?? '');
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<PlacePrediction> _results = const [];
  bool _searching = false;

  // Chosen location: seeded from the existing place, replaced on pick.
  GeoPoint? _location;
  String? _address;

  @override
  void initState() {
    super.initState();
    _location = widget.existing?.point;
    _address = widget.existing?.address;
    _searchCtrl.text = widget.existing?.address ?? '';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _label.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    if (q.trim().length < 3) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _searching = true);
      try {
        final r = await widget.places.autocomplete(q.trim());
        if (mounted) setState(() => _results = r);
      } on ApiException {
        if (mounted) setState(() => _results = const []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _pick(PlacePrediction p) async {
    try {
      final d = await widget.places.details(p.placeId);
      if (!mounted) return;
      setState(() {
        _location = d.location;
        _address = d.address;
        _searchCtrl.text = d.address;
        _results = const [];
      });
      FocusScope.of(context).unfocus();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  bool get _valid => _label.text.trim().isNotEmpty && _location != null;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: AppSpacing.lg + insets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.existing == null ? 'Add a place' : 'Edit place',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final quick in const ['Home', 'Work'])
                ActionChip(
                  label: Text(quick),
                  // setState so `_valid` (and the Save button) re-evaluates:
                  // the TextField's onChanged does not fire for programmatic
                  // controller writes.
                  onPressed: () => setState(() => _label.text = quick),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _label,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Label',
              hintText: 'Home, Work, Gym…',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              labelText: 'Address',
              prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            onChanged: _onQuery,
          ),
          if (_results.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in _results)
                    ListTile(
                      dense: true,
                      leading: const Icon(PhosphorIconsRegular.mapPin),
                      title: Text(p.primaryText),
                      subtitle: p.secondaryText.isEmpty
                          ? null
                          : Text(p.secondaryText),
                      onTap: () => _pick(p),
                    ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Save',
            onPressed: _valid
                ? () => Navigator.pop(
                      context,
                      _PlaceForm(
                        label: _label.text.trim(),
                        address: _address ?? _searchCtrl.text.trim(),
                        location: _location!,
                      ),
                    )
                : null,
          ),
        ],
      ),
    );
  }
}
