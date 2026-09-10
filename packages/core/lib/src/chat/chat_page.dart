import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../network/api_exception.dart';
import '../realtime/realtime_client.dart';
import 'chat_remote_data_source.dart';

/// In-trip chat with the other party. Loads history over REST, receives live
/// messages over the socket (`trip:message`), and sends over REST. Messages are
/// deduped by id so the sender's socket echo doesn't double up.
class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.tripId,
    required this.currentUserId,
    required this.title,
    required this.chat,
    required this.realtime,
  });

  final String tripId;
  final String currentUserId;
  final String title;
  final ChatRemoteDataSource chat;
  final RealtimeClient realtime;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _messages = <ChatMessage>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<Map<String, dynamic>>? _sub;
  StreamSubscription<void>? _reconnectSub;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sub = widget.realtime.on('trip:message').listen(_onIncoming);
    // Messages the other party sent while our socket was down were never
    // pushed to us; re-pull history on every reconnect. `_merge` dedupes by
    // id, so nothing already on screen doubles up.
    _reconnectSub = widget.realtime.reconnects.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _reconnectSub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final history = await widget.chat.history(widget.tripId);
      if (!mounted) return;
      setState(() {
        _mergeAll(history);
        _loading = false;
      });
      _scrollToEnd();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  void _onIncoming(Map<String, dynamic> data) {
    if (data['tripId'] != widget.tripId) return;
    final msg = ChatMessage.fromJson(data);
    if (!mounted) return;
    setState(() => _merge(msg));
    _scrollToEnd();
  }

  void _merge(ChatMessage m) {
    if (_messages.any((e) => e.id == m.id)) return;
    _messages.add(m);
    _messages.sort((a, b) => a.ts.compareTo(b.ts));
  }

  void _mergeAll(List<ChatMessage> ms) {
    for (final m in ms) {
      _merge(m);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final msg = await widget.chat.send(widget.tripId, text);
      _input.clear();
      if (mounted) setState(() => _merge(msg));
      _scrollToEnd();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(child: _body(context)),
          _composer(context),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(AppColors.accent),
        ),
      );
    }
    if (_error != null && _messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Text('Say hello 👋', style: Theme.of(context).textTheme.bodyLarge),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final m = _messages[i];
        return _Bubble(message: m, mine: m.from == widget.currentUserId);
      },
    );
  }

  Widget _composer(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Message…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});
  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = mine ? AppColors.accent : theme.colorScheme.surfaceContainerHighest;
    final fg = mine ? Colors.white : theme.colorScheme.onSurface;
    final time = message.time;
    final hh = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final stamp = '$hh:${time.minute.toString().padLeft(2, '0')} '
        '${time.hour < 12 ? 'AM' : 'PM'}';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(message.text, style: TextStyle(color: fg)),
            const SizedBox(height: 2),
            Text(
              stamp,
              style: theme.textTheme.bodySmall?.copyWith(
                color: fg.withValues(alpha: 0.7),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
