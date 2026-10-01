# FAIRSVIA Visual Direction v2 — three 10/10 plans

*Owner's document, Sep 24, 2026 (@pratyush). Saved verbatim in substance;
build notes for this repo at the end.*

## Summary

Three directions can each reach 10/10; they differ in mood, cost and risk, not
quality. Build A and B as full prototypes and test them side by side; treat C
as the likely winner that combines them if both test well.

| | Plan A — Midnight Teal | Plan B — Daylight 3D | Plan C — Day & Night |
|---|---|---|---|
| Mood | Premium, calm, night-friendly | Friendly, bright, playful | Adapts to time and system setting |
| Background | Dark grey #0E0F11 | White #FFFFFF / light grey #F5F6F7 | Light by day, dark by night |
| Brand colour | Teal #2BC4C4 | Deep teal #0A7C7C for text and buttons; bright teal #2BC4C4 inside illustrations | Both teals, one per mode |
| Hero icons | Flat outline + white/silver car renders | Airbnb-style 3D clay icons, Ola-style coloured vehicles | 3D icons, separate render per mode |
| Utility icons | Phosphor Regular | Phosphor Regular | Phosphor Regular |
| Closest reference | Uber | Airbnb 2025, Ola | Google Maps, Apple Maps |
| Build effort | 3–4 weeks | 5–6 weeks | 7–8 weeks |
| 3D icon cost | None | One set of ~20 icons | Two renders of the same 20 |
| Main risk | Looks like every other dark ride app | Icons that don't match look cheap | Two themes to maintain and QA |

Recommendation: ship the shared foundation first; preference test A vs B with
30+ riders in week 3; in-app A/B in weeks 5–8. If B wins by day and riders ask
for dark at night, build C.

## Shared foundation (all plans)

1. All seven critical bugs fixed (map fit, real driver data, Miami default,
   login line break, marker overlap, chip alignment, unavailable tiers).
2. One brand colour — teal. Other colours only with fixed meaning: red = SOS
   and destructive, amber = payment instructions, yellow = stars, blue = the
   system location dot only.
3. Driver-card trust signals: plate as the largest text, driver photo, car
   image in the actual colour, name + ETA in the title, PIN in four boxes.
4. One utility icon family: Phosphor Regular 24 px everywhere. Only hero icons
   change between plans.
5. Accessibility: 4.5:1 text, 3:1 icons, 44 pt targets, screen-reader labels,
   Dynamic Type, Reduce Motion.
6. Same layout and copy in every plan (so a test measures the look only).

Icon tiers: **utility** (back, menu, close, call, message, safety, chevrons —
Phosphor in all plans) and **hero** (ride types, payment, Add a stop, Pre-book,
empty/success states — flat in A, 3D in B and C).

## Plan A — Midnight Teal

Dark, calm, premium, flat icons; cheapest and closest to Uber. Identity from
the logomark, typeface and motion.

| Token | Value | Use |
|---|---|---|
| bg.base | #0E0F11 | Screen background |
| surface.1 | #17181B | Sheets, cards |
| surface.2 | #1F2024 | Secondary buttons, chips |
| text.primary | #FFFFFF | Headings, values |
| text.secondary | #A0A3A8 | Subtitles (~7:1 on surface.1) |
| brand | #2BC4C4 | Primary buttons, route, selection |
| on.brand | #0E0F11 | Text on teal |

Hero icons: four flat 3/4-view silver cars with one teal stripe (shape tells
the tier); duotone payment glyphs; Phosphor action icons in a 40 px teal-tint
circle; teal line illustrations for empty/success. Signature details: soft
teal glow under the route, 2 % grain on the sheet, logomark as pickup pin.

## Plan B — Daylight 3D

Bright white app, one teal, Airbnb-style 3D hero icons, Ola-style vehicles.

| Token | Value | Use |
|---|---|---|
| bg.base | #F5F6F7 | Page background |
| surface.1 | #FFFFFF | Sheets, cards |
| surface.2 | #EEF0F2 | Secondary buttons, chips |
| border.subtle | #E3E5E8 | Dividers |
| text.primary | #111315 | Headings (~18:1) |
| text.secondary | #5F646B | Subtitles (~6:1) |
| brand | #0A7C7C | Buttons, links, selection (~5:1 with white) |
| brand.bright | #2BC4C4 | Route, map pickup, illustrations only |
| brand.tint | #E6F6F6 | Selected-row fill, icon containers |
| on.brand | #FFFFFF | Text on teal |

