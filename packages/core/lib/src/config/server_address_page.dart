import 'package:design_system/design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../network/token_storage.dart';
import 'app_config.dart';

/// Pilot builds only: point the app at a different server. Reached by a
/// long-press on the sign-in logo when [AppConfig.allowServerOverride] is on.
///
/// The address is checked (GET …/health) before it is saved, and applies the
/// next time the app opens — every service was built with the old one.
class ServerAddressPage extends StatefulWidget {
  const ServerAddressPage({
    super.key,
    required this.store,
    required this.current,
    this.probe,
  });

  final KeyValueStore store;

  /// The address the app is using now.
  final String current;

  /// Health check; defaults to a real GET. Tests inject one.
  final Future<bool> Function(String baseUrl)? probe;

  @override
  State<ServerAddressPage> createState() => _ServerAddressPageState();
}

class _ServerAddressPageState extends State<ServerAddressPage> {
  late final TextEditingController _url =
      TextEditingController(text: widget.current);
  bool _busy = false;
  String? _error;
  String? _saved;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  static Future<bool> _get(String baseUrl) async {
    try {
      final res = await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      )).get<Map<String, dynamic>>('$baseUrl/health');
      return res.statusCode == 200 && res.data?['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<void> _save() async {
    final url = _url.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (!AppConfig.isValidOverride(url)) {
      setState(() => _error =
          'Use the full https address ending in /api/v1, e.g. '
          'https://example.trycloudflare.com/api/v1');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await (widget.probe ?? _get)(url);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'No FAIRSVIA server answered at that address. Check it and '
            'try again.';
      });
      return;
    }
    await widget.store.write(AppConfig.serverOverrideKey, url);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _saved = url;
    });
  }

  Future<void> _reset() async {
    await widget.store.delete(AppConfig.serverOverrideKey);
    if (!mounted) return;
    setState(() => _saved = 'the built-in address');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Server address')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(
              'Pilot builds only. Use this if the test server moved to a new '
              'address.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Server address',
                errorText: _error,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Check and save',
              loading: _busy,
              onPressed: _busy ? null : _save,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: _busy ? null : _reset,
              child: const Text('Use the built-in address'),
            ),
            if (_saved != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Saved. Close the app completely and open it again to use '
                '$_saved.',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: AppColors.accentInk),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
