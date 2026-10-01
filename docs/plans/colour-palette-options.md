# FAIRSVIA colour palette options (beyond Samarkand Turquoise)

*Prepared 2026-09-24 for the owner. This is a design proposal only: **no code or existing files were changed.** Every contrast number here was computed by a script (WCAG 2.x relative luminance), not estimated; the scripts sit next to the mocks (see "Reproduce"). The mock PNGs and scripts are in docs/brand/research/.*

## TL;DR: ranked recommendation

| Rank | Palette | Light ink / highlight | Dark ink / highlight | One-line verdict |
|---|---|---|---|---|
| 1 | **Ikat Indigo** (`THEME=indigo`) | `#4B32C3` / `#6A4DF0` | `#A898FF` / `#B6A8FF` | Unclaimed by any ride app here; strongest semantic and CVD separation; watch for PhonePe purple |
| 2 | **Registan Lapis & Gold** (`THEME=lapis`) | `#1D3F9E` / `#2F5BD3` | `#8EA8FF` / gold `#F0C052` | Most Samarkand; beautiful dark mode, but blue clashes with the location-dot and info-blue rules |
| 3 | **Marigold** (`THEME=marigold`) | `#B8430A` / `#D9570F` | `#FF9F43` / `#FFB547` | Most Indian and emotional; warm colours crowd warning and danger; near Swiggy and Yandex |
| 4 | **Bukhara Copper** (`THEME=copper`) | graphite `#1F2023` / copper `#B4541E` | `#E8894F` / `#F09A5E` | Premium and quiet, but light mode is Uber's black button; copper ≈ amber for CVD users |
| 5 | **Anor Garnet** (`THEME=garnet`) | `#9B1B45` / `#C2255C` | `#FF6B94` / `#FF7AA0` | Distinctive but red-family, so it fights SOS and danger in a safety-critical app |

**My recommendation:** A/B test **Ikat Indigo** against the current **Samarkand Turquoise**, with **Registan Lapis** as the alternate. The logic:
- Turquoise itself is not taken by any competitor in these markets.
- Indigo is the only candidate that is both unclaimed and robust for semantics and CVD.
- Lapis is the best story for the Uzbekistan launch, if the location-dot conflict is solved.

Marigold is the best choice if the brief is "feel Indian first", but it costs us the conventional warning and danger colours.

**Two findings about the *current* palette, found while building the baseline:**
1. The shipped light highlight `#0FA3A8` against a light map grey `#E5E7EB` is **2.49:1**, below the 3:1 non-text minimum for the route line. Against `#E6F6F6` (the selected-row tint) it is 2.77:1.
2. Plan B's bright route teal `#2BC4C4` on the same map grey is **1.73:1** (2.14 on white).

In other words, the light-mode turquoise route line fails WCAG 1.4.11 today. Every palette below was tuned so its light highlight passes.

Other baseline notes:
- Shipped `success` `#05944F` (3.92) and `warning` `#C67C00` (3.34) are below 4.5 on white when used as text.
- Shipped dark `error` `#E11900` is 3.81 on `#141414`. `dangerDark` exists for this but is used only by the v2 builds.
- `textTertiaryLight` `#757575` on `#F3F3F3` is 4.15.

## 1. Competitor colour research

Where a source gives a hex, it is cited. **"Inference"** marks what I believe from product knowledge or screenshots but could not confirm in a primary source this session.

