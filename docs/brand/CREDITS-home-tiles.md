# Home service-tile images: sources and licences

These four tiles (in `home/`, `home/2.0x/`, `home_dark/`, `home_dark/2.0x/`) are
cut-outs made from free-licence stock images. All the licences allow commercial
use with no attribution required; we record the sources here anyway.

| Tile | Source | Author | Licence | What we changed |
|---|---|---|---|---|
| `ride.png` | https://unsplash.com/photos/a-white-car-on-a-white-background-oa68pmfG-qk | Hyundai Motor Group (unsplash.com/@hyundaimotorgroup) | Unsplash License (https://unsplash.com/license), not Unsplash+ | Cropped. Removed the grille badge and the "SONATA" plate text (plate left blank). Background removed with rembg `birefnet-general`. Graded, reframed, new contact shadow. |
| `prebook.png` | https://unsplash.com/photos/a-calendar-with-the-word-jan-on-it-z5pClnWen9M | Behnam Norouzi | Unsplash License, not Unsplash+ | Background removed. Printed content (month, year "2023", date grid) wiped to a fitted paper surface, then reprinted with a teal header strip and a large "25" in Inter ExtraBold. Slight lean-back perspective, graded, shadow. |
| `someone_else.png` | https://unsplash.com/photos/a-close-up-of-a-cell-phone-on-a-white-surface-sXVzE285xo0 | 2H Media (unsplash.com/@2hmedia) | Unsplash License, not Unsplash+ | Background removed. Our own light screen showing two teal avatars and buttons, perspective-warped onto the blank black screen, with the glass sheen kept. Graded, shadow. |
| `saved.png` | https://pixabay.com/illustrations/location-icon-hd-8k-4k-plastic-9546695/ (CDN file `location-icon-9546695_1280.png`) | Pixabay upload; the page names no author | Pixabay Content License (https://pixabay.com/service/license-summary/) | This is a realistic 3D render, not a photograph, supplied as a transparent PNG. Red recoloured to brand teal. Graded, reframed, shadow. |

Licence notes:
- **Unsplash License:** free to use for commercial and non-commercial purposes, attribution
  not required. You may not sell unaltered copies or build a competing stock service.
- **Pixabay Content License:** free to use, attribution not required. You may not sell
  unaltered copies or use the image in a trademark or logo. We do neither: this is a UI illustration.
- **Trade-dress caveat (ride):** the car is a real, recognisable model (Hyundai Sonata). We
  removed the badge and plate text, but the stock licence does not give any rights to a
  vehicle's design or trademarks. If legal wants zero brand association, replace
  it with a generic render.

We processed the images with scripts in `docs/brand/research/home-tiles-photo-src/`
(`car_edit.py`, `phone.py`, `build.py`).
