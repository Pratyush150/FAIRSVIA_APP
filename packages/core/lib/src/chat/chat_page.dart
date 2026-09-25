import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../network/api_exception.dart';
import '../realtime/realtime_client.dart';
import 'chat_remote_data_source.dart';
import 'chat_widgets.dart';

/// Uber-style one-tap canned phrases, each with the icon its suggestion row
/// shows. The shared set reads naturally from either rider or driver, so a
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
/// Empty: a header (the other party's avatar, name and [subtitle] — car and
/// plate for the rider) and the quick replies as a vertical list of
/// full-width rows that stagger in. With messages: bubbles grouped by sender
/// with day separators, and the quick replies one tap away behind the
/// composer's lightning button, still one per line.
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

  /// Who is on the other end ('driver' / 'rider'), for the empty-state hint.
  final String peerRole;
  final List<(String, IconData)> quickReplies;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final _messages = <ChatMessage>[];

  /// Ids present when history first loaded: those appear without the pop-in;
  /// anything that arrives later animates.
  final _initialIds = <String>{};
  bool _historyLoaded = false;
  bool _repliesOpen = false;
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
    setState(() {
      _sending = true;
      _repliesOpen = false;
    });
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hasMessages = !_loading && _messages.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            AppAvatar(name: widget.title, size: 36),
            const SizedBox(width: AppSpacing.sm + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.title, overflow: TextOverflow.ellipsis),
                  if (widget.subtitle != null)
                    Text(
                      widget.subtitle!,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: dark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _body(context)),
          if (hasMessages) _repliesPanel(context),
          ChatComposer(
            controller: _input,
            sending: _sending,
            onSend: _send,
            leading: hasMessages ? _repliesToggle(context) : null,
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

  /// The first screen: who you're talking to, what this is for, and the
  /// quick replies one per line.
  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final secondary = dark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;
    final ink = AppColors.inkFor(dark);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      children: [
        Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      ink.withValues(alpha: 0.55),
                      ink.withValues(alpha: 0.12),
                    ],
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.scaffoldBackgroundColor,
                  ),
                  child: AppAvatar(name: widget.title, size: 76),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: ink,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.scaffoldBackgroundColor,
                      width: 3,
                    ),
                  ),
                  child: Icon(
                    PhosphorIconsRegular.chatCircle,
                    size: 15,
                    color: AppColors.onInkFor(dark),
                  ),
                ).popIn(delay: AppMotion.slow),
              ),
            ],
          ),
        ).popIn(),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          header: true,
          child: Text(
            'Chat with ${widget.title}',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ).reveal(delay: AppMotion.stagger),
        if (widget.subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.subtitle!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: secondary),
          ).reveal(delay: AppMotion.stagger * 2),
        ],
        const SizedBox(height: AppSpacing.md),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.softFor(dark),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  PhosphorIconsRegular.shieldCheck,
                  size: 16,
                  color: AppColors.accentTextFor(dark),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Messages go straight to your ${widget.peerRole}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.accentTextFor(dark),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ).reveal(delay: AppMotion.stagger * 3),
        const SizedBox(height: AppSpacing.xl),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
          child: Text(
            'QUICK REPLIES',
            style: theme.textTheme.labelSmall?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ).reveal(delay: AppMotion.stagger * 4),
        for (final (i, (text, icon)) in widget.quickReplies.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ChatSuggestionRow(
              key: ValueKey('quick-reply-$i'),
              text: text,
              icon: icon,
              // _sendText guards against double-sends while one is in flight.
              onTap: () => _sendText(text),
            ),
          ).revealStaggered(i, base: AppMotion.stagger * 5),
      ],
    );
  }

  /// The conversation, anchored to the bottom like every messenger (a
  /// reversed list: index 0 is the newest message), opening with a small
  /// intro card so a short thread never floats in an empty screen.
  Widget _thread(BuildContext context) {
    final n = _messages.length;
    // Index of the newest own message, for the "Sent" tick.
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
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      itemCount: n + 1,
      // Keep each bubble's element (and its one-shot pop-in) attached to its
      // message when a new one is inserted at index 0.
      findChildIndexCallback: (key) {
        if (key == const ValueKey('chat-intro')) return n;
        if (key is! ValueKey<String>) return null;
        final pos = _messages.indexWhere((m) => m.id == key.value);
        return pos < 0 ? null : n - 1 - pos;
      },
      itemBuilder: (context, index) {
        if (index == n) {
          return KeyedSubtree(
            key: const ValueKey('chat-intro'),
            child: _threadIntro(context),
          );
        }
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

  /// A compact "who is this" card at the top of a thread.
  Widget _threadIntro(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final secondary = dark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
      child: Column(
        children: [
          AppAvatar(name: widget.title, size: 56),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Chat with ${widget.title}',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (widget.subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                widget.subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: secondary),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Messages go straight to your ${widget.peerRole}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: secondary),
          ),
        ],
      ),
    );
  }

  Widget _repliesToggle(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: IconButton(
        tooltip: _repliesOpen ? 'Hide quick replies' : 'Quick replies',
        isSelected: _repliesOpen,
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
        onPressed: () {
          AppHaptics.selection();
          setState(() => _repliesOpen = !_repliesOpen);
        },
        icon: AnimatedSwitcher(
          duration: AppMotion.normal,
          transitionBuilder: (child, anim) => AppMotion.reduced(context)
              ? FadeTransition(opacity: anim, child: child)
              : RotationTransition(
                  turns: Tween(begin: 0.75, end: 1.0).animate(anim),
                  child: ScaleTransition(scale: anim, child: child),
                ),
          child: Icon(
            _repliesOpen
                ? PhosphorIconsRegular.caretDown
                : PhosphorIconsRegular.lightning,
            key: ValueKey(_repliesOpen),
            color: AppColors.accentTextFor(dark),
          ),
        ),
      ),
    );
  }

  /// With a conversation on screen: the same suggestions, still one per
  /// line, sliding open above the composer.
  Widget _repliesPanel(BuildContext context) {
    return AnimatedSize(
      duration: AppMotion.of(context, AppMotion.slow),
      curve: AppMotion.enter,
      alignment: Alignment.bottomCenter,
      child: !_repliesOpen
          ? const SizedBox(width: double.infinity)
          : ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.4,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.xs,
                ),
                children: [
                  for (final (i, (text, icon)) in widget.quickReplies.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ChatSuggestionRow(
                        key: ValueKey('quick-reply-$i'),
                        compact: true,
                        text: text,
                        icon: icon,
                        onTap: () => _sendText(text),
                      ),
                    ).revealStaggered(i),
                ],
              ),
            ),
    );
  }
}
