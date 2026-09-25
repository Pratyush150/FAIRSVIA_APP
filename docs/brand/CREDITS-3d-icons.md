# Credits: Daylight 3D hero icons (stand-in set)

These are **stand-ins** for the commissioned 3D clay set described in
`docs/plans/visual-direction-v2.md` (the "3D icon brief"). They are built from
**Microsoft Fluent Emoji 3D** artwork, recoloured and composited. They are not the
final commissioned art.

- Source repo: https://github.com/microsoft/fluentui-emoji, pinned to commit
  `1ffb34c752ecf5d402f04cfb4b392c77f57c54bc` (main as of 2026-08-24). Files were fetched from GitHub raw and
  jsDelivr (`cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@1ffb34c…`); the two hosts matched on the files spot-checked (auto-rickshaw PNG byte-identical; LICENSE text identical).
- Licence: **MIT**, © Microsoft Corporation. The licence file was downloaded from the
  repo root and checked: MIT permits commercial use, modification and
  distribution; the only condition is that the copyright notice and permission
  notice be included. Copies:
  `packages/design_system/assets/heroes/daylight/LICENSE-fluentui-emoji.txt` and
  `packages/design_system/assets/vehicles/daylight/LICENSE-fluentui-emoji.txt`.
  The app's open-source licences screen should also include this notice when the
  icons ship (not wired up yet).
- Font used in `cash.png`: Lato Black (Łukasz Dziedzic), SIL Open Font License 1.1 —
  only the "₹" glyph, rendered into the bitmap.
- Microsoft's name and logos are not used; the emoji artwork alone is MIT-licensed.

## Output format

Every file is a transparent RGBA PNG, 256×256 at 1x, with a 512×512 copy in
`2.0x/`. The subject fills about 80 % of the canvas on its longest side. The six
vehicles share one scale and one ground line (all face left, as in the source) so they
line up in the ride list.

**Resolution caveat:** the Fluent 3D PNGs are published at 256×256 only. The 512 px
versions are Lanczos **upscales** (effectively 2× from the 256 px source), so
they are softer than true 512 px renders. The 1x files are the sharp ones.

## Per-file sources and modifications

Paths are relative to `packages/design_system/assets/`.

