# FAIRSVIA Visual Direction v3: research and three new plans (D, E, F)

*Research note, 2026-09-24. Adds to `visual-direction-v2.md` (Plans A, B, C) and
`ui-10-audit-plan.md`; it does not replace them. No code was changed.*

## How to read this

- **Sourced**: every claim about another app has a URL next to it. They are
  numbered and listed in the Sources section at the end.
- **Inference**: my own reading or proposal. It is marked *(inference)*.
- **What I could not check**: I did not look at screenshots of other apps. Mobbin
  needs a login, and Fast Company and the Uber Design Medium post returned
  HTTP 403. So nothing below describes pixel-level details of another app's
  current screens. Where a source only describes a feature, I say what the
  feature is and do not guess how it looks.
- **Contrast figures**: I computed them myself with the WCAG 2.x
  relative-luminance formula (script in the session scratchpad, not
  committed). They are not measured on a device.
- **Rules carried over from v2**: every plan here keeps the v2 shared
  foundation. That means the teal brand, fixed-meaning colours (red = SOS,
  amber = payment instructions, yellow = stars, blue = location dot), Phosphor
  Regular utility icons, the **Safety pill**, the **plate-first driver card**
  (plate in Inter, tabular, the largest line), **PIN in four boxes**, and the
  same layout and copy. Plans D, E and F change only the look. Where a plan
  bends a foundation rule, it says so.

---

## Part 1 — What the leading apps do (2023–2026)

### 1.1 Home and "Where to"

| App | What is documented | Source |
|---|---|---|
| Uber | 2023 redesign: a simpler home screen "with fewer taps". "Where to?" opens saved places and personalised suggestions. It added iPhone Live Activities and Dynamic Island support for ride status. | [1], [2] |
| Uber | GO-GET 2026 (29 Apr 2026): **One Search**. The "Where to?" bar now returns places, food and items from across the platform. Voice booking was also added. | [3] |
| Ola | April 2024 redesign: a new bottom navigation bar (Ride / Parcel) with ride types across the top (Daily, Electric, Outstation, Rentals, Priority). It moved to Ola's own maps. | [4], [5] |
| Grab | Case studies note that Grab detects your location on launch and puts the destination search first. They describe this as a "smart default" that lowers effort. | [6] |
| Lyft | 2018 redesign: asks "where you're going" *before* showing ride options. Also added one-tap requests for frequent destinations. | [7] |

**Takeaway** *(inference)*: the pattern is the same everywhere. Destination
comes first, saved and predicted places come next, and the map stays in the
background. The apps compete on fewer taps and personalisation, not on how
the home screen looks. A FAIRSVIA direction can therefore make its mark
through surfaces and type without touching this flow.

### 1.2 Choose ride

| App | What is documented | Source |
|---|---|---|
| Uber | Mobbin lists Uber's "Ride Options" screen (UberX, XL, Black, with price and a confirm button). Mobbin needs a login, so I did not view it. | [8] |
| Yandex Go | After you pick a tariff and route, a **colour informer** appears in green, yellow, orange or red. Closer to red means fewer free cars, worse traffic or weather, and a higher price. Tapping it shows the orders-to-cars ratio and the reasons. | [9] |
| inDrive | The rider proposes a fare. Drivers accept or counter, and the rider picks a driver by rating, car model, arrival time and trip history. | [10] |
| Rapido | Flexi Fare lets riders set their own price for autos. The booking flow is: pick vehicle, pick drop, confirm. | [11] |
| Lyft | Price Lock is a $2.99/month cap on prices for specific routes. | [12] |

**Takeaway** *(inference)*: the tier list works as a comparison table, and the
leading apps now explain *why* a price is what it is (Yandex's informer,
Lyft's cap). FAIRSVIA already shows "Pickup in 2 min · Drop 11:41 PM" (audit
3.7). A demand indicator in the Yandex style is a product decision, not a
visual one, so none of the plans below adds it. They leave room for it.

### 1.3 Finding a driver, the driver card and trust signals

| App | What is documented | Source |
|---|---|---|
| Rapido | Shows the captain's photo, licence plate and **helmet reminders** upfront. Every ride is insured by Acko at no extra cost. | [11], [13] |
| Rapido | Your PIN **stays the same on every ride**, so there is nothing new to remember. | [13] |
| Uber | 4-digit PIN verification, required on every trip or at night only. India launch: 9 Jan 2020. | [14] |
| Uber India | Features listed: Record My Ride, Ambulance Assistance, Set Your Own PIN, Women Rider Preference, Helmet Selfie Verification, RideCheck, a 24×7 safety line. | [15] |
| inDrive | The driver's details (rating, car model, trip history) are shown *before* you accept. | [10] |
| Namma Yatri | Driver verification by OTP. Live ride tracking on the lock screen (Live Activities). | [16] |
| Grab | Selfie verification for passengers and drivers. Design research recognises that users are often on low-end or hand-me-down phones with cracked screens and weak batteries. | [17] |

