/// Screen-reader helpers shared by every app (audit 4.3).
abstract final class AppA11y {
  /// [text] read one character at a time: "MH 12 AB 3456" → "M H 1 2 A B 3 4
  /// 5 6". Screen readers otherwise say a plate or code as a word or a number
  /// ("four thousand eight hundred…"), which is useless for matching a car or
  /// reading out a PIN. Spaces and separators in [text] are dropped; the
  /// characters themselves are kept in order.
  static String spell(String text) => text
      .split('')
      .where((c) => c.trim().isNotEmpty && c != '-' && c != '·')
      .join(' ');
}
