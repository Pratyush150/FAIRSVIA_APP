# Icons and illustration options (research, 2026-09-24)

Scope: where FAIRSVIA's three icon tiers could come from, what the licences
actually say, and a ranked pick for each. It builds on
`docs/plans/visual-direction-v2.md` (icon tiers, 3D icon brief) and
`docs/brand/CREDITS-3d-icons.md` (the current Fluent Emoji 3D stand-ins).
This is research only. No code or assets were changed.

**Verified vs assumed**
- Verified here: icon counts and coverage came from the live Iconify API
  (`api.iconify.design/collections`, `/search`, `/{set}.json`) on 2026-09-24.
  Samples were downloaded and rendered, and the contact sheet was looked at
  (see "Samples" below). Licence texts were read directly for 3dicons (repo
  `LICENSE` = CC0 1.0), Kenney Car Kit (`License.txt` in the zip = CC0),
  unDraw (licence page), Freepik/Magnific (terms page) and the Sketchfab
  auto-rickshaw model page. `Icons.electric_rickshaw`, `Icons.two_wheeler` and
  `Icons.currency_rupee` were confirmed in the local Flutter SDK
  (`flutter/packages/flutter/lib/src/material/icons.dart`).
- Taken from secondary sources (search snippets; the vendor page returned 403
  or could not be fetched): Iconscout licence terms, Blush licence terms, Open
  Peeps/Humaaans CC0, Fiverr gig prices, Upwork rates. Each one is marked
  where it is used. Read the vendor page yourself before paying or shipping.

## Samples

- Contact sheet:
  `docs/brand/research/icons-contact.png`
  (1700×2326). It is built by `build_contact.py` in the same folder. Raw
  samples and where each came from are in `samples/` (see `samples/SOURCES.txt`).
  The scratch folder is temporary. If the sheet is worth keeping, copy it into
  `docs/brand/`.
- Section A: 9 utility families × 13 ride concepts at 48 px.
- Section B: vehicle art. Fluent 3D, the repo's current stand-ins, Noto,
  OpenMoji, Kenney and Quaternius.
- Section C: 3dicons.co clay and colour next to the current Fluent-based heroes.

What the sheet shows:
- **Auto-rickshaw is the gap.** Of 9 utility families, only Material Symbols
  has one (`electric_rickshaw`). At 48 px it looks like a small delivery van
  with a lightning bolt, not a Pune auto. No utility family has a UPI glyph
  (the UPI mark is NPCI's trademark, so use NPCI's official logo files under
  their brand rules, not an icon-set lookalike).
- **Phosphor covers everything else**: car, moped, `currency-inr`, siren,
  shield-check, map-pin, chat, phone, star and receipt. Its `path` is a
  weaker "route" icon than Tabler's or Lucide's `route`.
- **Fluent System Icons** has a combined "dollar-rupee" glyph (wrong for
  India) and no SOS or route icon. **Heroicons** has no car, bike, SOS or
  route, so it is out. **Iconoir** has no rupee or SOS.
- **Fluent Emoji 3D vehicles** are cute, toy-like, side-on and facing left.
  They are not the 3/4 view the brief asks for. The recoloured repo stand-ins
  hang together as a set. The Fluent auto-rickshaw is the only free 3D auto
  that fits the style.
- **Noto** (flat, Apache-2.0) has the most recognisable auto-rickshaw of any
  free source: yellow-green, Indian proportions. It is flat, though, so it
  clashes with 3D heroes.
- **Kenney and Quaternius** are low-poly game art. They are CC0 and in true
  3D, so you can re-render them from any angle, but out of the box they look
  like a game, not a premium app. There is no Indian vehicle in either.
  Kenney's own preview PNGs are only 64 px.
- **3dicons.co** is good quality at 400 px with a real 3/4 "dynamic" angle
  and clay/colour/gradient/premium finishes. It has a rupee coin, wallet,
  map-pin, shield, mobile, calendar, gift, star and chat. It has **no
  vehicles** (120 icons, full list checked). Its material look (glossy,
  realistic) is **not** the same style as Fluent Emoji 3D (soft, toy-like), so
  mixing the two on one screen will look like two sets.

## 1. Utility icons

