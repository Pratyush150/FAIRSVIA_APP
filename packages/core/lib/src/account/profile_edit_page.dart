import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../network/api_exception.dart';
import 'users_remote_data_source.dart';

/// Edit the signed-in user's display name and email (`PATCH /users/me`).
/// Returns the updated [AppUser] via `Navigator.pop` on success.
class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key, required this.users, required this.user});

  final UsersRemoteDataSource users;
  final AppUser user;

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.user.fullName ?? '');
  late final TextEditingController _email =
      TextEditingController(text: widget.user.email ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await widget.users.updateMe(
        fullName: _name.text.trim().isEmpty ? null : _name.text.trim(),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(updated);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _PhoneField(phone: widget.user.phone),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(PhosphorIconsRegular.user),
              ),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'Enter your name';
                if (t.length < 2) return 'Name is too short';
                if (t.length > 120) return 'Name is too long';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(PhosphorIconsRegular.envelopeSimple),
              ),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null; // optional
                final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t);
                return ok ? null : 'Enter a valid email';
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: const TextStyle(color: AppColors.error)),
            ],
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Save changes',
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _PhoneField extends StatelessWidget {
  const _PhoneField({required this.phone});
  final String phone;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: phone,
      enabled: false,
      decoration: const InputDecoration(
        labelText: 'Phone (cannot be changed)',
        prefixIcon: Icon(PhosphorIconsRegular.phone),
      ),
    );
  }
}
