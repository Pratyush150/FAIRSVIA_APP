# FairsVia — UI Excellence Research

**How to make the app "best in the market," mapped to our stack.**
Research compiled July 2026. Target: current (2024–2025) best practice for a premium Flutter / Material 3 ride-hailing app.

---

## About this document

This is deep, cited desk research benchmarking current best-in-class consumer / mobility / fintech apps and design systems — Uber (Base), Lyft, Bolt, Grab, DoorDash, Airbnb, Linear, Stripe, Revolut, Cash App, Monzo — plus the two governing specs, **Apple Human Interface Guidelines (HIG)** and **Material Design 3 (M3)**. Every non-obvious claim is cited with a numbered URL in [Sources](#sources).

**Honesty caveats (binding project rule #1).** Two classes of numbers deserve a health warning:

1. **Vendor pixel specs don't exist publicly.** Uber/Lyft/Bolt/Grab do not publish exact pixel dimensions for their ride screens, and their design-system sites (`base.uber.com`) are JavaScript-rendered, so a fetcher can't extract values. Where a number describes a named vendor component it is **convergent convention from teardowns/case studies**, not an official spec — flagged inline.
2. **`m3.material.io` and Apple HIG pages are client-rendered** and return no body text to a fetcher. M3/Apple numeric tokens below are cross-verified against the sources that *encode the identical tokens* — the Flutter framework source (`typography.dart`, `Durations`, `Curves`), `material-components-android` docs, and the `material_design` Dart token package. Provenance is cited per claim.

Ground-truth specs (WCAG, Flutter APIs, pub.dev package metadata, GitHub source) are directly fetched and reliable.

The final section — **[Concrete recommendations for FairsVia](#7-concrete-recommendations-for-ubernav)** — is a prioritised punch-list keyed to our actual design-system code (`packages/design_system/`), including contrast ratios computed from our real hex values.

---

## Table of contents

1. [Icons](#1-icons)
2. [Buttons & touch targets](#2-buttons--touch-targets)
3. [Colour](#3-colour)
4. [Typography](#4-typography)
5. [Spacing, layout, elevation, motion & haptics](#5-spacing-layout-elevation-motion--haptics)
6. [Ride-hailing-specific UI patterns](#6-ride-hailing-specific-ui-patterns)
7. [Concrete recommendations for FairsVia](#7-concrete-recommendations-for-ubernav)
8. [Sources](#sources)

---

## 1. Icons

### 1.1 Outlined vs filled vs duotone — and the "fill = selected" rule

The single most important icon rule for a premium app is the **outline-inactive → filled-active** state pattern. Material 3 ships a dedicated **Fill axis (0 → 1)** on Material Symbols precisely so one glyph can toggle between unfilled (default/idle) and filled (active/selected) — `FILL 0` = default, `FILL 1` = completely filled [1][2]. This is the canonical mechanism for a selected bottom-nav destination.

- **Outlined** — lighter visual weight; the safe default for inactive states, dense lists, toolbars.
- **Filled (solid)** — higher salience; reserve for the *one* selected nav item, primary actions, and to draw the eye. Overuse flattens hierarchy.
- **Duotone** — two layers, secondary at ~20–30 % opacity (Phosphor's duotone secondary layer is 20–30 %) [6][9]. Reads decorative/illustrative — fine for empty states and marketing surfaces, but **avoid duotone in functional nav/toolbars**; it hurts scannability.

**The convention across the reference apps** (reported as documented industry convention; vendor design-system bodies are JS-gated): Uber, Lyft, Cash App, Monzo, Revolut, Airbnb use **outline-inactive → filled-active for the bottom tab bar**, with the active icon/label also taking the brand or on-surface accent color. Linear and Stripe lean almost entirely **monochrome outline**, spending color on status/semantics rather than nav fill (their surfaces are sidebar/desktop-first). SF Symbols apps express the same idea via *rendering modes* rather than a fill axis [10].

> **Rule:** represent "selected" as the *same glyph, FILL 0→1 + neutral→accent color* — never by switching to a different icon shape.

### 1.2 Best icon library for a premium Flutter app

Live pub.dev data (fetched July 2026):

| Library | Flutter package | Version / freshness | Icons | Styles / axes | Notes |
|---|---|---|---|---|---|
| **Material Symbols** | **`material_symbols_icons`** (publisher hiveright.tech, verified) | **4.2951.0, ~1 mo old** | **4,255** | Weight 100–700, **Fill 0–1**, Grade −50→200, Optical 20–48 | Only Flutter pkg exposing the Fill axis; app-wide `IconThemeData` defaults; auto-synced to Google's font. Best maintained [5]. |
| Phosphor | `phosphor_flutter` (verified) | 2.1.0, **~2 yrs old** | ~1,000+ | Thin/Light/Regular/Bold/**Fill/Duotone** (6) | Most stylistic range; own (non-Material) language; package is stale [6]. |
| Lucide (current) | **`flutter_lucide`** (verified) | **1.11.0, ~2 mo old** | **1,699+** | Outline only, 2 px stroke, rounded caps | Maintained Lucide route; crisp SaaS look; **no fill variants** [7]. |
| Lucide (legacy) | `lucide_icons` | 0.257.0, **~3 yrs, archived** | ~1,450 | Outline | Effectively unmaintained — avoid [8]. |
| SF Symbols | *no legal Flutter port* | — | 6,900+ | Mono/Hierarchical/Palette/Multicolor | Apple license forbids use off Apple platforms [10]. |

**Recommendation: standardise on `material_symbols_icons`.** Reasons: (1) it is the *only* Flutter package exposing the Fill axis — the exact M3 mechanism for outline→filled selected-nav [1][2][5]; (2) full 4-axis control lets you match icon weight to font weight, tune emphasis via Grade, and get correct optical sizing at 18/20/24 dp, all set once via `IconThemeData`; (3) freshest and best-maintained credible option (updated ~1 month ago, verified publisher) vs. Phosphor (~2 yr stale) and legacy Lucide (~3 yr, archived); (4) zero style clash with M3 components. Trade-off: single stylistic language (no duotone) — if marketing/empty-state screens later need illustrative duotone, add Phosphor **only there**, never in nav/toolbars. Second choice, if the brand deliberately wants a softer rounded-terminal SaaS aesthetic, is `flutter_lucide` — but you lose the fill-toggle nav pattern.

### 1.3 Design specs (grid, stroke, optical size, terminals)

- **Grid:** 24 × 24 dp canvas (Material system-icon standard) [3].
- **Live area / padding:** keep content in a **20 × 20 dp live area** → **2 dp** padding all around, on the 24 dp canvas [3][4].
- **Stroke weight:** Material system icons use a **2 dp stroke**, dropping to **1.5 dp only when 2 dp won't fit** the detail [3]. Lucide is a strict **2 px stroke on 24 × 24** with round caps/joins and `absoluteStrokeWidth` so stroke stays 2 px even at 48 px [9].
- **Corner rounding:** Material uses a **2 dp corner radius on the icon silhouette** but keeps **flat (square) stroke ends** for shapes ≤ 2 dp wide [3]; Lucide is the opposite — rounded caps everywhere. Pick one convention and keep terminals uniform.
- **Optical sizing:** Material Symbols' Optical Size axis (20–48 dp) auto-adjusts stroke so thin strokes don't vanish when small or look chunky when large [2]. SF Symbols achieves this via 9 weights × 3 scales tied to the font's cap height [10].

### 1.4 Standard sizes (dp) by context

| Context | Icon size | Touch target |
|---|---|---|
| Default system icon | **24 dp** | — |
| Bottom navigation | 24 dp | ≥ 48 dp nav item [11][12] |
| App-bar actions | 24 dp | 48 dp icon-button hit area [11] |
| Inline / list leading | 24 dp (20 dp dense) | — |
| Inside buttons (text/chip) | **18 dp** (24 dp in M3 Expressive) | inherits button |
| Standalone icon button | 24 dp | **48 × 48 dp** (hard floor) [11][12] |
| Hero / empty-state | 36–48 dp+ | n/a (illustrative) |

> **Hard rule:** any tappable icon gets a **48 × 48 dp** minimum target — a 24 dp glyph in transparent 48 dp padding [11][12].

### 1.5 Consistency rules & common mistakes

- **One icon set, period.** Mixing packs (different grids/strokes/terminals) is the #1 tell of an amateur UI. If a glyph is missing, draw the closest match *in that library's style*.
- **Match icon stroke to font weight** (SF Symbols formalises 9 symbol weights ↔ font weights) [10]. A 1 px icon next to bold text looks broken; use Material Symbols' Weight axis to pair.
- **Align terminal radius to your UI radius** — rounded UI → rounded-terminal icons (Lucide/Phosphor); crisp/geometric UI → Material's flat caps.
- **Default icons to neutral** (`onSurface`/`onSurfaceVariant`); spend **accent color** only on selected nav, primary CTAs, and semantic status. If most icons are colored, none stand out.
- **Contrast:** any functional icon needed to understand content must hit **≥ 3:1** against its background (WCAG 1.4.11 Non-text Contrast); decorative icons redundant with adjacent 4.5:1 text are exempt [13]. Use the Grade axis (−25 on dark to cut glare, up to +200 for emphasis) rather than nudging weight [2].
- **Common mistakes:** mixing sets/strokes; "selected" as a different glyph; ignoring optical sizing; targets < 48 dp; over-coloring; duotone in functional nav.

---

## 2. Buttons & touch targets

### 2.1 Minimum touch target — the four binding rules

| Guideline | Number | Level |
|---|---|---|
| **Material 3 / Android** | **48 × 48 dp** | Baseline recommendation [12][17] |
| **Apple HIG** | **44 × 44 pt** | Recommended minimum [17] |
| **WCAG 2.5.8 Target Size (Minimum)** | **24 × 24 CSS px** | AA (new in WCAG 2.2) [15] |
| **WCAG 2.5.5 Target Size (Enhanced)** | **44 × 44 CSS px** | AAA [16] |

WCAG 2.5.8's spacing exception: an undersized target still passes if a 24 px circle centered on it doesn't intersect another target's circle [15].

> **Stance:** enforce **48 dp as the hard floor** for every tappable element — it satisfies Material, clears Apple's 44, clears WCAG AA (24) and approaches AAA (44). In Flutter this is what `MaterialTapTargetSize.padded` gives; keep it, never `.shrinkWrap` primary controls.

### 2.2 Button heights & the size ladder

M3's default filled-button *visual* height is **40 dp** (tap target padded to 48) [Sources: M3 buttons specs]. **M3 Expressive** introduced an explicit five-size scale: **XS 32 / S 36 / M 40 / L 48 / XL 56 dp** with 24 dp icons [10-buttons]. But 40 dp reads short for a mobile primary CTA; conversion/UX guidance converges on **~48–56 px** for the primary action, with 50 pt called the comfortable target [17-cta].

**Recommended heights:**

| Role | Height | Basis |
|---|---|---|
| **Primary CTA** (sticky "Confirm", "Request ride") | **56 dp** (M3 XL) | optimal thumb-tap band [17-cta] |
| Standard / inline primary | 48 dp (M3 L) | tap target ideal |
| Secondary (outlined / tonal) | 48 dp | aligns with primary in a row |
| Tertiary (text) | 40 dp visual / 48 dp tap | low emphasis |

Ride-hailing note: Uber ships a formal **"Button dock"** in Base for exactly the confirm-at-bottom case. Uber/Lyft/Bolt/Grab/Careem/DiDi all use **map + bottom-sheet + full-width bottom confirm** [14-dock]. No authoritative "Uber Confirm = N dp" figure exists publicly — design to M3 XL 56 dp + full-width and you're in the same visual class.

### 2.3 Padding, min-width, icon gap (M3)

- **Horizontal padding:** 24 dp both sides (text-only); **16 dp leading / 24 dp trailing** with a leading icon.
- **Icon inside button:** 18 dp (24 dp in Expressive); **icon-to-label gap 8 dp**.
- **Min width:** grouped buttons 48 dp; standalone buttons should never truncate the label.
- Don't set explicit vertical padding to hit height — let the 40/48/56 dp height + centered content define it.

### 2.4 Corner radius — the 2024/2025 divergence

M3's default is **fully rounded (pill/stadium)**; Expressive buttons even morph shape on press [10-buttons]. The premium field has split deliberately:

| App | Action-button radius | Camp |
|---|---|---|
| Cash App, M3 default | Full pill | Pill / playful |
| Revolut, Monzo | Rounded-rect ~8–16 px | Fintech-modern |
| **Stripe** | **4–8 px, no pills** on actions (pills reserved for badges) | Conservative rect |
| Linear | ~6–8 px, sharp/technical | Conservative rect |

Radius semantics: **2–4 px = serious/professional, 8–12 px = friendly/modern, 9999 px (pill) = attention-grabbing CTA but can't stack tightly** [9-radius].

> **Recommendation for a rider-facing product:** **pill for the primary CTA** (native M3, reads as "THE action," warmer than fintech-severe 4–8 px) and **12–16 dp rounded-rect for cards/sheets**. Whatever you choose, apply one radius token consistently — bigger shapes get bigger radii.

### 2.5 Hierarchy

- **Primary → M3 Filled.** Solid brand fill, one per screen.
- **Secondary → Filled-tonal or Outlined.** Tonal (`secondaryContainer`) for a soft second action; Outlined (1 dp `outline`) for Cancel/Back.
- **Tertiary → Text button.** Colored label only.
- **Destructive → Filled or Outlined in `error`.** Never share the primary's neutral brand color.

One primary per view; at most 1–2 secondaries; they must not visually compete.

### 2.6 States — M3 state-layer opacities

M3 renders feedback as a **state layer** (translucent overlay in the content color) at a fixed opacity per state [20-states]:

| State | State-layer opacity |
|---|---|
| Hover | **8 %** |
| Focus | **10 %** |
| Pressed | **10 %** |
| Dragged | **16 %** |

**Disabled** is by opacity, not a state layer: canonical M3 tokens are **content 38 % / container 12 %** (verified in the `material_design` Dart token package; scrim/backdrop 50 %) [19-disabled][21-disabled]. (Don't mix these with the *additive* Material-2 scale.)

**Loading:** replace the label with a centered indeterminate spinner (~18–24 dp, 2–2.5 dp stroke), **keep the button at full width/height** (no layout jump), and disable interaction — essential for a sticky Confirm so it doesn't resize when the request fires. Keep the focus ring visible for keyboard/switch access.

### 2.7 Full-width vs inline

Go **full-width** when it's the single primary action, when it lives in a sticky bottom bar (thumb-friendliest, no horizontal aiming), or on mobile checkout/forms. Keep **inline/auto-width** for two peer actions in a row (Cancel | Confirm), for secondary/tertiary buttons in content, and on tablets cap CTA width (~400–480 dp) so it doesn't stretch grotesquely [15-cta][16-cta].

### 2.8 The sticky bottom CTA ("button dock" / "buy-bar")

The defining ride-hailing/checkout pattern. Anatomy:

- **Structure:** a persistent bar pinned bottom, holding **price + primary CTA + status** (ride-hailing "buy-bar" mandatory elements). Uber formalises it as the "Button dock" in Base [14-dock].
- **CTA height:** 48–56 dp (56 for hero confirm), full-width minus bar padding.
- **Bar padding:** 16 dp gutters.
- **Safe-area inset (critical):** pad the bottom by the device safe-area inset so the CTA clears the home indicator. Web: `calc(env(safe-area-inset-bottom) + 1rem)`. **Flutter:** wrap in `SafeArea(bottom: true)` or add `MediaQuery.viewPadding.bottom` — never hardcode (0 on old devices, ~34 px on notched iPhones) [13-safe].
- **Separation:** lift the bar off scrolling content with a 1 dp top divider or a soft top shadow/scrim so content doesn't bleed into the CTA.
- **Whitespace:** ≥ 20–30 px clear space around the CTA.
- **Payoff:** sticky bottom CTAs are documented at +5–12 % mobile checkout-completion lift in A/B tests [13-safe].

Flutter: use `Scaffold.bottomNavigationBar` or a persistent `bottomSheet` footer (not a `Stack`-positioned widget) so it composes with keyboard inset + `SafeArea`.

**Quick spec sheet:**

```
Touch-target floor:   48 × 48 dp (everything tappable)
Primary CTA:          56 dp sticky / 48 dp inline
Secondary/outlined:   48 dp
Text/tertiary:        40 dp visual, 48 dp tap
H-padding:            24 dp text-only · 16 lead / 24 trail with icon
Icon / gap:           18–24 dp / 8 dp
Radius:               pill CTA · 12–16 dp cards
State layers (M3):    hover 8 · focus 10 · pressed 10 · dragged 16 %
Disabled:             content 38 % · container 12 %
Bottom dock:          full-width CTA · 16 dp gutters · SafeArea bottom · top divider
```

---

## 3. Colour

### 3.1 How elite teams build a palette

One brand hue, a long neutral ramp, a small set of semantic hues, and surface/elevation layers. The differences are step count and color space.

**Neutral ramp — step counts:**
- **Tailwind:** 11 steps `50…950` (`500` = base). The **`950` step was added in 2024** for dark-mode contrast; v4 defines the palette in **OKLCH** for perceptual uniformity [7-tw].
- **Radix Colors:** a **12-step** scale with fixed semantic roles (below) [2-radix].
- **Material 3:** generates **tonal palettes of 13 tones** (0,10,…,95,99,100) per key color, from which named roles are picked [8-m3][9-m3].

**Radix 12-step role map** (the cleanest spec to memorise) [2-radix]:

| Steps | Role |
|---|---|
| 1–2 | Backgrounds (app bg, subtle bg) |
| 3–5 | Component backgrounds (normal / hover / pressed) |
| 6–8 | Borders (subtle / interactive / strong-focus) |
| 9–10 | Solid (9 = purest/highest-chroma brand solid; 10 = hover) |
| 11–12 | Text (low-contrast / high-contrast) |

Radix guarantees step 11 ≈ Lc 60 and step 12 ≈ Lc 90 (APCA) over step-2 background [2-radix].

**M3 color roles** (what you theme in Flutter `ColorScheme`): `primary`/`onPrimary`/`primaryContainer`/`onPrimaryContainer` (same for secondary/tertiary/error); surfaces `surface`, `surfaceContainerLowest…Highest`, `surfaceVariant`, `onSurface`, `onSurfaceVariant`, `outline`, `outlineVariant`, `inverseSurface`. Convention: an `on*` role is the guaranteed-legible text/icon color on its paired fill; `*Container` roles are fills for foreground elements and **must not be used for text** [1-roles][10-roles]. Tone → role mapping (light / dark): `primary` = tone **40 / 80**; `onPrimary` = **100 / 20**; `primaryContainer` = **90 / 30**; `surface` = **99 / 10**; `onSurface` = **10 / 90** [9-m3][10-roles].

**Semantic colors:** success = green, warning = amber, error = red, info = blue, each a *separate ramp* with the same structure so each has a legible text step and a solid step. Stripe generates semantic tokens as a layer referencing core color tokens [6-stripe].

### 3.2 WCAG contrast — exact ratios

**SC 1.4.3 Contrast (Minimum), AA** [3-wcag]:
- **Normal text: 4.5:1**
- **Large text: 3:1** — "large" = **≥ 18 pt, or ≥ 14 pt bold** (≈ 24 px, or ≈ 18.66 px bold).
- Exempt: disabled/inactive UI, pure decoration, **logos/brand-name text**. Do **not** round: 4.499:1 fails.

**SC 1.4.11 Non-text Contrast, AA** [13]: **3:1** for UI component states/boundaries required to identify the control (focus rings, input borders, checked states) and meaningful graphic parts. Exempt: inactive components, logos, redundant graphics, pure hover.

**SC 1.4.6 Contrast (Enhanced), AAA** [5-wcag]: **Normal 7:1, Large 4.5:1**.

**APCA / WCAG 3 status (be accurate):** APCA was *exploratory only and was pulled from the WCAG 3 working draft in mid-2023* for lack of consensus; the published WCAG 3 draft has **no finalized contrast method** and isn't expected to be a standard until ~2030+ [12-apca][13-wcag3]. APCA is perceptual/polarity-aware and outputs an **Lc value** (Lc 60 ≈ readable body), but carries **no conformance weight** today. **Design to WCAG 2.1/2.2 ratios for compliance; use APCA only as a secondary check** [12-apca].

### 3.3 Dark-mode construction

- **Avoid pure black.** Material recommends a dark base of **`#121212`** (not `#000`): shadows are unreadable on pure black, large `#000`↔`#FFF` areas cause eye strain, and off-black leaves headroom to show elevation as lighter surfaces [15-dark].
- **Avoid pure white text.** Use white-on-dark opacity tiers: **high-emphasis 87 % · medium 60 % · disabled 38 %** [15-dark].
- **Elevation = lightness.** In M2 dark theme a semi-transparent white overlay rises with elevation: **0 dp 0 % → 1 dp 5 % → 8 dp 12 % → 24 dp 16 %**. In **M3** this became a **tonal `surfaceTint` overlay of the primary color** scaling with elevation (Flutter: `surfaceTintColor`/`applyElevationOverlayColor`). Either way, **higher surfaces are lighter** [15-dark][11-tint].
- **Desaturate/lighten brand in dark.** Saturated light-theme brand (tone ~40 / "500") vibrates and fails contrast on dark; use a lighter, less-saturated tone (~80 / "200") — exactly why M3 maps `primary` tone 40 (light) → 80 (dark) [9-m3][15-dark].
- **Limit large saturated areas;** any primary used for text/large elements must still hit ≥ 4.5:1 on the dark surface [15-dark].
- **Apple HIG** echoes this: base vs elevated surfaces (elevated = lighter), use semantic system colors that auto-adapt, and **test the same color in both appearances** — a color can pass in one and fail the other [18-hig][19-hig].

### 3.4 Accent discipline

**60-30-10 rule:** ~60 % neutral surface, ~30 % secondary, ~**10 % accent**. Reserve the brand color for the highest-priority actions (primary CTA, active/selected states, key links). The mechanism is *contrast through scarcity* — when brand appears *only* on primary actions, users instantly read "act here." Overuse destroys the signal [20-6030]. Aligns with M3's guidance that `primary` is for "the most important actions" [10-roles].

### 3.5 State colors, legible in both themes

- Build success/warning/error/info as **full ramps** (like neutrals) so each has a light-mode and dark-mode text step plus a container step.
- **Never rely on hue alone** (red/green fail for color-blind users) — pair with icon/label (WCAG + Apple) [4-wcag][18-hig].
- In dark mode, **lighten + desaturate** each state color (e.g. error tone 40 → 80) so red/green stay legible on `#121212` rather than glowing.
- Verify each state's text over both its container *and* the base surface in *both* themes.

### 3.6 Target ratios & verification

| Text role | AA minimum | Premium target |
|---|---|---|
| Body / primary text | 4.5:1 | 7:1 (AAA) |
| Secondary / caption | 4.5:1 (still normal size) | ≥ 4.5:1 — don't drop below just because it's "secondary" |
| Large / headings (≥ 24 px or ≥ 18.66 px bold) | 3:1 | 4.5:1 |
| Disabled text | no requirement (exempt) | keep clearly dimmer than 4.5:1 so it reads disabled |
| UI borders / focus / icons / control states | 3:1 (1.4.11) | 3:1 |

**How teams verify:** Stripe built a CIELAB tool so every default text color passes AA over white *and* over tinted product backgrounds; their heuristic — colors whose scale numbers differ by ≥ 500 hit 4.5:1 [6-stripe]. M3 tonal role pairs are "accessible by default" (guaranteed ≥ 3:1). Standard checkers: WebAIM, Stark, Figma plugins, DevTools; APCA tools only as a secondary perceptual check. **Always test both themes and with Increase Contrast / Bold Text on** [18-hig].

---

## 4. Typography

### 4.1 Type-scale construction

Modular-scale ratios: **Minor Third 1.200** (compact — explicitly recommended for mobile/data-dense UI), **Major Third 1.250** (moderate), **Perfect Fourth 1.333** (high contrast, makes key info pop) [7-scale][8-scale]. Use ~1.2 for the mobile body/UI range and reserve 1.25–1.333 for the few hero/display sizes. Note M3's scale is hand-tuned, not pure-geometric.

**Material 3 type scale** — exact tokens from Flutter's `_M3Typography` (canonical M3 2021 values; letterSpacing in logical px, height as a multiple) [10-typo]:

| Role | Size (sp) | Line-height | Weight | Letter-spacing (px) |
|---|---|---|---|---|
| Display Large | 57 | 1.12 | 400 | −0.25 |
| Display Small | 36 | 1.22 | 400 | 0 |
| Headline Large | 32 | 1.25 | 400 | 0 |
| Headline Small | 24 | 1.33 | 400 | 0 |
| Title Large | 22 | 1.27 | 400 | 0 |
| Title Medium | 16 | 1.50 | 500 | 0.15 |
| Body Large | 16 | 1.50 | 400 | 0.5 |
| Body Medium | 14 | 1.43 | 400 | 0.25 |
| Label Large | 14 | 1.43 | 500 | 0.1 |
| Label Small | 11 | 1.45 | 500 | 0.5 |

**Apple HIG text styles** (default size; note the pattern — large sizes get negative tracking, small sizes positive) [4-hig][6-hig]:

| Style | Size (pt) | Weight | Tracking (pt) |
|---|---|---|---|
| Large Title | 34 | Bold | −1.05 |
| Title 1 | 28 | Bold | −0.8 |
| Headline | 17 | Semibold | −0.43 |
| Body | 17 | Regular | −0.43 |
| Footnote | 13 | Regular | +0.03 |
| Caption 2 | 11 | Regular | +0.15 |

Apple auto-switches optical size: **SF Pro Text ≤ 19 pt, SF Pro Display ≥ 20 pt** [4-hig].

### 4.2 Weights

Ship **3–4 weights**, not the whole family: 400 body, 500/600 emphasis, 700 headings (M3 uses 400 body / 500 titles-labels; Apple pairs Regular body with Semibold/Bold headings) [1-typo][10-typo]. **Plus Jakarta Sans** ships 7 static weights each with italic — ExtraLight 200 / Light 300 / **Regular 400 / Medium 500 / SemiBold 600 / Bold 700** / ExtraBold 800 — plus a variable weight axis 200–800 [3-pjs][9-pjs]. Ship 400/500/600/700 or the variable font.

### 4.3 Line-height, letter-spacing, body size

- **Line-height:** headings tight (**1.1–1.25**; M3 Display Large 1.12), body loose (**1.4–1.5**; M3 Body Large 1.50) [10-typo].
- **Letter-spacing:** tighten large headings (**negative**; M3 Display −0.25 px, Apple Large Title −1.05 pt, target ~−0.02 em on hero text), keep body near-zero, open up small labels/caps (**positive**; M3 Label +0.4–0.5 px) [10-typo][4-hig].
- **Optimal body size on mobile:** **16 sp (Material) / 17 pt (Apple)** minimum. iOS Safari auto-zooms input fields < 16 px — a signal that's too small [6-read]. (Note: 16 px is a convention, not a hard WCAG number — WCAG 1.4.4 only requires resize to 200 %.)

### 4.4 Tabular figures for fares (important)

In proportional fonts digit widths vary, so a live-updating number **jitters horizontally** each frame — jarring on fares, timers, ETAs, and misaligns numbers in a column [2-tnum][12-tnum]. **Tabular figures (`tnum`)** make every digit the same width, so changing numbers stay put and columns align. Rule: *if a number changes or lines up with others, use tabular figures*.

**Flutter:**
```dart
Text(fareText, style: TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontFeatures: [FontFeature.tabularFigures()],  // == FontFeature.enable('tnum')
));
```
`FontFeature.tabularFigures()` is documented as equivalent to enabling `tnum`; mutually exclusive with `proportionalFigures()` [5-tnum][11-feat].

**Does Plus Jakarta Sans support it? Yes** — the tokotype changelog records *"Adding Tabular Figures (.tf)"* in **v2.600 (Nov 2021)** [9-pjs]. Verify the bundled `.ttf` is v2.600+, then apply the feature to every fare, price-per-km, ETA, countdown, and rating figure.

### 4.5 Readability

Target ~50–75 characters/line (usually near-full-width single column on phones); contrast defers to WCAG (§3); truncate free text with `maxLines` + `TextOverflow.ellipsis` but **never truncate prices/fares/ETAs** — give them tabular figures and enough width [6-read].

---

## 5. Spacing, layout, elevation, motion & haptics

### 5.1 Spacing — 8 pt grid with 4 px sub-steps

Lay out in multiples of 8 (8, 16, 24, 32, 40, 48, 56, 64…) with **4 px** as a half-step for tight relationships (icon-to-label, label-to-input) [15-grid][16-grid]. Why 8: common screen dimensions and pixel densities divide by 8, so an 8-based system scales cleanly across @1x/@1.5x/@2x/@3x without fractional pixels, and it removes per-decision guesswork. Material is explicitly hybrid — an **8 dp component grid** plus a **4 dp baseline grid for typography** [15-grid]. Concrete token ladder: **4, 8, 12, 16, 24, 32, 48, 64**.

### 5.2 Density & list heights

- **Tap targets:** Material 48 dp, Apple 44 pt; **≥ 8 dp/pt spacing** between targets (16 pt+ for frequent controls) [17-tt][18-tt].
- **M3 list-item heights:** single-line **56 dp**, two-line **72 dp**, three-line **88 dp** [19-lists].
- **Density:** Flutter `VisualDensity.compact` shifts each axis −2 units; use it only on scanning-heavy screens (30+ toggle rows). Keep default touch UI at comfortable density so rows still meet 48 dp.

### 5.3 Elevation — the M3 model (shadow vs border)

**M3 elevation levels → dp** [2-elev][3-elev][4-elev]:

| Level | dp | Components |
|---|---|---|
| 0 | 0 | Filled buttons, **outlined cards** |
| 1 | 1 | Elevated cards, bottom sheets, switches |
| 2 | 3 | Nav bar, menus, scrolled top app bar |
| 3 | 6 | **FAB, dialogs**, pickers |
| 4–5 | 8 / 12 | Mostly hover/drag |

**Tonal elevation replaces heavy shadows:** an elevated surface is tinted by a semi-transparent overlay of the theme's **primary color** (the surface tint) — higher elevation = more tint = subtly lighter surface (and in dark mode, elevation reads as a lighter surface, not a shadow) [2-elev][5-tone].

**Modern shadow-vs-border guidance:** a 1 px hairline border gives a crisp boundary that survives any background; a shadow conveys depth but can vanish on pure-white/pure-dark. Best practice is a **hybrid** — hairline + a soft low shadow [20-shadow]. Premium shadows are **layered, not single** (Josh Comeau): stack 2–5 low-opacity shadows (tight contact + wider ambient), keep a consistent light source (vertical offset ≈ 2× horizontal), and **tint the shadow** (match background hue, avoid pure black). Example medium recipe: three layers `1px 2px 2px`, `2px 4px 4px`, `3px 6px 6px`, each 0.333 opacity [20-shadow].

> **Net:** default cards to low elevation (0–1) with a hairline border + one soft tinted shadow; reserve Level 3 (6 dp) for genuinely floating things. Let tonal tint, not shadow depth, carry hierarchy.

### 5.4 Motion — M3 duration & easing tokens

**Duration tokens (ms)**, mirrored in Flutter's `Durations` class [1-motion][14-dur]: short1 50 · short2 100 · short3 150 · short4 200 · medium1 250 · medium2 300 · medium3 350 · medium4 400 · long1 450 · long2 500 · long3 550 · long4 600 · extralong 700–1000. Grouping: **short 50–200 ms** (icon state, ripple, selection), **medium 250–400 ms** (cards expanding, entering elements), **long 450–600 ms** (large/hero transitions). Larger travel → longer duration.

**Easing tokens (cubic-bezier)** [1-motion][23-motion]:

| Token | cubic-bezier | Use |
|---|---|---|
| **Emphasized** | *two-segment* (see below) | Default; hero/brand moments |
| Emphasized decelerate | `(0.05, 0.7, 0.1, 1.0)` | Elements **entering** |
| Emphasized accelerate | `(0.3, 0.0, 0.8, 0.15)` | Elements **exiting** permanently |
| **Standard** | `(0.2, 0.0, 0, 1.0)` | Simple small in-screen changes |
| Linear | `(0, 0, 1, 1)` | Progress, ripple opacity |

> **Correction (verified):** M3 "Emphasized" easing is **not** the single bezier `(0.2,0,0,1)` that many blogs cite — *that is the **Standard** token*. Real Emphasized is a two-segment (three-point) cubic, implemented in Flutter as **`Curves.easeInOutCubicEmphasized`** [12-curves][13-curves][23-motion].

**What reads premium vs sluggish** [21-nng][22-micro]: sweet spot **200–300 ms** (broadly 100–500 ms acceptable); < 100 ms feels instant but can look like a hard cut; ≥ 400 ms starts to feel slow for frequent actions; > 500 ms reads sluggish. Premium feel = **emphasized easing + right duration**, not long duration. "Fast in, slow settle" (decelerate) reads high-quality; linear/symmetric ease-in-out on entrances reads mechanical.

**Flutter `Curves`:** M3 emphasized → `Curves.easeInOutCubicEmphasized`; `Curves.easeOutCubic` = `Cubic(0.215, 0.61, 0.355, 1.0)` (good decelerate for entrances); `Curves.fastOutSlowIn` = classic Material standard [12-curves][13-curves].

**Spring physics:** use springs for interruptible, gesture-driven motion (drag-to-dismiss, sheets following a finger) — they handle velocity hand-off and mid-flight re-targeting that fixed-duration curves can't; use duration+curve for deterministic choreographed transitions [11-spring]. iOS 17+ defaults to springs; premium iOS = short response (0.25–0.4 s) + high damping (0.7–0.85) → snappy, settles cleanly (`.snappy`, `.smooth`) [11-spring].

### 5.5 Haptics

**iOS families** [8-hap][9-hap][10-hap]: **Selection** (light tick across discrete steps), **Impact** (light/medium/heavy + soft/rigid — "snapped into place"), **Notification** (success/warning/error — reports an outcome). **Android** has no notification taxonomy (uses `HapticFeedbackConstants` / `VibrationEffect`).

**Flutter `HapticFeedback` — the ACTUAL API** [6-hap][7-hap]: only `selectionClick()`, `lightImpact()`, `mediumImpact()`, `heavyImpact()`, `vibrate()`.

> **Correction (verified):** Flutter has **no** `successNotification`/`warningNotification`/`errorNotification` — those appear in AI-generated text but are not in the class. To fire iOS notification haptics, use a platform channel/plugin; in pure Flutter approximate (error → `heavyImpact`, success/warning → `mediumImpact`) [6-hap][7-hap].

**When to fire (restraint):** commit moments (ride requested/accepted → `mediumImpact`), snapping a control into place, toggles/selection (`selectionClick`), and errors (a heavier cue). HIG: haptics complement a clear visual/audio change, never substitute for one; overuse dulls them. Nothing on ordinary navigation [8-hap][24-hig].

---

## 6. Ride-hailing-specific UI patterns

> Numbers labeled **[spec]** are authoritative (Material/Apple docs); **[observed]** are teardown/case-study convention; **[impl]** are engineering write-ups.

### 6.1 Map + draggable bottom sheet

Full-screen interactive map as base; floating "Where to?" bar near top; a bottom sheet owning everything else, dragging between snap points — the shared structure of Uber, Lyft, Google/Apple Maps [1-rh][2-rh].

- **Detents: use 3, not a continuum** — **Collapsed (peek) → Half → Expanded (full)**. iOS `UISheetPresentationController`: `.medium()` ≈ 50 %, `.large()` = full, custom for peek [7-rh][8-rh]. Android/M3: `STATE_COLLAPSED` / `STATE_HALF_EXPANDED` (ratio **0.5** [spec]) / `STATE_EXPANDED` [6-rh].
- **Peek height:** enough to show the CTA + a hint of more (~120–200 dp in practice); Material default is `auto` [6-rh]. Every draggable edge needs a handle, and snap targets should map to content stages [4-rh].
- **Drag handle [spec]:** Material reserves a **48 × 48 dp** touch target; visible pill ~**4 × 32 dp** centered. iOS `prefersGrabberVisible = true` [5-rh][6-rh][7-rh].
- **Corner radius [spec]:** M3 default top corners **28 dp** (`cornerExtraLarge`), bottom flush [5-rh][6-rh].
- **Elevation/scrim [spec]:** standard sheet **1 dp, no scrim** (map stays usable); modal sheet adds a scrim. Max width **640 dp**; fling velocity **500 px/s** [6-rh].
- **Keep the map interactive behind the sheet:** iOS 16.4+ `.presentationBackgroundInteraction(.enabled(upThrough: .medium))` lets the user pan/zoom at peek/half, auto-dimming when expanded — the "Apple Maps effect." Android's standard sheet has no scrim so the map stays touchable [10-rh][11-rh].
- **Map padding so the pin isn't hidden [impl]:** as the sheet rises, apply `contentPadding`/`setMapPaddingBottom` = the covered height (shifts only the logical viewport, cheap per-frame), then re-center the camera (`moveCamera`) after settle so the pin stays optically centered in the *visible* region [13-rh][14-rh].

> **Flutter build:** one `DraggableScrollableSheet` (or `showModalBottomSheet` + `snapSizes`) with **three** snap sizes (e.g. 0.14 / 0.42 / 0.92), 28 px top radius, a 4 × 32 handle in a 48 px tap zone, `isScrollControlled: true`; drive `GoogleMap.padding` from the sheet controller's `pixels` each frame and re-center the active marker after settle.

### 6.2 Driver / trip card

Appears post-match and during trip; Uber composes it from Base Card + Avatar and the **ActionCard** pattern (stacked single-purpose cards, action cards pinned bottom, stacking upward) [3-rh][12-rh]. Info in hierarchy order [observed]:

1. **Status line / ETA** — largest text ("Arriving in 3 min"); the single most-watched number.
2. **Vehicle identity** — make/model + **color** + **license plate** (plate on a plate-styled chip — highest-utility field for curb-finding).
3. **Driver block** — circular photo (~40–56 dp), first name + initial, **star rating** to one decimal ("4.95 ★"), optional badges.
4. **Actions row** — **Message** + **Call** as equal-weight icon buttons (number-masked), a **Safety shield** entry, overflow (Cancel / Share / Add stop).

Layout: driver+vehicle in a horizontal header (avatar left, name/rating stacked, vehicle+plate right/second line); Call/Message equal-weight, thumb-reachable, min 44 × 44; never bury the safety shield in overflow.

### 6.3 Live tracking

- **Markers [observed]:** directional **car glyph** (not a generic pin) that **rotates to its bearing**; a user puck (dot + accuracy halo/heading cone); distinct pickup/drop pins.
- **Smooth movement [impl] — the core trick:** GPS pings arrive every few seconds; writing them straight to the marker teleports. **Interpolate** between last/new position over **~300–500 ms** with a frame ticker (`AnimationController`/`Ticker`), `pos = v·end + (1−v)·start` for v 0→1, setting rotation to the bearing between consecutive points [15-rh][16-rh][17-rh].
- **Route polyline:** draw the road-snapped path; as a premium touch, trim/de-emphasize the traveled portion behind the car. Fit the camera to car + next waypoint respecting sheet padding [17-rh].
- **ETA:** recomputed server-side from live traffic (not distance÷speed), so it drifts — update the headline on each payload and animate number changes subtly rather than snapping [17-rh].

> **Flutter:** one `AnimationController` per tracked vehicle, `Tween` the `LatLng`, `Marker.rotation` from `Geolocator.bearingBetween`, throttle camera follows so they don't fight manual pan.

### 6.4 "Confirm ride" sticky CTA

Sticky bottom CTA pinned to the sheet's bottom edge, always visible; the peek detent's content. Stacked above the button (bottom-up): payment-method chip → promo/price line → tier summary (name + price + capacity) → CTA. Uber's ActionCard model literally has bottom-pinned cards stacking upward [12-rh].

**Tap vs slide:** convention is **tap** for booking ("Confirm UberX"); **slide-to-confirm** is reserved for higher-stakes/irreversible or safety actions because it "cannot be accidentally executed by simply touching a button" [24-rh]. For a standard ride (cheap to cancel) a tap CTA is right; reserve slide/press-and-hold for SOS/"Start trip." Ship a full-width tap CTA (48–56 dp, high-contrast) with the price *in or immediately above* the button ("Confirm · $14.20").

### 6.5 Fare display

**Upfront pricing is the standard** — one **total fare per tier before requesting**, not a running meter; it already bakes in surge [18-rh][20-rh]. **Surge** shows as a higher number with a small indicator (bolt/heat icon or "Fares are higher due to demand"); Uber no longer exposes the exact multiplier to riders in most markets [18-rh]. **Breakdown** hides behind an **info (ⓘ)** tap — base, distance/time, surge, tolls, fees, promos, taxes [18-rh][19-rh]. Presentation: one **bold** currency figure per tier, symbol + 2 decimals, **tabular/lining figures** so prices align vertically across tiers; strike-through original for promos; keep ETA and capacity as smaller secondary metadata so **price is the dominant number**.

### 6.6 Tier / vehicle selection

**Vertical scrolling list is the modern default** (Uber moved off the horizontal carousel years ago; Lyft/Bolt/Grab are vertical) because each row carries icon + name + descriptor + capacity + ETA + price on one line without truncation and scales to many tiers; carousels hide price/capacity and force swiping [22-rh]. Per-row [observed]: **left** vehicle illustration (distinct silhouette per tier); **center** name + one-line descriptor + capacity ("👤 4") + ETA; **right** **price** (bold) + promo strike-through + surge indicator. **Selected state:** tinted background + border/check + slight elevation; selection drives the sticky CTA label and the price above the button, and updates the map's pickup ETA. Rows ~72–88 dp.

### 6.7 Safety affordances

Both Uber and Lyft treat safety as a **persistent, always-reachable Safety Toolkit** (a **shield icon** on the trip map/sheet), not a buried menu [21-rh]:

- **Emergency → 911** with on-screen trip details for the dispatcher (live location, car, plate); Uber supports text-to-911 where available.
- **Share My Trip** — live route + driver + ETA to trusted contacts; can auto-share at night.
- **RideCheck (Uber)** — GPS + accelerometer detect unexpected long stops, route deviation, or a possible crash, then proactively check in with both parties. Lyft's equivalent is "Smart Trip Check-in."
- **PIN / Verify Your Ride** — a 4-digit PIN the rider gives the driver before the trip confirms the correct match (plus plate/model/photo shown pre-trip).
- **Audio Recording** — optional encrypted in-trip recording for evidence.
- **24/7 Live Help** — chat/call a safety agent (Uber's ADT integration) who can escalate to 911 with location.
- **Anonymised contact** — number masking for call/message.

> **Design opinion:** put the shield as a *persistent top-level control* (top-right of map or driver-card header, never overflow); open a full-height safety sheet; make the emergency trigger the one place you use **slide-to-confirm / press-and-hold** so it can't fire accidentally.

**Ride-hailing defaults summary:**

| Element | Value | Basis |
|---|---|---|
| Sheet snap points | 3: peek / half / full | convention |
| Half-expanded ratio | 0.5 | Material [spec] |
| Top corner radius | 28 dp | Material XL [spec] |
| Drag handle | 4 × 32 visible in 48 × 48 target | Material [spec] |
| Sheet elevation / scrim | 1 dp / none (standard) | Material [spec] |
| Max sheet width / fling | 640 dp / 500 px/s | Material [spec] |
| Marker glide | 300–500 ms interpolate + bearing rotation | impl |
| CTA | tap to book; slide only for emergency | convention |
| Fare | single upfront total/tier, surge baked in, ⓘ breakdown | Uber docs |
| Tier list | vertical rows, price dominant, capacity+ETA metadata | observed |

---

## 7. Concrete recommendations for FairsVia

Keyed to our actual design system (`packages/design_system/lib/src/`). **Keep emerald `#12B76A` and Plus Jakarta Sans** — the changes below sharpen the system rather than replace it. Priorities: **P0 = correctness/accessibility (do first), P1 = premium polish, P2 = nice-to-have.**

### What's already right (keep it)

Our system is already strong: warm stone neutrals + a single emerald accent (good accent discipline, §3.4); 56 dp full-width `PrimaryButton` with press-scale 0.97 + light haptic; radius scale 10/16/20/28 (28 = sheet corner, matches M3 §6.1); layered warm-tinted shadows (`AppElevation`, matches §5.3 "layered, tinted"); dark base `#121110`/`#1C1A19` (off-black, not pure — §3.3); motion tokens 140/260/420 ms in the premium band (§5.4); tight negative tracking on large headings (§4.3). The gaps are contrast, the icon library, tabular figures, and a few token refinements.

### P0 — Accessibility & correctness (do first)

**7.1 Fix emerald contrast — this is the biggest issue.** Computed from our real hex values (sRGB WCAG 2.x):

| Pair | Ratio | Verdict |
|---|---|---|
| White on `accent #12B76A` (PrimaryButton label) | **2.62:1** | ❌ fails AA (needs 4.5:1) |
| White on `accentPressed #0E9E5B` | 3.47:1 | ❌ fails |
| `accent` as text on white / `background #FAF9F7` | 2.62 / 2.49:1 | ❌ fails (affects TextButton `foregroundColor: accent`, `onPrimaryContainer: accent`) |
| White on a darker `#0A7D48` | **5.20:1** | ✅ passes AA |
| `accent` on `surfaceDark #1C1A19` (dark mode) | 6.61:1 | ✅ good |

The emerald reads beautifully but **white text on it fails WCAG AA**, and **emerald-as-text on light surfaces fails badly** (§3.2 [3-wcag]). Two-part fix that *keeps `#12B76A` as the brand identity color*:

- Introduce **`accentInk = #0A7D48`** (darker emerald, ~tone 35) and use it for: (a) the filled CTA background where a white label sits (→ 5.2:1), and (b) any emerald *text/icon on light* — TextButton foreground, `onPrimaryContainer`, links, selected-chip labels. Keep `#12B76A` for large fills, the switch track, dark-mode accent, and decorative brand moments where no small text sits on it.
- Alternatively keep `#12B76A` as the button fill but switch the label to dark ink `#1C1917` — but that dilutes the emerald-CTA identity, so **`accentInk` for text-bearing surfaces is preferred.**
- In dark mode emerald is fine as-is (6.6:1); no change needed there.

**7.2 Fix tertiary text contrast.** `textTertiaryLight #8A837D` on background = **3.55:1**, on `surfaceMuted #F5F3F0` = **3.37:1** — both **fail 4.5:1** for normal text [3-wcag]. `textTertiaryDark #78716C` on dark = 3.93:1, also short. Fixes: darken tertiary-light to ~`#6F6862` (≈ 4.6:1) and tertiary-dark to ~`#8A837D` (≈ 4.7:1), **or** restrict tertiary text to large/non-essential use only (timestamps, ≥ 18.66 px bold) and never use it for body copy. (`textSecondary` is fine — 7.25:1 light / 7.48:1 dark.)

**7.3 Adopt a real icon package.** Today we use the built-in Material *rounded* icon font (`Icons.*_rounded`) with no dedicated package. Add **`material_symbols_icons`** (§1.2 [5]) and standardise on it: set app-wide defaults via `IconThemeData`, use **FILL 0 inactive → FILL 1 active** for bottom-nav (§1.1), keep icons **neutral** except selected-nav/CTA/status which take `accentInk`/semantic colors (§1.5). Sizes: 24 dp default, 18 dp in buttons, 48 dp targets. Match icon Weight to font weight. *(If the team prefers our current rounded aesthetic, `Icons.*_rounded` is internally consistent — but it can't do the fill-toggle nav pattern, which Material Symbols gives natively.)*

**7.4 Tabular figures on all numerics.** Add `fontFeatures: [FontFeature.tabularFigures()]` to every fare, price-per-km, ETA, countdown, and rating. Plus Jakarta Sans supports `tnum` since v2.600 (§4.4 [9-pjs]) — verify the bundled `.ttf` is ≥ v2.600. Best done as a `TextStyle` helper (e.g. `AppTypography.numeric(...)` or an extension) so live-updating fares/timers stop jittering. **High visible-polish, low effort.**

**7.5 Verify sticky-CTA safe-area inset.** Ensure the bottom "Confirm" dock pads by `MediaQuery.viewPadding.bottom` / `SafeArea(bottom: true)` so it clears the home indicator (§2.8 [13-safe]), and add a 1 dp top divider or soft top shadow so scrolling content doesn't bleed into the CTA.

### P1 — Premium polish

**7.6 Align the type theme to M3 metrics.** Our `titleMedium`/`bodyLarge` use height 1.3/1.45; nudge body toward **1.5** (M3 Body Large, §4.1 [10-typo]) for calmer reading. Small labels: our `labelSmall` already has +0.4 tracking (good, §4.3). Keep the negative tracking on display/headline. Body stays at 16 sp (bodyLarge) — correct (§4.3).

**7.7 Codify the M3 emphasized curve.** `AppMotion.emphasized` is currently `Curves.easeOutQuart`. For entrances that's fine, but for shared-axis/container transitions use **`Curves.easeInOutCubicEmphasized`** — the real M3 emphasized curve (§5.4 [13-curves]); many teams mislabel the Standard bezier as emphasized. Keep durations (140/260/420) — they sit in the premium 100–500 ms band. Add an explicit `emphasizedDecelerate`/`emphasizedAccelerate` pair for enter/exit if you build custom route transitions.

**7.8 Honest haptics naming.** `AppHaptics.success()` currently calls `mediumImpact()` and `heavy()` calls `heavyImpact()` — fine, but our doc comment implies iOS notification haptics, which the stock Flutter API does **not** provide (§5.5 [6-hap]). Either add a platform-channel/plugin for true `UINotificationFeedbackGenerator` success/warning/error, or update the comment to state these are impact approximations. Keep the semantic wrapper — it's the right pattern.

**7.9 Button-radius intent.** We use `radius = 16` (rounded-rect) for the primary CTA. That's a valid, warm choice (Revolut/Monzo camp, §2.4). If we want the more "this is THE action" M3 signal, switch **only the primary sticky CTA** to `pill` (StadiumBorder) while keeping 16 dp on cards/inputs — a deliberate, cheap brand decision. Either is defensible; don't mix per-screen.

**7.10 Card elevation discipline.** Our `cardTheme` already pairs a hairline border with `elevation: 0` (matches §5.3 hybrid) — good. Ensure resting cards use `AppElevation.sm` (soft) and reserve `md`/`float` for genuinely floating overlays (map buttons, FAB) so shadow depth still means "elevated."

### P2 — Nice-to-have

**7.11 Dark-mode tonal elevation.** We use fixed dark surfaces (`surfaceDark`/`surfaceMutedDark`). Consider a third, slightly-lighter container tone for stacked/elevated dark surfaces so "higher = lighter" holds (§3.3) — e.g. a `surfaceElevatedDark ≈ #2E2A28` for sheets sitting above cards.

**7.12 Semantic ramps.** Our semantics are single values (`success/warning/error/info`). For richer states, add a `container` + `on` step per semantic (§3.5) so error/success banners have a legible tinted background in both themes without hand-mixing alpha.

**7.13 Ride-screen specifics** (when building the rider flow): three-detent `DraggableScrollableSheet` (~0.14 / 0.42 / 0.92), 28 dp top radius (we have `radiusXl = 28` ✓), 4 × 32 handle in a 48 dp tap zone, map padding driven from the sheet controller with post-settle re-center (§6.1); directional car marker with 300–500 ms `LatLng` interpolation + bearing rotation (§6.3); vertical tier list, ~72–88 dp rows, bold right-aligned tabular price (§6.6); persistent safety shield with a slide-to-confirm SOS (§6.7).

### Punch-list summary

| # | Change | Priority | File(s) |
|---|---|---|---|
| 7.1 | Add `accentInk #0A7D48` for white-label CTA + emerald-on-light text | **P0** | `app_colors.dart`, `primary_button.dart`, `app_theme.dart` |
| 7.2 | Darken tertiary text to ~4.6:1 (or restrict to large text) | **P0** | `app_colors.dart` |
| 7.3 | Adopt `material_symbols_icons`; FILL toggle on nav; neutral-by-default | **P0** | `pubspec.yaml`, `app_theme.dart`, nav widgets |
| 7.4 | Tabular figures on all fares/ETAs/ratings | **P0** | `app_typography.dart` (+ numeric helper) |
| 7.5 | Verify sticky-CTA safe-area inset + top divider | **P0** | ride-screen scaffold |
| 7.6 | Nudge body line-height toward 1.5 | P1 | `app_typography.dart` |
| 7.7 | Use `Curves.easeInOutCubicEmphasized` for container transitions | P1 | `app_motion.dart` |
| 7.8 | Correct haptics naming / add true notification haptics | P1 | `app_motion.dart` |
| 7.9 | Consider pill radius for the primary sticky CTA only | P1 | `primary_button.dart` |
| 7.10 | Enforce elevation discipline (sm resting, float overlays) | P1 | usage across apps |
| 7.11 | Add a lighter dark elevated surface tone | P2 | `app_colors.dart` |
| 7.12 | Container + on steps per semantic color | P2 | `app_colors.dart` |
| 7.13 | Build ride screen to §6 patterns | P2 | rider app |

---

## Sources

Numbers are grouped by the section that uses them. Suffix tags (e.g. `[10-typo]`) disambiguate reuse.

**Icons (§1)**
1. Material 3 — Applying icons: https://m3.material.io/styles/icons/applying-icons
2. Material Symbols docs (axes, optical size): https://developers.google.com/fonts/docs/material_symbols
3. Material — Icons style (grid, live area, stroke): https://m1.material.io/style/icons.html
4. Icon grids & keylines demystified: https://minoraxis.medium.com/icon-grids-keylines-demystified-5a228fe08cfd
5. pub.dev — material_symbols_icons: https://pub.dev/packages/material_symbols_icons
6. pub.dev — phosphor_flutter: https://pub.dev/packages/phosphor_flutter
7. pub.dev — flutter_lucide: https://pub.dev/packages/flutter_lucide
8. pub.dev — lucide_icons (legacy): https://pub.dev/packages/lucide_icons
9. Lucide — stroke width: https://lucide.dev/guide/lucide/basics/stroke-width
10. Apple HIG — SF Symbols: https://developer.apple.com/design/human-interface-guidelines/sf-symbols
11. Material 3 — Icon-button accessibility: https://m3.material.io/components/icon-buttons/accessibility
12. Android accessibility — touch target (48 dp): https://support.google.com/accessibility/android/answer/7101858
13. WCAG 2.1 — SC 1.4.11 Non-text Contrast: https://www.w3.org/WAI/WCAG21/Understanding/non-text-contrast.html
14. Uber Base — Icons: https://base.uber.com/6d2425e9f/p/52f72c-icons

**Buttons & touch targets (§2)** — also uses 12, 13 above
15. WCAG 2.2 — SC 2.5.8 Target Size (Minimum): https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html
16. WCAG — SC 2.5.5 Target Size (Enhanced): https://silktide.com/accessibility-guide/the-wcag-standard/2-5/input-modalities/2-5-5-target-size-enhanced/
17. LogRocket — Accessible touch target sizes: https://blog.logrocket.com/ux-design/all-accessible-touch-target-sizes/
   - `[17-cta]` DesignStudio — CTA button best practices: https://www.designstudiouiux.com/blog/cta-button-design-best-practices/
   - `[15-cta]` Mobile checkout optimization: https://www.btng.studio/articles/mobile-checkout-optimization-guide/
   - `[16-cta]` DesignMonks — mobile button size: https://www.designmonks.co/blog/perfect-mobile-button-size
- M3 buttons specs: https://m3.material.io/components/buttons/specs
- `[10-buttons]` M3 Expressive (size ladder, shape morph): https://supercharge.design/blog/material-3-expressive
- `[9-radius]` Button radius in UI design: https://medium.com/uxdworld/button-radius-in-ui-design-8e8f35dc6726
- `[20-states]` M3 — State layers (8/10/10/16 %): https://m3.material.io/foundations/interaction/states/state-layers
- `[19-disabled]` pub.dev — material_design M3OpacityToken (38 %/12 %): https://pub.dev/documentation/material_design/latest/material_design/M3OpacityToken.html
- `[21-disabled]` Disabled state alpha for Material buttons: https://owaisidris.medium.com/disabled-state-alpha-material-button-c2d21607ce7c
- `[14-dock]` Uber Base — Button dock: https://base.uber.com/6d2425e9f/p/46ed03-button-dock
- `[13-safe]` Shopify safe-area inset variable: https://shopify.dev/changelog/new-css-variable-for-mobile-safe-area-insets

**Colour (§3)**
- `[1-roles]` M3 — Color roles: https://m3.material.io/styles/color/roles
- `[2-radix]` Radix Colors — Understanding the 12-step scale: https://www.radix-ui.com/colors/docs/palette-composition/understanding-the-scale
- `[3-wcag]` WCAG 2.1 — SC 1.4.3 Contrast (Minimum): https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html
- `[4-wcag]` WCAG 2.1 — SC 1.4.11 Non-text Contrast: https://www.w3.org/WAI/WCAG21/Understanding/non-text-contrast.html
- `[5-wcag]` WCAG 2.1 — SC 1.4.6 Contrast (Enhanced): https://www.w3.org/WAI/WCAG21/Understanding/contrast-enhanced.html
- `[6-stripe]` Stripe — Designing accessible color systems: https://stripe.com/blog/accessible-color-systems
- `[7-tw]` Tailwind CSS — Colors (950 step, OKLCH): https://tailwindcss.com/docs/colors
- `[8-m3]` M3 — Key colors & tones: https://m3.material.io/styles/color/the-color-system/key-colors-tones
- `[9-m3]` M3 — How the color system works (tones): https://m3.material.io/styles/color/system/how-the-system-works
- `[10-roles]` Material Components Android — Color roles: https://github.com/material-components/material-components-android/blob/master/docs/theming/Color.md
- `[11-tint]` Flutter — Material.surfaceTintColor: https://api.flutter.dev/flutter/material/Material/surfaceTintColor.html
- `[12-apca]` Understanding the APCA algorithm: https://www.accessibilitychecker.org/blog/apca-advanced-perceptual-contrast-algorithm/
- `[13-wcag3]` Adrian Roselli — WCAG 3 Contrast status: https://adrianroselli.com/2026/04/wcag3-contrast-as-of-april-2026.html
- `[15-dark]` Material (M2) — Dark theme (#121212, overlays, opacities): https://m2.material.io/design/color/dark-theme.html
- `[18-hig]` Apple HIG — Dark Mode: https://developer.apple.com/design/human-interface-guidelines/dark-mode
- `[19-hig]` Apple HIG — Color: https://developer.apple.com/design/human-interface-guidelines/color
- `[20-6030]` The 60-30-10 rule for UI color: https://uxplanet.org/the-60-30-10-rule-a-foolproof-way-to-choose-colors-for-your-ui-design-d15625e56d25

**Typography (§4)**
- `[1-typo]` M3 — Type scale tokens: https://m3.material.io/styles/typography/type-scale-tokens
- `[10-typo]` Flutter — typography.dart (`_M3Typography` exact tokens): https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/material/typography.dart
- `[4-hig]` Apple HIG typography table (Dynamic Type, tracking): https://gist.github.com/eonist/b9c180a67980c6e18a5184f19bff68fa
- `[6-hig]` Apple HIG — Typography: https://developer.apple.com/design/human-interface-guidelines/typography
- `[7-scale]` Cieden — Typographic scales (1.25 / 1.333): https://cieden.com/book/sub-atomic/typography/different-type-scale-types
- `[8-scale]` Type scale generator & mobile guidance: https://wtfont.app/en/type-scale-generator/
- `[3-pjs]` / `[9-pjs]` Plus Jakarta Sans (weights, variable axis, "Adding Tabular Figures" v2.600): https://tokotype.github.io/plusjakarta-sans/ · https://github.com/tokotype/PlusJakartaSans
- `[2-tnum]` Flutter Pro Design — tabular figures: https://flutterpro.design/details/tabular-figures
- `[5-tnum]` Flutter API — FontFeature.tabularFigures: https://api.flutter.dev/flutter/dart-ui/FontFeature/FontFeature.tabularFigures.html
- `[11-feat]` Flutter API — FontFeature (tnum/lnum/pnum): https://api.flutter.dev/flutter/dart-ui/FontFeature-class.html
- `[12-tnum]` Code With Andrea — TextStyle with tabular figures: https://codewithandrea.com/tips/text-style-tabular-figures/
- `[6-read]` Best font sizes for readability (16 px, 1.5 lh, 50–75 chars): https://www.greadme.com/blog/seo/best-font-sizes-for-readability-complete-guide

**Spacing, elevation, motion, haptics (§5)**
- `[1-motion]` M3 — Easing & duration tokens/specs: https://m3.material.io/styles/motion/easing-and-duration/tokens-specs
- `[23-motion]` material-components-android — Motion.md (cubic-bezier values): https://github.com/material-components/material-components-android/blob/master/docs/theming/Motion.md
- `[2-elev]` M3 — Applying elevation: https://m3.material.io/styles/elevation/applying-elevation
- `[3-elev]` M3 — Elevation tokens: https://m3.material.io/styles/elevation/tokens
- `[4-elev]` Basics of elevation on Android (level→dp): https://designfornative.com/basics-of-elevation-on-android/
- `[5-tone]` M3 — Tone-based surface color (surface tint): https://m3.material.io/blog/tone-based-surface-color-m3
- `[20-shadow]` Josh W. Comeau — Designing beautiful shadows in CSS: https://www.joshwcomeau.com/css/designing-shadows/
- `[12-curves]` Flutter API — Curves class: https://api.flutter.dev/flutter/animation/Curves-class.html
- `[13-curves]` Flutter API — Curves.easeInOutCubicEmphasized: https://api.flutter.dev/flutter/animation/Curves/easeInOutCubicEmphasized-constant.html
- `[14-dur]` Flutter API — Durations class (M3 tokens): https://api.flutter.dev/flutter/material/Durations-class.html
- `[11-spring]` Apple — SwiftUI spring(response:dampingFraction:): https://developer.apple.com/documentation/swiftui/animation/spring(response:dampingfraction:blendduration:)
- `[6-hap]` Flutter API — HapticFeedback class: https://api.flutter.dev/flutter/services/HapticFeedback-class.html
- `[7-hap]` Flutter API — HapticFeedback.selectionClick (platform mapping): https://api.flutter.dev/flutter/services/HapticFeedback/selectionClick.html
- `[8-hap]` Apple HIG — Playing haptics: https://developer.apple.com/design/human-interface-guidelines/playing-haptics
- `[9-hap]` Apple — UIImpactFeedbackGenerator.FeedbackStyle: https://developer.apple.com/documentation/uikit/uiimpactfeedbackgenerator/feedbackstyle
- `[10-hap]` Apple — UINotificationFeedbackGenerator.FeedbackType: https://developer.apple.com/documentation/uikit/uinotificationfeedbackgenerator/feedbacktype
- `[24-hig]` Apple HIG — Feedback: https://developer.apple.com/design/human-interface-guidelines/feedback
- `[15-grid]` Designary — Grid systems & the 4px grid: https://blog.designary.com/p/layout-basics-grid-systems-and-the-4px-grid
- `[16-grid]` Design with the 4px grid system: https://medium.com/@nishaznani/design-with-4px-grid-system-1676d1091f51
- `[17-tt]` LogRocket — Accessible touch target sizes: https://blog.logrocket.com/ux-design/all-accessible-touch-target-sizes/
- `[18-tt]` Human Standards — Touch targets & spacing: https://www.humanstandards.org/code-design-tokens/touch-targets-spacing/
- `[19-lists]` Material — Lists (56/72/88 dp): https://m1.material.io/components/lists.html
- `[21-nng]` NN/g — Executing UX animations (duration): https://www.nngroup.com/articles/animation-duration/
- `[22-micro]` Microinteractions UI best practices (200–500 ms): https://createbytes.com/insights/microinteractions-ui-best-practices

**Ride-hailing patterns (§6)**
- `[1-rh]` Uber Base — Sheet: https://base.uber.com/6d2425e9f/p/033e0d-sheet/b/46994b
- `[2-rh]` Uber Base — Patterns: https://base.uber.com/6d2425e9f/p/966802-patterns
- `[3-rh]` Uber Base — Card: https://base.uber.com/6d2425e9f/p/02338d-card
- `[4-rh]` LogRocket — Designing bottom sheets: https://blog.logrocket.com/ux-design/bottom-sheets-optimized-ux/
- `[5-rh]` M3 — Bottom sheets specs: https://m3.material.io/components/bottom-sheets/specs
- `[6-rh]` material-components-android — BottomSheet docs: https://github.com/material-components/material-components-android/blob/master/docs/components/BottomSheet.md
- `[7-rh]` Apple — UISheetPresentationController: https://developer.apple.com/documentation/uikit/uisheetpresentationcontroller
- `[8-rh]` Apple — Detent: https://developer.apple.com/documentation/uikit/uisheetpresentationcontroller/detent
- `[10-rh]` Apple — presentationBackgroundInteraction: https://developer.apple.com/documentation/swiftui/view/presentationbackgroundinteraction(_:)
- `[11-rh]` AppCoda — SwiftUI bottom sheet background/scrolling: https://www.appcoda.com/swiftui-bottom-sheet-background/
- `[12-rh]` Uber Blog — Developing the ActionCard pattern: https://www.uber.com/blog/developing-the-actioncard-design-pattern/
- `[13-rh]` Turo Engineering — Compose map + moving bottom sheet: https://medium.com/turo-engineering/adjusting-compose-google-map-while-bottom-sheet-moves-4a7465305137
- `[14-rh]` android-maps-compose — contentPadding offsets camera (#142): https://github.com/googlemaps/android-maps-compose/issues/142
- `[15-rh]` UberCarAnimation (marker interpolation + bearing): https://github.com/amanjeetsingh150/UberCarAnimation
- `[16-rh]` MindOrks — Uber car animation: https://blog.mindorks.com/how-to-add-uber-car-animation-in-android-app/
- `[17-rh]` MapAtlas — Live driver tracking map: https://mapatlas.eu/blog/live-driver-tracking-map-tutorial
- `[18-rh]` Uber Help — Surge in upfront fare: https://help.uber.com/riders/article/will-surge-pricing-be-included-in-the-upfront-fare
- `[19-rh]` Uber — Marketplace pricing: https://www.uber.com/us/en/marketplace/pricing/
- `[20-rh]` Uber — Understanding Upfront Fares: https://uberpubpolicy.medium.com/understanding-upfront-fares-7ab69c656101
- `[21-rh]` Uber — Our commitment to safety (Toolkit, RideCheck, PIN, Share, Live Help): https://www.uber.com/us/en/safety/our-commitment/
- `[22-rh]` UI/UX case study — Cab booking app (tier/capacity): https://medium.com/@alishbanaeem057/ui-ux-design-case-study-cab-booking-app-b9b5f82b69ab
- `[24-rh]` Slide-to-confirm rationale: https://medium.com/@saminadellinger/step-by-step-guide-to-slide-buttons-on-figma-mobile-friendly-ui-design-94f0a86be1b7
- `[25-rh]` Uber Design — Designing the new Uber app: https://medium.com/uber-design/designing-the-new-uber-app-16afcc1d3c2e
- `[26-rh]` Mobbin — Uber iOS screen references: https://mobbin.com/explore/screens/c10e664b-3737-4dc2-b62c-7067045996ba
