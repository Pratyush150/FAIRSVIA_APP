// Generated from Phosphor Icons (MIT, fonts/Phosphor-LICENSE.txt) —
// only the icons the apps use. The phosphor_flutter package can't be used:
// it subclasses IconData, which current Flutter forbids. To add an icon,
// add its name from phosphoricons.com and look its code point up in the
// Phosphor font's glyph table.
import 'package:flutter/widgets.dart';

/// The font behind [PhosphorIconsRegular]: Regular, except in the Plan E
/// "Ink & Paper" build (`--dart-define=THEME=ink`), whose utility icons are
/// drawn in Phosphor Light — the same code points, a 12-unit stroke instead
/// of 16 — so every screen reads as line art without touching call sites.
/// Build-time, so the icon font tree-shaker still sees constants.
///
/// Plan G "3D Clay" (`THEME=clay3d`) swaps both Regular and Fill for
/// 'Phosphor3D': a colour-bitmap font (CBDT/CBLC for Android, sbix for iOS;
/// tool/icons3d/build.py) whose glyph at each of these code points is the
/// Blender-rendered 3D icon of the same name. Colour bitmaps ignore
/// `Icon.color`, so every icon keeps its own rendered colours.
const String _theme = String.fromEnvironment('THEME');
const String _regularFamily = _theme == 'ink'
    ? 'PhosphorLight'
    : _theme == 'clay3d'
    ? 'Phosphor3D'
    : 'PhosphorRegular';

/// The font behind [PhosphorIconsFill]: Fill, or the 3D font under clay3d.
const String _fillFamily = _theme == 'clay3d' ? 'Phosphor3D' : 'PhosphorFill';

