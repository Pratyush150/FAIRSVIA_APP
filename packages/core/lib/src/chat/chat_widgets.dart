import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Shared building blocks for the two conversation screens — the in-trip chat
/// ([ChatPage]) and the support thread — so bubbles, day separators, the
/// suggestion rows and the composer look and move the same in both.
///
/// Every animation here goes through [AppMotion] tokens and the
/// [AppReveal.motion] helper, so Reduce Motion turns movement into a plain
/// fade.

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
/// tighter spacing, one tail, one timestamp.
const Duration chatGroupWindow = Duration(minutes: 3);

/// A centred "Today" pill between days.
class ChatDaySeparator extends StatelessWidget {
  const ChatDaySeparator({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Center(
        child: Semantics(
          header: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: dark
                  ? AppColors.surfaceMutedDark
                  : AppColors.surfaceMutedLight,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: dark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One message bubble. `mine` = brand teal, right-aligned; otherwise the
/// muted surface (surface.2), left-aligned. [first]/[last] place it inside a
/// sender group: only the last bubble of a group gets the tail corner and the
/// timestamp. [animateIn] pops a freshly arrived bubble in from its tail.
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
    const big = Radius.circular(20);
    const small = Radius.circular(6);
    final radius = BorderRadius.only(
      topLeft: !mine && !first ? small : big,
      bottomLeft: !mine ? small : big,
      topRight: mine && !first ? small : big,
      bottomRight: mine ? small : big,
    );
    final stamp = time == null ? null : chatClock(time!);
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.75,
      ),
      padding: const EdgeInsets.fromLTRB(14, 9, 14, 8),
      decoration: BoxDecoration(color: bg, borderRadius: radius),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: theme.textTheme.bodyLarge?.copyWith(color: fg, height: 1.3),
          ),
          if (last && stamp != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                stamp,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: fg.withValues(alpha: 0.72),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );

    Widget child = Column(
      crossAxisAlignment: mine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (first && senderLabel != null)
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 3),
            child: Text(
              senderLabel!,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.accentTextFor(dark),
              ),
            ),
          ),
        bubble,
      ],
    );
    if (animateIn) {
      final origin = mine ? Alignment.bottomRight : Alignment.bottomLeft;
      child = child.motion(
        (w) => w
            .animate()
            .fadeIn(duration: AppMotion.normal, curve: AppMotion.standard)
            .scaleXY(
              begin: 0.82,
              end: 1,
              alignment: origin,
              duration: AppMotion.slow,
              curve: AppMotion.enter,
            )
            .moveY(
              begin: 10,
              end: 0,
              duration: AppMotion.slow,
              curve: AppMotion.enter,
            ),
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

/// "Sent ✓✓" under the newest own message — the send was accepted by the
/// server. (There are no read receipts in the data, so it never claims
/// "Read".) The ticks pop in once.
class ChatSentTick extends StatelessWidget {
  const ChatSentTick({super.key, this.label = 'Sent'});
  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = dark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;
    return Padding(
      padding: const EdgeInsets.only(top: 4, right: 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: color, fontSize: 11),
            ),
            const SizedBox(width: 3),
            Icon(
              PhosphorIconsRegular.checks,
              size: 14,
              color: AppColors.accentTextFor(dark),
            ).popIn(delay: AppMotion.normal),
          ],
        ),
      ),
    ).reveal();
  }
}

/// A full-width, tappable suggestion row: icon bead + phrase + a small send
/// arrow. At least 56 dp tall (48 dp in [compact] mode).
class ChatSuggestionRow extends StatelessWidget {
  const ChatSuggestionRow({
    super.key,
    required this.text,
    required this.icon,
    required this.onTap,
    this.compact = false,
  });

  final String text;
  final IconData icon;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final fill = dark
        ? Color.alphaBlend(
            AppColors.inkFor(true).withValues(alpha: 0.06),
            AppColors.surfaceMutedDark,
          )
        : AppColors.surfaceLight;
    final border = dark
        ? Colors.white.withValues(alpha: 0.07)
        : AppColors.inkFor(false).withValues(alpha: 0.12);
    final radius = BorderRadius.circular(compact ? 14 : 18);
    return Semantics(
      button: true,
      label: 'Send quick reply: $text',
      excludeSemantics: true,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  AppHaptics.selection();
                  onTap!();
                },
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: compact ? 48 : 58),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 12,
                vertical: compact ? 4 : 8,
              ),
              child: Row(
                children: [
                  if (compact)
                    Icon(icon, size: 20, color: AppColors.accentTextFor(dark))
                  else
                    AppIconBadge(icon: icon),
                  SizedBox(width: compact ? 12 : 14),
                  Expanded(
                    child: Text(
                      text,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    PhosphorIconsRegular.paperPlaneRight,
                    size: 18,
                    color: AppColors.accentTextFor(dark).withValues(alpha: 0.8),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The message composer: a pill text field and a round send button that
/// fills with the brand teal, grows and turns its plane to point forward once
/// there is something to send (Reduce Motion: the colour change only).
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    this.sending = false,
    this.hintText = 'Message…',
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
    final fieldFill = dark
        ? AppColors.surfaceMutedDark
        : AppColors.surfaceMutedLight;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: dark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ?leading,
              if (leading == null) const SizedBox(width: AppSpacing.xs),
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
                    fillColor: fieldFill,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: AppColors.inkFor(dark).withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
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

/// The composer's send button. Idle: a muted disc with a tilted plane.
/// Active: teal, full size, plane levelled. Sending: a spinner.
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
    final bg = on
        ? AppColors.inkFor(dark)
        : (dark ? AppColors.surfaceMutedDark : AppColors.surfaceMutedLight);
    final fg = on ? AppColors.onInkFor(dark) : AppColors.iconNeutralFor(dark);
    final move = AppMotion.of(context, AppMotion.slow);
    return AnimatedScale(
      scale: on || sending ? 1 : 0.9,
      duration: move,
      curve: AppMotion.enter,
      child: AnimatedContainer(
        duration: AppMotion.normal,
        curve: AppMotion.standard,
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          boxShadow: on
              ? [
                  BoxShadow(
                    color: AppColors.inkFor(dark).withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        child: IconButton(
          tooltip: 'Send message',
          onPressed: on ? onPressed : null,
          style: IconButton.styleFrom(
            minimumSize: const Size(48, 48),
            disabledForegroundColor: fg,
            foregroundColor: fg,
          ),
          icon: sending
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(AppColors.inkFor(dark)),
                  ),
                )
              : AnimatedRotation(
                  turns: on ? 0 : -0.07,
                  duration: move,
                  curve: AppMotion.enter,
                  child: Icon(PhosphorIconsRegular.paperPlaneRight, color: fg),
                ),
        ),
      ),
    );
  }
}
