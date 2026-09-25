import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../chat/chat_widgets.dart';
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

  /// Messages on screen at first load don't pop in; later ones do.
  Set<String>? _initialIds;

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
        _initialIds ??= {for (final m in t.messages) m.id};
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
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.sm,
                    ),
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
          if (t != null && !t.isClosed)
            _composer()
          else if (t != null)
            _closed(),
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
              const Icon(
                PhosphorIconsRegular.warningCircle,
                color: AppColors.error,
                size: 40,
              ),
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
                icon: const Icon(PhosphorIconsRegular.arrowClockwise),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    final msgs = t.messages;
    bool joins(SupportMessage? a, SupportMessage b) =>
        a != null &&
        a.isFromAdmin == b.isFromAdmin &&
        a.createdAt != null &&
        b.createdAt != null &&
        chatSameDay(a.createdAt!, b.createdAt!) &&
        b.createdAt!.difference(a.createdAt!).abs() <= chatGroupWindow;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.md,
      ),
      itemCount: msgs.length,
      itemBuilder: (context, i) {
        final m = msgs[i];
        final prev = i > 0 ? msgs[i - 1] : null;
        final next = i + 1 < msgs.length ? msgs[i + 1] : null;
        final at = m.createdAt?.toLocal();
        final newDay =
            at != null &&
            (prev?.createdAt == null ||
                !chatSameDay(prev!.createdAt!.toLocal(), at));
        return Column(
          key: ValueKey(m.id),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (newDay) ChatDaySeparator(label: chatDayLabel(at)),
            ChatBubble(
              text: m.body,
              mine: !m.isFromAdmin,
              senderName: 'Support',
              senderLabel: m.isFromAdmin ? 'Support' : null,
              time: at,
              first: newDay || !joins(prev, m),
              last: next == null || !joins(m, next),
              animateIn: !(_initialIds?.contains(m.id) ?? true),
            ),
          ],
        );
      },
    );
  }

  Widget _composer() {
    return ChatComposer(
      controller: _reply,
      sending: _sending,
      enabled: !_sending,
      onSend: _send,
      hintText: 'Write a reply…',
      submitOnEnter: false,
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
