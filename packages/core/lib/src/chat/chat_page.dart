import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../network/api_exception.dart';
import '../realtime/realtime_client.dart';
import 'chat_remote_data_source.dart';
import 'chat_widgets.dart';

/// Uber-style one-tap canned phrases. The icons are kept for API
/// compatibility; the plain suggestion rows show only the text. The shared set reads naturally from either rider or driver, so a
/// tap sends instantly without typing.
const List<(String, IconData)> kChatQuickReplies = [
  ("I'm here", PhosphorIconsRegular.mapPin),
  ('On my way', PhosphorIconsRegular.navigationArrow),
  ('2 min away', PhosphorIconsRegular.clock),
  ('Where are you?', PhosphorIconsRegular.question),
  ('Please wait', PhosphorIconsRegular.hourglass),
  ('Thanks!', PhosphorIconsRegular.heart),
];

/// In-trip chat with the other party. Loads history over REST, receives live
/// messages over the socket (`trip:message`), and sends over REST. Messages are
/// deduped by id so the sender's socket echo doesn't double up.
///
/// Deliberately plain: an app bar with the name and one muted [subtitle] line
/// (car · plate for the rider). Empty: a muted "Send a message to …" line and
/// the quick replies as plain rows, one per line. With messages: flat bubbles
/// grouped by sender with quiet day separators; suggestions are only offered
/// while the thread is empty.
class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.tripId,
    required this.currentUserId,
    required this.title,
    required this.chat,
    required this.realtime,
    this.subtitle,
    this.peerRole = 'driver',
    this.quickReplies = kChatQuickReplies,
  });

  final String tripId;
  final String currentUserId;
  final String title;
  final ChatRemoteDataSource chat;
  final RealtimeClient realtime;

  /// A line under the name, e.g. "White Maruti Dzire · MH 12 AB 1234".
  final String? subtitle;

  /// Who is on the other end ('driver' / 'rider'), for the composer hint.
  final String peerRole;
  final List<(String, IconData)> quickReplies;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final _messages = <ChatMessage>[];

  /// Ids present when history first loaded: those appear without the fade;
  /// anything that arrives later fades in.
  final _initialIds = <String>{};
  bool _historyLoaded = false;
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
    WidgetsBinding.instance.addObserver(this);
    _sub = widget.realtime.on('trip:message').listen(_onIncoming);
    // Messages the other party sent while our socket was down were never
    // pushed to us; re-pull history on every reconnect. `_merge` dedupes by
    // id, so nothing already on screen doubles up.
    _reconnectSub = widget.realtime.reconnects.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
        if (!_historyLoaded) {
          _initialIds.addAll(_messages.map((m) => m.id));
          _historyLoaded = true;
        }
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

  Future<void> _send() => _sendText(_input.text);

  Future<void> _sendText(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final msg = await widget.chat.send(widget.tripId, text);
      _input.clear();
      if (mounted) setState(() => _merge(msg));
      _scrollToEnd();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Keyboard opened or closed: keep the newest message in view.
  @override
  void didChangeMetrics() => _scrollToEnd();

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients || !mounted) return;
      // The thread is a reversed list: the newest message sits at offset 0.
      // Reduce Motion: jump, don't scroll.
      if (AppMotion.reduced(context)) {
        _scroll.jumpTo(0);
      } else {
        _scroll.animateTo(
          0,
          duration: AppMotion.normal,
          curve: AppMotion.standard,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (widget.subtitle != null)
              Text(
                widget.subtitle!,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: dark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _body(context)),
          ChatComposer(
            controller: _input,
            sending: _sending,
            onSend: _send,
            hintText: 'Message your ${widget.peerRole}',
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return Center(
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
    if (_messages.isEmpty) return _emptyState(context);
    return _thread(context);
  }

  /// Nothing sent yet: one muted line in the middle and the suggestions,
  /// one per line, just above the composer.
  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = dark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;
    final divider = Divider(
      height: 1,
      thickness: 0.5,
      indent: AppSpacing.lg,
      endIndent: AppSpacing.lg,
      color: dark ? AppColors.borderDark : AppColors.borderLight,
    );
    final firstName = widget.title.trim().split(RegExp(r'\s+')).first;
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      'Send a message to $firstName',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.xs,
                ),
                child: Text(
                  'Suggestions',
                  style: theme.textTheme.labelMedium?.copyWith(color: muted),
                ),
              ),
              for (final (i, (text, _)) in widget.quickReplies.indexed) ...[
                if (i > 0) divider,
                ChatSuggestionRow(
                  key: ValueKey('quick-reply-$i'),
                  text: text,
                  // _sendText guards against double-sends while one is in
                  // flight.
                  onTap: () => _sendText(text),
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
            ],
          ),
        ),
      ],
    );
  }

  /// The conversation, anchored to the bottom like every messenger (a
  /// reversed list: index 0 is the newest message).
  Widget _thread(BuildContext context) {
    final n = _messages.length;
    // Index of the newest own message, for the "Sent" line.
    final lastMine = _messages.lastIndexWhere(
      (m) => m.from == widget.currentUserId,
    );
    bool joins(ChatMessage? a, ChatMessage b) =>
        a != null &&
        a.from == b.from &&
        chatSameDay(a.time, b.time) &&
        (b.ts - a.ts).abs() <= chatGroupWindow.inMilliseconds;
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      itemCount: n,
      // Keep each bubble's element (and its one-shot fade) attached to its
      // message when a new one is inserted at index 0.
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        final pos = _messages.indexWhere((m) => m.id == key.value);
        return pos < 0 ? null : n - 1 - pos;
      },
      itemBuilder: (context, index) {
        final i = n - 1 - index;
        final m = _messages[i];
        final prev = i > 0 ? _messages[i - 1] : null;
        final next = i + 1 < n ? _messages[i + 1] : null;
        final newDay = prev == null || !chatSameDay(prev.time, m.time);
        final mine = m.from == widget.currentUserId;
        return Column(
          key: ValueKey(m.id),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (newDay) ChatDaySeparator(label: chatDayLabel(m.time)),
            ChatBubble(
              text: m.text,
              mine: mine,
              senderName: widget.title,
              time: m.time,
              first: newDay || !joins(prev, m),
              last: next == null || !joins(m, next),
              animateIn: !_initialIds.contains(m.id),
            ),
            if (i == lastMine && i == n - 1)
              ChatSentTick(key: ValueKey('sent-${m.id}')),
          ],
        );
      },
    );
  }
}
