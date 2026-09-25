import 'package:flutter/material.dart';
import '../theme/phosphor_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';

/// A slim bar at the top of the screen reporting realtime connectivity.
///
/// Down → an amber "Reconnecting…" bar, held for as long as the socket is
/// down. Back up → a green "Connected" confirmation for
/// [reconnectedHold], then it collapses to nothing. The confirmation matters:
/// without it a rider who watched the bar sit there has no signal that live
/// updates resumed, and the map silently catching up looks the same as the map
/// still being stale.
///
/// It collapses to zero height when connected and idle, so it can be placed
/// unconditionally at the top of a scaffold body. Marked as an assertive live
/// region so screen readers announce each change.
class ConnectionBanner extends StatefulWidget {
  const ConnectionBanner({
    super.key,
    required this.connected,
    this.message = 'Reconnecting… live updates are paused',
    this.reconnectedMessage = 'Connected — live updates resumed',
  });

  final bool connected;
  final String message;
  final String reconnectedMessage;

  /// How long the green confirmation stays up after the socket recovers.
  static const Duration reconnectedHold = Duration(seconds: 3);

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends State<ConnectionBanner> {
  /// True between a recovery and the end of [ConnectionBanner.reconnectedHold].
  bool _confirming = false;
  // Guards the delayed hide: a second drop inside the hold window must not be
  // cleared by the first drop's timer firing late.
  int _holdToken = 0;

  @override
  void didUpdateWidget(ConnectionBanner old) {
    super.didUpdateWidget(old);
    if (old.connected == widget.connected) return;
    if (widget.connected) {
      // Only confirm a genuine recovery — not the very first build, which is
      // already `connected: true` and has nothing to reassure anyone about.
      final token = ++_holdToken;
      setState(() => _confirming = true);
      Future<void>.delayed(ConnectionBanner.reconnectedHold, () {
        if (mounted && token == _holdToken) setState(() => _confirming = false);
      });
    } else {
      _holdToken++; // cancel any pending hide
      setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showing = !widget.connected || _confirming;
    final text =
        widget.connected ? widget.reconnectedMessage : widget.message;
    // Dark ink on the ochre, white on the deep green: both ≥4.5:1.
    final ink = widget.connected ? Colors.white : AppColors.onWarning;
    return AnimatedSize(
      duration: AppMotion.of(context, AppMotion.normal),
      alignment: Alignment.topCenter,
      child: !showing
          ? const SizedBox(width: double.infinity)
          : Semantics(
              liveRegion: true,
              container: true,
              label: text,
              child: Material(
                color: widget.connected
                    ? AppColors.successBanner
                    : AppColors.warning,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.connected)
                          Icon(PhosphorIconsRegular.check,
                              size: 16, color: ink)
                        else
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(ink),
                            ),
                          ),
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(
                          child: Text(
                            text,
                            style: TextStyle(
                              color: ink,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
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
