import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../network/api_exception.dart';
import 'format.dart';
import 'support_remote_data_source.dart';
import 'support_thread_page.dart';
import 'widgets/async_content.dart';

/// Status → chip colour. Open/active are "live"; resolved/closed are muted.
Color supportStatusColor(String status) {
  switch (status) {
    case 'open':
      return AppColors.warning;
    case 'active':
      return AppColors.accent;
    case 'resolved':
      return AppColors.success;
    default: // closed
      return Colors.grey;
  }
}

/// The user's list of support tickets, with a "New ticket" action. Opening a
/// row shows the full thread ([SupportThreadPage]).
class SupportPage extends StatefulWidget {
  const SupportPage({super.key, required this.support, this.isDriver = false});

  final SupportRemoteDataSource support;
  final bool isDriver;

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  int _reloadKey = 0;

  Future<void> _openThread(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SupportThreadPage(support: widget.support, ticketId: id),
      ),
    );
    if (mounted) setState(() => _reloadKey++);
  }

  Future<void> _newTicket() async {
    final created = await showModalBottomSheet<SupportTicket>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewTicketSheet(support: widget.support),
    );
    if (created != null && mounted) {
      setState(() => _reloadKey++);
      _openThread(created.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & support')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newTicket,
        icon: const Icon(Icons.add),
        label: const Text('New ticket'),
      ),
      body: AsyncContent<List<SupportTicket>>(
        key: ValueKey(_reloadKey),
        load: widget.support.listMine,
        isEmpty: (list) => list.isEmpty,
        emptyIcon: Icons.support_agent,
        emptyTitle: 'No support tickets',
        emptyMessage: widget.isDriver
            ? 'Have a problem with a trip, a rider or a payout? Open a '
                'ticket and our team will help.'
            : 'Have a problem with a ride? Open a ticket and our team '
                'will help.',
        builder: (context, list, _) => ListView.separated(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final t = list[i];
            return ListTile(
              title: Text(
                t.subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${Fmt.status(t.category)} · ${Fmt.dateShort(t.updatedAt ?? t.createdAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              trailing: _StatusChip(status: t.status),
              onTap: () => _openThread(t.id),
            );
          },
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = supportStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        Fmt.status(status),
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

const _categories = <String, String>{
  'payment': 'Payment / billing',
  'safety': 'Safety',
  'lost_item': 'Lost item',
  'driver': 'Driver',
  'app': 'App problem',
  'other': 'Other',
};

class _NewTicketSheet extends StatefulWidget {
  const _NewTicketSheet({required this.support});
  final SupportRemoteDataSource support;

  @override
  State<_NewTicketSheet> createState() => _NewTicketSheetState();
}

class _NewTicketSheetState extends State<_NewTicketSheet> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  String _category = 'other';
  bool _submitting = false;
  // Rendered inside the sheet: a SnackBar would appear on the page's
  // Scaffold, i.e. underneath this modal, where nobody can see it.
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final subject = _subject.text.trim();
    final message = _message.text.trim();
    if (subject.length < 3 || message.isEmpty) {
      setState(() => _error = subject.length < 3
          ? 'Give the ticket a subject (at least 3 characters).'
          : 'Describe what happened.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      final ticket = await widget.support.create(
        subject: subject,
        message: message,
        category: _category,
      );
      navigator.pop(ticket);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      // Anything non-API (parse error, unexpected null…) must still release
      // the button, otherwise the sheet is stuck "submitting" forever.
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + insets,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New support ticket',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.lg),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final e in _categories.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: _submitting
                ? null
                : (v) => setState(() => _category = v ?? 'other'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _subject,
            enabled: !_submitting,
            maxLength: 140,
            decoration: const InputDecoration(
              labelText: 'Subject',
              hintText: 'Short summary',
            ),
          ),
          TextField(
            controller: _message,
            enabled: !_submitting,
            minLines: 3,
            maxLines: 6,
            maxLength: 2000,
            decoration: const InputDecoration(
              labelText: 'What happened?',
              alignLabelWithHint: true,
            ),
          ),
          if (_error != null) ...[
            Text(
              _error!,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.error),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: 'Submit ticket',
            loading: _submitting,
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }
}