| Brand | Signature colour | How it is used in-app | Dark mode | Sources |
|---|---|---|---|---|
| **Uber** | Black `#000000` / white; one blue accent `#276EF1`; negative `#E11900`, warning `#FFC043`, positive `#048848` (Base) | Primary CTA is the black pill; the UI chrome is deliberately colourless | Semantic "Platform Colors" tokens (`?textPrimary`, etc.) flip per theme; linter blocks raw hex | [Superdesign on Base](https://superdesign.dev/blog/uber-design-system), [Base Web v9](https://baseweb.design/blog/base-web-v9/), [Uber dark-mode blog](https://www.uber.com/us/en/blog/from-light-to-dark-the-story-behind-dark-mode/), [shadcn Uber tokens](https://www.shadcn.io/design/uber) |
| **Ola** | Logo: black `#000000` + pear/lime `#D7DF23` | *Inference:* the app uses black primary buttons with the lime-green as an accent (logo, highlights), not as button fill | *Inference:* no well-documented public dark theme | [BrandPalettes – Ola Cabs](https://brandpalettes.com/ola-cabs-logo-colors/), [1000logos – Ola](https://1000logos.net/ola-cabs-logo/) |
| **Rapido** | Yellow `#FFCC0F` with near-black `#272324` | *Inference:* yellow fills primary buttons with black text; yellow is the brand everywhere (captain helmets, bikes) | *Inference:* none documented | [Brandfetch – Rapido](https://brandfetch.com/rapido.bike), [Rapido Labs design system (403 when fetched)](https://medium.com/rapido-labs/building-rapidos-design-system-54a0e94bf5dc) |
| **Bolt** | Green `#34BB78` (Pantone 7480); refresh added a darker green for accessible contrast | One unified green across cars, bags and apps; "accent elements" highlight information (no public detail on button vs accent) | Not documented in the refresh article | [Bolt refresh](https://bolt.eu/en/refresh/), [BrandColorCode – Bolt](https://www.brandcolorcode.com/bolt) |
| **Yandex Go** | Yellow (Yandex taxi yellow `#FFCC00`, "Supernova"); Yandex corporate red/orange + black | *Inference:* yellow primary buttons with black text in the taxi flow; Yandex Go leads in Uzbekistan | *Inference:* has a dark theme | [Design Compass – Yandex Go](https://designcompass.org/en/2025/07/23/yandex-go/), [BrandPalettes – Yandex](https://brandpalettes.com/yandex-colors/), [Behance – ONY Yandex Go](https://www.behance.net/gallery/103007517/Yandex-Go?locale=en_US) |
| **inDrive** | Bright lime-green `#C1F11D` (2022–23 rebrand; pushed "richer, more energetic" in the May 2026 redesign) | *Inference:* lime CTA on dark/graphite UI; strong in Kazakhstan, Uzbekistan and Central Asia | *Inference:* dark-leaning brand | [logos-world](https://logos-world.net/indrive-unveils-new-logo-and-brand-identity/), [1000logos 2026 redesign](https://1000logos.net/news/indrive-logo-redesign-shows-what-happens-when-a-tech-brand-stops-looking-like-every-other-tech-brand/), [Brandfetch – inDrive](https://brandfetch.com/indrive.com) |
| **Grab** | Green `#00B14F` | *Inference:* green primary buttons and accents | Not verified | [encycolorpedia #00b14f](https://encycolorpedia.com/00b14f), [BrandColorCode – Grab](https://www.brandcolorcode.com/grab-holdings), [Mobbin – Grab (403)](https://mobbin.com/colors/brand/grab) |
| **Careem** | Careem Green `#00E784`; Forest `#00493E`; Midnight Blue `#001942`; Go sub-brand blue `#3837E4` | Official: green is the "green thread", "particularly in call-to-action buttons and celebratory moments"; Midnight Blue for text legibility on green | Not stated | [Careem brand – Colour](https://brand.careem.com/colour/), [Careem blog](https://blog.careem.com/posts/say-hello-to-the-new-careem-%F0%9F%92%9A) |
| **Namma Yatri** | *Inference:* yellow + black (auto-rickshaw yellow); yellow-black number plates in the car imagery are confirmed | *Inference:* yellow primary buttons with black text | Not verified | [Play Store](https://play.google.com/store/apps/details?id=in.juspay.nammayatri&hl=en_US), [Medium UX review (403)](https://medium.com/@msonam2018/namma-yatri-why-this-indigenous-mobility-app-earns-a-4-5-5-ux-rating-bc854c70dfb0) |
| **Lyft** | Pink `#FF00BF`, black `#11111F` | Pink for brand moments; per the shadcn token dump, dark mode uses purple-magenta `#820076` for CTAs on a warm `#1D0C17` | As left (third-party token dump, *treat as unverified*) | [BrandColors – Lyft](https://www.brandcolors.net/b/lyft), [shadcn Lyft tokens](https://www.shadcn.io/design/lyft) |

Adjacent brands that matter on an Indian phone (*inference, general knowledge*): **PhonePe** purple `~#5F259F`, **Swiggy** orange `~#FC8019`, **Zomato** red `~#E23744`, **Paytm** blue.

**Correction to the brief:** it lists "Ola green/black". Ola's documented mark is **black plus a pear/lime `#D7DF23`**, so "Ola green" in the sense of Bolt or Grab green is not accurate. The yellow-green is still close to inDrive's lime, which is another reason to avoid lime.

### Colours to avoid, and why

| Colour | Owned by | Verdict |
|---|---|---|
| Yellow `#FFCC00`-ish | Rapido (India), Yandex Go (Uzbekistan leader), Namma Yatri (inferred), Ola's pear | **Avoid** as brand. It is also the yellow of taxi and auto-rickshaws, so we would never read as distinct. Keep yellow only for stars. |
| Pure black as the primary | Uber | **Avoid** as the sole identity. It is fine as neutral ink (Copper option), but then the brand has to come from elsewhere. |
| Mid/bright green | Bolt `#34BB78`, Grab `#00B14F`, Careem `#00E784`, Ola lime | **Avoid.** Four competitors, plus a clash with our `success` meaning. This is why an "Emerald" option was dropped. |
| Electric lime on graphite | inDrive `#C1F11D` (very strong in Central Asia) | **Avoid.** It would look like an inDrive knock-off in Tashkent. |
| Hot pink / magenta | Lyft (not in market) | Low market risk, but pink-on-dark shows up in Anor's dark mode; noted there. |
| Purple | PhonePe (payments, India) | Not a ride competitor, but it appears on our payment screens; see Ikat Indigo. |

## 2. Method

- **Tokens:** bg.base, surface.1, surface.2, border, text.primary, text.secondary, brand/ink, on.brand, highlight (route/selection), brand.tint, success, warning, danger, for light and dark.
- **Required checks (all must pass):**
  - text.primary and text.secondary on surface.1 ≥ 4.5
  - on.brand on brand ≥ 4.5
  - highlight against map grey (`#E5E7EB` light / `#2A2C31` dark) ≥ 3.0, the WCAG 1.4.11 non-text minimum for the route line
- **Extra checks (reported, also all passing):**
  - brand and highlight on surface.1 ≥ 3
  - highlight on brand.tint ≥ 3 (the selected-row outline)
  - text.secondary on surface.2 ≥ 4.5
  - success, warning and danger on surface.1 ≥ 4.5, so they can be used as text
- **Separation:** CIEDE2000 ΔE between brand/highlight and success/warning/danger. My target was ≥ 20 for every pair in normal vision. I also simulated protanopia and deuteranopia (Machado 2009, severity 1.0) for the risky pairs.
- **Result:** all five palettes pass every required and extra contrast check. The first drafts of Marigold, Anor, Copper and Lapis-dark had semantic colours too close to the brand (worst: Copper light highlight vs warning, ΔE **2.9**). They were retuned before being presented here.
- **Limitations:** the map grey is a flat stand-in. Real tiles vary: parks, water and label halos. The route should keep a 1–2 px halo in surface colour, as the current app does, and each palette should be re-checked on a real map screenshot on the emulator. The CVD simulation is a model, not a user test.

## 3. The five palettes (in ranked order)

Contact sheet (current turquoise baseline at top-left, then the five): `docs/brand/research/all.png`

![all palettes](/tmp/claude-1000/-home-nova-robotics-ubernav/32b0b03b-f246-44cd-933a-739a28167dfc/scratchpad/palettes/all.png)

### 1. Ikat Indigo: `THEME=indigo`

*Indigo dye of Indian block print and Uzbek ikat silk: deep, calm, premium.*

Mock: `/tmp/claude-1000/-home-nova-robotics-ubernav/32b0b03b-f246-44cd-933a-739a28167dfc/scratchpad/palettes/ikat-indigo.png`

![Ikat Indigo](/tmp/claude-1000/-home-nova-robotics-ubernav/32b0b03b-f246-44cd-933a-739a28167dfc/scratchpad/palettes/ikat-indigo.png)

**Why it works.** No ride-hailing brand in India or Central Asia owns indigo. It reads calm and premium, and it has real roots in both markets: Indian indigo dye and Uzbek ikat (*abr*) silk, which is indigo plus saffron. Keep a marigold `#F5A524` for illustrations and 3D icons only, never for UI state. It separates best from the semantic colours of any option: ΔE00 is 27 or more everywhere, and it still holds at 39+ under simulated protan/deutan vision. The route contrast is strong (4.31 light, 6.68 dark).

**Risks, stated honestly.**
- **PhonePe purple (`#5F259F`) is the biggest payments brand in India**, and its logo will appear next to our buttons on the UPI screens. Our indigo is bluer and brighter (hue 250° against PhonePe's 269°, computed), but some people may still think "PhonePe" at first sight.
- Careem uses `#3837E4` for its Go/ride sub-brand, which is close. Careem does not operate in India or Uzbekistan today, so the clash is low-risk.
- In the mock, the dark-mode button (`#A898FF` lavender) looks a little pastel. If the owner wants more punch, a more saturated `#9C8CFF` also passes: 6.78:1 with `#120E2A` text and 6.52:1 on surface.1 (computed).

**Tokens**

| token | light | dark |
|---|---|---|
| bg.base | `#F6F5FB` | `#0E0D16` |
| surface.1 | `#FFFFFF` | `#171522` |
| surface.2 | `#EFEDF7` | `#211E30` |
| border | `#E1DEEE` | `#2E2A42` |
| text.primary | `#141225` | `#FFFFFF` |
| text.secondary | `#5E5A72` | `#A9A5BD` |
| brand / ink | `#4B32C3` | `#A898FF` |
| on.brand | `#FFFFFF` | `#120E2A` |
| highlight (route, selection) | `#6A4DF0` | `#B6A8FF` |
| brand.tint | `#EEEAFD` | `#251F45` |
| success | `#0A7D3E` | `#34C77B` |
| warning | `#946200` | `#F5A623` |
| danger | `#C8231B` | `#FF5A52` |

**Computed contrast (WCAG ratio)**

| check | light | dark |
|---|---|---|
| text.primary / surface.1 | 18.37 pass | 18.00 pass |
| text.secondary / surface.1 | 6.60 pass | 7.55 pass |
| on.brand / brand | 8.26 pass | 7.67 pass |
| highlight / map grey | 4.31 pass | 6.68 pass |
| brand / surface.1 (button edge) *(extra)* | 8.26 pass | 7.37 pass |
| highlight / surface.1 (selected outline) *(extra)* | 5.34 pass | 8.60 pass |
| highlight / brand.tint *(extra)* | 4.53 pass | 7.37 pass |
| text.secondary / surface.2 *(extra)* | 5.70 pass | 6.81 pass |
| success / surface.1 *(extra)* | 5.23 pass | 8.23 pass |
| warning / surface.1 *(extra)* | 5.24 pass | 8.88 pass |
| danger / surface.1 *(extra)* | 5.66 pass | 5.86 pass |

**Build it as a theme variant.** Snippet only, not applied. It follows the existing const-conditional mechanism on `AppColors.variant` in `packages/design_system/lib/src/theme/app_colors.dart`:

```dart
// THEME=indigo  (flutter build ... --dart-define=THEME=indigo)
// 1. Flag, next to planDark / planLight; and count it as a v2-style build
//    (softer radii, dark-mode danger) by widening `v2`:
static const bool indigo = variant == 'indigo';
static const bool v2 = planDark || planLight || indigo;

// 2. Ink / highlight. Light ink -> _tealInk, light highlight -> _turquoise,
//    dark highlight -> _turquoiseBright, text on dark ink -> _onTurquoise.
static const Color _tealInk = indigo ? Color(0xFF4B32C3)
    : (planLight ? Color(0xFF0A7C7C) : Color(0xFF0B3C49));
static const Color _turquoise = indigo ? Color(0xFF6A4DF0)
    : (planLight ? Color(0xFF2BC4C4) : Color(0xFF0FA3A8));
static const Color _turquoiseBright = indigo ? Color(0xFFB6A8FF)
    : (planDark ? Color(0xFF2BC4C4) : Color(0xFF2EC4C6));
static const Color _onTurquoise = indigo ? Color(0xFF120E2A)
    : (planDark ? Color(0xFF0E0F11) : Color(0xFF00181B));
// NEW: dark ink separate from the dark highlight (today they share
// _turquoiseBright). Then in inkFor: `dark ? _inkDark : _tealInk`.
static const Color _inkDark = indigo ? Color(0xFFA898FF) : _turquoiseBright;

// 3. Pressed ink (inside accentPressed's `turquoise ?` arm):
//    dark:  indigo ? const Color(0xFF9486E0) : const Color(0xFF26A9AB)
//    light: indigo ? const Color(0xFF402AA6) : (planLight ? ... existing ...)

// 4. Tints (softFor):
//    dark:  indigo ? const Color(0xFF251F45) : (planDark ? ... existing ...)
//    light: indigo ? const Color(0xFFEEEAFD) : const Color(0xFFE6F6F6)

// 5. Surfaces, text, lines (prepend `indigo ? X :` to each existing ternary):
static const Color surfaceLight      = Color(0xFFFFFFFF);
static const Color surfaceMutedLight = indigo ? Color(0xFFEFEDF7) : (planLight ? Color(0xFFEEF0F2) : Color(0xFFF3F3F3));
static const Color backgroundLight   = indigo ? Color(0xFFF6F5FB) : (planLight ? Color(0xFFF5F6F7) : Color(0xFFFFFFFF));
static const Color surfaceDark       = indigo ? Color(0xFF171522) : (planDark ? Color(0xFF17181B) : Color(0xFF141414));
static const Color surfaceMutedDark  = indigo ? Color(0xFF211E30) : (planDark ? Color(0xFF1F2024) : Color(0xFF282828));
static const Color backgroundDark    = indigo ? Color(0xFF0E0D16) : (planDark ? Color(0xFF0E0F11) : Color(0xFF000000));
static const Color accentSoftDark    = indigo ? Color(0xFF211E30) : (planDark ? Color(0xFF1F2024) : Color(0xFF282828));
static const Color textPrimaryLight  = indigo ? Color(0xFF141225) : (planLight ? Color(0xFF111315) : Color(0xFF000000));
static const Color textSecondaryLight= indigo ? Color(0xFF5E5A72) : (planLight ? Color(0xFF5F646B) : Color(0xFF545454));
static const Color textTertiaryLight = indigo ? Color(0xFF686B71) : Color(0xFF757575); // #757575 is <4.5 on the tinted surface.2
static const Color textSecondaryDark = indigo ? Color(0xFFA9A5BD) : (planDark ? Color(0xFFA0A3A8) : Color(0xFFAFAFAF));
static const Color borderLight       = indigo ? Color(0xFFE1DEEE) : (planLight ? Color(0xFFE3E5E8) : Color(0xFFE8E8E8));
static const Color borderDark        = indigo ? Color(0xFF2E2A42) : (planDark ? Color(0xFF2A2C31) : Color(0xFF333333));

// 6. Semantic. `success` is one colour for both modes today; add a dark twin.
static const Color success     = indigo ? Color(0xFF0A7D3E) : Color(0xFF05944F);
static const Color successDark = indigo ? Color(0xFF34C77B) : Color(0xFF05944F);
static Color successFor(bool dark) => dark ? successDark : success;
static const Color warning     = indigo ? Color(0xFF946200) : Color(0xFFC67C00);
static const Color error       = indigo ? Color(0xFFC8231B) : Color(0xFFE11900);
static const Color warningDark = indigo ? Color(0xFFF5A623) : Color(0xFFF5A623);
static const Color dangerDark  = indigo ? Color(0xFFFF5A52) : Color(0xFFFF4D4F);
static const Color errorInk    = indigo ? Color(0xFFC8231B) : Color(0xFFB21400); // white on it >= 4.8
```

### 2. Registan Lapis & Gold: `THEME=lapis`

*Lapis tilework and gold of Samarkand's Registan; blue reads 'maps & trust' in both markets.*

Mock: `/tmp/claude-1000/-home-nova-robotics-ubernav/32b0b03b-f246-44cd-933a-739a28167dfc/scratchpad/palettes/registan-lapis.png`

![Registan Lapis & Gold](/tmp/claude-1000/-home-nova-robotics-ubernav/32b0b03b-f246-44cd-933a-739a28167dfc/scratchpad/palettes/registan-lapis.png)

**Why it works.** This is the most Samarkand of the five: lapis-blue tiles and gold. The light mode is very legible (route 4.77:1). The dark mode's gold route on a navy map is the most striking image in the contact sheet.

**Risks, stated honestly.**
- **Blue already has a job in this app.** The system location dot is blue (foundation rule 2 in visual-direction-v2), and so is `info` `#276EF1`. In light mode a lapis route would sit next to a blue "you are here" dot, so we would have to change the dot or the rule.
- In India a blue primary looks like fintech or government (Paytm, many bank apps). It is professional but not memorable.
- **The gold dark highlight collapses into the warning colour under CVD** (ΔE 6.4 deutan, 11.1 protan). Warnings must always carry an icon and a label. Colour alone is not enough.
- Gold is close to the Yandex Go yellow family, and Yandex Go is the market leader in Uzbekistan. Using it only in dark mode, only as a line, keeps the risk small but real.

**Tokens**

| token | light | dark |
|---|---|---|
| bg.base | `#F4F6FA` | `#0B0F1A` |
| surface.1 | `#FFFFFF` | `#141A28` |
| surface.2 | `#ECEFF5` | `#1C2334` |
| border | `#DDE2EB` | `#2A3246` |
| text.primary | `#0F1729` | `#FFFFFF` |
| text.secondary | `#556070` | `#A3ACBD` |
| brand / ink | `#1D3F9E` | `#8EA8FF` |
| on.brand | `#FFFFFF` | `#0B0F1A` |
| highlight (route, selection) | `#2F5BD3` | `#F0C052` |
| brand.tint | `#E8EEFB` | `#1E2A4A` |
| success | `#0A7D3E` | `#34C77B` |
| warning | `#946200` | `#FF8A3D` |
| danger | `#C8231B` | `#FF4D6D` |

**Computed contrast (WCAG ratio)**

| check | light | dark |
|---|---|---|
| text.primary / surface.1 | 17.87 pass | 17.38 pass |
| text.secondary / surface.1 | 6.38 pass | 7.61 pass |
| on.brand / brand | 9.30 pass | 8.38 pass |
| highlight / map grey | 4.77 pass | 8.23 pass |
| brand / surface.1 (button edge) *(extra)* | 9.30 pass | 7.61 pass |
| highlight / surface.1 (selected outline) *(extra)* | 5.90 pass | 10.24 pass |
| highlight / brand.tint *(extra)* | 5.07 pass | 8.33 pass |
| text.secondary / surface.2 *(extra)* | 5.54 pass | 6.86 pass |
| success / surface.1 *(extra)* | 5.23 pass | 7.95 pass |
| warning / surface.1 *(extra)* | 5.24 pass | 7.41 pass |
| danger / surface.1 *(extra)* | 5.66 pass | 5.41 pass |

**Build it as a theme variant.** Snippet only, not applied. It follows the existing const-conditional mechanism on `AppColors.variant` in `packages/design_system/lib/src/theme/app_colors.dart`:

```dart
// THEME=lapis  (flutter build ... --dart-define=THEME=lapis)
// 1. Flag, next to planDark / planLight; and count it as a v2-style build
//    (softer radii, dark-mode danger) by widening `v2`:
static const bool lapis = variant == 'lapis';
static const bool v2 = planDark || planLight || lapis;

// 2. Ink / highlight. Light ink -> _tealInk, light highlight -> _turquoise,
//    dark highlight -> _turquoiseBright, text on dark ink -> _onTurquoise.
static const Color _tealInk = lapis ? Color(0xFF1D3F9E)
    : (planLight ? Color(0xFF0A7C7C) : Color(0xFF0B3C49));
static const Color _turquoise = lapis ? Color(0xFF2F5BD3)
    : (planLight ? Color(0xFF2BC4C4) : Color(0xFF0FA3A8));
static const Color _turquoiseBright = lapis ? Color(0xFFF0C052)
    : (planDark ? Color(0xFF2BC4C4) : Color(0xFF2EC4C6));
static const Color _onTurquoise = lapis ? Color(0xFF0B0F1A)
    : (planDark ? Color(0xFF0E0F11) : Color(0xFF00181B));
// NEW: dark ink separate from the dark highlight (today they share
// _turquoiseBright). Then in inkFor: `dark ? _inkDark : _tealInk`.
static const Color _inkDark = lapis ? Color(0xFF8EA8FF) : _turquoiseBright;

// 3. Pressed ink (inside accentPressed's `turquoise ?` arm):
//    dark:  lapis ? const Color(0xFF7D94E0) : const Color(0xFF26A9AB)
//    light: lapis ? const Color(0xFF193686) : (planLight ? ... existing ...)

// 4. Tints (softFor):
//    dark:  lapis ? const Color(0xFF1E2A4A) : (planDark ? ... existing ...)
//    light: lapis ? const Color(0xFFE8EEFB) : const Color(0xFFE6F6F6)

// 5. Surfaces, text, lines (prepend `lapis ? X :` to each existing ternary):
static const Color surfaceLight      = Color(0xFFFFFFFF);
static const Color surfaceMutedLight = lapis ? Color(0xFFECEFF5) : (planLight ? Color(0xFFEEF0F2) : Color(0xFFF3F3F3));
static const Color backgroundLight   = lapis ? Color(0xFFF4F6FA) : (planLight ? Color(0xFFF5F6F7) : Color(0xFFFFFFFF));
static const Color surfaceDark       = lapis ? Color(0xFF141A28) : (planDark ? Color(0xFF17181B) : Color(0xFF141414));
static const Color surfaceMutedDark  = lapis ? Color(0xFF1C2334) : (planDark ? Color(0xFF1F2024) : Color(0xFF282828));
static const Color backgroundDark    = lapis ? Color(0xFF0B0F1A) : (planDark ? Color(0xFF0E0F11) : Color(0xFF000000));
static const Color accentSoftDark    = lapis ? Color(0xFF1C2334) : (planDark ? Color(0xFF1F2024) : Color(0xFF282828));
static const Color textPrimaryLight  = lapis ? Color(0xFF0F1729) : (planLight ? Color(0xFF111315) : Color(0xFF000000));
static const Color textSecondaryLight= lapis ? Color(0xFF556070) : (planLight ? Color(0xFF5F646B) : Color(0xFF545454));
static const Color textTertiaryLight = lapis ? Color(0xFF686B71) : Color(0xFF757575); // #757575 is <4.5 on the tinted surface.2
static const Color textSecondaryDark = lapis ? Color(0xFFA3ACBD) : (planDark ? Color(0xFFA0A3A8) : Color(0xFFAFAFAF));
static const Color borderLight       = lapis ? Color(0xFFDDE2EB) : (planLight ? Color(0xFFE3E5E8) : Color(0xFFE8E8E8));
static const Color borderDark        = lapis ? Color(0xFF2A3246) : (planDark ? Color(0xFF2A2C31) : Color(0xFF333333));

// 6. Semantic. `success` is one colour for both modes today; add a dark twin.
static const Color success     = lapis ? Color(0xFF0A7D3E) : Color(0xFF05944F);
static const Color successDark = lapis ? Color(0xFF34C77B) : Color(0xFF05944F);
static Color successFor(bool dark) => dark ? successDark : success;
static const Color warning     = lapis ? Color(0xFF946200) : Color(0xFFC67C00);
static const Color error       = lapis ? Color(0xFFC8231B) : Color(0xFFE11900);
static const Color warningDark = lapis ? Color(0xFFFF8A3D) : Color(0xFFF5A623);
static const Color dangerDark  = lapis ? Color(0xFFFF4D6D) : Color(0xFFFF4D4F);
static const Color errorInk    = lapis ? Color(0xFFC8231B) : Color(0xFFB21400); // white on it >= 4.8
```

### 3. Marigold: `THEME=marigold`

*Marigold garlands and saffron: warm, festive, unmistakably Indian; also the apricot/sun of Uzbek bazaars.*

Mock: `/tmp/claude-1000/-home-nova-robotics-ubernav/32b0b03b-f246-44cd-933a-739a28167dfc/scratchpad/palettes/marigold.png`

![Marigold](/tmp/claude-1000/-home-nova-robotics-ubernav/32b0b03b-f246-44cd-933a-739a28167dfc/scratchpad/palettes/marigold.png)

**Why it works.** This is the most emotional and the most Indian option: marigold garlands, saffron, festival light. In Uzbekistan it maps to apricots and sun. The light mode is warm and distinctive, and the route passes at 3.19:1, the smallest margin of the five.

**Risks, stated honestly.**
- **Warm crowding.** An orange brand leaves no room for a conventional amber warning or a red danger. I moved warning to olive-gold (`#7A5C00` / `#E8E05A`) and danger to crimson (`#BE185D` / `#FF5C8A`). They now pass ΔE00 ≥ 20, but under simulated protan vision the highlight and warning are only 7.0 (light) and 7.9 (dark) apart. Warning must never rely on colour alone.
- **Brand adjacency.** Swiggy orange (`#FC8019`) owns orange on Indian phones, and the dark-mode `#FF9F43` button sits near Yandex Go's yellow-orange in Uzbekistan. Rapido `#FFCC0F` is yellower. The deep saffron light ink `#B8430A` is safer than the dark ink.
- The light ink only passes 5.46:1 with white. That is fine, but it leaves little room for a lighter tweak.

**Tokens**

| token | light | dark |
|---|---|---|
| bg.base | `#FAF7F2` | `#110D0A` |
| surface.1 | `#FFFFFF` | `#1B1612` |
| surface.2 | `#F3EEE6` | `#25201A` |
| border | `#E8E1D6` | `#352D25` |
| text.primary | `#1A140E` | `#FFFFFF` |
| text.secondary | `#6B6158` | `#B0A69B` |
| brand / ink | `#B8430A` | `#FF9F43` |
| on.brand | `#FFFFFF` | `#1A0E00` |
| highlight (route, selection) | `#D9570F` | `#FFB547` |
| brand.tint | `#FDEFE3` | `#3A2512` |
| success | `#0A7D3E` | `#34C77B` |
| warning | `#7A5C00` | `#E8E05A` |
| danger | `#BE185D` | `#FF5C8A` |

**Computed contrast (WCAG ratio)**

| check | light | dark |
|---|---|---|
| text.primary / surface.1 | 18.26 pass | 17.95 pass |
| text.secondary / surface.1 | 6.04 pass | 7.50 pass |
| on.brand / brand | 5.46 pass | 9.30 pass |
| highlight / map grey | 3.19 pass | 7.95 pass |
| brand / surface.1 (button edge) *(extra)* | 5.46 pass | 8.80 pass |
| highlight / surface.1 (selected outline) *(extra)* | 3.95 pass | 10.21 pass |
| highlight / brand.tint *(extra)* | 3.50 pass | 8.22 pass |
| text.secondary / surface.2 *(extra)* | 5.23 pass | 6.75 pass |
| success / surface.1 *(extra)* | 5.23 pass | 8.21 pass |
| warning / surface.1 *(extra)* | 6.25 pass | 13.03 pass |
| danger / surface.1 *(extra)* | 6.04 pass | 6.11 pass |

**Build it as a theme variant.** Snippet only, not applied. It follows the existing const-conditional mechanism on `AppColors.variant` in `packages/design_system/lib/src/theme/app_colors.dart`:

```dart
// THEME=marigold  (flutter build ... --dart-define=THEME=marigold)
// 1. Flag, next to planDark / planLight; and count it as a v2-style build
//    (softer radii, dark-mode danger) by widening `v2`:
static const bool marigold = variant == 'marigold';
static const bool v2 = planDark || planLight || marigold;

// 2. Ink / highlight. Light ink -> _tealInk, light highlight -> _turquoise,
//    dark highlight -> _turquoiseBright, text on dark ink -> _onTurquoise.
static const Color _tealInk = marigold ? Color(0xFFB8430A)
    : (planLight ? Color(0xFF0A7C7C) : Color(0xFF0B3C49));
static const Color _turquoise = marigold ? Color(0xFFD9570F)
    : (planLight ? Color(0xFF2BC4C4) : Color(0xFF0FA3A8));
static const Color _turquoiseBright = marigold ? Color(0xFFFFB547)
    : (planDark ? Color(0xFF2BC4C4) : Color(0xFF2EC4C6));
static const Color _onTurquoise = marigold ? Color(0xFF1A0E00)
    : (planDark ? Color(0xFF0E0F11) : Color(0xFF00181B));
// NEW: dark ink separate from the dark highlight (today they share
// _turquoiseBright). Then in inkFor: `dark ? _inkDark : _tealInk`.
static const Color _inkDark = marigold ? Color(0xFFFF9F43) : _turquoiseBright;

// 3. Pressed ink (inside accentPressed's `turquoise ?` arm):
//    dark:  marigold ? const Color(0xFFE08C3B) : const Color(0xFF26A9AB)
//    light: marigold ? const Color(0xFF9C3908) : (planLight ? ... existing ...)

// 4. Tints (softFor):
//    dark:  marigold ? const Color(0xFF3A2512) : (planDark ? ... existing ...)
//    light: marigold ? const Color(0xFFFDEFE3) : const Color(0xFFE6F6F6)

// 5. Surfaces, text, lines (prepend `marigold ? X :` to each existing ternary):
static const Color surfaceLight      = Color(0xFFFFFFFF);
static const Color surfaceMutedLight = marigold ? Color(0xFFF3EEE6) : (planLight ? Color(0xFFEEF0F2) : Color(0xFFF3F3F3));
static const Color backgroundLight   = marigold ? Color(0xFFFAF7F2) : (planLight ? Color(0xFFF5F6F7) : Color(0xFFFFFFFF));
static const Color surfaceDark       = marigold ? Color(0xFF1B1612) : (planDark ? Color(0xFF17181B) : Color(0xFF141414));
static const Color surfaceMutedDark  = marigold ? Color(0xFF25201A) : (planDark ? Color(0xFF1F2024) : Color(0xFF282828));
static const Color backgroundDark    = marigold ? Color(0xFF110D0A) : (planDark ? Color(0xFF0E0F11) : Color(0xFF000000));
static const Color accentSoftDark    = marigold ? Color(0xFF25201A) : (planDark ? Color(0xFF1F2024) : Color(0xFF282828));
static const Color textPrimaryLight  = marigold ? Color(0xFF1A140E) : (planLight ? Color(0xFF111315) : Color(0xFF000000));
static const Color textSecondaryLight= marigold ? Color(0xFF6B6158) : (planLight ? Color(0xFF5F646B) : Color(0xFF545454));
static const Color textTertiaryLight = marigold ? Color(0xFF686B71) : Color(0xFF757575); // #757575 is <4.5 on the tinted surface.2
static const Color textSecondaryDark = marigold ? Color(0xFFB0A69B) : (planDark ? Color(0xFFA0A3A8) : Color(0xFFAFAFAF));
static const Color borderLight       = marigold ? Color(0xFFE8E1D6) : (planLight ? Color(0xFFE3E5E8) : Color(0xFFE8E8E8));
static const Color borderDark        = marigold ? Color(0xFF352D25) : (planDark ? Color(0xFF2A2C31) : Color(0xFF333333));

// 6. Semantic. `success` is one colour for both modes today; add a dark twin.
static const Color success     = marigold ? Color(0xFF0A7D3E) : Color(0xFF05944F);
static const Color successDark = marigold ? Color(0xFF34C77B) : Color(0xFF05944F);
static Color successFor(bool dark) => dark ? successDark : success;
static const Color warning     = marigold ? Color(0xFF7A5C00) : Color(0xFFC67C00);
static const Color error       = marigold ? Color(0xFFBE185D) : Color(0xFFE11900);
static const Color warningDark = marigold ? Color(0xFFE8E05A) : Color(0xFFF5A623);
static const Color dangerDark  = marigold ? Color(0xFFFF5C8A) : Color(0xFFFF4D4F);
static const Color errorInk    = marigold ? Color(0xFFBE185D) : Color(0xFFB21400); // white on it >= 4.8
```

### 4. Bukhara Copper: `THEME=copper`

*Graphite and hammered copper of Bukhara's coppersmiths: quiet, premium, one warm signature.*

Mock: `/tmp/claude-1000/-home-nova-robotics-ubernav/32b0b03b-f246-44cd-933a-739a28167dfc/scratchpad/palettes/bukhara-copper.png`

![Bukhara Copper](/tmp/claude-1000/-home-nova-robotics-ubernav/32b0b03b-f246-44cd-933a-739a28167dfc/scratchpad/palettes/bukhara-copper.png)

**Why it works.** This is the premium option. Buttons are graphite, and one warm copper signature is used for the route, the selection and the dark-mode ink. It has the least visual noise, and dark mode (copper button, 7.34:1) looks rich.

**Risks, stated honestly.**
- **Light mode is Uber's look**: a black pill button on white. With the Road-V logo recoloured, the brand is carried only by the route and the selection outline.
- **Copper is next to amber.** Before retuning, the light highlight `#B4541E` was ΔE **2.9** from the old warning, so I moved warning to `#7A6200` and danger to crimson. Under simulated protan vision the light highlight and warning are still only **1.9** apart, which means indistinguishable, so warning needs an icon and a label.
- Dark copper sits close to Marigold's dark mode. They are not really two different directions.

**Tokens**

| token | light | dark |
|---|---|---|
| bg.base | `#F6F5F3` | `#0F0F10` |
| surface.1 | `#FFFFFF` | `#18181A` |
| surface.2 | `#EFEDEA` | `#222225` |
| border | `#E3E0DB` | `#2F2F33` |
| text.primary | `#151412` | `#FFFFFF` |
| text.secondary | `#625E58` | `#A7A5A1` |
| brand / ink | `#1F2023` | `#E8894F` |
| on.brand | `#FFFFFF` | `#1B0D04` |
| highlight (route, selection) | `#B4541E` | `#F09A5E` |
| brand.tint | `#F8ECE3` | `#33221A` |
| success | `#0A7D3E` | `#34C77B` |
| warning | `#7A6200` | `#E8D44D` |
| danger | `#BE123C` | `#FF5C8A` |

**Computed contrast (WCAG ratio)**

| check | light | dark |
|---|---|---|
| text.primary / surface.1 | 18.41 pass | 17.73 pass |
| text.secondary / surface.1 | 6.44 pass | 7.21 pass |
| on.brand / brand | 16.29 pass | 7.34 pass |
| highlight / map grey | 4.01 pass | 6.31 pass |
| brand / surface.1 (button edge) *(extra)* | 16.29 pass | 6.86 pass |
| highlight / surface.1 (selected outline) *(extra)* | 4.97 pass | 8.01 pass |
| highlight / brand.tint *(extra)* | 4.28 pass | 6.85 pass |
| text.secondary / surface.2 *(extra)* | 5.51 pass | 6.45 pass |
| success / surface.1 *(extra)* | 5.23 pass | 8.11 pass |
| warning / surface.1 *(extra)* | 5.87 pass | 11.78 pass |
| danger / surface.1 *(extra)* | 6.29 pass | 6.04 pass |

**Build it as a theme variant.** Snippet only, not applied. It follows the existing const-conditional mechanism on `AppColors.variant` in `packages/design_system/lib/src/theme/app_colors.dart`:

```dart
// THEME=copper  (flutter build ... --dart-define=THEME=copper)
// 1. Flag, next to planDark / planLight; and count it as a v2-style build
//    (softer radii, dark-mode danger) by widening `v2`:
static const bool copper = variant == 'copper';
static const bool v2 = planDark || planLight || copper;

// 2. Ink / highlight. Light ink -> _tealInk, light highlight -> _turquoise,
//    dark highlight -> _turquoiseBright, text on dark ink -> _onTurquoise.
static const Color _tealInk = copper ? Color(0xFF1F2023)
    : (planLight ? Color(0xFF0A7C7C) : Color(0xFF0B3C49));
static const Color _turquoise = copper ? Color(0xFFB4541E)
    : (planLight ? Color(0xFF2BC4C4) : Color(0xFF0FA3A8));
static const Color _turquoiseBright = copper ? Color(0xFFF09A5E)
    : (planDark ? Color(0xFF2BC4C4) : Color(0xFF2EC4C6));
static const Color _onTurquoise = copper ? Color(0xFF1B0D04)
    : (planDark ? Color(0xFF0E0F11) : Color(0xFF00181B));
// NEW: dark ink separate from the dark highlight (today they share
// _turquoiseBright). Then in inkFor: `dark ? _inkDark : _tealInk`.
static const Color _inkDark = copper ? Color(0xFFE8894F) : _turquoiseBright;

// 3. Pressed ink (inside accentPressed's `turquoise ?` arm):
//    dark:  copper ? const Color(0xFFCC7946) : const Color(0xFF26A9AB)
//    light: copper ? const Color(0xFF3A3B3D) : (planLight ? ... existing ...)

// 4. Tints (softFor):
//    dark:  copper ? const Color(0xFF33221A) : (planDark ? ... existing ...)
//    light: copper ? const Color(0xFFF8ECE3) : const Color(0xFFE6F6F6)

// 5. Surfaces, text, lines (prepend `copper ? X :` to each existing ternary):
static const Color surfaceLight      = Color(0xFFFFFFFF);
static const Color surfaceMutedLight = copper ? Color(0xFFEFEDEA) : (planLight ? Color(0xFFEEF0F2) : Color(0xFFF3F3F3));
static const Color backgroundLight   = copper ? Color(0xFFF6F5F3) : (planLight ? Color(0xFFF5F6F7) : Color(0xFFFFFFFF));
static const Color surfaceDark       = copper ? Color(0xFF18181A) : (planDark ? Color(0xFF17181B) : Color(0xFF141414));
static const Color surfaceMutedDark  = copper ? Color(0xFF222225) : (planDark ? Color(0xFF1F2024) : Color(0xFF282828));
static const Color backgroundDark    = copper ? Color(0xFF0F0F10) : (planDark ? Color(0xFF0E0F11) : Color(0xFF000000));
static const Color accentSoftDark    = copper ? Color(0xFF222225) : (planDark ? Color(0xFF1F2024) : Color(0xFF282828));
static const Color textPrimaryLight  = copper ? Color(0xFF151412) : (planLight ? Color(0xFF111315) : Color(0xFF000000));
static const Color textSecondaryLight= copper ? Color(0xFF625E58) : (planLight ? Color(0xFF5F646B) : Color(0xFF545454));
static const Color textTertiaryLight = copper ? Color(0xFF686B71) : Color(0xFF757575); // #757575 is <4.5 on the tinted surface.2
static const Color textSecondaryDark = copper ? Color(0xFFA7A5A1) : (planDark ? Color(0xFFA0A3A8) : Color(0xFFAFAFAF));
static const Color borderLight       = copper ? Color(0xFFE3E0DB) : (planLight ? Color(0xFFE3E5E8) : Color(0xFFE8E8E8));
static const Color borderDark        = copper ? Color(0xFF2F2F33) : (planDark ? Color(0xFF2A2C31) : Color(0xFF333333));

// 6. Semantic. `success` is one colour for both modes today; add a dark twin.
static const Color success     = copper ? Color(0xFF0A7D3E) : Color(0xFF05944F);
static const Color successDark = copper ? Color(0xFF34C77B) : Color(0xFF05944F);
static Color successFor(bool dark) => dark ? successDark : success;
static const Color warning     = copper ? Color(0xFF7A6200) : Color(0xFFC67C00);
static const Color error       = copper ? Color(0xFFBE123C) : Color(0xFFE11900);
static const Color warningDark = copper ? Color(0xFFE8D44D) : Color(0xFFF5A623);
static const Color dangerDark  = copper ? Color(0xFFFF5C8A) : Color(0xFFFF4D4F);
static const Color errorInk    = copper ? Color(0xFFBE123C) : Color(0xFFB21400); // white on it >= 4.8
```

### 5. Anor (Pomegranate) Garnet: `THEME=garnet`

*Anor, the pomegranate: Central Asian symbol of plenty and a staple of Indian fruit carts.*

Mock: `/tmp/claude-1000/-home-nova-robotics-ubernav/32b0b03b-f246-44cd-933a-739a28167dfc/scratchpad/palettes/anor-garnet.png`

![Anor (Pomegranate) Garnet](/tmp/claude-1000/-home-nova-robotics-ubernav/32b0b03b-f246-44cd-933a-739a28167dfc/scratchpad/palettes/anor-garnet.png)

**Why it works.** The pomegranate (*anor*) is a strong Central Asian symbol, and garnet is rich and unlike any ride competitor. Light mode reads like a premium lifestyle brand.

**Risks, stated honestly. This is why it ranks last.**
- **A red-family brand in a safety app.** SOS and destructive actions are red by rule. I moved danger to orange-red (`#C2410C` / `#FF6A3D`) and warning to olive-gold to keep ΔE00 ≥ 20, but under simulated deutan vision brand and danger are only 17–19 apart. An SOS button must never look like a booking button.
- The dark-mode pink (`#FF6B94`) reads as Lyft or a dating app. Lyft does not operate in these markets, but the association is common.
- "Red car" and "red button" also carry cultural weight (danger, stop) that works against "confirm your ride".

**Tokens**

| token | light | dark |
|---|---|---|
| bg.base | `#FAF6F6` | `#120C0E` |
| surface.1 | `#FFFFFF` | `#1C1417` |
| surface.2 | `#F3ECEC` | `#271C20` |
| border | `#E8DEDF` | `#3A2A2F` |
| text.primary | `#1C1214` | `#FFFFFF` |
| text.secondary | `#6A5C5F` | `#B5A5AA` |
| brand / ink | `#9B1B45` | `#FF6B94` |
| on.brand | `#FFFFFF` | `#2A0512` |
| highlight (route, selection) | `#C2255C` | `#FF7AA0` |
| brand.tint | `#FBE9EF` | `#3A1622` |
| success | `#0A7D3E` | `#34C77B` |
| warning | `#7A6200` | `#F2D04C` |
| danger | `#C2410C` | `#FF6A3D` |

**Computed contrast (WCAG ratio)**

| check | light | dark |
|---|---|---|
| text.primary / surface.1 | 18.32 pass | 18.08 pass |
| text.secondary / surface.1 | 6.35 pass | 7.68 pass |
| on.brand / brand | 7.97 pass | 6.89 pass |
| highlight / map grey | 4.57 pass | 5.68 pass |
| brand / surface.1 (button edge) *(extra)* | 7.97 pass | 6.70 pass |
| highlight / surface.1 (selected outline) *(extra)* | 5.66 pass | 7.35 pass |
| highlight / brand.tint *(extra)* | 4.85 pass | 6.48 pass |
| text.secondary / surface.2 *(extra)* | 5.45 pass | 7.01 pass |
| success / surface.1 *(extra)* | 5.23 pass | 8.26 pass |
| warning / surface.1 *(extra)* | 5.87 pass | 11.97 pass |
| danger / surface.1 *(extra)* | 5.18 pass | 6.35 pass |

**Build it as a theme variant.** Snippet only, not applied. It follows the existing const-conditional mechanism on `AppColors.variant` in `packages/design_system/lib/src/theme/app_colors.dart`:

```dart
// THEME=garnet  (flutter build ... --dart-define=THEME=garnet)
// 1. Flag, next to planDark / planLight; and count it as a v2-style build
//    (softer radii, dark-mode danger) by widening `v2`:
static const bool garnet = variant == 'garnet';
static const bool v2 = planDark || planLight || garnet;

// 2. Ink / highlight. Light ink -> _tealInk, light highlight -> _turquoise,
//    dark highlight -> _turquoiseBright, text on dark ink -> _onTurquoise.
static const Color _tealInk = garnet ? Color(0xFF9B1B45)
    : (planLight ? Color(0xFF0A7C7C) : Color(0xFF0B3C49));
static const Color _turquoise = garnet ? Color(0xFFC2255C)
    : (planLight ? Color(0xFF2BC4C4) : Color(0xFF0FA3A8));
static const Color _turquoiseBright = garnet ? Color(0xFFFF7AA0)
    : (planDark ? Color(0xFF2BC4C4) : Color(0xFF2EC4C6));
static const Color _onTurquoise = garnet ? Color(0xFF2A0512)
    : (planDark ? Color(0xFF0E0F11) : Color(0xFF00181B));
// NEW: dark ink separate from the dark highlight (today they share
// _turquoiseBright). Then in inkFor: `dark ? _inkDark : _tealInk`.
static const Color _inkDark = garnet ? Color(0xFFFF6B94) : _turquoiseBright;

// 3. Pressed ink (inside accentPressed's `turquoise ?` arm):
//    dark:  garnet ? const Color(0xFFE05E82) : const Color(0xFF26A9AB)
//    light: garnet ? const Color(0xFF84173B) : (planLight ? ... existing ...)

// 4. Tints (softFor):
//    dark:  garnet ? const Color(0xFF3A1622) : (planDark ? ... existing ...)
//    light: garnet ? const Color(0xFFFBE9EF) : const Color(0xFFE6F6F6)

// 5. Surfaces, text, lines (prepend `garnet ? X :` to each existing ternary):
static const Color surfaceLight      = Color(0xFFFFFFFF);
static const Color surfaceMutedLight = garnet ? Color(0xFFF3ECEC) : (planLight ? Color(0xFFEEF0F2) : Color(0xFFF3F3F3));
static const Color backgroundLight   = garnet ? Color(0xFFFAF6F6) : (planLight ? Color(0xFFF5F6F7) : Color(0xFFFFFFFF));
static const Color surfaceDark       = garnet ? Color(0xFF1C1417) : (planDark ? Color(0xFF17181B) : Color(0xFF141414));
static const Color surfaceMutedDark  = garnet ? Color(0xFF271C20) : (planDark ? Color(0xFF1F2024) : Color(0xFF282828));
static const Color backgroundDark    = garnet ? Color(0xFF120C0E) : (planDark ? Color(0xFF0E0F11) : Color(0xFF000000));
static const Color accentSoftDark    = garnet ? Color(0xFF271C20) : (planDark ? Color(0xFF1F2024) : Color(0xFF282828));
static const Color textPrimaryLight  = garnet ? Color(0xFF1C1214) : (planLight ? Color(0xFF111315) : Color(0xFF000000));
static const Color textSecondaryLight= garnet ? Color(0xFF6A5C5F) : (planLight ? Color(0xFF5F646B) : Color(0xFF545454));
static const Color textTertiaryLight = garnet ? Color(0xFF686B71) : Color(0xFF757575); // #757575 is <4.5 on the tinted surface.2
static const Color textSecondaryDark = garnet ? Color(0xFFB5A5AA) : (planDark ? Color(0xFFA0A3A8) : Color(0xFFAFAFAF));
static const Color borderLight       = garnet ? Color(0xFFE8DEDF) : (planLight ? Color(0xFFE3E5E8) : Color(0xFFE8E8E8));
static const Color borderDark        = garnet ? Color(0xFF3A2A2F) : (planDark ? Color(0xFF2A2C31) : Color(0xFF333333));

// 6. Semantic. `success` is one colour for both modes today; add a dark twin.
static const Color success     = garnet ? Color(0xFF0A7D3E) : Color(0xFF05944F);
static const Color successDark = garnet ? Color(0xFF34C77B) : Color(0xFF05944F);
static Color successFor(bool dark) => dark ? successDark : success;
static const Color warning     = garnet ? Color(0xFF7A6200) : Color(0xFFC67C00);
static const Color error       = garnet ? Color(0xFFC2410C) : Color(0xFFE11900);
static const Color warningDark = garnet ? Color(0xFFF2D04C) : Color(0xFFF5A623);
static const Color dangerDark  = garnet ? Color(0xFFFF6A3D) : Color(0xFFFF4D4F);
static const Color errorInk    = garnet ? Color(0xFFC2410C) : Color(0xFFB21400); // white on it >= 4.8
```

## 4. What else a new variant touches (outside `app_colors.dart`)

These are needed for any of the five. They are listed so nobody believes a colour swap is the whole job.

- **`inkFor` must use a separate dark ink.** Today the dark ink and the dark highlight are both `_turquoiseBright`. Every option here uses different dark ink and highlight values, so each snippet adds `_inkDark`.
- **`v2` widening.** `AppSpacing` (radii) and `app_theme.dart` (dark danger) key off `AppColors.v2`. Each snippet widens `v2` so the new variant gets the v2 radii and the brighter dark danger (`app_theme.dart:37`). If that is not wanted, add a separate `alt` flag instead.
- **`success` has no dark twin today.** The snippets add `successDark` / `successFor`, but callers of `AppColors.success` in dark mode need to switch to `successFor(isDark)`. That is a code change I have not made.
- **Hard-coded teal outside tokens.**
  - `packages/design_system/lib/src/widgets/ridevela_mark.dart:35-37`: logo navy and teal
  - `packages/design_system/lib/src/widgets/vehicle_glyph.dart:76-77`: glyph fills
  - `apps/rider_app/android/app/src/main/res/values/ic_launcher_background.xml`: launcher background
  - `docs/brand/png|svg/*`: the Road-V logo. The logo needs a recolour per palette: tile = light ink, V = on.brand, lane dashes = highlight.
- **Vehicle art.** `VehicleGlyph.artSet` falls through to the `midnight` flat-car set, which has a **teal stripe**. A non-teal palette needs recoloured car art, or the drawn glyphs as `mono` uses.
- **`ThemeController.buildDefault`**: new variants follow the phone (the `_` branch), which is probably right.
- **Tests:** `packages/design_system/test/theme_variant_test.dart` pins the teal values per variant. Each new variant needs a matching test group, plus a golden or visual check on the emulator per CLAUDE.md §4.

## 5. Colour separation data

CIEDE2000 between brand/highlight and the semantic colours (normal vision, final values):

| palette | mode | brand↔danger | hi↔danger | brand↔warning | hi↔warning |
|---|---|---|---|---|---|
| baseline-turquoise | light | 53.4 | 57.6 | 50.5 | 44.3 |
| baseline-turquoise | dark | 62.1 | 62.1 | 46.5 | 46.5 |
| registan-lapis | light | 44.7 | 45.0 | 54.2 | 54.8 |
| registan-lapis | dark | 40.3 | 47.1 | 47.0 | 21.8 |
| marigold | light | 27.8 | 32.0 | 24.0 | 26.8 |
| marigold | dark | 37.7 | 45.0 | 28.2 | 20.0 |
| ikat-indigo | light | 43.9 | 43.8 | 58.6 | 58.5 |
| ikat-indigo | dark | 39.2 | 38.8 | 55.7 | 53.1 |
| anor-garnet | light | 25.5 | 25.1 | 44.3 | 47.0 |
| anor-garnet | dark | 23.4 | 24.3 | 54.8 | 53.5 |
| bukhara-copper | light | 35.2 | 21.5 | 34.6 | 23.2 |
| bukhara-copper | dark | 29.0 | 31.3 | 31.2 | 27.2 |

Simulated colour-vision deficiency (Machado 2009, severity 1.0). Values below ~10 mean the pair is effectively the same colour for that viewer:

| palette | mode | brand↔danger protan | deutan | hi↔danger protan | deutan | hi↔warning protan | deutan |
|---|---|---|---|---|---|---|---|
| baseline-turquoise | light | 34.3 | 47.4 | 41.1 | 40.4 | 35.0 | 41.2 |
| baseline-turquoise | dark | 46.7 | 42.2 | 46.7 | 42.2 | 37.1 | 41.4 |
| registan-lapis | light | 49.0 | 59.8 | 52.5 | 60.3 | 56.8 | 60.3 |
| registan-lapis | dark | 34.9 | 45.6 | 31.4 | 16.3 | 11.1 | 6.4 |
| marigold | light | 33.0 | 16.8 | 36.4 | 21.6 | 7.0 | 16.1 |
| marigold | dark | 33.6 | 18.2 | 36.6 | 20.2 | 7.9 | 4.7 |
| ikat-indigo | light | 53.8 | 62.7 | 56.3 | 62.1 | 60.6 | 62.2 |
| ikat-indigo | dark | 45.9 | 51.8 | 45.1 | 49.6 | 54.6 | 55.4 |
| anor-garnet | light | 28.9 | 19.4 | 29.8 | 15.7 | 30.6 | 14.0 |
| anor-garnet | dark | 28.4 | 17.2 | 29.9 | 19.0 | 38.1 | 23.0 |
| bukhara-copper | light | 16.8 | 33.0 | 17.7 | 8.0 | 1.9 | 6.6 |
| bukhara-copper | dark | 28.1 | 13.3 | 29.3 | 13.8 | 14.5 | 9.5 |

**Takeaway:** the warm options (Marigold, Copper, Lapis-dark gold) cannot use colour alone to tell "your route / selected" apart from "warning" for colour-blind riders; about 8 % of men have red-green CVD. Indigo, and Lapis in light mode, stay above 39 in every case. Whatever palette is picked, warnings and SOS should always carry an icon and a text label. The app largely does this already.

## 6. Reproduce

All inputs and scripts are in `/tmp/claude-1000/-home-nova-robotics-ubernav/32b0b03b-f246-44cd-933a-739a28167dfc/scratchpad/palettes/`:
- `palettes_def.py`: the token values
- `contrast.py`: WCAG ratios
- `deltae.py`: CIEDE2000
- `cvd.py`: protan/deutan simulation
- `render.py`: the PIL mocks, drawn with Inter
- `gendart.py`: the Dart snippets above, generated from the same values so they cannot drift

Run `python3 contrast.py`. It prints `REQUIRED FAILS (excluding baseline): 0`.

**Not done / not verified:**
- No palette was built into the app or run on the emulator. These are static PIL mocks, not screenshots.
- No user testing.
- The competitor in-app usage marked *Inference* was not confirmed from a primary source. Rapido, Mobbin and the Namma Yatri Medium review returned 403, and Namma Yatri's open-source colour file path could not be located this session.
