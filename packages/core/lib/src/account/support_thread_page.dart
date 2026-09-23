import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../network/api_exception.dart';
import 'format.dart';
import 'support_page.dart' show supportStatusColor;
import 'support_remote_data_source.dart';

/// A single support ticket's conversation, with a reply composer at the bottom.
/// Admin replies appear left-aligned; the user's own messages right-aligned.
class SupportThreadPage extends StatefulWidget {
  const SupportThreadPage({
    super.key,
    required this.support,
    required this.ticketId,
  });

  final SupportRemoteDataSource support;
  final String ticketId;

  @override
  State<SupportThreadPage> createState() => _SupportThreadPageState();
}

class _SupportThreadPageState extends State<SupportThreadPage> {
  final _reply = TextEditingController();
  final _scroll = ScrollController();
  SupportTicket? _ticket;
  Object? _error;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = await widget.support.thread(widget.ticketId);
      if (!mounted) return;
      setState(() {
        _ticket = t;
        _loading = false;
      });
      _scrollToEnd();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final body = _reply.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final t = await widget.support.reply(widget.ticketId, body);
      if (!mounted) return;
      _reply.clear();
      setState(() {
        _ticket = t;
        _sending = false;
      });
      _scrollToEnd();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _ticket;
    return Scaffold(
      appBar: AppBar(
        title: Text(t?.subject ?? 'Ticket'),
        bottom: t == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
                    child: Text(
                      Fmt.status(t.status),
                      style: TextStyle(
                        color: supportStatusColor(t.status),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
      ),
      body: Column(
        children: [
          Expanded(child: _body(t)),
          if (t != null && !t.isClosed) _composer() else if (t != null) _closed(),
        ],
      ),
    );
  }

  Widget _body(SupportTicket? t) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(AppColors.accent),
        ),
      );
    }
    if (_error != null || t == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 40),
              const SizedBox(height: AppSpacing.md),
              Text(
                _error is ApiException
                    ? (_error! as ApiException).message
                    : 'Could not load this ticket.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: t.messages.length,
      itemBuilder: (context, i) => _Bubble(message: t.messages[i]),
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _reply,
                enabled: !_sending,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'Write a reply…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }

  Widget _closed() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          'This ticket is closed.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final SupportMessage message;

  @override
  Widget build(BuildContext context) {
    final admin = message.isFromAdmin;
    final theme = Theme.of(context);
    return Align(
      alignment: admin ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: admin
              ? theme.colorScheme.surfaceContainerHighest
              : AppColors.accent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment:
              admin ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            if (admin)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  'Support',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            Text(
              message.body,
              style: TextStyle(color: admin ? null : Colors.white),
            ),
            if (message.createdAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  Fmt.dateTime(message.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: admin
                        ? theme.textTheme.bodySmall?.color
                        : Colors.white70,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