| Family | Licence | Count (Iconify, 2026-09-24) | Weights / variants | Ride-app coverage (of car, auto, bike, wallet, ₹, SOS, shield, pin, route, chat, phone, star, receipt) | Flutter |
|---|---|---|---|---|---|
| **Phosphor** (current) | MIT | 9,072 (all weights) | 6: thin, light, regular, bold, fill, duotone | 12/13, missing auto | Already bundled as a trimmed TTF + `phosphor_icons.dart` (the `phosphor_flutter` package can't be used, see that file's header) |
| Lucide | ISC | 1,853 | 1 stroke style; stroke width adjustable in SVG | 12/13 (missing auto); has `receipt-indian-rupee` | `lucide_icons_flutter` / font; SVG |
| Tabler | MIT | 6,202 (≈5.1k outline + ≈1k filled) | outline + filled, 2 px stroke on 24 grid | 12/13 (missing auto); has `sos`, `receipt-rupee`, `coin-rupee` | `tabler_icons` / font |
| Material Symbols | Apache-2.0 | 15,717 | outlined/rounded/sharp × fill 0/1 × weight 100–700 × grade × optical size | **13/13**: only family with `electric_rickshaw`; `two_wheeler`, `sos`, `currency_rupee` | `Icons.*` built into Flutter (older Material Icons font); full Symbols through `material_symbols_icons` |
| Fluent UI System Icons | MIT | 19,850 | regular + filled, sizes 12–48 | 10/13, missing auto, SOS, route; rupee is only "dollar-rupee" | `fluentui_system_icons` |
| Hugeicons (free) | MIT (free Stroke Rounded only; other styles are paid) | 6,065 | free: 1 style (stroke rounded) | 12/13 (missing auto); `rupee`, `siren`, `route-01` | `hugeicons` package |
| Remix Icon | Apache-2.0 (per Iconify; Remix has changed its licence before, re-check the repo) | 3,188 | line + fill | 12/13 (missing auto) | `remixicon` / font |
| Iconoir | MIT | 1,671 | regular + solid (some) | 10/13, missing auto, ₹, SOS | SVG / `iconoir_flutter` |
| Heroicons | MIT | 1,288 | outline, solid, mini, micro | 8/13, missing car, auto, bike, SOS, route | SVG only |

**Ranked recommendation (a) utility icons**

1. **Keep Phosphor Regular (primary).** MIT, 6 weights (Fill already bundled
   for selected states), 12/13 coverage including `currency-inr`, `moped`,
   `siren`. Switching now would churn every screen for no gain.
2. **Material Symbols as the one-off fallback for the auto-rickshaw glyph.**
   Use it only in small places (a filter chip, a trip-history row), where
   Flutter's built-in `Icons.electric_rickshaw` needs no new dependency. It
   is a filled Material shape next to Phosphor's 1.5 px stroke, so it will
   look slightly off. A better fix is to **draw one Phosphor-style auto glyph**
   (24 grid, 1.5 px stroke, round caps) and add it to the trimmed font. That
   is a few hours for a designer, or part of the commission below.
3. **Tabler as the backup family** if Phosphor ever falls short. It has the
   closest stroke feel, outline + filled pairs, and `sos` and
   `receipt-rupee`. Lucide is equally good, but it has only one style (no
   filled icons for selected states).

## 2. Hero / 3D / illustration sources

