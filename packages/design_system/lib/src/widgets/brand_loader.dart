import 'package:flutter/material.dart';

import 'lottie_moment.dart';

/// The branded loading indicator: the teal Lottie arc
/// ([LottieMoment.spinner]) in place of a stock CircularProgressIndicator.
///
/// Announced to screen readers as [label] (the art itself is decorative).
/// Under Reduce Motion it shows one still frame of the arc, in the same box,
/// so layouts never jump. Use it for waits that take a beat (app start,
/// fetching fares, a payment going through); keep the plain indicator for
/// tiny inline spinners inside buttons, where a 16 px arc reads the same.
class BrandLoader extends StatelessWidget {
  const BrandLoader({super.key, this.size = 40, this.label = 'Loading'});

  final double size;

  /// What a screen reader says for this wait.
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      liveRegion: true,
      child: SizedBox(
        width: size,
        height: size,
        child: LottieMoment.spinner(size: size),
      ),
    );
  }
}
