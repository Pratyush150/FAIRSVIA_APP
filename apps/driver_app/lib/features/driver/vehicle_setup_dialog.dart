import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import 'driver_cubit.dart';

/// The driver's vehicle: make, model, colour, plate and vehicle type (car
/// tiers, or India's auto-rickshaw and bike taxi). First-time setup, and
/// "Vehicle" from the account menu (prefilled from [initial]).
class VehicleSetupDialog extends StatefulWidget {
  const VehicleSetupDialog({
    super.key,
    required this.cubit,
    this.initial,
    this.goOnlineAfter = true,
  });
  final DriverCubit cubit;

  /// Existing vehicle when editing (null on first-time setup).
  final DriverProfile? initial;
  final bool goOnlineAfter;

  @override
  State<VehicleSetupDialog> createState() => _VehicleSetupDialogState();
}

class _VehicleSetupDialogState extends State<VehicleSetupDialog> {
  late final _make = TextEditingController(text: widget.initial?.vehicleMake);
  late final _model = TextEditingController(text: widget.initial?.vehicleModel);
  late final _color = TextEditingController(text: widget.initial?.vehicleColor);
  late final _plate = TextEditingController(text: widget.initial?.plateNumber);
  late String _tier = widget.initial?.vehicleTier ?? 'economy';
  bool _saving = false;

  /// Auto-rickshaw and bike taxi are built but held back by the owner
  /// (2026-09-24); `--dart-define=EXTRA_TIERS=true` offers them again, in
  /// step with the server's EXTRA_TIERS.
  static const bool extraTiers = bool.fromEnvironment('EXTRA_TIERS');

  /// What the driver drives, in the order riders see ride types (cheapest
  /// first).
  static const _vehicleTypes = [
    if (extraTiers) ('bike', 'Bike (bike taxi, 1 rider)'),
    if (extraTiers) ('auto', 'Auto (auto-rickshaw, 3 riders)'),
    ('economy', 'Economy'),
    ('comfort', 'Comfort'),
    ('xl', 'XL'),
    ('premium', 'Premium'),
  ];

  /// Make / model examples per vehicle type, for the validation hints.
  static const _examples = {
    'bike': ('Honda', 'Activa 6G'),
    'auto': ('Bajaj', 'RE Compact'),
    'economy': ('Toyota', 'Camry'),
  };
  String? _error;

  @override
  void dispose() {
    _make.dispose();
    _model.dispose();
    _color.dispose();
    _plate.dispose();
    super.dispose();
  }

  String? _validate() {
    final make = _make.text.trim();
    final model = _model.text.trim();
    final plate = _plate.text.trim();
    final ex = _examples[_tier] ?? _examples['economy']!;
    if (make.isEmpty) return 'Enter the vehicle make (e.g. ${ex.$1}).';
    if (model.isEmpty) return 'Enter the vehicle model (e.g. ${ex.$2}).';
    // Same rule as the server: riders match this plate before getting in.
    // Autos and bikes carry the same registration format as cars.
    if (!Market.current.isValidPlate(plate)) {
      return 'Enter the number plate as it is on the vehicle, e.g. '
          '${Market.current.examplePlate}.';
    }
    return null;
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final color = _color.text.trim();
    // The dialog stays up until the server has accepted the vehicle, so a
    // rejected save is shown here instead of vanishing behind the map.
    final ok = await widget.cubit.onboard(
      make: _make.text.trim(),
      model: _model.text.trim(),
      plate: _plate.text.trim().toUpperCase(),
      tier: _tier,
      color: color.isEmpty ? null : color,
      goOnlineAfter: widget.goOnlineAfter,
    );
    if (!mounted) return;
    if (ok) {
      navigator.pop(true);
    } else {
      setState(() {
        _saving = false;
        _error = widget.cubit.state.error ?? 'Could not save the vehicle.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return AlertDialog(
      title: Text(editing ? 'Your vehicle' : 'Set up your vehicle'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _make,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Make'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _model,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Model'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _color,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Colour (optional)'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _plate,
              enabled: !_saving,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Plate number'),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _tier,
              // Match the text fields above; the dropdown default
              // (titleMedium) rendered "Economy" visibly larger.
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: const InputDecoration(labelText: 'Vehicle type'),
              items: [
                for (final (value, label) in _vehicleTypes)
                  DropdownMenuItem(value: value, child: Text(label)),
              ],
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _tier = v ?? 'economy'),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(editing ? 'Save' : 'Save & go online'),
        ),
      ],
    );
  }
}