| Source | Licence (key terms) | Style | India vehicles? | Notes |
|---|---|---|---|---|
| **Microsoft Fluent Emoji 3D** (current stand-in) | MIT, © Microsoft. "Permission is hereby granted, free of charge … to use, copy, modify, merge, publish, distribute, sublicense, and/or sell … subject to: the above copyright notice and this permission notice shall be included." https://github.com/microsoft/fluentui-emoji/blob/main/LICENSE | Soft, toy-like 3D, 256 px PNG only | **Yes: auto-rickshaw**, motor scooter, motorcycle, car, taxi, SUV, oncoming car | Side view facing left, not 3/4. 256 px limit (the 2× assets are upscales, see CREDITS). Needs a licence notice in the app's licences screen (not wired up yet). |
| **3dicons.co** (Vijay Verma) | **CC0 1.0**: "you can use on any personal or commercial projects without any attribution required." https://3dicons.co/ , repo `LICENSE` https://github.com/realvjy/3dicons | Blender 3D; clay / colour / gradient / premium; 3 camera angles; 400 px PNG (Figma has more) | **No vehicles at all** | 120 icons ("1400+ renders"). Has rupee, wallet, map-pin, shield (`sheild`), mobile, calendar, gift, star, chat, tick. Good fit for payment/empty/success heroes. |
| Google Noto Emoji | Images **Apache-2.0**; fonts OFL-1.1. https://github.com/googlefonts/noto-emoji | Flat, bold colour | **Yes: auto-rickshaw** (best-reading one), scooter, cars (front view) | Flat, so it only fits Plan A-style flat heroes. Apache-2.0 needs the licence and NOTICE carried along. |
| OpenMoji | **CC BY-SA 4.0** (attribution + ShareAlike) https://openmoji.org | Outline-flat | Yes: auto-rickshaw | ShareAlike on modified art is a real obligation. Not recommended for brand art. |
| Kenney (Car Kit 3.1 etc.) | **CC0**: "You can use this content for personal, educational, and commercial purposes … crediting … is not a requirement." (`License.txt`, https://kenney.nl/assets/car-kit) | Low-poly game 3D, GLB/FBX/OBJ | No (sedan, hatchback-sports, SUV, taxi, van, police…) | Real 3D, so it can be re-lit and rendered at 3/4 in Blender in the clay style. Needs remodelling to look Indian and non-gamey. |
| Quaternius Cars | **CC0** (https://quaternius.com/packs/cars.html, poly.pizza) | Low-poly game 3D | No (taxi, police, SUV, 2 sports, 2 normal) | Same as Kenney. Clean shapes, Western cars. |
| Sketchfab auto-rickshaws | Mostly **CC BY 4.0** (attribution), not CC0. For example "Low Poly Autorickshaw aka TukTuk" by Nirmal.Justin, CC Attribution, 4.8k tris: https://sketchfab.com/3d-models/autorickshaw-c7c87455ad014b3f9fc8c9fb2d164a61 . Sketchfab's CC0 cars are mostly "concept car" series, not India-typical. | Varies | **Yes (CC BY)** | A usable base for a Blender auto render if the in-app credit is acceptable. Not downloaded (needs a login). Check each model's licence badge; some are "Standard"/NoAI or non-commercial. |
| Iconscout 3D | Free assets: **attribution required** and "limited commercial use" (from search snippets; https://iconscout.com/licenses returned 403, **not read directly**). Paid plan from ~$12/mo removes attribution. | Huge mixed catalogue, many artists | Some auto-rickshaw 3D packs exist | Mixed artists means mixed styles. Read the licence page yourself before relying on it. |
| Freepik (now **Magnific**) | Free: "conditioned upon any use … being duly attributed"; Premium: no attribution. **Both:** no use in "apps … aimed to be resold, in which the Content is the main element"; no trademark/logo use; no AI/ML use. Licences stay valid after the subscription ends. https://www.magnific.com/legal/terms-of-use | Huge, mixed | Many Indian auto/vehicle 3D packs | Usable for in-app illustration with Premium, but not exclusive (competitors can use the same art), and not for the logo. |
| Blush | Free illustrations: "irrevocable, nonexclusive, worldwide … download, copy, modify … without … attributing" (from search snippet; https://blush.design/license returned 403, **not read directly**). Pro ($12/mo) = SVG + large PNG. | Flat 2D, many artists' collections | No specific vehicles | Good for people/onboarding scenes; flat. |
| unDraw | Free commercial use, no attribution. **Forbids** compiling into a competing pack, AI/ML training, and automated scraping. https://undraw.co/license | Flat 2D, one accent colour | No | Recolour to teal in one click. Samples were **not** downloaded because the licence forbids automated download. |
| Open Peeps / Humaaans (Pablo Stanley) | **CC0** (from search snippets: https://www.openpeeps.com/ , https://www.humaaans.com/) | Hand-drawn / flat people | No | For people moments only (onboarding, support, referral). |

## Ranked recommendations

### (a) Utility icons
1. **Phosphor Regular + Fill** (keep; MIT; 12/13).
2. **Flutter `Icons.electric_rickshaw`** (Material, Apache-2.0) for the auto
   glyph until a custom Phosphor-style auto is drawn.
3. **Tabler** (MIT) as the backup family.

### (b) Ride-type vehicle art
1. **Commission the 3D set** (see section 3): Economy hatch, Comfort sedan,
   XL MPV, Premium, auto-rickshaw and bike, 3/4 view, clay, one scene file.
   This is the only route to India-typical vehicles (Swift/Dzire/Ertiga-like
   shapes, a Bajaj-style auto) in one style and at the brief's 3/4 angle.
2. **Keep the Fluent Emoji 3D stand-ins (MIT)** until then. They are already
   in the repo, consistent, legal (MIT notice still has to reach the licences
   screen), and include a real auto-rickshaw. Known faults: side-on not 3/4,
   256 px source, toy look.
3. **Self-render from CC0/CC-BY 3D models in Blender.** Use Kenney or
   Quaternius cars (CC0) plus a CC BY Sketchfab auto, with clay material and
   the brief's lighting, rendered at 512² and 3/4. It is free in money, but
   several days of Blender work, and the models are Western/low-poly, so they
   need remodelling to look Indian. Only worth it if someone on the team knows
   Blender. Blender cannot be run on this box today (`blender` not installed),
   so this is unverified.

### (c) Hero illustrations (payment, empty/success, safety, pre-book)
1. **Same commission as (b)**, so heroes and vehicles share one style.
2. **3dicons.co (CC0)** for the non-vehicle heroes. It has rupee coin,
   wallet, map-pin, shield, mobile, calendar, gift, star, tick and chat at
   400 px with a 3/4 angle and a clay finish that suits Plan B. **Caveat:** it
   will clash with the Fluent vehicles if both are on one screen. Use it only
   if the vehicles are also replaced, or keep it off the Choose-ride screen.
3. **Fluent Emoji 3D (MIT, current)** for heroes. It is consistent with the
   current vehicles and needs no change now. For flat Plan A, unDraw
   (recolour to teal) or Noto are the flat alternatives.

## 3. Commissioning a custom 3D set (India)

The brief's scope is 20 icons, one `.blend`, 512² masters, PNG 1×/2×/3×,
optional dark renders.

| Channel | Observed price | Source | Notes |
|---|---|---|---|
| Fiverr, entry-level Blender clay-icon gigs | from **$5–$20 per icon** (starting prices) | Gig titles in search results: fiverr.com/lanaaniep ($5), fiverr.com/bryanpamungkas ($10, "clay style… with blender"), fiverr.com/mahendrazulfa ($20; $50 "professional") | Gig pages returned 403, so tiers, source-file terms and commercial-use add-ons were **not** checked. Starting prices usually cover 1 simple icon. Vehicles are harder. |
| Fiverr Pro 3D artists (incl. India) | about **$30–$264 per project** | fiverr.com Pro 3D-artist listing (search snippet) | Vetted sellers. Ask for a `.blend` file and a copyright-assignment clause. |
| Upwork Blender / 3D artists | **$25–$40/h** typical, median ~$30/h; $25–$80/h for Blender work | https://www.upwork.com/hire/3d-artists/cost/ , https://www.upwork.com/hire/blender3d-freelancers/ | Global figures. India-only rates were not published on those pages. |
| Indian freelancers (Behance / direct) | icon design **$15–35 per icon** in South Asia; 3D/CGI projects **₹40,000–₹2,00,000** per project | Medium pricing guide (search snippet); https://nitinmonga.in/blog/how-much-should-a-freelance-designer-charge-in-india-in-2026/ | Behance "Hire" (https://www.behance.net/hire/services/icon-design) lists studios doing 3D icon sprints. Prices are quote-only. |

**Realistic estimate** (my synthesis, not a quote): a style-consistent
20-icon clay set with 5–6 vehicles from a competent Indian freelancer is
about **₹60,000–₹2,00,000** (roughly ₹3,000–₹10,000 per icon, which matches
the brief's own budget). Add about 30 % for a dark-mode render pass. Timeline:
about **1 week** for the 3-icon test (Economy car, rupee note, check) plus
revisions, then **2–4 weeks** for the rest. Bargain Fiverr gigs ($5–$20) are
fine for the 3-icon test but rarely hold one style across 20 icons.

**Contract must-haves:** full copyright assignment (not only a licence),
source `.blend` + textures, no stock or AI-generated parts without disclosure,
the right to recolour and re-render, and delivery at 512² with
the brief's camera and lighting. Run the 3-icon test with 2–3 artists in
parallel and pick one.

## Open items / not done
- Iconscout and Blush licence pages were blocked (HTTP 403). Their terms above
  come from search snippets and must be read by a human before use.
- Fiverr gig tiers could not be opened (403). Only starting prices are known.
- No Sketchfab model was downloaded (needs a login), and no Blender render
  was tried (Blender is not installed here).
- The contact sheet is saved at docs/brand/research/icons-contact.png.