| File | Source (Fluent Emoji 3D, MIT) | Modification |
|---|---|---|
| `vehicles/daylight/economy.png` (+ `2.0x/`) | [`assets/Automobile/3D/automobile_3d.png`](https://github.com/microsoft/fluentui-emoji/blob/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/assets/Automobile/3D/automobile_3d.png) | Red body recoloured to teal #2BC4C4 (hue mask, lightness remapped; windows, tyres, lights, bumper untouched). Placed at the shared vehicle scale/baseline. |
| `vehicles/daylight/comfort.png` (+ `2.0x/`) | [`assets/Taxi/3D/taxi_3d.png`](https://github.com/microsoft/fluentui-emoji/blob/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/assets/Taxi/3D/taxi_3d.png) | Roof taxi sign removed (roof rebuilt from adjacent columns); door checker pattern painted out (interpolated from surrounding paint); yellow body recoloured to slate #5B6B80; taillight kept red. |
| `vehicles/daylight/xl.png` (+ `2.0x/`) | [`assets/Sport utility vehicle/3D/sport_utility_vehicle_3d.png`](https://github.com/microsoft/fluentui-emoji/blob/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/assets/Sport%20utility%20vehicle/3D/sport_utility_vehicle_3d.png) | Blue body recoloured to sand #E8D5B5. Windows protected by hand-drawn masks (window and body blues overlap in hue). Roof rack, spare wheel, bumper untouched. |
| `vehicles/daylight/premium.png` (+ `2.0x/`) | [`assets/Police car/3D/police_car_3d.png`](https://github.com/microsoft/fluentui-emoji/blob/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/assets/Police%20car/3D/police_car_3d.png) | Roof light bar removed; black and grey police panels both recoloured to graphite #3A3D42 (per-panel lightness reference so it reads as one paint colour; highlights boosted so it reads on white). Panel seams remain as thin shut lines. |
| `vehicles/daylight/driver.png` (+ `2.0x/`) | [`assets/Automobile/3D/automobile_3d.png`](https://github.com/microsoft/fluentui-emoji/blob/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/assets/Automobile/3D/automobile_3d.png) | Same as economy, body recoloured to light grey #D9DDE2. |
| `vehicles/daylight/auto.png` (+ `2.0x/`) | [`assets/Auto rickshaw/3D/auto_rickshaw_3d.png`](https://github.com/microsoft/fluentui-emoji/blob/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/assets/Auto%20rickshaw/3D/auto_rickshaw_3d.png) | Original colours; scaled to the shared vehicle scale/baseline only. |
| `heroes/daylight/cash.png` (+ `2.0x/`) | [`assets/Dollar banknote/3D/dollar_banknote_3d.png`](https://github.com/microsoft/fluentui-emoji/blob/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/assets/Dollar%20banknote/3D/dollar_banknote_3d.png) | "$" glyph painted out; "₹" drawn in its place with Lato Black (SIL Open Font License 1.1; glyph rendered into the image). Note colour unchanged. |
| `heroes/daylight/upi.png` (+ `2.0x/`) | [`assets/Mobile phone/3D/mobile_phone_3d.png`](https://github.com/microsoft/fluentui-emoji/blob/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/assets/Mobile%20phone/3D/mobile_phone_3d.png)<br>[`assets/Check mark button/3D/check_mark_button_3d.png`](https://github.com/microsoft/fluentui-emoji/blob/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/assets/Check%20mark%20button/3D/check_mark_button_3d.png) | Composite: phone with the check-mark button as a bottom-right badge, soft drop shadow added under the badge. |
| `heroes/daylight/card.png` (+ `2.0x/`) | [`assets/Credit card/3D/credit_card_3d.png`](https://github.com/microsoft/fluentui-emoji/blob/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/assets/Credit%20card/3D/credit_card_3d.png) | Re-padded only. |
| `heroes/daylight/add_stop.png` (+ `2.0x/`) | [`assets/Round pushpin/3D/round_pushpin_3d.png`](https://github.com/microsoft/fluentui-emoji/blob/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/assets/Round%20pushpin/3D/round_pushpin_3d.png)<br>[`assets/Plus/3D/plus_3d.png`](https://github.com/microsoft/fluentui-emoji/blob/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/assets/Plus/3D/plus_3d.png) | Composite: pushpin with a small plus at top-right, soft shadow under the plus. |
| `heroes/daylight/prebook.png` (+ `2.0x/`) | [`assets/Spiral calendar/3D/spiral_calendar_3d.png`](https://github.com/microsoft/fluentui-emoji/blob/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/assets/Spiral%20calendar/3D/spiral_calendar_3d.png)<br>[`assets/Check mark button/3D/check_mark_button_3d.png`](https://github.com/microsoft/fluentui-emoji/blob/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/assets/Check%20mark%20button/3D/check_mark_button_3d.png) | Composite: spiral calendar with the check-mark button badge (calendar-check). |
| `heroes/daylight/search_car.png` (+ `2.0x/`) | [`assets/Automobile/3D/automobile_3d.png`](https://github.com/microsoft/fluentui-emoji/blob/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/assets/Automobile/3D/automobile_3d.png)<br>[`assets/Magnifying glass tilted left/3D/magnifying_glass_tilted_left_3d.png`](https://github.com/microsoft/fluentui-emoji/blob/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/assets/Magnifying%20glass%20tilted%20left/3D/magnifying_glass_tilted_left_3d.png) | Composite: the teal economy car (recoloured as above) with the magnifying glass over its roof, soft shadow under the glass. |
| `heroes/daylight/no_cars.png` (+ `2.0x/`) | [`assets/Automobile/3D/automobile_3d.png`](https://github.com/microsoft/fluentui-emoji/blob/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/assets/Automobile/3D/automobile_3d.png)<br>[`assets/Zzz/3D/zzz_3d.png`](https://github.com/microsoft/fluentui-emoji/blob/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/assets/Zzz/3D/zzz_3d.png) | Composite "sleeping car": the light-grey driver car with Zzz above it. |
| `heroes/daylight/done.png` (+ `2.0x/`) | [`assets/Check mark button/3D/check_mark_button_3d.png`](https://github.com/microsoft/fluentui-emoji/blob/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/assets/Check%20mark%20button/3D/check_mark_button_3d.png) | Re-padded only. |
| `heroes/daylight/safety.png` (+ `2.0x/`) | [`assets/Shield/3D/shield_3d.png`](https://github.com/microsoft/fluentui-emoji/blob/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/assets/Shield/3D/shield_3d.png) | Re-padded only. |
| `heroes/daylight/wallet.png` (+ `2.0x/`) | [`assets/Purse/3D/purse_3d.png`](https://github.com/microsoft/fluentui-emoji/blob/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/assets/Purse/3D/purse_3d.png) | Re-padded only. |
| `heroes/daylight/gift.png` (+ `2.0x/`) | [`assets/Wrapped gift/3D/wrapped_gift_3d.png`](https://github.com/microsoft/fluentui-emoji/blob/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/assets/Wrapped%20gift/3D/wrapped_gift_3d.png) | Re-padded only. |
| `heroes/daylight/star.png` (+ `2.0x/`) | [`assets/Star/3D/star_3d.png`](https://github.com/microsoft/fluentui-emoji/blob/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/assets/Star/3D/star_3d.png) | Re-padded only. |

## How the recolouring was done

Python with PIL and numpy. Body paint was picked out by hue and saturation (soft
edges, so no hard fringes). Lights, windows and wheels were kept out with
hand-placed masks where the hues overlapped. The paint's shading was then mapped
onto the target colour, so highlights and shadows stay. Build scripts were kept in
the session scratchpad and are not in the repo.

## MIT licence text (Fluent Emoji)

```
    MIT License

    Copyright (c) Microsoft Corporation.

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE
```

## Realistic Home tiles (2026-09-25)

`packages/design_system/assets/home/` and `home_dark/` (ride, prebook, someone_else,
saved, add_stop, coins, star, tag) are now original Blender 4.2 Cycles renders,
built procedurally by the scripts in `docs/brand/icons-realistic/` (no third-party
models). The only third-party input is the lighting environment:

- HDRI **"Studio Small 09"** from Poly Haven (https://polyhaven.com/a/studio_small_09),
  2k .hdr, licence **CC0** (public domain, no attribution required; credited here
  anyway). Downloaded at render time to `~/.cache/ridevela-3d/`, not committed.
- Printed text on the calendar page / tag uses Lato Black (SIL OFL 1.1), rasterised.
