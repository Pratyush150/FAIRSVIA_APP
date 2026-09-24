from palettes_def import P
FLAG={"registan-lapis":"lapis","marigold":"marigold","ikat-indigo":"indigo","anor-garnet":"garnet","bukhara-copper":"copper"}
PRESS={"registan-lapis":("#193686","#7D94E0"),"marigold":("#9C3908","#E08C3B"),"ikat-indigo":("#402AA6","#9486E0"),"anor-garnet":("#84173B","#E05E82"),"bukhara-copper":("#3A3B3D","#CC7946")}
def c(h): return "Color(0xFF%s)"%h.lstrip('#').upper()
def snip(n):
    f=FLAG[n]; L=P[n]["light"]; D=P[n]["dark"]; lp,dp=PRESS[n]
    return f"""```dart
// THEME={f}  (flutter build ... --dart-define=THEME={f})
// 1. Flag, next to planDark / planLight; and count it as a v2-style build
//    (softer radii, dark-mode danger) by widening `v2`:
static const bool {f} = variant == '{f}';
static const bool v2 = planDark || planLight || {f};

// 2. Ink / highlight. Light ink -> _tealInk, light highlight -> _turquoise,
//    dark highlight -> _turquoiseBright, text on dark ink -> _onTurquoise.
static const Color _tealInk = {f} ? {c(L['brand'])}
    : (planLight ? Color(0xFF0A7C7C) : Color(0xFF0B3C49));
static const Color _turquoise = {f} ? {c(L['hi'])}
    : (planLight ? Color(0xFF2BC4C4) : Color(0xFF0FA3A8));
static const Color _turquoiseBright = {f} ? {c(D['hi'])}
    : (planDark ? Color(0xFF2BC4C4) : Color(0xFF2EC4C6));
static const Color _onTurquoise = {f} ? {c(D['on'])}
    : (planDark ? Color(0xFF0E0F11) : Color(0xFF00181B));
// NEW: dark ink separate from the dark highlight (today they share
// _turquoiseBright). Then in inkFor: `dark ? _inkDark : _tealInk`.
static const Color _inkDark = {f} ? {c(D['brand'])} : _turquoiseBright;

// 3. Pressed ink (inside accentPressed's `turquoise ?` arm):
//    dark:  {f} ? const {c(dp)} : const Color(0xFF26A9AB)
//    light: {f} ? const {c(lp)} : (planLight ? ... existing ...)

// 4. Tints (softFor):
//    dark:  {f} ? const {c(D['tint'])} : (planDark ? ... existing ...)
//    light: {f} ? const {c(L['tint'])} : const Color(0xFFE6F6F6)

// 5. Surfaces, text, lines (prepend `{f} ? X :` to each existing ternary):
static const Color surfaceLight      = {c(L['s1'])};
static const Color surfaceMutedLight = {f} ? {c(L['s2'])} : (planLight ? Color(0xFFEEF0F2) : Color(0xFFF3F3F3));
static const Color backgroundLight   = {f} ? {c(L['bg'])} : (planLight ? Color(0xFFF5F6F7) : Color(0xFFFFFFFF));
static const Color surfaceDark       = {f} ? {c(D['s1'])} : (planDark ? Color(0xFF17181B) : Color(0xFF141414));
static const Color surfaceMutedDark  = {f} ? {c(D['s2'])} : (planDark ? Color(0xFF1F2024) : Color(0xFF282828));
static const Color backgroundDark    = {f} ? {c(D['bg'])} : (planDark ? Color(0xFF0E0F11) : Color(0xFF000000));
static const Color accentSoftDark    = {f} ? {c(D['s2'])} : (planDark ? Color(0xFF1F2024) : Color(0xFF282828));
static const Color textPrimaryLight  = {f} ? {c(L['text'])} : (planLight ? Color(0xFF111315) : Color(0xFF000000));
static const Color textSecondaryLight= {f} ? {c(L['text2'])} : (planLight ? Color(0xFF5F646B) : Color(0xFF545454));
static const Color textTertiaryLight = {f} ? Color(0xFF686B71) : Color(0xFF757575); // #757575 is <4.5 on the tinted surface.2
static const Color textSecondaryDark = {f} ? {c(D['text2'])} : (planDark ? Color(0xFFA0A3A8) : Color(0xFFAFAFAF));
static const Color borderLight       = {f} ? {c(L['border'])} : (planLight ? Color(0xFFE3E5E8) : Color(0xFFE8E8E8));
static const Color borderDark        = {f} ? {c(D['border'])} : (planDark ? Color(0xFF2A2C31) : Color(0xFF333333));

// 6. Semantic. `success` is one colour for both modes today; add a dark twin.
static const Color success     = {f} ? {c(L['success'])} : Color(0xFF05944F);
static const Color successDark = {f} ? {c(D['success'])} : Color(0xFF05944F);
static Color successFor(bool dark) => dark ? successDark : success;
static const Color warning     = {f} ? {c(L['warning'])} : Color(0xFFC67C00);
static const Color error       = {f} ? {c(L['danger'])} : Color(0xFFE11900);
static const Color warningDark = {f} ? {c(D['warning'])} : Color(0xFFF5A623);
static const Color dangerDark  = {f} ? {c(D['danger'])} : Color(0xFFFF4D4F);
static const Color errorInk    = {f} ? {c(L['danger'])} : Color(0xFFB21400); // white on it >= 4.8
```"""
import sys
for n in FLAG: open(f"snip_{FLAG[n]}.md","w").write(snip(n))
print(snip("ikat-indigo"))
