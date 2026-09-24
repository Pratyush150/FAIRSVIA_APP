import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../network/api_exception.dart';
import 'emergency_contacts_page.dart';
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

/// Opens the messaging app with [text] pre-filled (the user picks who to send
/// it to), falling back to the clipboard when no SMS app can be opened.
Future<void> shareTripText(BuildContext context, String text) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final sms = Uri(scheme: 'sms', queryParameters: {'body': text});
    if (await canLaunchUrl(sms)) {
      await launchUrl(sms, mode: LaunchMode.externalApplication);
      return;
    }
  } catch (_) {
    // fall through to the clipboard fallback
  }
  await Clipboard.setData(ClipboardData(text: text));
  messenger.showSnackBar(
    const SnackBar(content: Text('Trip details copied — paste to share')),
  );
}

/// Where the person is right now, best effort. Null when unknown.
typedef SafetyLocator = Future<({double lat, double lng})?> Function();

/// Opens the safety sheet for an active trip.
///
/// [locate] is asked for a position when SOS is pressed (device GPS first,
/// then e.g. the car's last position) so contacts get a map link.
Future<void> showSafetySheet(
  BuildContext context, {
  required String tripId,
  required SafetyRemoteDataSource safety,
  required String shareText,
  SafetyLocator? locate,
  Future<bool> Function(Uri uri)? launch,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => SafetySheet(
      tripId: tripId,
      safety: safety,
      shareText: shareText,
      locate: locate,
      launch: launch,
    ),
  );
}

/// In-trip safety: call local emergency services, send an SOS to the user's
/// emergency contacts and to RideVela safety, share the trip. Every line of
/// copy states only what actually happened.
class SafetySheet extends StatefulWidget {
  const SafetySheet({
    super.key,
    required this.tripId,
    required this.safety,
    required this.shareText,
    this.locate,
    this.launch,
  });

  final String tripId;
  final SafetyRemoteDataSource safety;
  final String shareText;
  final SafetyLocator? locate;
  final Future<bool> Function(Uri uri)? launch;

  @override
  State<SafetySheet> createState() => _SafetySheetState();
}

class _SafetySheetState extends State<SafetySheet> {
  List<EmergencyNumber> _numbers = EmergencyNumber.fallback;
  List<EmergencyContact>? _contacts;
  bool _sending = false;
  SosResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Independent, and never allowed to throw: this sheet is opened in an
  // emergency, and the call buttons already work from the fallback list.
  void _load() {
    _loadNumbers();
    _loadContacts();
  }

  Future<void> _loadNumbers() async {
    try {
      final n = await widget.safety.emergencyNumbers();
      if (mounted && n.isNotEmpty) setState(() => _numbers = n);
    } catch (_) {}
  }

  Future<void> _loadContacts() async {
    try {
      final c = await widget.safety.contacts();
      if (mounted) setState(() => _contacts = c);
    } catch (_) {}
  }

