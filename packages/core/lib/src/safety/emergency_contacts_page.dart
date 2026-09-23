import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../network/api_exception.dart';
import 'safety_remote_data_source.dart';
import 'package:shared_models/shared_models.dart';

/// Up to three people who get a text — with the location, car and plate —
/// when the user presses SOS during a ride.
class EmergencyContactsPage extends StatefulWidget {
  const EmergencyContactsPage({super.key, required this.safety});

  final SafetyRemoteDataSource safety;

  @override
  State<EmergencyContactsPage> createState() => _EmergencyContactsPageState();
}

class _EmergencyContactsPageState extends State<EmergencyContactsPage> {
  List<EmergencyContact>? _contacts;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final c = await widget.safety.contacts();
      if (mounted) setState(() => _contacts = c);
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  Future<void> _add() async {
    final added = await showModalBottomSheet<EmergencyContact>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddContactSheet(safety: widget.safety),
    );
    if (added == null || !mounted) return;
    AppHaptics.success();
    setState(() => _contacts = [...?_contacts, added]);
  }

  Future<void> _remove(EmergencyContact c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${c.name}?'),
        content: const Text("They won't be texted if you press SOS."),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final before = _contacts;
    setState(() => _contacts = _contacts?.where((x) => x.id != c.id).toList());
    try {
      await widget.safety.removeContact(c.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _contacts = before);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contacts = _contacts;
    final canAdd = contacts != null &&
        contacts.length < SafetyRemoteDataSource.maxContacts;

    return Scaffold(
      appBar: AppBar(title: const Text('Emergency contacts')),
      floatingActionButton: canAdd && contacts.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.person_add_alt_rounded),
              label: const Text('Add contact'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 96),
        children: [
          Text(
            'If you press SOS during a ride, these people get a text with '
            'where you are, the car and its plate.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: AppSpacing.xl),
          if (_loadError != null)
            EmptyState(
              icon: Icons.cloud_off_rounded,
              title: "Couldn't load your contacts",
              message: _loadError!,
              action: OutlinedButton(
                  onPressed: _load, child: const Text('Try again')),
            )
          else if (contacts == null)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: CircularProgressIndicator(),
            ))
          else if (contacts.isEmpty)
            EmptyState(
              icon: Icons.contact_emergency_rounded,
              title: 'No emergency contacts yet',
              message: 'Add up to 3 people you trust — family, a partner, '
                  'a close friend.',
              action: FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.person_add_alt_rounded),
                label: const Text('Add a contact'),
              ),
            )
          else ...[
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < contacts.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 72),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                      leading: AppAvatar(name: contacts[i].name, size: 44),
                      title: Text(contacts[i].name),
                      subtitle: Text(contacts[i].phone),
                      trailing: IconButton(
                        tooltip: 'Remove ${contacts[i].name}',
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _remove(contacts[i]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              canAdd
                  ? '${contacts.length} of ${SafetyRemoteDataSource.maxContacts} added'
                  : "You've added the maximum of "
                      '${SafetyRemoteDataSource.maxContacts}. Remove one to '
                      'add someone else.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _AddContactSheet extends StatefulWidget {
  const _AddContactSheet({required this.safety});

  final SafetyRemoteDataSource safety;

  @override
  State<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<_AddContactSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController(text: '+998 ');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final c = await widget.safety.addContact(
        _name.text.trim(),
        Market.current.toE164(_phone.text)!,
      );
      if (mounted) Navigator.of(context).pop(c);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add emergency contact', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter their name' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: 'Mobile number',
                helperText: 'e.g. ${Market.current.examplePhone}',
              ),
              validator: (v) => Market.current.toE164(v ?? '') == null
                  ? 'Enter a mobile number'
                  : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Save contact',
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
