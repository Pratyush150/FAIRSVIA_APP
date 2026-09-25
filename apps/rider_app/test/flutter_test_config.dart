import 'dart:async';

import 'package:design_system/design_system.dart';

/// Looping effects (the Home search-bar sweep, the poster shimmer) would keep `pumpAndSettle`
/// from ever settling; tests get their static frame instead.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SweepBorder.debugDisableLoops = true;
  PosterShimmer.debugDisableLoops = true;
  await testMain();
}
