import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Shared building blocks for the two conversation screens — the in-trip chat
/// ([ChatPage]) and the support thread — so bubbles, day separators, the
/// suggestion rows and the composer look and move the same in both.
///
/// Deliberately plain (WhatsApp/Uber-style): flat rounded bubbles, quiet
/// text separators, a plain send icon. The only motion is a short fade on a
/// newly arrived bubble, and none at all under Reduce Motion.

/// "3:07 PM".
String chatClock(DateTime t) {
  final hh = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$hh:${t.minute.toString().padLeft(2, '0')} '
      '${t.hour < 12 ? 'AM' : 'PM'}';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Today" / "Yesterday" / "Mon, 22 Sep" for a day separator.
String chatDayLabel(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  final base = '${_weekdays[t.weekday - 1]}, ${t.day} ${_months[t.month - 1]}';
  return t.year == n.year ? base : '$base ${t.year}';
}

bool chatSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Consecutive messages from one sender within this window share a group:
/// tighter spacing and one timestamp.
const Duration chatGroupWindow = Duration(minutes: 3);

Color _muted(bool dark) =>
    dark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

/// A quiet centred "Today" between days: small muted text, no pill.
class ChatDaySeparator extends StatelessWidget {
  const ChatDaySeparator({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
      child: Center(
        child: Semantics(
          header: true,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: _muted(dark),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// One message bubble: a plain rounded rectangle (radius 18). `mine` = brand
/// teal, right-aligned; otherwise surface.2, left-aligned. [first]/[last]
/// place it inside a sender group: groups sit tight together and only the
/// last bubble carries the timestamp. [animateIn] fades a freshly arrived
/// bubble in over 150 ms (no fade under Reduce Motion).
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.text,
    required this.mine,
    required this.senderName,
    this.time,
    this.first = true,
    this.last = true,
    this.senderLabel,
    this.animateIn = false,
  });

  final String text;
  final bool mine;

  /// Who sent it, for screen readers ("You" for [mine]).
  final String senderName;
  final DateTime? time;
  final bool first;
  final bool last;

  /// Optional name printed above the first bubble of a group (support: "Support").
  final String? senderLabel;
  final bool animateIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final bg = mine
        ? AppColors.inkFor(dark)
        : (dark ? AppColors.surfaceMutedDark : AppColors.surfaceMutedLight);
    // On the teal: white in light; in dark the brighter turquoise carries the
    // palette's own on-ink (white on it would fail contrast).
    final fg = mine ? AppColors.onInkFor(dark) : theme.colorScheme.onSurface;
    final stamp = time == null ? null : chatClock(time!);
    Widget child = Column(
      crossAxisAlignment: mine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (first && senderLabel != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 3),
            child: Text(
              senderLabel!,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: _muted(dark),
              ),
            ),
          ),
        Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.75,
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: fg,
                  height: 1.3,
                ),
              ),
              if (last && stamp != null)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    stamp,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: fg.withValues(alpha: 0.7),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    if (animateIn && !AppMotion.reduced(context)) {
      child = child.animate().fadeIn(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }

    return Semantics(
      container: true,
      label:
          '${mine ? 'You' : senderName}'
          '${stamp == null ? '' : ', $stamp'}: $text',
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.only(top: first ? AppSpacing.sm : 2),
          child: Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A small muted "Sent" under the newest own message — the send was accepted
/// by the server. (There are no read receipts in the data, so it never claims
/// "Read".)
class ChatSentTick extends StatelessWidget {
  const ChatSentTick({super.key, this.label = 'Sent'});
  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 3, right: 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: _muted(dark), fontSize: 11),
        ),
      ),
    );
  }
}

/// One suggestion: a full-width, 48 dp plain-text row. Rows are stacked one
/// per line with thin dividers between them — no icons, no arrows.
class ChatSuggestionRow extends StatelessWidget {
  const ChatSuggestionRow({super.key, required this.text, required this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Send quick reply: $text',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                AppHaptics.selection();
                onTap!();
              },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: 12,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(text, style: theme.textTheme.bodyLarge),
            ),
          ),
        ),
      ),
    );
  }
}

/// The message composer: a rounded text field and a plain send icon button,
/// enabled only once there is text.
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    this.sending = false,
    this.hintText = 'Message',
    this.leading,
    this.submitOnEnter = true,
    this.enabled = true,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool sending;
  final String hintText;
  final Widget? leading;
  final bool submitOnEnter;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(22),
      borderSide: BorderSide.none,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: dark ? AppColors.borderDark : AppColors.borderLight,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ?leading,
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  textInputAction: submitOnEnter
                      ? TextInputAction.send
                      : TextInputAction.newline,
                  onSubmitted: submitOnEnter ? (_) => onSend() : null,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: hintText,
                    filled: true,
                    fillColor: dark
                        ? AppColors.surfaceMutedDark
                        : AppColors.surfaceMutedLight,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    border: border,
                    enabledBorder: border,
                    disabledBorder: border,
                    focusedBorder: border,
                  ),
                ),
              ),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => ChatSendButton(
                  active: controller.text.trim().isNotEmpty && enabled,
                  sending: sending,
                  onPressed: onSend,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The composer's send button: a plain 48 dp icon button, teal when there is
/// something to send, muted and disabled otherwise; a small spinner while
/// sending.
class ChatSendButton extends StatelessWidget {
  const ChatSendButton({
    super.key,
    required this.active,
    required this.sending,
    required this.onPressed,
  });

  final bool active;
  final bool sending;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final on = active && !sending;
    return IconButton(
      tooltip: 'Send message',
      onPressed: on ? onPressed : null,
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: AppColors.accentTextFor(dark),
        disabledForegroundColor: AppColors.iconNeutralFor(
          dark,
        ).withValues(alpha: 0.6),
      ),
      icon: sending
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(
                  AppColors.accentTextFor(dark),
                ),
              ),
            )
          : const Icon(PhosphorIconsRegular.paperPlaneRight),
    );
  }
}
