# Icon audit — 2026-09-24 (audit item 2.1)

Owner's brief: icons are the differentiator. This pass checks every icon the
four Flutter apps render against the eight rules in
`docs/plans/ui-10-audit-plan.md` §2.1 and the utility/hero split in
`docs/plans/visual-direction-v2.md`, fixes the violations, and adds a sheet and
a test so the rules stay true.

**Sheet:** `docs/brand/research/icon-inventory.png` — every utility icon at its
real size and in its real container, grouped by screen, light panel left, dark
panel right. Red frame = breaks a rule (none left); amber frame = a documented
exception. Regenerate:

```
python3 docs/brand/research/icon_inventory.py > /tmp/inventory.md   # rescans code, rewrites the test data
cd packages/design_system
ICON_SHEET_OUT=$PWD/../../docs/brand/research/icon-inventory.png \
  flutter test test/icon_inventory_sheet_test.dart
```

Without `ICON_SHEET_OUT` the same test only checks the rules (it runs in CI
with the rest of the design_system suite and never writes to `docs/`).

## What was verified vs. assumed

- Verified: `flutter analyze` + `flutter test` pass in design_system, core,
  rider_app, driver_app, admin_app after these changes. The sheet was rendered
  and looked at (both panels); the fixes in "Fixed after looking at the sheet"
  came from that.
- Verified by test (`icon_inventory_sheet_test.dart`): every inventoried icon
  is 16/20/24, or 32/40/48 as a hero/medallion, or a named exception; Fill
  appears only on the seven state glyphs; every `AppIconBadge` tone clears
  3:1 (glyph on its fill over the surface) in light and dark; the badge is
  40 px with a 20 px glyph.