**Takeaway** *(inference)*: trust rests on the same items everywhere: photo,
plate, vehicle, PIN, and for bikes the helmet. FAIRSVIA's plate-first card
and four PIN boxes already match the strongest pattern. A plan should make
these items *more legible*, not decorate them. Grab's point about low-end
phones matters for Plan F.

### 1.4 In-trip, completed and live status

| App | What is documented | Source |
|---|---|---|
| Uber | Live Activities and Dynamic Island show ride progress while you use other apps. | [1] |
| Android 16 | Released 10 Jun 2025. Adds a progress-style notification template and "Live Updates" meant for rideshare, delivery and navigation. Sources note Uber already used custom progress bars. | [18], [19] |
| Namma Yatri | Lock-screen live tracking. Share your live ride with friends and family. | [16], [20] |

**Takeaway** *(inference)*: the in-trip screen now has a second home on the
lock screen. Each plan below includes a *Live Activity / Live Update styling*
so the look carries over there. The iOS side cannot be built on this server,
so that stays a plan, not a claim.

### 1.5 Safety entry points

| App | What is documented | Source |
|---|---|---|
| Uber | The **Safety Toolkit** opens from a shield icon on the map and shows large tiles: emergency button, report an incident, share trip, safety info, and (US) Live Help from ADT agents. | [21], [14] |
| Uber | Trusted Contacts (up to five) and trip-sharing reminders. | [15] |
| Namma Yatri | SOS button to alert emergency contacts. Live tracking can be shared. | [20] |
| Uber (US) | Women Preferences: piloted Aug 2025, expanded nationwide in 2026. | [22] |

**Takeaway**: FAIRSVIA's labelled **Safety** pill is *more* explicit than an
unlabelled shield. It stays as it is in every plan below.

### 1.6 What makes Indian apps feel local

| Signal | Evidence | Source |
|---|---|---|
| Autos and bikes as main vehicle types | Rapido: "Auto, Bike or Cab"; Namma Yatri started with autos; Uber runs UberAuto | [13], [16], [23] |
| Cash and direct UPI to the driver | Namma Yatri: "Pay directly to the Driver in cash or UPI". Since 18 Feb 2025, Uber autos are paid only in cash or UPI straight to the driver, under a subscription model | [16], [24] |
| Many Indian languages | Namma Yatri: English, Kannada, Tamil, Telugu, Hindi. Rapido: "multiple Indian languages" | [16], [11] |
| Clear over sleek | Rapido's yellow-black palette is "simple, high-contrast, and legible even on older screens … Instead of trying to be sleek, it tries to be clear." | [11] |
| Transparency as a feature | Namma Yatri: rate card, "no hidden charges", open data on rides and drivers, zero commission | [16], [25] |
| Metro as part of the trip | Namma Yatri has metro ticket planning. Rapido offers Delhi Metro tickets (2025) | [20], [11] |
| Insurance and helmets shown to the rider | Rapido | [13] |

A caution on **BluSmart**: it was an all-electric cab platform. It shut down
in April 2025 amid the Gensol fund-diversion case, and refunds were handled
manually [26], [27]. Its app is no longer a live reference. The lesson I draw
*(inference)* is that riders need clear refund and receipt paths, which Plan E
leans into.

### 1.7 Brand systems worth learning from