Surfaces: white sheets, 16 px radius, soft shadow (0 −4 24 rgba(17,19,21,.08)).
Hero icons: 3D clay vehicles (Economy teal, Comfort slate blue, XL sand, Premium
graphite); 3D rupee note / phone-with-check (UPI) / card; 3D pin-plus and
calendar tiles (2-up); 3D check, car-with-magnifier, sleeping car. Selected
row: brand.tint fill, 2 px deep-teal border, car nudges up 4 px.

## Plan C — Day & Night

Both A and B in one app, switching with the system appearance; optional
override Light / Dark / Automatic; **never switch mid-trip** (lock the theme
when a ride is confirmed, apply changes after it ends). Same token names in
both modes; brand #0A7C7C light / #2BC4C4 dark. 3D icons rendered twice from
one scene (light: key top-left + soft floor shadow; dark: lower key, thin rim
light, no floor shadow).

## Screen-by-screen differences (layout and copy identical)

| Screen | A — Midnight Teal | B — Daylight 3D |
|---|---|---|
| Splash | Teal arrow + white wordmark on #0E0F11 | Teal mark + near-black wordmark on white; small 3D turn |
| Login | Dark field, teal focus ring | White field, 1 px border, deep-teal ring; 3D phone illustration |
| Location permission | Teal line illustration | 3D pin on a map tile |
| Set destination | Teal pin with the logomark | Bright-teal 3D pin that lifts while dragging |
| Choose ride | Four silver flat cars; teal outline | Four coloured 3D cars; teal-tint fill + deep-teal border |
| Payment row | Teal duotone Cash glyph | 3D rupee note; UPI as 3D phone |
| Finding driver | Teal radar on dark map | Teal radar on light map; 3D car with magnifier |
| Driver on the way | Photo over a flat car in the actual colour | Photo over a 3D car in the actual colour |
| Driver arrived | PIN boxes on surface.2, white digits | PIN boxes on teal-tint, deep-teal digits |
| In trip | Dark map, teal route with glow | Light map, bright-teal route |
| Add a stop / Pre-book | Phosphor icon in teal-tint circle | 3D pin-plus / calendar tiles, 2-up |
| Ride completed | Teal line check that draws itself | 3D check with bounce; 3D rupee note |
| No cars nearby | Teal line illustration | 3D sleeping car |
| Driver account | Phosphor rows on surface.1 | Phosphor rows on white; 3D wallet on Earnings |

Never changes: utility icons, button positions, sheet heights, copy, Safety
pill, yellow stars, plate style.

## 3D icon brief (Plans B and C)

One artist, one scene file, one style sheet: matte clay; 3/4 view (30° above,
35° left); key light top-left, soft fill right, gentle AO; 15 % contact shadow
(light render); palette teal #2BC4C4, deep teal #0A7C7C, slate #5B6B80, sand
#E8D5B5, graphite #3A3D42, white, rupee green #6BBF8A, star yellow #F5C542;
~8 % bevel, chunky; transparent; 512² master, subject ~80 %; PNG 1×/2×/3× at
48/64/96 pt, WebP for Android, source .blend. Icons (20): Economy hatch, Comfort
sedan, XL MPV, Premium sedan, neutral recolourable driver car, rupee note,
UPI phone, card, pin-plus, calendar-check, map pin, car-with-magnifier,
sleeping car, check badge, phone-with-message, shield-with-heart, wallet,
gift box, star, auto-rickshaw (optional). Budget ≈ ₹3,000–10,000 per icon
(+30 % for dark renders); test 3 icons first (Economy car, rupee note, check).

## Testing and decision

Test 1 desirability (week 3, 30+ per plan, product reaction cards); Test 2
tasks (week 4, 5–8 riders per plan, outdoors for half); Test 3 in-app A/B
(weeks 5–8, sticky 50/50 flag; primary metric booking conversion; guardrails:
time to confirm, early cancels, wrong-car reports, tickets, crashes; ~3,700
sessions per arm for a 3-point change). Decision rules: B wins → ship B; A wins
→ ship A (3D for marketing only); split → build C; night complaints about B →
C; any icon < 4/5 recognition → relabel or replace; any guardrail worse > 10 %
→ stop that arm.

---

## Build notes (this repo)

- Theme variants are build-time: `--dart-define=THEME=` **`midnight`** (Plan
  A), **`daylight`** (Plan B), **`daynight`** (Plan C: follows the phone, with
  the Light / Dark / Same-as-phone override in Account → Appearance, and the
  theme held steady during a ride). Existing `turquoise` / `mono` remain for
  comparison. Layout and copy are shared, as the plan requires.
- **3D clay icons need an illustrator** (the brief above). Until those exist,
  Plan B/C builds use vector stand-ins in the same palette and angle —
  clearly placeholders, not the final art.
- Photos of drivers need a storage decision before the driver card can show
  real photos (audit plan 2.6).