/// Phosphor Regular — the default weight (Light under THEME=ink, see above).
abstract final class PhosphorIconsRegular {
  static const IconData addressBook = IconData(0xe6f8, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData arrowClockwise = IconData(0xe036, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData arrowLeft = IconData(0xe058, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData arrowRight = IconData(0xe06c, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData arrowUpRight = IconData(0xe092, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData arrowsLeftRight = IconData(0xe0a0, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData bank = IconData(0xe0b4, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData bell = IconData(0xe0ce, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData bellRinging = IconData(0xe5e8, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData bookmarkSimple = IconData(0xe0ea, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData briefcase = IconData(0xe0ee, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData broadcast = IconData(0xe0f2, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData calendarBlank = IconData(0xe10a, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData calendarDots = IconData(0xe7b4, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData calendarCheck = IconData(0xe712, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData calendarX = IconData(0xe10c, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData car = IconData(0xe112, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData cards = IconData(0xe0f8, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData caretDown = IconData(0xe136, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData caretLeft = IconData(0xe138, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData caretRight = IconData(0xe13a, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData caretUp = IconData(0xe13c, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData chartLineUp = IconData(0xe156, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData chatCircle = IconData(0xe168, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData chatCircleSlash = IconData(0xe16a, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData chatText = IconData(0xe17a, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData check = IconData(0xe182, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData checks = IconData(0xe53a, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData circle = IconData(0xe18a, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData circleHalf = IconData(0xe18c, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData clock = IconData(0xe19a, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData cloudSlash = IconData(0xe1b6, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData coins = IconData(0xe78e, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData compass = IconData(0xe1c8, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData copy = IconData(0xe1ca, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData creditCard = IconData(0xe1d2, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData deviceMobile = IconData(0xe1e0, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData dotsThree = IconData(0xe1fe, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData envelopeSimple = IconData(0xe218, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData export = IconData(0xeaf0, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData flag = IconData(0xe244, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData gpsFix = IconData(0xedd6, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData gpsSlash = IconData(0xedd4, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData handHeart = IconData(0xe810, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData headset = IconData(0xe584, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData heart = IconData(0xe2a8, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData heartbeat = IconData(0xe2ac, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData hourglass = IconData(0xe2b2, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData house = IconData(0xe2c2, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData info = IconData(0xe2ce, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData lightning = IconData(0xe2de, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData list = IconData(0xe2f0, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData magnifyingGlass = IconData(0xe30c, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData mapPin = IconData(0xe316, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData mapPinPlus = IconData(0xe314, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData mapTrifold = IconData(0xe31a, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData money = IconData(0xe588, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData moon = IconData(0xe330, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData moonStars = IconData(0xe58e, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData navigationArrow = IconData(0xeade, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData note = IconData(0xe348, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData paperPlaneRight = IconData(0xe396, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData path = IconData(0xe39c, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData pencilSimple = IconData(0xe3b4, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData percent = IconData(0xe3b6, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData personSimpleWalk = IconData(0xe73a, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData phone = IconData(0xe3b8, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData piggyBank = IconData(0xea04, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData plus = IconData(0xe3d4, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData question = IconData(0xe3e8, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData receipt = IconData(0xe3ec, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData record = IconData(0xe3ee, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData ruler = IconData(0xe6b8, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData shieldCheck = IconData(0xe40c, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData signOut = IconData(0xe42a, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData siren = IconData(0xe9b8, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData squaresFour = IconData(0xe464, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData star = IconData(0xe46a, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData sun = IconData(0xe472, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData tag = IconData(0xe478, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData taxi = IconData(0xe902, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData ticket = IconData(0xe490, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData toggleLeft = IconData(0xe674, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData trash = IconData(0xe4a6, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData tray = IconData(0xe4aa, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData trendUp = IconData(0xe4ae, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData user = IconData(0xe4c2, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData userCircle = IconData(0xe4c4, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData userMinus = IconData(0xe4ce, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData userPlus = IconData(0xe4d0, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData users = IconData(0xe4d6, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData wallet = IconData(0xe68a, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData warning = IconData(0xe4e0, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData warningCircle = IconData(0xe4e2, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData wrench = IconData(0xe5d4, fontFamily: _regularFamily, fontPackage: 'design_system');
  static const IconData x = IconData(0xe4f6, fontFamily: _regularFamily, fontPackage: 'design_system');

  /// Phosphor's own motorcycle — the bike-taxi glyph (a rider/helmet cue was
  /// tried and turns to a blob at 20-24 px).
  static const IconData motorcycle = IconData(0xe80a, fontFamily: _regularFamily, fontPackage: 'design_system');

  // FAIRSVIA additions — not part of Phosphor. Our own paths on Phosphor's
  // 256 grid and 16-unit stroke (the font itself is MIT), added to the
  // vendored fonts at private-use code points by tool/ridevela_glyphs/build.py.
  /// Indian auto-rickshaw, side-on (Phosphor has none).
  static const IconData autoRickshaw = IconData(0xf8f0, fontFamily: _regularFamily, fontPackage: 'design_system');
  /// Banknote with ₹ — cash payment (Phosphor `money` has no currency mark).
  static const IconData cashRupee = IconData(0xf8f2, fontFamily: _regularFamily, fontPackage: 'design_system');
}

/// Phosphor Fill — for states only: rated, favourited, selected.
abstract final class PhosphorIconsFill {
  static const IconData checkCircle = IconData(0xe184, fontFamily: _fillFamily, fontPackage: 'design_system');
  static const IconData circle = IconData(0xe18a, fontFamily: _fillFamily, fontPackage: 'design_system');
  static const IconData bookmarkSimple = IconData(0xe0ea, fontFamily: _fillFamily, fontPackage: 'design_system');
  static const IconData heart = IconData(0xe2a8, fontFamily: _fillFamily, fontPackage: 'design_system');
  static const IconData sealCheck = IconData(0xe606, fontFamily: _fillFamily, fontPackage: 'design_system');
  static const IconData shieldCheck = IconData(0xe40c, fontFamily: _fillFamily, fontPackage: 'design_system');
  static const IconData square = IconData(0xe45e, fontFamily: _fillFamily, fontPackage: 'design_system');
  static const IconData star = IconData(0xe46a, fontFamily: _fillFamily, fontPackage: 'design_system');
  static const IconData toggleRight = IconData(0xe676, fontFamily: _fillFamily, fontPackage: 'design_system');
  static const IconData motorcycle = IconData(0xe80a, fontFamily: _fillFamily, fontPackage: 'design_system');

  // FAIRSVIA additions (see PhosphorIconsRegular) — Fill weights of our paths.
  static const IconData autoRickshaw = IconData(0xf8f0, fontFamily: _fillFamily, fontPackage: 'design_system');
  static const IconData cashRupee = IconData(0xf8f2, fontFamily: _fillFamily, fontPackage: 'design_system');
}

/// Phosphor Light (MIT, fonts/Phosphor-LICENSE.txt; vendored from
/// @phosphor-icons/web 2.1.1, src/light/Phosphor-Light.ttf): the line-art
/// weight of Plan E "Ink & Paper". Same code points as Regular (checked
/// glyph by glyph against both fonts' cmaps), plus the FAIRSVIA additions
/// built into it by `tool/ridevela_glyphs/build.py light`. Under THEME=ink
/// [PhosphorIconsRegular] already resolves to this font; use this class
/// directly for a glyph that must be Light in every build.
abstract final class PhosphorIconsLight {
  static const IconData addressBook = IconData(0xe6f8, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData arrowClockwise = IconData(0xe036, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData arrowUpRight = IconData(0xe092, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData arrowsLeftRight = IconData(0xe0a0, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData bank = IconData(0xe0b4, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData bell = IconData(0xe0ce, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData bellRinging = IconData(0xe5e8, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData briefcase = IconData(0xe0ee, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData broadcast = IconData(0xe0f2, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData calendarBlank = IconData(0xe10a, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData calendarDots = IconData(0xe7b4, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData calendarCheck = IconData(0xe712, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData calendarX = IconData(0xe10c, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData car = IconData(0xe112, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData cards = IconData(0xe0f8, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData caretDown = IconData(0xe136, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData caretRight = IconData(0xe13a, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData caretUp = IconData(0xe13c, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData chartLineUp = IconData(0xe156, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData chatCircle = IconData(0xe168, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData chatCircleSlash = IconData(0xe16a, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData chatText = IconData(0xe17a, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData check = IconData(0xe182, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData checks = IconData(0xe53a, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData circle = IconData(0xe18a, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData circleHalf = IconData(0xe18c, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData clock = IconData(0xe19a, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData cloudSlash = IconData(0xe1b6, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData coins = IconData(0xe78e, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData compass = IconData(0xe1c8, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData copy = IconData(0xe1ca, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData creditCard = IconData(0xe1d2, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData deviceMobile = IconData(0xe1e0, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData dotsThree = IconData(0xe1fe, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData envelopeSimple = IconData(0xe218, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData export = IconData(0xeaf0, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData flag = IconData(0xe244, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData gpsFix = IconData(0xedd6, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData gpsSlash = IconData(0xedd4, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData handHeart = IconData(0xe810, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData headset = IconData(0xe584, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData bookmarkSimple = IconData(0xe0ea, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData heart = IconData(0xe2a8, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData heartbeat = IconData(0xe2ac, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData hourglass = IconData(0xe2b2, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData house = IconData(0xe2c2, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData info = IconData(0xe2ce, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData lightning = IconData(0xe2de, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData list = IconData(0xe2f0, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData magnifyingGlass = IconData(0xe30c, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData mapPin = IconData(0xe316, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData mapPinPlus = IconData(0xe314, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData mapTrifold = IconData(0xe31a, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData money = IconData(0xe588, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData moon = IconData(0xe330, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData moonStars = IconData(0xe58e, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData navigationArrow = IconData(0xeade, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData note = IconData(0xe348, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData paperPlaneRight = IconData(0xe396, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData path = IconData(0xe39c, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData pencilSimple = IconData(0xe3b4, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData percent = IconData(0xe3b6, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData personSimpleWalk = IconData(0xe73a, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData phone = IconData(0xe3b8, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData piggyBank = IconData(0xea04, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData plus = IconData(0xe3d4, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData question = IconData(0xe3e8, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData receipt = IconData(0xe3ec, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData record = IconData(0xe3ee, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData ruler = IconData(0xe6b8, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData shieldCheck = IconData(0xe40c, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData signOut = IconData(0xe42a, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData siren = IconData(0xe9b8, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData squaresFour = IconData(0xe464, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData star = IconData(0xe46a, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData sun = IconData(0xe472, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData tag = IconData(0xe478, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData taxi = IconData(0xe902, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData ticket = IconData(0xe490, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData toggleLeft = IconData(0xe674, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData trash = IconData(0xe4a6, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData tray = IconData(0xe4aa, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData trendUp = IconData(0xe4ae, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData user = IconData(0xe4c2, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData userCircle = IconData(0xe4c4, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData userMinus = IconData(0xe4ce, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData userPlus = IconData(0xe4d0, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData users = IconData(0xe4d6, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData wallet = IconData(0xe68a, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData warning = IconData(0xe4e0, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData warningCircle = IconData(0xe4e2, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData wrench = IconData(0xe5d4, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData x = IconData(0xe4f6, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData motorcycle = IconData(0xe80a, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData autoRickshaw = IconData(0xf8f0, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
  static const IconData cashRupee = IconData(0xf8f2, fontFamily: 'PhosphorLight', fontPackage: 'design_system');
}