- Assumed / static: sizes in the inventory are resolved from source (explicit
  `size:`, the shared widget's fixed size, or the theme default). It is not a
  runtime capture of every screen. Not checked on a device or emulator
  (none used in this pass, per instructions). iOS not built here.

## The eight rules — where things stand

| # | Rule | Before | After |
|---|---|---|---|
| 1 | One library | Already Phosphor everywhere — **no Material `Icons.*` left** in `packages/*/lib` or `apps/*/lib` (grep). | Unchanged. |
| 2 | 24 / 20 / 16 px | 43 explicit off-scale sizes (28× 18, 7× 14, 2× 15, 17, 12, 28, 34, 36, 44) **plus** the theme's `IconThemeData(size: 22)` — every unsized icon in all apps rendered at 22 — plus off-scale sizes inside shared widgets (`AppCircleButton` 22, `AppStatusChip` 13, quick-action card 22, `_StatCard` 22, `_Fact` 22, pre-book rows 22, `RecenterPill` 17, `ConnectionBanner` 15) and Material's 18 px default for `Filled/Outlined/TextButton.icon` and chip avatars. | Theme icon size 24; button `iconSize: 20` on all three button themes; chip `iconTheme` 20; every explicit size moved to 16/20/24 (utility) or 32/48 (hero). Test-enforced. |
| 3 | Regular; Fill only for a state | Fill without a state: account menu **Saved places** (star) and **Favourite drivers** (heart), rider **Safety** pill (shield), saved-place chips in search (star), admin **Completed** stat (checkCircle), pre-book destination (a 24 px filled square that read as a black block). | All Regular. Fill remains only for: rating stars, a favourited driver, a selected option / done, verified seal, route-rail destination marker, online dot, a switch that is on. Test-enforced. |
| 4 | Colour by meaning | Decorative teal on ride-details label glyphs; list/menu rows on `textSecondary`/`textTertiary` greys; driver's later-stop flag on the **light-mode** tertiary grey in dark mode; receipt payment glyph on the light-mode grey in dark mode; sign-out red not tuned for dark. | Label/row glyphs on `AppColors.iconNeutralFor(dark)`; colour only for brand action, danger, success, warning, rating. Sign-out uses `dangerFor(dark)`. |
| 5 | ONE 40 px container | Eight different containers: 46 px circles (driver online/offline), 36 px circle (driver offer pickup), 40 px surface circle (rider quick actions), 40 px accentSoft / muted / surfaceContainerHighest circles (search), 40 px rounded **squares** (admin stats), `CircleAvatar` (scheduled rides, trip history, favourite drivers), 40 px circle with a **24** px glyph (driver priming reasons). | New `AppIconBadge` (design_system): 40 px circle, 20 px glyph, tone = meaning (`brand` accentSoft/accent, `danger`, `success`, `warning`, `neutral`). Used by all of the above plus the safety-sheet header. Favourite drivers now show `AppAvatar` (it is a person, not an icon). |
| 6 | Labels | Admin ticket-detail close button had no tooltip/label. | Tooltip "Close". Every other icon-only `IconButton` has a tooltip or a `Semantics` label (the error overlay's two buttons use `Semantics` on purpose — a Tooltip there needs an Overlay that is not there). Badges are `ExcludeSemantics` — the row text next to them carries the meaning. |
| 7 | 3:1 contrast | Empty states in `AsyncContent` drew a bare 48 px icon in `theme.disabledColor` (under 3:1). Admin offline dot in `disabledColor`. | Empty states use the shared `EmptyState` medallion; offline dot uses the neutral icon grey. Badge tones test-checked ≥ 3:1. **Open:** rating stars `#FFC043` are ~1.7:1 on white — see "Left open". |
| 8 | 44 pt targets | Checked: `AppCircleButton` 48, `IconButton` default 48, `StarRating` 48, text buttons `buttonHeightTertiary`, rider ride pills 48 hit area (drawn 40). No icon-only control under 44 found. | Unchanged. |

Hero tier (visual-direction-v2): the Plan B/C 3D art (`_HeroIcon` in
`live_ride_sheets.dart`, the `done` art on trip complete, the cash chip) is
untouched. The quick-action cards still show the 3D tile on a plain disc when
`_HeroIcon.enabled`; everywhere else they now fall back to `AppIconBadge`
instead of a 22 px glyph on a white disc.

Sizing convention used for the moves (so the next person picks the same step):
**24** = standalone glyphs, list/menu leading icons, app-bar and map buttons;
**20** = inline with body text, inside buttons/chips, inside `AppIconBadge`,
banners; **16** = inline with small/caption text (chips on the live-ride sheet,
rating stars, status chips, pills). Heroes: **32** in a 64/72 medallion,
**40/48** standalone (error states, map pin, scheduled-ride confirmation).

## Changes, file by file

design_system
- `lib/src/widgets/app_icon_badge.dart` (new) — `AppIconBadge`, `AppIconBadge.danger`, `AppIconBadgeTone`, `colorsFor()`; exported from `design_system.dart`.
- `lib/src/theme/app_theme.dart` — `iconTheme.size` 22→24; `iconSize: 20` on Filled/Outlined/Text button themes; chip `iconTheme` size 20.
- `app_circle_button.dart` 22→24 · `app_status_chip.dart` 13→16 · `recenter_pill.dart` 17→20 · `connection_banner.dart` 15→16.

core
- `account/account_menu_page.dart` — Saved places / Favourite drivers Fill→Regular; row icons, chevron, pencil → `iconNeutralFor`; sign-out → `dangerFor(dark)`.
- `account/delete_account_page.dart` — hero 56/28 → 64/32; fact glyphs 22→24, neutral token.
- `account/trip_history_page.dart` — `CircleAvatar` → `AppIconBadge` with status tone (success / danger / warning).
- `account/scheduled_rides_page.dart` — `CircleAvatar` → `AppIconBadge`.
- `account/favorite_drivers_page.dart` — icon `CircleAvatar` → `AppAvatar` (name initials).
- `account/receipt_page.dart` — payment glyph on neutral token (was light-mode grey in dark); route points 16→20.
- `account/widgets/async_content.dart` — empty state uses shared `EmptyState` (was bare 48 px disabled-grey icon).
- `safety/safety_sheet.dart` — header shield → `AppIconBadge.danger`; notice glyphs 24→20 (inline with body text).
- `debug/error_overlay.dart` — 18→20.

rider_app
- `sheets/live_ride_sheets.dart` — quick-action cards use `AppIconBadge` (3D hero kept for Plan B/C); pickup dot 18→20; chips 14→16; driver rating star 14→16; ETA clock, stop flags 18→20; "on my way" confirmation 24→20.
- `sheets/sheet_shell.dart` — Safety pill Fill shield → Regular.
- `sheets/ride_details_sheet.dart` — detail glyphs 18 teal → 20 neutral; star 15→16.
- `sheets/ride_options_sheet.dart` — thirteen 18/16/14 sizes → 20/16.
- `sheets/where_to_sheet.dart` — saved-place circles → `AppIconBadge` neutral; "Later" pill 18→16.
- `sheets/completed_sheet.dart` — favourite heart 18→20; done medallion glyph 36→32.
- `sheets/pre_book_page.dart` — row glyphs 22→24; destination Fill square → Regular mapPin.
- `destination_search_page.dart` — "Set location on the map" and result rows → `AppIconBadge`; saved-place chip Fill star → Regular mapPin (same as Saved places / Where-to); route rail 14/12→16; error + arrow 18→20.
- `map_picker_page.dart` — centre pin 44→48 (offset −20→−22 so the tip stays on centre).
- `location_banner.dart` 18→20.

driver_app
- `home_page.dart` — online/offline 46 px circles → `AppIconBadge` (brand / neutral); offer pickup 36 px circle → `AppIconBadge`; trip-complete medallion 60/34 → 64/32; banners 18/24 → 20; later-stop flag on neutral token (was light-mode grey in dark); rider star 14→16; distance arrow 16→20.
- `features/driver/location_priming_page.dart` — reasons use `AppIconBadge` (were 24 px glyphs in the 40 px circle).

admin_app
- `home_page.dart` — stat cards' 40 px rounded squares → `AppIconBadge` with tones; Completed stat Fill → Regular check (success tone); 18→20 ×3; active-controls banner 24→20; offline dot colour; close button tooltip.

Tests / tooling
- `packages/core/test/account/account_menu_page_test.dart` — chevron now expects `AppColors.iconNeutralDark` (was `textTertiaryDark`, an intended change); rider page asserts Regular star/heart in the menu and the one Fill star on the rating line.
- `packages/design_system/test/icon_inventory_sheet_test.dart` (new) + `icon_inventory_data.dart` (generated) — rules 2/3/5/7 as tests; sheet render.
- `docs/brand/research/icon_inventory.py` (new) — the scanner.

## Fixed after looking at the sheet

- Pre-book destination was a 24 px **filled** square beside Regular 24 px
  glyphs — a heavy black block. Now Regular mapPin (matches ride details and
  the receipt).
- Search saved-place chips showed a Fill star for "other" places while the
  Saved places page and Where-to rows show a mapPin. Unified on mapPin.
- The generator mis-read the appearance sheet's (mode, label, icon) records as
  empty-state medallions; fixed in the scanner (they are 24 px row icons).

## Exceptions (amber on the sheet)

- Admin driver-list online dot: `PhosphorIconsFill.circle` at 12 px — a status
  dot, not an icon.
- `AppAvatar` fallback glyph: half the avatar size by design.
- `StarRating` (rating input): its own `size`, default 40 (hero tier), 48 px target.
- Rating stars `#FFC043` are ~1.7:1 on white (rule 7 says 3:1). They always sit
  beside the numeric rating, so the number carries the meaning; flagged amber,
  not fixed (see below).
- The live-ride driver photo's car-colour disc (28 px, 16 px car) is an
  avatar overlay showing the car's paint colour, not an icon container.

## Left open

1. **Star colour vs 3:1** — a light-mode star that passes 3:1 on white needs to
   be about `#B7791F` (3.6:1), which reads brown rather than gold. Owner call:
   keep gold as decoration next to the number, or darken in light mode only.
2. **Driver safety button** stays a red shield `IconButton` in the trip header,
   while the rider has a neutral labelled "Safety" pill. Different decisions
   per app; not changed here — worth one decision.
3. Banners that tint a whole row (warning/success/error notices, pickup note,
   passenger, promo applied) keep a bare 20 px glyph on the row tint rather
   than a badge — a badge on a tinted row would double-tint. That is a
   judgement call, stated here so it can be overruled.
4. Inventory sizes are static. A runtime pass over each screen (widget tests
   that walk `Icon` widgets per screen) would catch sizes coming from
   `IconTheme` overrides that a source scan cannot see.
5. `phosphor_icons.dart` and the fonts were not touched (another agent owns
   them). No glyph was added; `PhosphorIconsRegular.checkCircle` does not exist
   in the subset, which is why the admin Completed stat uses `check`.

## Before — every row the scanner fails at HEAD 0823481

Explicit sizes only: the theme-default 22 px and the off-scale sizes inside shared widgets (listed under rule 2 above) are not rows here, because the scanner resolves shared-widget sizes to their current values. Fill misuse that the scanner can see from source is included; the account-menu Fill star/heart were passed through `_Item` and are listed under rule 3.

| file:line | icon | size | colour role | container | weight | 1 lib | 2 size | 3 fill | 5 container | note |
|---|---|---|---|---|---|---|---|---|---|---|
| apps/admin_app/lib/home_page.dart:1552 | warningCircle | 18 | danger | plain | Regular | ok | **NO (18)** | ok | ok |  |
| apps/admin_app/lib/home_page.dart:1588 | chartLineUp | 18 | default | plain | Regular | ok | **NO (18)** | ok | ok |  |
| apps/admin_app/lib/home_page.dart:2077 | mapTrifold | 18 | default | plain | Regular | ok | **NO (18)** | ok | ok |  |
| apps/driver_app/lib/home_page.dart:1004 | check | 34 | brand | plain | Regular | ok | **NO (34)** | ok | ok |  |
| apps/driver_app/lib/home_page.dart:1204 | flag | 18 | warning | plain | Regular | ok | **NO (18)** | ok | ok |  |
| apps/driver_app/lib/home_page.dart:1314 | userCircle | 18 | brand | plain | Regular | ok | **NO (18)** | ok | ok |  |
| apps/driver_app/lib/home_page.dart:1369 | note | 18 | brand | plain | Regular | ok | **NO (18)** | ok | ok |  |
| apps/driver_app/lib/home_page.dart:1705 | star | 14 | star | plain | Fill | ok | **NO (14)** | ok | ok |  |
| apps/driver_app/lib/home_page.dart:1731 | record | 18 | brand | plain | Regular | ok | **NO (18)** | ok | ok |  |
| apps/rider_app/lib/features/trip/destination_search_page.dart:318 | warningCircle | 18 | danger | plain | Regular | ok | **NO (18)** | ok | ok |  |
| apps/rider_app/lib/features/trip/destination_search_page.dart:459 | arrowUpRight | 18 | neutral | plain | Regular | ok | **NO (18)** | ok | ok |  |
| apps/rider_app/lib/features/trip/destination_search_page.dart:534 | record | 14 | brand | plain | Regular | ok | **NO (14)** | ok | ok |  |
| apps/rider_app/lib/features/trip/destination_search_page.dart:542 | square | 12 | brand | plain | Fill | ok | **NO (12)** | ok | ok |  |
| apps/rider_app/lib/features/trip/location_banner.dart:101 | gpsSlash | 18 | on-dark | plain | Regular | ok | **NO (18)** | ok | ok |  |
| apps/rider_app/lib/features/trip/location_banner.dart:114 | caretRight | 18 | on-dark | plain | Regular | ok | **NO (18)** | ok | ok |  |
| apps/rider_app/lib/features/trip/map_picker_page.dart:276 | mapPin | 44 | brand | plain | Regular | ok | **NO (44)** | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/completed_sheet.dart:47 | heart | 18 | danger | plain | Fill | ok | **NO (18)** | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/completed_sheet.dart:47 | heart | 18 | danger | plain | Regular | ok | **NO (18)** | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/completed_sheet.dart:130 | check | 36 | brand | medallion | Regular | ok | **NO (36)** | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:489 | record | 18 | brand | plain | Regular | ok | **NO (18)** | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:508 | car | 14 | default | plain | Regular | ok | **NO (14)** | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:515 | money | 14 | default | plain | Regular | ok | **NO (14)** | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:518 | creditCard | 14 | default | plain | Regular | ok | **NO (14)** | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:674 | star | 14 | star | plain | Fill | ok | **NO (14)** | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:845 | clock | 18 | brand | plain | Regular | ok | **NO (18)** | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:890 | flag | 18 | warning | plain | Regular | ok | **NO (18)** | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_details_sheet.dart:136 | star | 15 | star | plain | Fill | ok | **NO (15)** | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:136 | userPlus | 18 | default | plain | Regular | ok | **NO (18)** | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:148 | userCircle | 18 | brand | plain | Regular | ok | **NO (18)** | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:171 | x | 18 | default | plain | Regular | ok | **NO (18)** | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:346 | mapPinPlus | 18 | default | plain | Regular | ok | **NO (18)** | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:501 | clock | 18 | default | plain | Regular | ok | **NO (18)** | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:511 | x | 18 | default | plain | Regular | ok | **NO (18)** | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:739 | checkCircle | 18 | brand | plain | Fill | ok | **NO (18)** | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:821 | tag | 18 | success | plain | Regular | ok | **NO (18)** | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:832 | x | 18 | default | plain | Regular | ok | **NO (18)** | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:954 | user | 14 | default | plain | Regular | ok | **NO (14)** | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/sheet_shell.dart:190 | shieldCheck | 16 | default | plain | Fill | ok | ok | **NO** | ok |  |
| apps/rider_app/lib/features/trip/sheets/where_to_sheet.dart:144 | clock | 18 | default | plain | Regular | ok | **NO (18)** | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/where_to_sheet.dart:148 | caretDown | 18 | default | plain | Regular | ok | **NO (18)** | ok | ok |  |
| packages/core/lib/src/account/delete_account_page.dart:101 | userMinus | 28 | danger | plain | Regular | ok | **NO (28)** | ok | ok |  |
| packages/core/lib/src/debug/error_overlay.dart:136 | warningCircle | 18 | on-dark | plain | Regular | ok | **NO (18)** | ok | ok |  |
| packages/design_system/lib/src/widgets/connection_banner.dart:91 | check | 15 | on-dark | plain | Regular | ok | **NO (15)** | ok | ok |  |
| packages/design_system/lib/src/widgets/recenter_pill.dart:67 | gpsFix | 17 | brand | plain | Regular | ok | **NO (17)** | ok | ok |  |

## After — full inventory (every Phosphor reference, 281)

Colour roles: `default` = on-surface ink via the theme; `neutral` = iconNeutral / secondary greys; `brand` = accent ink; `on-dark` = white on a dark chip/banner. Containers: `badge` = AppIconBadge; `medallion` = hero disc (EmptyState 72, completion 64); `map button` = AppCircleButton. Rule columns: 1 library, 2 size scale, 3 Fill only for a state, 5 one container. Rules 4 (colour by meaning), 6 (labels), 7 (3:1) and 8 (44 pt) are covered per screen above and in the sheet test — they cannot be read off a single source reference.

| file:line | icon | size | colour role | container | weight | 1 lib | 2 size | 3 fill | 5 container | note |
|---|---|---|---|---|---|---|---|---|---|---|
| apps/admin_app/lib/home_page.dart:52 | taxi | 24 | brand | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:69 | heartbeat | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:75 | signOut | 24 | danger | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:87 | squaresFour | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:88 | squaresFour | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:95 | shieldCheck | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:100 | shieldCheck | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:105 | path | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:106 | path | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:110 | users | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:111 | users | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:115 | car | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:116 | car | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:120 | mapTrifold | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:121 | mapTrifold | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:125 | headset | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:126 | headset | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:130 | tag | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:131 | tag | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:135 | cards | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:136 | cards | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:140 | money | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:141 | money | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:145 | arrowsLeftRight | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:146 | arrowsLeftRight | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:150 | toggleLeft | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:151 | toggleRight | 24 | default | plain | Fill | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:240 | arrowClockwise | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:360 | caretRight | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:471 | x | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:755 | users | 20 | brand | badge | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:759 | car | 20 | brand | badge | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:763 | broadcast | 20 | success | badge | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:768 | path | 20 | warning | badge | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:773 | check | 20 | success | badge | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:778 | money | 20 | brand | badge | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:782 | bank | 20 | brand | badge | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:947 | coins | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:974 | magnifyingGlass | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:1104 | circle | 12 | success | plain | Fill | ok | exc. | ok | ok | status dot, 12 px by design |
| apps/admin_app/lib/home_page.dart:1198 | plus | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:1550 | warningCircle | 20 | danger | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:1586 | chartLineUp | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:1797 | warning | 20 | warning | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:1833 | toggleRight | 24 | warning | plain | Fill | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:1833 | toggleLeft | 24 | warning | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:1894 | siren | 24 | on-dark | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:1908 | caretRight | 24 | on-dark | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:1927 | shieldCheck | 32 | brand | medallion | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:2076 | mapTrifold | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:2139 | plus | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:2147 | cards | 32 | brand | medallion | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:2191 | pencilSimple | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/admin_app/lib/home_page.dart:2196 | trash | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/driver_app/lib/features/account/driver_profile_stats.dart:80 | star | 16 | star | plain | Fill | ok | ok | ok | ok |  |
| apps/driver_app/lib/features/driver/location_priming_page.dart:135 | broadcast | 20 | brand | badge | Regular | ok | ok | ok | ok |  |
| apps/driver_app/lib/features/driver/location_priming_page.dart:141 | path | 20 | brand | badge | Regular | ok | ok | ok | ok |  |
| apps/driver_app/lib/features/driver/location_priming_page.dart:147 | navigationArrow | 20 | brand | badge | Regular | ok | ok | ok | ok |  |
| apps/driver_app/lib/features/driver/location_priming_page.dart:155 | shieldCheck | 20 | brand | badge | Regular | ok | ok | ok | ok |  |
| apps/driver_app/lib/features/driver/location_priming_page.dart:303 | gpsSlash | 20 | danger | plain | Regular | ok | ok | ok | ok |  |
| apps/driver_app/lib/home_page.dart:597 | list | 24 | default | map button | Regular | ok | ok | ok | ok |  |
| apps/driver_app/lib/home_page.dart:756 | broadcast | 20 | brand | badge | Regular | ok | ok | ok | ok |  |
| apps/driver_app/lib/home_page.dart:879 | moonStars | 20 | neutral | badge | Regular | ok | ok | ok | ok |  |
| apps/driver_app/lib/home_page.dart:945 | personSimpleWalk | 20 | brand | plain | Regular | ok | ok | ok | ok |  |
| apps/driver_app/lib/home_page.dart:984 | check | 32 | brand | medallion | Regular | ok | ok | ok | ok |  |
| apps/driver_app/lib/home_page.dart:1015 | money | 20 | warning | plain | Regular | ok | ok | ok | ok |  |
| apps/driver_app/lib/home_page.dart:1123 | shieldCheck | 24 | danger | plain | Regular | ok | ok | ok | ok |  |
| apps/driver_app/lib/home_page.dart:1141 | navigationArrow | 20 | brand | plain | Regular | ok | ok | ok | ok |  |
| apps/driver_app/lib/home_page.dart:1158 | mapPinPlus | 20 | warning | plain | Regular | ok | ok | ok | ok |  |
| apps/driver_app/lib/home_page.dart:1185 | flag | 20 | warning | plain | Regular | ok | ok | ok | ok |  |
| apps/driver_app/lib/home_page.dart:1224 | navigationArrow | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/driver_app/lib/home_page.dart:1298 | userCircle | 20 | brand | plain | Regular | ok | ok | ok | ok |  |
| apps/driver_app/lib/home_page.dart:1318 | phone | 24 | brand | plain | Regular | ok | ok | ok | ok |  |
| apps/driver_app/lib/home_page.dart:1353 | note | 20 | brand | plain | Regular | ok | ok | ok | ok |  |
| apps/driver_app/lib/home_page.dart:1472 | shieldCheck | 24 | danger | plain | Regular | ok | ok | ok | ok |  |
| apps/driver_app/lib/home_page.dart:1499 | warningCircle | 16 | danger | plain | Regular | ok | ok | ok | ok |  |
| apps/driver_app/lib/home_page.dart:1679 | user | 16 | neutral | plain | Regular | ok | ok | ok | ok |  |
| apps/driver_app/lib/home_page.dart:1689 | star | 16 | star | plain | Fill | ok | ok | ok | ok |  |
| apps/driver_app/lib/home_page.dart:1708 | record | 20 | brand | badge | Regular | ok | ok | ok | ok |  |
| apps/driver_app/lib/home_page.dart:1988 | chatCircle | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/destination_search_page.dart:241 | house | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/destination_search_page.dart:242 | briefcase | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/destination_search_page.dart:245 | mapPin | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/destination_search_page.dart:320 | warningCircle | 20 | danger | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/destination_search_page.dart:340 | mapTrifold | 20 | brand | badge | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/destination_search_page.dart:346 | caretRight | 24 | neutral | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/destination_search_page.dart:380 | compass | 32 | brand | medallion | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/destination_search_page.dart:411 | mapPin | 20 | neutral | badge | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/destination_search_page.dart:443 | arrowUpRight | 20 | neutral | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/destination_search_page.dart:518 | record | 16 | brand | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/destination_search_page.dart:526 | square | 16 | brand | plain | Fill | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/location_banner.dart:101 | gpsSlash | 20 | on-dark | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/location_banner.dart:114 | caretRight | 20 | on-dark | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/map_picker_page.dart:173 | hourglass | 24 | default | map button | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/map_picker_page.dart:174 | gpsFix | 24 | default | map button | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/map_picker_page.dart:205 | mapPin | 20 | brand | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/map_picker_page.dart:278 | mapPin | 48 | brand | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/completed_sheet.dart:47 | heart | 20 | danger | plain | Fill | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/completed_sheet.dart:47 | heart | 20 | danger | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/completed_sheet.dart:130 | check | 32 | brand | medallion | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/completed_sheet.dart:165 | money | 16 | warning | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/completed_sheet.dart:367 | caretUp | 20 | brand | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/completed_sheet.dart:368 | caretDown | 20 | brand | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/completed_sheet.dart:507 | check | 16 | brand | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:63 | taxi | 20 | brand | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:246 | caretRight | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:370 | chatCircle | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:381 | phone | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:489 | record | 20 | brand | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:508 | car | 16 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:515 | money | 16 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:518 | creditCard | 16 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:617 | car | 16 | neutral | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:674 | star | 16 | star | plain | Fill | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:736 | checkCircle | 20 | success | plain | Fill | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:751 | personSimpleWalk | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:768 | dotsThree | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:786 | export | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:793 | headset | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:801 | x | 24 | danger | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:846 | clock | 20 | brand | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:891 | flag | 20 | warning | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:950 | mapPinPlus | 20 | brand | badge | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:959 | calendarCheck | 20 | brand | badge | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:1028 | caretRight | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:1208 | flag | 24 | warning | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart:1367 | tag | 24 | brand | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/pre_book_page.dart:181 | record | 24 | brand | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/pre_book_page.dart:191 | mapPin | 24 | brand | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/pre_book_page.dart:200 | calendarBlank | 24 | brand | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/pre_book_page.dart:320 | caretRight | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_details_sheet.dart:136 | star | 16 | star | plain | Fill | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_details_sheet.dart:150 | car | 20 | neutral | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_details_sheet.dart:157 | ticket | 20 | neutral | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_details_sheet.dart:177 | record | 20 | neutral | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_details_sheet.dart:184 | mapPin | 20 | neutral | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_details_sheet.dart:190 | ruler | 20 | neutral | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_details_sheet.dart:196 | clock | 20 | neutral | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_details_sheet.dart:202 | money | 20 | neutral | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_details_sheet.dart:203 | creditCard | 20 | neutral | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_details_sheet.dart:211 | trendUp | 20 | neutral | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_details_sheet.dart:217 | tag | 20 | neutral | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_details_sheet.dart:293 | receipt | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:53 | info | 16 | warning | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:136 | userPlus | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:148 | userCircle | 20 | brand | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:171 | x | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:324 | record | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:337 | x | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:346 | mapPinPlus | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:501 | clock | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:511 | x | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:540 | calendarCheck | 48 | brand | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:604 | creditCard | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:607 | caretDown | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:622 | money | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:670 | creditCard | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:673 | check | 24 | brand | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:739 | checkCircle | 20 | brand | plain | Fill | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:821 | tag | 20 | success | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:832 | x | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:852 | tag | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:954 | user | 16 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:997 | info | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/ride_options_sheet.dart:1104 | note | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/sheet_shell.dart:121 | info | 16 | warning | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/sheet_shell.dart:191 | shieldCheck | 16 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/sheet_shell.dart:199 | export | 16 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/sheet_shell.dart:353 | chatCircle | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/where_to_sheet.dart:27 | house | 20 | neutral | badge | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/where_to_sheet.dart:28 | briefcase | 20 | neutral | badge | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/where_to_sheet.dart:29 | mapPin | 20 | neutral | badge | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/where_to_sheet.dart:62 | magnifyingGlass | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/where_to_sheet.dart:144 | clock | 16 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/where_to_sheet.dart:148 | caretDown | 16 | default | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/features/trip/sheets/where_to_sheet.dart:202 | gpsSlash | 24 | warning | plain | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/home_page.dart:731 | list | 24 | default | map button | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/home_page.dart:754 | gpsFix | 24 | default | map button | Regular | ok | ok | ok | ok |  |
| apps/rider_app/lib/home_page.dart:755 | gpsFix | 24 | default | map button | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/account_menu_page.dart:189 | bell | 24 | neutral | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/account_menu_page.dart:194 | receipt | 24 | neutral | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/account_menu_page.dart:209 | wallet | 24 | neutral | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/account_menu_page.dart:216 | money | 24 | neutral | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/account_menu_page.dart:224 | car | 24 | neutral | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/account_menu_page.dart:232 | clock | 24 | neutral | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/account_menu_page.dart:241 | star | 24 | neutral | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/account_menu_page.dart:251 | creditCard | 24 | neutral | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/account_menu_page.dart:265 | heart | 24 | neutral | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/account_menu_page.dart:277 | addressBook | 24 | neutral | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/account_menu_page.dart:284 | circleHalf | 24 | neutral | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/account_menu_page.dart:289 | headset | 24 | neutral | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/account_menu_page.dart:302 | signOut | 24 | danger | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/account_menu_page.dart:385 | caretRight | 20 | neutral | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/account_menu_page.dart:447 | star | 16 | star | plain | Fill | ok | ok | ok | ok |  |
| packages/core/lib/src/account/account_menu_page.dart:463 | pencilSimple | 20 | neutral | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/delete_account_page.dart:102 | userMinus | 32 | danger | medallion | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/delete_account_page.dart:123 | trash | 24 | neutral | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/delete_account_page.dart:130 | calendarX | 24 | neutral | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/delete_account_page.dart:135 | receipt | 24 | neutral | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/delete_account_page.dart:141 | deviceMobile | 24 | neutral | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/delete_account_page.dart:149 | wallet | 24 | neutral | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/delete_account_page.dart:305 | info | 20 | danger | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/driver_payouts_page.dart:231 | sealCheck | 20 | success | plain | Fill | ok | ok | ok | ok |  |
| packages/core/lib/src/account/driver_payouts_page.dart:253 | bank | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/driver_payouts_page.dart:317 | car | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/driver_payouts_page.dart:319 | handHeart | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/driver_payouts_page.dart:321 | bank | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/driver_payouts_page.dart:323 | percent | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/driver_payouts_page.dart:325 | receipt | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/favorite_drivers_page.dart:44 | heart | 32 | brand | medallion | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/favorite_drivers_page.dart:64 | heart | 24 | danger | plain | Fill | ok | ok | ok | ok |  |
| packages/core/lib/src/account/inbox_page.dart:52 | checks | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/inbox_page.dart:62 | bell | 32 | brand | medallion | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/inbox_page.dart:74 | bell | 24 | brand | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/inbox_page.dart:74 | bellRinging | 24 | brand | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/payment_methods_page.dart:139 | plus | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/payment_methods_page.dart:146 | creditCard | 32 | brand | medallion | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/payment_methods_page.dart:154 | creditCard | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/profile_edit_page.dart:71 | user | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/profile_edit_page.dart:87 | envelopeSimple | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/profile_edit_page.dart:124 | phone | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/receipt_page.dart:75 | money | 16 | neutral | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/receipt_page.dart:75 | creditCard | 16 | neutral | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/receipt_page.dart:189 | record | 20 | brand | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/receipt_page.dart:191 | mapPin | 20 | brand | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/saved_places_page.dart:109 | plus | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/saved_places_page.dart:116 | star | 32 | brand | medallion | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/saved_places_page.dart:129 | trash | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/saved_places_page.dart:142 | house | 24 | neutral | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/saved_places_page.dart:143 | briefcase | 24 | neutral | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/saved_places_page.dart:144 | mapPin | 24 | neutral | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/saved_places_page.dart:284 | magnifyingGlass | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/saved_places_page.dart:307 | mapPin | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/scheduled_rides_page.dart:79 | calendarCheck | 32 | brand | medallion | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/scheduled_rides_page.dart:89 | clock | 20 | brand | badge | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/support_page.dart:67 | plus | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/support_page.dart:74 | headset | 32 | brand | medallion | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/support_thread_page.dart:149 | warningCircle | 40 | danger | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/support_thread_page.dart:160 | arrowClockwise | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/support_thread_page.dart:209 | paperPlaneRight | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/trip_history_page.dart:32 | receipt | 32 | brand | medallion | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/trip_history_page.dart:129 | check | 20 | brand | badge | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/trip_history_page.dart:133 | x | 20 | brand | badge | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/trip_history_page.dart:135 | car | 20 | brand | badge | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/widgets/async_content.dart:15 | tray | 32 | brand | medallion | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/widgets/async_content.dart:118 | warningCircle | 40 | danger | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/account/widgets/async_content.dart:124 | arrowClockwise | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/auth/presentation/otp_page.dart:182 | wrench | 16 | warning | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/chat/chat_page.dart:245 | paperPlaneRight | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/debug/error_overlay.dart:136 | warningCircle | 20 | on-dark | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/debug/error_overlay.dart:170 | copy | 24 | on-dark | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/debug/error_overlay.dart:179 | x | 24 | on-dark | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/safety/emergency_contacts_page.dart:92 | userPlus | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/safety/emergency_contacts_page.dart:108 | cloudSlash | 32 | brand | medallion | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/safety/emergency_contacts_page.dart:122 | addressBook | 32 | brand | medallion | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/safety/emergency_contacts_page.dart:128 | userPlus | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/safety/emergency_contacts_page.dart:147 | trash | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/safety/safety_sheet.dart:218 | shieldCheck | 20 | danger | badge | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/safety/safety_sheet.dart:257 | siren | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/safety/safety_sheet.dart:273 | warningCircle | 20 | danger | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/safety/safety_sheet.dart:281 | export | 20 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/safety/safety_sheet.dart:382 | checkCircle | 20 | success | plain | Fill | ok | ok | ok | ok |  |
| packages/core/lib/src/safety/safety_sheet.dart:392 | userPlus | 20 | warning | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/safety/safety_sheet.dart:400 | chatText | 20 | success | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/safety/safety_sheet.dart:409 | chatCircleSlash | 20 | warning | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/theme/appearance_sheet.dart:38 | circleHalf | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/theme/appearance_sheet.dart:41 | sun | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/core/lib/src/theme/appearance_sheet.dart:44 | moon | 24 | default | plain | Regular | ok | ok | ok | ok |  |
| packages/design_system/lib/src/widgets/app_avatar.dart:55 | user | size * 0.5 | brand | plain | Regular | ok | exc. | ok | ok | avatar fallback: half the avatar size |
| packages/design_system/lib/src/widgets/connection_banner.dart:91 | check | 16 | on-dark | plain | Regular | ok | ok | ok | ok |  |
| packages/design_system/lib/src/widgets/map_placeholder.dart:32 | mapTrifold | 48 | brand | plain | Regular | ok | ok | ok | ok |  |
| packages/design_system/lib/src/widgets/recenter_pill.dart:67 | gpsFix | 20 | brand | plain | Regular | ok | ok | ok | ok |  |
| packages/design_system/lib/src/widgets/star_rating.dart:34 | star | size | neutral | plain | Fill | ok | exc. | ok | ok | rating input: StarRating(size:), default 40 |
| packages/design_system/lib/src/widgets/star_rating.dart:34 | star | size | neutral | plain | Regular | ok | exc. | ok | ok | rating input: StarRating(size:), default 40 |