  Future<void> _sendSos() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    AppHaptics.heavy();
    try {
      ({double lat, double lng})? at;
      try {
        at = await widget.locate?.call().timeout(const Duration(seconds: 4));
      } catch (_) {
        // Send without a location rather than not at all.
      }
      final result = await widget.safety
          .raiseSos(widget.tripId, lat: at?.lat, lng: at?.lng);
      if (!mounted) return;
      setState(() {
        _result = result;
        if (result.emergencyNumbers.isNotEmpty) {
          _numbers = result.emergencyNumbers;
        }
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.statusCode == null
            ? "No connection — the alert wasn't sent. Call emergency services "
                'directly, then try again.'
            : "The alert wasn't sent (${e.message}). Call emergency services "
                'directly, then try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = "The alert wasn't sent. Call emergency "
            'services directly, then try again.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _call(EmergencyNumber n) async {
    final messenger = ScaffoldMessenger.of(context);
    AppHaptics.medium();
    final ok = await dialPhone(n.number, launch: widget.launch);
    if (ok) return;
    await Clipboard.setData(ClipboardData(text: n.number));
    messenger.showSnackBar(
      SnackBar(content: Text('Dial ${n.number} — number copied')),
    );
  }

  Future<void> _shareTrip() => shareTripText(context, widget.shareText);

  Future<void> _manageContacts() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EmergencyContactsPage(safety: widget.safety),
    ));
    if (mounted) await _loadContacts();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final secondary =
        dark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return SingleChildScrollView(
      // Clear the system navigation bar: the last button sat on top of it.
      padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(PhosphorIconsRegular.shieldCheck, color: AppColors.error),
              const SizedBox(width: AppSpacing.sm),
              Text('Safety', style: theme.textTheme.headlineSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('CALL EMERGENCY SERVICES',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: secondary, letterSpacing: 0.8)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (var i = 0; i < _numbers.length && i < 3; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _CallTile(
                    number: _numbers[i],
                    onTap: () => _call(_numbers[i]),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          AnimatedSwitcher(
            duration: AppMotion.normal,
            switchInCurve: AppMotion.emphasized,
            child: _result != null
                ? _SentPanel(
                    key: const ValueKey('sent'),
                    result: _result!,
                    onAddContacts: _manageContacts,
                  )
                : Column(
                    key: const ValueKey('send'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PrimaryButton(
                        label: 'Send SOS alert',
                        icon: PhosphorIconsRegular.siren,
                        destructive: true,
                        loading: _sending,
                        onPressed: _sending ? null : _sendSos,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _SosExplainer(
                        contacts: _contacts,
                        onManage: _manageContacts,
                      ),
                    ],
                  ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            _Notice(
              icon: PhosphorIconsRegular.warningCircle,
              color: AppColors.error,
              text: _error!,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: _shareTrip,
            icon: const Icon(PhosphorIconsRegular.export),
            label: const Text('Share trip status'),
          ),
        ],
      ),
    );
  }
}

class _CallTile extends StatelessWidget {
  const _CallTile({required this.number, required this.onTap});

  final EmergencyNumber number;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: 'Call ${number.label}, ${number.number}',
      excludeSemantics: true,
      child: Material(
        color: dark ? AppColors.errorSoftDark : AppColors.errorSoft,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.md, horizontal: AppSpacing.sm),
            child: Column(
              children: [
                Text(number.number,
                    style: theme.textTheme.headlineSmall?.copyWith(
                        color: AppColors.error, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(number.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SosExplainer extends StatelessWidget {
  const _SosExplainer({required this.contacts, required this.onManage});

  final List<EmergencyContact>? contacts;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = contacts;
    final String text;
    if (c == null) {
      text = 'Sends your location, the car and its plate.';
    } else if (c.isEmpty) {
      text = "Alerts ${AppBrand.name} safety. You haven't added emergency "
          "contacts, so nobody you know will be texted.";
    } else {
      final n = c.map((x) => x.name).toList();
      final names = n.length == 1
          ? n.single
          : '${n.sublist(0, n.length - 1).join(', ')} and ${n.last}';
      text = 'Texts $names your location, the car and its plate, and '
          'alerts ${AppBrand.name} safety.';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: theme.textTheme.bodyMedium),
        if (c != null && c.length < SafetyRemoteDataSource.maxContacts)
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: onManage,
            child: Text(c.isEmpty ? 'Add emergency contacts' : 'Manage contacts'),
          ),
      ],
    );
  }
}

class _SentPanel extends StatelessWidget {
  const _SentPanel({super.key, required this.result, required this.onAddContacts});

  final SosResult result;
  final VoidCallback onAddContacts;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final lines = <Widget>[
      _Notice(
        icon: PhosphorIconsFill.checkCircle,
        color: AppColors.success,
        text: r.repeat
            ? 'Your alert is still open with ${AppBrand.name} safety — '
                'your location was updated.'
            : 'SOS sent to ${AppBrand.name} safety.',
      ),
    ];
    if (r.contactsTotal == 0) {
      lines.add(_Notice(
        icon: PhosphorIconsRegular.userPlus,
        color: AppColors.warning,
        text: 'No emergency contacts were texted — you have none saved.',
        action: TextButton(
            onPressed: onAddContacts, child: const Text('Add contacts')),
      ));
    } else if (r.contactsNotified == r.contactsTotal) {
      lines.add(_Notice(
        icon: PhosphorIconsRegular.chatText,
        color: AppColors.success,
        text: r.repeat
            ? 'Your contacts were already texted a minute ago.'
            : 'Texted your ${r.contactsTotal == 1 ? 'emergency contact' : '${r.contactsTotal} emergency contacts'}.',
      ));
    } else {
      final failed = r.contactsTotal - r.contactsNotified;
      lines.add(_Notice(
        icon: PhosphorIconsRegular.chatCircleSlash,
        color: AppColors.warning,
        text: 'Texted ${r.contactsNotified} of ${r.contactsTotal} contacts — '
            "$failed couldn't be reached. Call them if you can.",
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          lines[i],
        ],
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.text,
    this.action,
  });

  final IconData icon;
  final Color color;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
            ?action,
          ],
        ),
      ),
    );
  }
}
