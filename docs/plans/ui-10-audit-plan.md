# FAIRSVIA UI — path to 10/10 (plan, 2026-09-24)

Built from the owner's audit "RideVela UI & Icon Audit — Path to 10/10"
(Sep 24, 2026). Every claim was checked against the code before planning;
the **Code check** column says what was found. Shared Flutter code, so every
item lands on Android and iOS together (iOS verified on the Mac).

Scores are the audit's; "done" means built, tested and seen on a device.

---

## Decisions on the audit (where the plan differs)

| Audit says | Decision | Why |
|---|---|---|
| Phosphor Icons as the single library | **Adopt** (`phosphor_flutter`, MIT) | One family, six weights; Regular by default, Fill only for state |
| bg.base `#0E0F11` instead of pure black | **Adopt** | Matches Material dark guidance; our account/login screens are `#000000` today |
| Brand teal `#2BC4C4` | **Keep ours** `#2EC4C6` (dark) / `#0B3C49` (light) | Near-identical; ours is already shipped and tested for contrast |
| Radius 12 for cards/buttons, 20 for sheets | **Adopt** | Currently 8 / 16 |
| Logomark: keep the navigation arrow | **Owner decides** between the refined arrow and Road-V (logo page) | Both drawn; arrow already appears on login |
| Car art: one 3/4 view, same colour, shape carries the tier | **Adopt** | Current side views use colour per tier — Economy teal reads as "selected", Premium black disappears in dark mode |
| Round fares to whole rupees | **Adopt** for display; server keeps paise | Fares are estimates; the charged amount is exact on the receipt |
| Fonts: Inter + Inter Display/Satoshi, Noto Sans Devanagari | **Inter + Inter Display**; Devanagari with Hindi/Marathi strings (phase 4) | Inter already bundled |

---

## Phase 1 — fix what looks broken (target 7.5) — ✅ done 2026-09-24 (seen on the emulator)

| # | Item | Code check | Fix |
|---|---|---|---|
| 1.1 | Map zooms to a world view on live-trip screens | Partly fixed: null-island guard (Mac, 4e43bb0) + whole-route framing and post-layout re-fit (4909fb8). **Not re-verified on all 3 screens** | Re-verify driver-on-the-way / arrived / completed on device; completed screen gets a static route thumbnail instead of a live map |
| 1.2 | Placeholder driver ("Driver", letter avatar, FL plate) | **Confirmed**: onboarding accepts any plate; name optional; simulator onboards FL plates with no name | Require full name + photo before going online; Indian plate validation (`MH 12 AB 1234`) for MARKET=in, stored normalised, shown with spaces; simulator uses Indian names/plates |
| 1.3 | Driver map defaults to Miami | **Confirmed**: `_fallback` = Miami unless `FALLBACK_LOCATION` is passed | Fallback = last known position, else the market's city centre (Pune 18.52, 73.86; Tashkent) from `Market` |
| 1.4 | Hard line break "text you a / code" | **Confirmed** (`phone_entry_page.dart:96`) | Remove `\n`, let text wrap |
| 1.5 | Blue location dot overlaps pickup | **Confirmed** (seen in ride options) | Hide the dot within 30 m of pickup |
| 1.6 | Rating chips mixed alignment | To verify on completed screen | One left-aligned Wrap, 8 px gap |
| 1.7 | "No cars nearby" tiers selectable | **Confirmed**: row always tappable | 40 % opacity, disabled, never pre-selected; "No cars nearby" text stays |

## Phase 2 — trust and identity (target 8.5)

| # | Item | Fix |
|---|---|---|
| 2.1 | Icon system | `phosphor_flutter`; the 8 rules (one library, 24/20/16 px, Regular + Fill for state, colour by meaning, one 40 px container style, labels, 3:1 contrast, 44 pt targets); replace every icon per the audit's table |
| 2.2 ✅ | Driver card = verification | Plate as the hero (22 pt, 700, tabular, spaced); 56 px driver photo over a 3/4 car render tinted to the real car colour; "White Toyota Camry" under the plate; **Call** + **Message** side by side (the car button goes) |
| 2.3 ✅ | Titles with name + ETA | "Rahul arriving in 3 min" / "Rahul has arrived"; sentence case, never ALL CAPS |
| 2.4 ✅ | PIN as four boxes | 48×56 pt boxes, title size, surface.2, read digit by digit by screen readers |
| 2.5 ✅ | Safety pill | "Safety" pill with ShieldCheck (white at rest; red only during an active SOS); **Share trip** next to it in-trip |
| — | *Done 2026-09-24 (v1.4.2/5010, seen on emulator):* plate is the card's biggest line, car colour as a badge on the avatar, name + rating under it; "Sneha arriving in 9 min" / "Meet at your pickup spot"; PIN in four boxes; labelled Safety pill (neutral) on every live sheet, Safety + Share pills in-trip, Safety removed from the ••• menu. **Found and fixed on the way:** the SOS sheet showed Uzbek numbers (Police 102 / Ambulance 103) in the India build — now per market: 112 / Police 100 / Ambulance 108; server via `EMERGENCY_NUMBERS`. Still open from 2.2: a real driver photo (2.6) and the 3/4 car render (2.7). | |
| 2.6 | Driver photos | Photo upload at onboarding (storage decision needed — see plan §1 "document upload"); letter avatar only as fallback |
| 2.7 ◐ | Realistic ride-type cars | Redraw the four as one 3/4-view set, silver/white body, same lighting; shape carries the tier |

