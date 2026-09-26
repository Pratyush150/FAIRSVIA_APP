/// Display cleanup for place strings that may carry Google's "Unnamed Road"
/// placeholder (common in India, and already stored on older trips).
///
/// - "Unnamed Road, Dattwadi, Pune" -> "Dattwadi, Pune"
/// - "Unnamed Road" alone -> [fallback] (empty by default)
/// - "Mote Mangal Karyalay Rd, ..., Unnamed Road, ..." -> the part is dropped
/// Anything else is returned trimmed, unchanged.
String cleanPlaceLabel(String? raw, {String fallback = ''}) {
  if (raw == null) return fallback;
  final parts = raw
      .split(',')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty && !isUnnamedRoad(p))
      .toList();
  if (parts.isEmpty) return fallback;
  return parts.join(', ');
}

/// True if [s] is Google's "Unnamed Road" placeholder (any case/spacing).
bool isUnnamedRoad(String? s) =>
    s != null && RegExp(r'^unnamed\s+road$', caseSensitive: false)
        .hasMatch(s.trim());
