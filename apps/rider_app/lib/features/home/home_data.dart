import 'package:shared_models/shared_models.dart';

/// A place the rider has been dropped at before — one row of the Home's
/// "Recent" card.
class RecentDestination {
  const RecentDestination({required this.point, required this.address});

  final GeoPoint point;
  final String address;

  /// The first comma-separated part: "Phoenix Mall" of "Phoenix Mall, Viman
  /// Nagar, Pune". Falls back to the whole address.
  String get name {
    final first = address.split(',').first.trim();
    return first.isEmpty ? address : first;
  }
}

/// The last [limit] unique drop-offs from [history] (newest first, as the
/// `/trips/history` API returns it). Only completed rides count — a cancelled
/// request is not somewhere the rider went. Deduped by address text
/// (case/whitespace-insensitive) and by position (~50 m), so "Home" reached
/// twice from different pickups is one row.
List<RecentDestination> recentDestinations(
  List<Trip> history, {
  int limit = 3,
}) {
  final out = <RecentDestination>[];
  for (final t in history) {
    if (t.status != TripStatus.completed) continue;
    final addr = t.dropoff.address?.trim();
    if (addr == null || addr.isEmpty) continue;
    final key = addr.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final dup = out.any(
      (r) =>
          r.address.toLowerCase().replaceAll(RegExp(r'\s+'), ' ') == key ||
          _near(r.point, t.dropoff.point),
    );
    if (dup) continue;
    out.add(RecentDestination(point: t.dropoff.point, address: addr));
    if (out.length == limit) break;
  }
  return out;
}

/// The newest completed ride, if any — the candidate for "Rate your ride".
Trip? lastCompletedRide(List<Trip> history) {
  for (final t in history) {
    if (t.status == TripStatus.completed) return t;
  }
  return null;
}

/// Whether [point] is already one of [places] (same spot within ~50 m, or the
/// same address text) — drives the Home's filled heart.
SavedPlace? savedPlaceAt(
  List<SavedPlace> places,
  GeoPoint point,
  String? address,
) {
  final addr = address?.trim().toLowerCase();
  for (final p in places) {
    if (_near(p.point, point)) return p;
    if (addr != null &&
        addr.isNotEmpty &&
        (p.address?.trim().toLowerCase() == addr)) {
      return p;
    }
  }
  return null;
}

// ~50 m in degrees of latitude; longitude is close enough at city scale for a
// "same place" check (it only errs towards treating two spots as different).
bool _near(GeoPoint a, GeoPoint b) =>
    (a.lat - b.lat).abs() < 0.00045 && (a.lng - b.lng).abs() < 0.00045;
