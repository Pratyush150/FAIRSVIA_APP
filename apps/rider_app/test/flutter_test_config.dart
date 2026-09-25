import 'dart:async';

import 'package:design_system/design_system.dart';

/// Looping effects (the Home search-bar sweep) would keep `pumpAndSettle`
/// from ever settling; tests get their static frame instead.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SweepBorder.debugDisableLoops = true;
  await testMain();
}