## Phase 3 — system polish (target 9.2)

| # | Item | Fix |
|---|---|---|
| 3.1 | Tokens | bg.base `#0E0F11`, surface.1 `#17181B`, surface.2 `#1F2024`, border `#2A2B30`, text.secondary `#A0A3A8`, icon.neutral `#9A9DA3`, danger `#FF4D4F`, warning `#F5A623`; light-mode equivalents; no raw hex in widgets |
| 3.2 | Type scale | display 28/34/700, title 22/28/600, body.strong 17/24/600, body 15/22/400, caption 13/18/400, plate 22/28/700 tabular +4 % |
| 3.3 | Spacing / radius / elevation | 4 pt grid; 16 pt side margin; radius 12 / 20 / pill / 8 (PIN); tonal elevation + one sheet shadow; buttons 56 / 56 / 44 |
| 3.4 | Brand lockup | Chosen logomark + "FAIRSVIA" wordmark on splash (bar animates as loader, ≤ 1.5 s), login (64 px mark top-left, no banner), app icon, favicon, notification icon; "Driver" pill in the driver app |
| 3.5 ✅ | Login | "IN +91" prefix chip; hint `98765 43210`; tappable Terms / Privacy links; OTP autofill (`AutofillHints.oneTimeCode` + SMS Retriever) |
| 3.6 ✅ | Driver location priming | FAIRSVIA screen before the OS dialog; denied → banner with "Open Settings" |
| 3.7 ✅ | Choose ride | Whole-rupee fares; "Pickup in 2 min · Drop 11:41 PM"; info icon per row instead of "Details" links; payment row above Confirm |
| 3.8 ✅ | Finding driver | Radar at pickup on the map (3 rings, 1.6 s); "Economy · ₹102 · Cash" in the sheet; after 45 s "Still looking…" + other tier |
| 3.9 ✅ | Place names | Landmark/road name first, plus code only as a caption (pickup, map picker) — server reverse-geocode label |
| 3.10 ✅ | In-trip | Destination once; "On the way to X", "Arriving soon" under 500 m; hide Add a stop under 1 km |
| 3.11 ✅ | Ride completed | One "Total ₹75" line + expander; sticky Done; tips ₹10/₹20/₹50/Custom; favourite toggle Regular/Fill heart |
| 3.12 ✅ | Driver account | Phosphor rows; bg.base; spaced phone; rating, trips, plate on the profile card; chevron + title on one baseline |

*Phase 3 status 2026-09-24:* 3.5–3.12 done and seen on the emulator (commits
191b624…b6e5575). Known gaps: Android SMS auto-read not added (needs a native
plugin + server SMS hash); no "try another tier" while searching (the cubit
can't re-request); driver "trips" is last 7 days (no lifetime endpoint); Terms
/Privacy open a Draft page until public URLs exist. 4.4 so far = Indian digit
grouping only; Hindi/Marathi strings not done. 2.7 ◐ = art exists for the v2
variant builds only (A flat, B/C Fluent 3D stand-ins); the default turquoise
build still draws its cars in code.

## Phase 4 — feel and reach (target 9.5–10)

| # | Item | Fix |
|---|---|---|
| 4.1 | Motion tokens | ease.enter / ease.exit (M3 emphasized); 100 / 200 / 350 / 500 ms; the audit's moments (selection pop, pin lift, matched morph, star pop, check draw) |
| 4.2 | Reduce Motion | Cross-fades instead of movement; radar stops |
| 4.3 | Accessibility | Screen-reader labels on every icon button; PIN and plate read per character; Dynamic Type to max without truncation; colour never alone; status changes announced |
| 4.4 ✅ | India localisation | Indian digit grouping (₹1,25,000); Hindi + Marathi strings; map labels in one language; UPI/card/cash as options (UPI needs a payment provider) |
| 4.5 | Validation | Icon recognition (5 users), find-your-car (≥ 90 %), 5-user task test, contrast + target audit |

---

## Order of work

1. Phase 1 (bugs) — first, all together.
2. Logo decision (owner) → brand lockup (3.4) can then proceed.
3. Phase 2 → 3 → 4, each committed when built, tested and seen on the emulator; Mac re-verifies iOS per phase.

Blocked on decisions: logomark choice (owner); photo storage for driver photos (2.6); UPI provider (4.4).