| Brand | What is documented | Source |
|---|---|---|
| Uber Base | Black and white first, one blue accent (#276EF1, used sparingly), 4 px grid. Principles "go big" on legibility and "less is more" on styles. Uber Move typeface with a monospaced cut for numbers. (Hex values come from an analysis of the open-source Base Web tokens, not from Uber.) | [28], [29] |
| Bolt | Moved from Euclid to **Inter** "supporting over 990 languages". Added a darker green for readable contrast. Replaced flat "Corporate Memphis" art with **400+ 3D illustrations** that animate. | [30] |
| inDrive | Rebrand May 2026 (Border Zero): a **marker motif** that "highlights, connects, annotates, and crosses out"; a stronger green; "sketch-like illustrations inspired by quick marker strokes"; "fewer fonts, fewer effects". | [31] |
| Yandex Go | Super-app rebrand (Magic Camp): an "active and dynamic visual language" built on "showing rather than telling". | [32] |
| Grab | Duxton design system, the default since late 2023, ~50 % adopted by H2 2025. Hyperlocal design across its SEA markets. | [33] |
| Lyft Silver | App for older riders with type ~1.4× the standard size and a simpler interface. Taken from the search-result summary; the article itself returned 403. | [34] |
| Apple Liquid Glass | Announced 9 Jun 2025 (iOS 26). Translucent, fluid, more rounded elements across all Apple platforms. | [35], [36] |
| Material 3 Expressive | May 2025. Physics-based spring motion, a larger shape library with morphing, more type and colour choice. Based on 46 studies with 18,000+ participants. | [37], [38] |

### 1.8 Launch-market note: Uzbekistan

Yandex Go had an **86.3 %** ride-hailing share in Uzbekistan in 2023 (per
Wikipedia), and MyTaxi is the main local alternative [39], [40]. So in
Tashkent, Yandex Go's conventions are what riders expect *(inference)*. Uzbek
is officially written in Latin script, which needs the modifier letter
ʻ (U+02BB) in oʻ and gʻ, while Cyrillic is still widely read. **Every font
choice below has to be checked for ʻ and Cyrillic** before the Uzbekistan
build. I list what I believe each font covers, but I have **not verified glyph
coverage**.

---

## Part 2 — Three new directions

All three:
- keep teal as the only brand colour;
- keep Phosphor Regular utility icons and the plate style (Inter tabular);
- keep layout and copy identical to A/B/C, so they can go into the same
  preference test;
- are designed as build-time variants (`THEME=`), like A/B/C. Proposed names:
  `local`, `editorial`, `glass`.

Fonts in this repo are **bundled** (`packages/design_system/pubspec.yaml`),
not fetched at runtime. Every font named here is free under the OFL on Google
Fonts and would be bundled the same way as Inter.

### Summary

| | Plan D — Local Colour | Plan E — Ink & Paper | Plan F — Map Glass |
|---|---|---|---|
| Mood | Warm, vivid, made-here, Indic-script-first | Quiet, editorial, premium, receipt-grade clarity | Map is the whole screen; floating translucent controls |
| Reference apps | Rapido (clarity), Namma Yatri (transparency), Bolt (3D + Inter), Yandex Go ("show, don't tell") | Uber Base (black/white, one accent), inDrive 2026 (marker, fewer fonts), Lyft Silver (big type) | Apple Liquid Glass, Material 3 Expressive, Apple/Google Maps |
| Background | Warm paper #FBF7F0 / warm black #14110D | Paper #FAFAF7 / ink #0A0A0A | The map itself; glass sheets |
| Brand use | Deep teal buttons; marigold only in illustrations | **Ink** primary buttons; teal only for route, selection and one accent | Solid teal buttons; teal route with a glow |
| Type | Anek Latin + Anek Devanagari (or Mukta), Inter for plate and fares | Instrument Serif (display) + Inter | Manrope (or Onest) + Inter for numbers |
| Hero art | Flat-plus-grain illustrations of local vehicles and places, recoloured per market | Line drawings in a marker style, one colour | Soft 3D map-object icons (pins, cars) with a glass rim |
| Effort | 5–6 weeks (+ illustrator) | 3–4 weeks | 5–7 weeks (+ performance work) |
| Main risk | Looks like a Rapido or Ola copy, or cluttered | Looks cold, or reads as an Uber clone | Blur is slow and contrast unreliable on low-end Android |

---

### Plan D — "Local Colour" (India-local vivid, swappable per market)

**Mood.** FAIRSVIA should feel like it was made in Pune, not dropped in from
San Francisco. It uses warm off-white "paper" backgrounds, deep teal for
anything you tap, and a marigold accent that appears only in illustrations,
like marigold garlands on a dashboard. Illustrations show real local things: a
Pune auto, the Shaniwar Wada gate on the empty state, a chai stall on "No cars
nearby". Type is set so Hindi and Marathi look native, not bolted on. The
palette is built so the *illustration accent can be swapped per market*: for
Tashkent, marigold would become a majolica blue-turquoise tile motif
*(inference: a visual proposal, not researched cultural guidance; needs local
review)*. Following Rapido's lesson [11], clarity comes first, and the warmth
comes from colour temperature and art, not from clutter.

**References.** Rapido (clear, high contrast, legible on old screens) [11];
Namma Yatri (rate card, transparency, languages) [16]; Bolt (animated 3D/flat
illustrations, Inter for language reach) [30]; Yandex Go ("show, don't tell")
[32].

**Foundation deviation (needs owner sign-off).** It adds a second
*illustration-only* hue, marigold. This follows the v2 rule that bright teal
appears "inside illustrations only". Marigold is never used for text, icons
or state, so it does not clash with amber (payment instructions) or yellow
(stars).

**Colour tokens**

| Token | Light | Dark | Use |
|---|---|---|---|
| bg.base | #FBF7F0 | #14110D | Screen background (warm) |
| surface.1 | #FFFFFF | #1E1A15 | Sheets, cards |
| surface.2 | #F3EDE2 | #29241D | Chips, secondary buttons, PIN boxes |
| border.input | #9A8F7E | #6E6558 | Input and selected outlines |
| text.primary | #1C1A17 | #F6F1E8 | Headings, values |
| text.secondary | #5E574D | #B5AC9E | Subtitles |
| brand | #0A6E6E | #3CCFCF | Buttons, selection, links, route |
| on.brand | #FFFFFF | #0E0F11 | Text on brand |
| brand.tint | #E3F1EE | #173230 | Selected row fill |
| illus.marigold | #F2A93B | #F2A93B | **Illustrations only** |

Contrast (computed): text.primary on bg 16.3:1 (L) / 16.7:1 (D).
text.secondary on bg 6.7:1 (L), on surface.1 7.7:1 (D). White on brand
button **6.1:1** (L); dark on #3CCFCF **10.1:1** (D). Brand text on the tint
row 5.2:1. Input borders 3.2:1 (L) / 3.0:1 (D), just meeting 3:1 non-text.
Marigold on white is **2.0:1**, which is why it may never carry meaning.
Dark-mode brand.tint #173230 has not been computed; check before use.

**Type.** *Anek Latin* for UI and headings, paired with *Anek Devanagari*
(Ek Type, variable widths) so Latin and Devanagari share one design voice.
Alternative: *Mukta*, which covers Latin and Devanagari in one family.
*Inter* stays for the plate and fares, because it has tabular figures and is
already bundled. Uzbek: I believe Anek has **no Cyrillic** *(unverified)*, so
the Tashkent build would use Inter throughout, or *Onest* for headings.

**Icons.** Phosphor Regular for utility icons (unchanged). Hero art is
flat-plus-texture illustration: a 2 % paper grain, slightly offset colour
"print" registration, 3/4 view. Vehicles are drawn as local vehicles: the four
car tiers, plus an auto-rickshaw and a bike. Those last two only matter if
FAIRSVIA ever adds those tiers; the product has four car tiers today, so
**no auto or bike tier is implied**.

**5 signature details**
1. A **rangoli-dot loader**. The finding-driver radar is made of dots that
   build into a simple kolam pattern at the pickup. It falls back to plain
   rings under Reduce Motion.
2. **Script-aware headings**. In Hindi or Marathi, titles switch to Anek
   Devanagari with the matched width, and line-height grows about 15 % for
   matras.
3. **Rate card chip** on Choose ride. It opens the fare breakdown (base, per
   km, per min), in the spirit of Namma Yatri's "you can check the rate card"
   [16]. It is a visual slot for data the server already has.
4. **Pay-to-driver strip**. For cash or UPI, one amber strip says "Pay ₹102
   to Rahul: cash or UPI", keeping the amber = payment-instructions rule.
5. **Market-swappable accent**. `illus.accent` is one token: marigold for
   India, tile-turquoise for Uzbekistan. Art is exported in both.

**Screen by screen** (layout and copy identical to A/B/C)

| Screen | Plan D |
|---|---|
| Home / Where to | Warm paper sheet. "Where to?" field on surface.2 with a deep-teal focus ring. Saved places as round-cornered chips with Phosphor icons. Small marigold-accented illustration of the city on an empty history |
| Choose ride | Flat-textured 3/4 cars (same body colour; shape shows the tier). Selected row: brand.tint fill + 2 px brand border. Rate card chip on the info icon |
| Finding driver | Kolam-dot radar at the pickup on a warm-tinted map style. Sheet: "Economy · ₹102 · Cash" |
| Driver card (on the way / arrived) | Plate in Inter 22/700 on surface.2 in a thin border that looks like a number plate. Photo over a flat car in the real colour. PIN boxes on surface.2 with brand digits. Pay-to-driver strip when cash or UPI |
| In trip | Teal route with a thin marigold "progress already travelled" line. **This is illustration use on the map and bends the rule; alternative: a lighter teal.** Safety + Share pills unchanged |
| Completed / receipt | "Total ₹75" in Inter. The check illustration pops, with marigold confetti dots (Reduce Motion: static). Tips as chips |
| Safety sheet | Unchanged tiles. The only change is the warm surface; red stays for SOS only |

**Effort.** 5–6 weeks. Tokens and type take ~1 week. Devanagari layout QA
takes ~1 week. The illustration set (~20 items × 2 accents) needs an
illustrator, as the 3D brief in v2 does, costed separately. The kolam loader
is ~3 days.

**Main risk.** It ends up looking like a copy of Rapido or Ola, or "Indian"
turns into clichés and clutter. Mitigation: marigold only in art, no yellow
UI, and local review of the motifs by Pune and Tashkent riders in the
desirability test.

---

### Plan E — "Ink & Paper" (editorial, minimal, premium)

**Mood.** It reads like a well-printed ticket or a good newspaper: near-black
ink on paper-white, generous white space, hairline rules, and one serif for
big moments ("Rahul arriving in 3 min", "Total ₹75"). It is closer to Uber's
restraint [28] than A is, but with a *printed* character: numbers set like a
timetable and a receipt that looks like a receipt. Teal becomes a precise
accent, used for the route, the current selection and the one thing that
matters on a screen. The main button is **ink**. It is the cheapest plan here
and the easiest to keep accessible.

**References.** Uber Base (black/white, one accent, "go big" on legibility)
[28], [29]; inDrive 2026 ("fewer fonts, fewer effects", marker annotations)
[31]; Lyft Silver (bigger type for older riders) [34].

**Foundation note.** Teal is still the only brand colour, but it no longer
fills primary buttons. That differs from A and B and should be named in the
test.

**Colour tokens**

| Token | Light | Dark | Use |
|---|---|---|---|
| bg.base | #FAFAF7 | #0A0A0A | Paper / ink |
| surface.1 | #FFFFFF | #141413 | Sheets |
| surface.2 | #F0F0EC | #1D1D1B | Chips, PIN boxes |
| rule.hairline | #DAD9D3 | #2E2E2B | Decorative 1 px rules only |
| border.input | #8A8A83 | #707069 | Inputs and outlines (meaning-bearing) |
| text.primary | #0B0B0C | #F4F3EE | Ink |
| text.secondary | #55554F | #A3A29B | Captions |
| action.primary | #0B0B0C | #F4F3EE | Primary button fill |
| on.action | #FFFFFF | #0A0A0A | Button text |
| brand | #0A7C7C | #3FC9C9 | Route, selection mark, links, one accent |

Contrast (computed): ink on paper 18.8:1 (L) / 17.8:1 (D). Secondary 7.2:1
(L) / 7.2:1 (D). Primary button 19.7:1 (L) / 17.8:1 (D). Teal link text
5.0:1 on white and 4.8:1 on paper, so AA holds for normal text, only just.
Dark teal 9.1:1. Input borders 3.3:1 (L) / 3.7:1 (D). Hairlines (1.4:1,
2.7:1) are decorative and must never be the only boundary of a control.

**Type.** *Instrument Serif* (Regular + Italic) for display only: screen
titles 28/34 and the receipt total. *Inter* for everything else; plate and
fares use Inter tabular (unchanged). Instrument Serif has only one weight, so
it is never used below 22 pt. Uzbek: I believe Instrument Serif is Latin-only
*(unverified)*. That is fine for Uzbek Latin if ʻ renders, but it has **no
Cyrillic**, so the fallback is *PT Serif* or *Lora* (both have Cyrillic,
unverified here). Devanagari display: *Tiro Devanagari Hindi / Marathi*
(serif, matches the tone).

**Icons.** Phosphor **Light** for hero glyphs, used large (48–64 px) with no
container. Phosphor Regular stays for utility icons. Empty and success states
are single-colour **line drawings in a marker style**, related in spirit to
inDrive's 2026 marker [31] but not the same gesture *(inference: must stay
visibly distinct from inDrive's marker; brief the illustrator on this)*.

**5 signature details**
1. **Serif moments**. Only three places use the serif: the status title, the
   receipt total and the splash wordmark line. Nowhere else.
2. **Timetable numbers**. ETA, drop time and fare are set in Inter tabular in
   a right-aligned column on Choose ride, so prices line up like a timetable.
3. **Ticket receipt**. The Completed screen is a paper card with a
   perforated top edge, the route drawn as a thin teal line, fare lines with
   dotted leaders, and "Total ₹75" in serif. A "Get receipt / Report an
   issue" row sits under it (the BluSmart refund lesson, inference [27]).
4. **Marker underline**. A hand-drawn teal underline marks the selected tier
   and draws itself in 200 ms (Reduce Motion: appears at once).
5. **Big-type mode for free**. The layout is sparse, so Dynamic Type at the
   largest setting (Lyft Silver is ~1.4× [34]) fits without redesign. Make it
   a test criterion.

**Screen by screen**

| Screen | Plan E |
|---|---|
| Home / Where to | White sheet on a light desaturated map. "Where to?" in Inter 20/600, with a hairline under the field instead of a filled box. Saved places as a ruled list, not chips |
| Choose ride | Ruled rows, monochrome line-drawn cars, right-aligned tabular fares. Selection = teal marker underline + teal check. Ink "Confirm Economy" button |
| Finding driver | Radar as three thin teal circles (no fill). Serif title "Finding your driver" |
| Driver card | Serif title "Rahul arriving in 3 min". Plate in Inter 22/700 inside a 1.5 px ink border (plate-like). Photo + line-drawn car tinted to the real colour (the only colour fill on the card). PIN boxes on surface.2 with ink digits |
| In trip | Map with a teal 4 px route, no glow. Safety + Share pills in ink outline. "On the way to X" in Inter |
| Completed / receipt | Ticket receipt (detail 3). Rating stars stay yellow. Tips as outlined chips |
| Safety sheet | Tiles as a ruled list with Phosphor icons. SOS is the one red solid button |

**Effort.** 3–4 weeks, about the same as A. It needs no 3D art. Line
illustrations (~12) could be drawn in-house or commissioned cheaply. The
ticket receipt is ~3 days. Adding the serif is ~1 day.

**Main risk.** It feels cold or "Uber-lite" to Pune riders who are used to
Rapido or Ola colour, and the ink button looks too much like Uber's black
button. Mitigation: keep the warm paper tone (#FAFAF7, not #FFFFFF), use the
serif moments, and test desirability specifically against A.

---

### Plan F — "Map Glass" (map-first, translucent)

**Mood.** The map is the product. Sheets shrink to floating, rounded,
translucent panels that let the city show through. Motion uses springs, and
the sheet feels like a physical object. Pickup and driver pins are soft 3D
objects that sit *on* the map. It matches where iOS 26 (Liquid Glass [35],
[36]) and Android (M3 Expressive [37], [38]) are heading, so FAIRSVIA would
feel at home on 2026 phones. A glass-free solid fallback is part of the
design, not something added later, because many riders use low-end phones
[17].

**References.** Apple Liquid Glass [35], [36]; Material 3 Expressive
(spring motion, shape morphing) [37], [38]; Android 16 Live Updates for the
lock-screen continuation [18], [19]. Apple Maps and Google Maps as general
map-first references *(I did not research their current screens for this
note)*.

**Colour tokens** (glass = fill at the given alpha + background blur, σ ≈ 24)

| Token | Light | Dark | Use |
|---|---|---|---|
| glass.fill | #FFFFFF @ 72 % | #12161A @ 70 % | Floating sheets and pills |
| glass.fill.strong | #FFFFFF @ 84 % | #12161A @ 82 % | Sheets carrying secondary text |
| glass.rim | #FFFFFF @ 60 %, 1 px | #FFFFFF @ 12 %, 1 px | Top-edge highlight (decorative) |
| surface.solid (fallback) | #F7F8F9 | #15191D | Reduce Transparency, low-end devices |
| text.primary | #0F1417 | #F2F5F7 | |
| text.secondary | #4A545C | #A7B0B8 | |
| brand | #007A7A | #35D0D0 | Solid buttons, route |
| brand.onGlass.text | #005F5F | #35D0D0 | Teal *text* on glass |
| on.brand | #FFFFFF | #0E1114 | |
| map style | desaturated light / desaturated dark | | So glass tints stay neutral |

Contrast (computed). I worked it out for glass composited over a
**worst-case map pixel** (light: grey #6B7780; dark: light grey #8A96A0):
- Light glass at 72 %: primary 13.1:1, secondary 5.5:1, brand #007A7A as text
  only **3.6:1**, which fails AA for normal text. Hence brand.onGlass.text
  #005F5F (5.3:1).
- Dark glass at 70 %: primary 10.2:1, secondary 5.1:1, brand 5.9:1.
- Solid buttons: white on #007A7A is 5.2:1; dark on #35D0D0 is 10.0:1.
- The light glass rim is ~2.2:1, decorative only, so controls on glass also
  need a 3:1 outline or solid fill.

**Rule:** buttons are never glass; they are always solid brand or solid
surface.

**Type.** *Manrope* (geometric, rounded, with Cyrillic, *unverified*) for UI.
Alternative: *Onest* (built with Cyrillic in mind, *unverified*). *Inter*
tabular for plate, fares and ETA. Devanagari: *Noto Sans Devanagari*
(neutral, sits under a geometric Latin).

**Icons.** Phosphor Regular for utility icons. Hero map objects (pickup pin,
drop pin, the driver's car seen from above, the radar) are soft 3D objects
with a glass rim, rendered from above for the map. This is a *different* set
from v2's 3/4-view clay icons (4 map objects + 4 top-down cars). Ride-type
list icons can reuse the A (flat) or B (3D) cars.

**5 signature details**
1. **Floating sheets**: 12 px inset from the screen edges, 28 px radius,
   glass, snapping on springs (M3 Expressive-style physics). The map is
   visible around them on all sides.
2. **The sheet morphs** from the pill ("Where to?") into the tier list, then
   the driver card, then the in-trip pill. It is one continuous shape, not
   separate screens. Reduce Motion: cross-fade.
3. **Glass that knows its limits**: automatic solid fallback under Reduce
   Transparency, battery saver, or when a frame-time probe detects slow blur
   (inference: needs a device-tier heuristic, to be built and tested).
4. **3D car on the map** turns with the heading and carries a small plate
   tag. The plate appears *on the map* as well as on the card, helping with
   "find your car".
5. **Lock-screen continuity**: the Live Activity (iOS) and Live Update
   (Android 16) use the same pill shape, glass-dark colour and plate-first
   text as the in-app pill. iOS cannot be built here; Android can be
   verified on the emulator only if the image supports Live Updates.

**Screen by screen**

| Screen | Plan F |
|---|---|
| Home / Where to | Full-screen map. A single floating glass pill "Where to?" with saved places as small glass chips above it. No full-width sheet at rest |
| Choose ride | Pill expands (morph) into a floating glass card, max ~55 % height. Tiers on glass.fill.strong. Selected row as a solid brand.tint pill. Solid teal Confirm |
| Finding driver | Card shrinks to a pill "Finding your driver · Economy · ₹102". The 3D radar sits at the pickup on the map |
| Driver card | Glass card; the **plate section is solid surface** (never glass), so the plate stays at full contrast. Photo + car. PIN boxes solid surface.2. 3D car on the map with a plate tag |
| In trip | Map with a teal route and soft glow. Bottom glass pill "On the way to X · 11:41". Safety + Share pills float top-right as solid-rim glass |
| Completed / receipt | Map zooms out to the whole route (static thumbnail per audit 1.1); glass receipt card; sticky solid Done |
| Safety sheet | **Opens solid, never glass**: an emergency surface must be at full contrast and fast to draw |

**Effort.** 5–7 weeks. Tokens and the glass widget with fallback take ~1
week. The sheet morph takes ~1.5 weeks. Performance profiling and the
low-end fallback take ~1 week (`BackdropFilter` over a live platform map view
is costly in Flutter; *inference, must be measured on the emulator and a
low-end device*). 3D map objects take ~1 week plus an artist. Lock-screen
styling takes ~1 week (Android here, iOS on the Mac).

**Main risk.** Performance and legibility. Blur over a moving map can drop
frames on budget Android phones and drain battery. Contrast changes with
whatever map is underneath, and in bright sun glass reads worse than solid
*(inference)*. Mitigation: solid fallback built in, plate and Safety always
solid, and the task test held outdoors (as v2 Test 2 already plans).

---

## Part 3 — How D/E/F fit the existing plan

- **Testing**: D, E and F keep layout and copy identical, so they can join the
  v2 Test 1 desirability round. Recommendation *(inference)*: test **A, B, D,
  E** in week 3 (static screens are cheap). Build F only as a clickable
  prototype, because its value is motion and depth, which static reaction
  cards will not show.
- **Combinations** *(inference)*: E's type and receipt with B's 3D heroes;
  D's market-swappable accent on top of C's Day & Night; F's floating sheet
  with A's dark tokens.
- **Blocked items unchanged**: driver photo storage (audit 2.6), UPI provider
  (4.4), logomark (owner).
- **Must verify before any build**: font glyph coverage (ʻ, Cyrillic,
  Devanagari conjuncts) for Anek, Instrument Serif, Manrope and Onest; blur
  performance on the `pixel_uber` emulator and one low-end physical Android
  phone.

---

## Sources

1. BGR, "Uber releases major app redesign…" (22 Feb 2023) — https://www.bgr.com/tech/uber-releases-major-app-redesign-with-new-home-screen-and-more/
2. TechCrunch, "Uber redesigns app for simpler, more personalized experience" (22 Feb 2023) — https://techcrunch.com/2023/02/22/uber-redesigns-app-for-simpler-more-personalized-experience/
3. Uber Newsroom, "GO–GET 2026: One app for everything" (29 Apr 2026) — https://www.uber.com/us/en/newsroom/go-get-2026/
4. Business Today, "Ola CEO unveils new design of Ola app" (23 Apr 2024) — https://www.businesstoday.in/technology/news/story/many-changes-coming-soon-ola-ceo-bhavish-aggarwal-unveils-new-design-of-ola-app-426591-2024-04-23
5. ACKO Drive, "Ola app to switch from Google to in-house maps" — https://ackodrive.com/news/ola-app-to-switch-from-google-to-in-house-maps-ui-refresh-coming-soon/
6. Bootcamp/Medium, "Case study: Improvement on Grab booking experience" — https://medium.com/design-bootcamp/case-study-improvement-on-grab-booking-experience-1be8310c4c20
7. Lyft Blog, "Introducing the New Lyft App" (7 Jun 2018) — https://www.lyft.com/blog/posts/new-app
8. Mobbin, Uber iOS Ride Options (login required; not viewed) — https://mobbin.com/explore/screens/80fbd077-5b4c-4594-93b4-1ce8129b8f3f
9. TAdviser, "Yandex Go (formerly Yandex.Taxi application)" — https://tadviser.com/index.php/Product:Yandex_Go_(formerly_Yandex.Taxi_application)
10. inDrive — https://indrive.com/ ; Google Play listing — https://play.google.com/store/apps/details?id=sinet.startup.inDriver&hl=en_US
11. JustAnotherPM, "How Rapido redefined bike taxis in India" — https://japm.substack.com/p/how-rapido-redefined-bike-taxis-in
12. Lyft, Price Lock — https://www.lyft.com/rider/commute/pricelock
13. GrabOn, "Rapido Bike Taxi App: Ride Bookings & Benefits" — https://www.grabon.in/indulge/travel/rapido-app-ride-bookings-benefits/ ; Rapido App Store — https://apps.apple.com/us/app/rapido-bike-taxi-auto-cabs/id1198464606
14. Uber India Newsroom, "New safety features" (9 Jan 2020) — https://www.uber.com/in/en/newsroom/new-safety-features
15. Techlusive, "Uber launches four new safety features… in India" (via search summary; page returned 403) — https://www.techlusive.in/news/uber-launches-four-new-safety-features-for-riders-and-drivers-in-india-1667671/ ; RideGuru — https://ride.guru/lounge/p/what-are-uber-safety-tools-and-how-do-i-access-them
16. Namma Yatri, App Store (India) — https://apps.apple.com/in/app/namma-yatri-ride-booking-app/id1637429831
17. Grab Tech, "Driving Southeast Asia Forward Through People-Focused Design" (5 Nov 2019) — https://engineering.grab.com/driving-sea-forward-through-people-focused-design
18. Android Authority, "Android 16 QPR1 adds full support for Live Updates" — https://www.androidauthority.com/android-16-qpr1-live-updates-3573399/
19. Droid Life, "Android 16's Live Update notifications" (21 Feb 2025) — https://www.droid-life.com/2025/02/21/android-16-live-update-notifications/
20. Namma Yatri, Google Play — https://play.google.com/store/apps/details?id=in.juspay.nammayatri&hl=en_US ; Medium, "Beyond the Ride" — https://avinashsdalvi.medium.com/namma-yatris-success-secrets-revealed-04413fadd231
21. Uber Newsroom, "Uber's new Safety Toolkit" (30 Aug 2022) — https://www.uber.com/us/en/newsroom/ubers-new-safety-toolkit/
22. Uber Investor Relations, "Uber expands Women Preferences nationwide" (2026) — https://investor.uber.com/news-events/news/press-release-details/2026/Uber-Expands-Women-Preferences-Nationwide-Enabling-Women-Riders-to-Match-with-Women-Drivers-Across-the-U-S-/default.aspx
23. NPR, "Uber launches cash-only rickshaw service in Indian capital" (2015) — https://www.npr.org/sections/thetwo-way/2015/04/09/398563088/uber-launches-cash-only-rickshaw-service-in-indian-capital
24. Business Today, "No more digital payments on Uber auto…" (19 Feb 2025) — https://www.businesstoday.in/latest/trends/story/no-more-digital-payments-on-uber-auto-but-does-upi-payment-work-all-you-need-to-know-465147-2025-02-19
25. Rest of World, "Uber and Ola are copying India's fast-growing ride-hailing app" (2 May 2025) — https://restofworld.org/2025/uber-ola-copy-india-zero-commission-ride-hailing-app/ ; GitHub — https://github.com/nammayatri/nammayatri
26. TechCrunch, "BluSmart swept up in Gensol investigation" (15 Apr 2025) — https://techcrunch.com/2025/04/15/indian-ride-hailing-startup-blusmart-swept-up-in-gensol-investigation-alleging-misuse-of-ev-loans/
27. Cartoq, "BluSmart to customers: do NOT expect any refund" — https://www.cartoq.com/car-life/blusmart-viral-social-media-crisis-collapse-electric-cab-service/ ; Wikipedia — https://en.wikipedia.org/wiki/BluSmart
28. Superdesign, "How Uber designs its UI: the Base design system" (2026; third-party analysis of Base Web tokens) — https://superdesign.dev/blog/uber-design-system
29. Uber Base, Typography — https://base.uber.com/6d2425e9f/p/976582-typography
30. Bolt, "Our new look and why we upgraded" — https://bolt.eu/en/campaigns/refresh/
31. adobo Magazine, "inDrive unveils global rebrand…" (8 May 2026) — https://www.adobomagazine.com/design/indrive-unveils-global-rebrand-built-around-fairness-and-human-connection/ ; Brand New — https://www.underconsideration.com/brandnew/archives/new_logo_and_identity_for_indrive_by_border_zero.php
32. Design Compass, "Yandex Go brand design" — https://designcompass.org/en/2025/07/23/yandex-go/
33. Figma customer story, "How Grab scales hyperlocal experiences…" — https://www.figma.com/customers/how-grab-scales-hyperlocal-experiences-across-southeast-asia-with-figma-and-ai/
34. Fast Company, "How Lyft designed Lyft Silver for older riders" (page returned 403; claim from search summary) — https://www.fastcompany.com/91328470/how-lyft-designed-lyft-silver-for-older-riders
35. Engadget, "WWDC 2025: iOS 26, new Liquid Glass design…" — https://www.engadget.com/big-tech/wwdc-2025-ios-26-new-liquid-glass-design-and-everything-else-apple-announced-171718769.html
36. Apple Developer, "Meet Liquid Glass" (WWDC25) — https://developer.apple.com/videos/play/wwdc2025/219/
37. Google Design, "Expressive Design: Google's UX Research" — https://design.google/library/expressive-material-design-google-research
38. Dezeen, "Google ushers in age of expressive interfaces…" (28 May 2025) — https://www.dezeen.com/2025/05/28/google-ushers-in-age-of-expressive-interfaces-with-material-design-update/
39. Wikipedia, "Yandex Taxi" (Uzbekistan market share, 2023) — https://en.wikipedia.org/wiki/Yandex_Taxi
40. Things To Do in Uzbekistan, "Taxis & rideshare in Uzbekistan (2026)" — https://thingstodoinuzbekistan.com/transportation/taxi-rideshare/
