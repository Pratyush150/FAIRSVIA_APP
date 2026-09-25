import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// "Call rider" on the driver's en-route and waiting screens: opens the
/// phone's dialler on the rider's number (`tel:`). Only shown when the trip
/// payload carries a number (see `Trip.riderPhone`).
///
/// PILOT PRIVACY NOTE: this dials the rider's real number. Production should
/// dial a masked/proxy number issued per trip instead.
class CallRiderButton extends StatelessWidget {
  const CallRiderButton({
    super.key,
    required this.phone,
    this.dialer = dialPhone,
  });

  final String phone;

  /// Launches the dialler; injectable for tests.
  final Future<bool> Function(String phone) dialer;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Call rider',
      icon: Icon(PhosphorIconsRegular.phone, color: AppColors.accent),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        final ok = await dialer(phone);
        if (!ok) {
          messenger.showSnackBar(
            SnackBar(content: Text("Couldn't open the dialler for $phone")),
          );
        }
      },
    );
  }
}
