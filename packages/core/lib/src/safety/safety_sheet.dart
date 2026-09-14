import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../network/api_exception.dart';
import 'safety_remote_data_source.dart';

/// `tel:` URI for [phone], keeping only digits and a leading `+` so a number
/// formatted for display ("+1 (305) 555-0123") still dials.
Uri phoneCallUri(String phone) {
  final trimmed = phone.trim();
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  final plus = trimmed.startsWith('+') ? '+' : '';
  return Uri(scheme: 'tel', path: '$plus$digits');
}

/// Opens the phone dialler for [phone] (the rider's "Call driver" / the
/// driver's "Call rider"). Returns false when the number is unusable or the
/// device has no dialler (tablets, simulators); the caller can then fall back
/// to a message. [launch] is injectable for tests.
Future<bool> dialPhone(
  String phone, {
  Future<bool> Function(Uri uri)? launch,
}) async {
  final uri = phoneCallUri(phone);
  if (uri.path.replaceAll('+', '').isEmpty) return false;
  try {
    return await (launch ?? launchUrl)(uri);
  } catch (_) {
    return false;
  }
}

/// Opens the safety bottom sheet for an active trip.
Future<void> showSafetySheet(
  BuildContext context, {
  required String tripId,
  required SafetyRemoteDataSource safety,
  required String shareText,
  double? lat,
  double? lng,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SafetySheet(
      tripId: tripId,
      safety: safety,
      shareText: shareText,
      lat: lat,
      lng: lng,
    ),
  );
}

class _SafetySheet extends StatefulWidget {
  const _SafetySheet({
    required this.tripId,
    required this.safety,
    required this.shareText,
    this.lat,
    this.lng,
  });

  final String tripId;
  final SafetyRemoteDataSource safety;
  final String shareText;
  final double? lat;
  final double? lng;

  @override
  State<_SafetySheet> createState() => _SafetySheetState();
}

class _SafetySheetState extends State<_SafetySheet> {
  bool _alerting = false;
  bool _alerted = false;

  Future<void> _alert() async {
    setState(() => _alerting = true);
    try {
      await widget.safety.raiseSos(
        widget.tripId,
        lat: widget.lat,
        lng: widget.lng,
      );
      if (mounted) setState(() => _alerted = true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _alerting = false);
    }
  }

  Future<void> _shareTrip() async {
    await Clipboard.setData(ClipboardData(text: widget.shareText));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trip details copied — paste to share')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined, color: AppColors.error),
              const SizedBox(width: AppSpacing.sm),
              Text('Safety toolkit', style: theme.textTheme.headlineSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Emergency call — prominent. (Dialling is device-native; we surface
          // the number so the rider can call immediately.)
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radius),
            ),
            child: Row(
              children: [
                const Icon(Icons.call, color: AppColors.error),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Emergency services',
                          style: theme.textTheme.titleMedium),
                      Text('Call 911 for immediate help',
                          style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                Text('911',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(color: AppColors.error)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_alerted)
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.success),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text('Safety team alerted. Stay on the line.',
                        style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            )
          else
            PrimaryButton(
              label: 'Alert FairsVia Safety',
              loading: _alerting,
              onPressed: _alerting ? null : _alert,
            ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _shareTrip,
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share trip status'),
          ),
        ],
      ),
    );
  }
}
