/// A one-line, non-blocking note for the trip-complete sheet when the trip
/// did not end at the drop-off — e.g. "Ended 0.8 km before the drop-off ·
/// minimum fare". Null for an ordinary drop-off. [receipt] is the
/// `trip:completed` / POST complete payload.
String? completionNote(Map<String, dynamic> receipt) {
  final b = receipt['breakdown'];
  if (b is! Map) return null;
  final basis = switch (b['fareBasis']) {
    'metered' => 'metered fare',
    'minimum' => 'minimum fare',
    'estimate' => 'capped at the quote',
    _ => null,
  };
  final away = b['endedAwayFromDropoffM'];
  String? what;
  if (b['endReason'] == 'Rider ended the trip') {
    what = 'The rider ended the trip here';
  } else if (away is num && away > 0) {
    final d = away >= 1000
        ? '${(away / 1000).toStringAsFixed(1)} km'
        : '${away.round()} m';
    what = 'Ended $d before the drop-off';
  } else if (b['endedEarly'] == true) {
    what = 'Ended before the drop-off';
  }
  if (what == null) return null;
  return basis == null ? what : '$what · $basis';
}
