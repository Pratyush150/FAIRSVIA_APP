# Ride-list vehicle photos: sources and licences

All four car tiers are white (owner request, 2026-09-25), so the list reads as one set.

The vehicle pictures in the rider's "choose a ride" list (and the driver card,
receipts and trip history, which use the same `VehicleGlyph`) are cut-outs made
from free-licence photos (Unsplash, plus one Wikimedia Commons CC BY 4.0 photo for economy). Files: `packages/design_system/assets/vehicles/photo/`
(light sheet) and `photo_dark/` (dark sheet), each at 1x / `2.0x/` / `3.0x/`,
WebP with alpha, 120x75 logical px (16:10). Each file is 2–20 KB; the whole set (6 tiers + driver, light + dark, 3 densities) is about 350 KB, against about 2.1 MB for the clay renders it replaces in the bundle.

Five of the six photos came from Unsplash search results filtered to free-licence photos (`license=free`), none marked Unsplash+, so they are under the
Unsplash License: https://unsplash.com/license. Commercial use is allowed and
attribution is not required. We record the sources anyway.
The economy photo is from Wikimedia Commons under CC BY 4.0, which DOES require
attribution: credit Renée Kools, link the licence, and note it was modified
(see its row below; ship this line in the app's licences/credits screen).

| File | Class | Source photo | What we changed |
|---|---|---|---|
| `economy.webp` | Compact hatchback | https://commons.wikimedia.org/wiki/File:White_Opel_Karl_side_view.jpg (white Opel Karl, pure side view). Attribution: "White Opel Karl side view" by Renée Kools, licensed CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/), via Wikimedia Commons; modified (background removed, logos painted out, resized). Chosen so the hatchback is side-on like comfort, premium and xl. | Background removed (rembg birefnet-general). Maker logos on the two wheel covers painted out. No plate or lettering visible. Already faces left; not mirrored. |
| `comfort.webp`, `driver.webp` | Sedan | https://unsplash.com/photos/AbAcKL3iFEM (white sedan, pure side view, by pha tran / @alanka, Unsplash License). Chosen so the sedan is side-on like premium and xl. | Background removed (rembg birefnet-general). Maker logos on the wheel centre caps painted out. No plate visible. Already faces left; not mirrored. |
| `premium.webp` | Premium sedan | https://unsplash.com/photos/kb9dTYzZuiQ ("White sedan on wet road beside green grass", white Toyota Mark II-era sedan, pure side view) | Background removed. The photo's green film grade neutralised so the paint reads white. No badge, lettering or plate is visible from this angle. |
| `xl.webp` | 7-seat SUV (XL) | https://unsplash.com/photos/2xqFLkR0f4Y ("A white SUV parked in a parking lot with dark alloy wheels", large three-row body-on-frame SUV, pure side view) | Background removed. No badge, lettering or plate is visible from this angle. Mirrored to face left. |
| `auto.webp` | Auto-rickshaw | https://unsplash.com/photos/wiug8R9aZSQ ("black and yellow vehicle near yellow wall and red door") | Background removed. Registration plate refilled as a blank plate. Mirrored to face left. |
| `bike.webp` | Bike taxi | https://unsplash.com/photos/pQ3oaH_EQhI ("A blue and black motorcycle parked outdoors", Yamaha MT-09) | Background removed. Tank emblem, "MT-09" decal and "YAMAHA" fender lettering painted out. |

For every file we also: trimmed to the vehicle, placed it on a shared ground line
inside a transparent 16:10 canvas with a margin (the app shows it with
`BoxFit.contain`, so nothing is ever cropped), and added a soft contact shadow.
The dark-sheet copies lift the paint by 12 % and use a faint light floor glow
in place of the dark shadow, so graphite and navy bodies keep their shape on the
dark glass sheet.

How we made them: backgrounds were removed with rembg `birefnet-general`, then
`docs/brand/vehicles/photo/build.py` did the rest (badge inpainting with OpenCV
Telea, blank plates, mirroring, framing, shadows, WebP export). The source
photos are not committed; the script's docstring says how to fetch them.

Licence notes and caveats:
- **Unsplash License:** free for commercial and non-commercial use, no attribution
  required. You may not sell unaltered copies or build a competing stock service.
- **Trade dress:** these are real, recognisable models (VW Golf, Hyundai Sonata, a
  Toyota sedan, a large three-row SUV, Yamaha MT-09). We removed the badges, lettering and
  plate text we could find, but the stock licence gives no rights to a vehicle's
  design or trademarks. Tiny wheel-cap logos may remain on some wheels; at the
  list size (76 px wide) they are under one pixel. If legal wants zero brand
  association, replace these with generic renders.
- No Ola or Uber images, logos or text were used.
