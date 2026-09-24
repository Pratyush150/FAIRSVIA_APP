import re
SP="/tmp/claude-1000/-home-nova-robotics-ubernav/32b0b03b-f246-44cd-933a-739a28167dfc/scratchpad/palettes"
con=open('contrast_out.md').read()
def contrast(n):
    m=re.search(r"## "+re.escape(n)+r"\n(.*?)(?=\n## |\nREQUIRED)",con,re.S); return m.group(1).strip()
tok=open('tokens_out.md').read()
def tokens(n):
    m=re.search(r"### "+re.escape(n)+r"\n(.*?)(?=\n### |\Z)",tok,re.S); return m.group(1).strip()
snip=lambda f: open(f"snip_{f}.md").read()
from palettes_def import P
deltae=open('deltae_out.md').read().strip()
cvd=open('cvd_out.md').read().strip()

INFO={
"ikat-indigo":("Ikat Indigo","indigo",
"""**Why it works.** No ride-hailing brand in India or Central Asia owns indigo. It reads calm and premium, and it has real roots in both markets: Indian indigo dye and Uzbek ikat (*abr*) silk, which is indigo plus saffron. Keep a marigold `#F5A524` for illustrations and 3D icons only, never for UI state. It separates best from the semantic colours of any option: ΔE00 is 27 or more everywhere, and it still holds at 39+ under simulated protan/deutan vision. The route contrast is strong (4.31 light, 6.68 dark).

**Risks, stated honestly.**
- **PhonePe purple (`#5F259F`) is the biggest payments brand in India**, and its logo will appear next to our buttons on the UPI screens. Our indigo is bluer and brighter (hue ~250° against PhonePe's ~275°), but some people may still think "PhonePe" at first sight.
- Careem uses `#3837E4` for its Go/ride sub-brand, which is close. Careem does not operate in India or Uzbekistan today, so the clash is low-risk.
- In the mock, the dark-mode button (`#A898FF` lavender) looks a little pastel. A more saturated `#9C8CFF` would still pass (it needs a re-check) if the owner wants more punch."""),
"registan-lapis":("Registan Lapis & Gold","lapis",
"""**Why it works.** This is the most Samarkand of the five: lapis-blue tiles and gold. The light mode is very legible (route 4.77:1). The dark mode's gold route on a navy map is the most striking image in the contact sheet.

**Risks, stated honestly.**
- **Blue already has a job in this app.** The system location dot is blue (foundation rule 2 in visual-direction-v2), and so is `info` `#276EF1`. In light mode a lapis route would sit next to a blue "you are here" dot, so we would have to change the dot or the rule.
- In India a blue primary looks like fintech or government (Paytm, many bank apps). It is professional but not memorable.
- **The gold dark highlight collapses into the warning colour under CVD** (ΔE 6.4 deutan, 11.1 protan). Warnings must always carry an icon and a label. Colour alone is not enough.
- Gold is close to the Yandex Go yellow family, and Yandex Go is the market leader in Uzbekistan. Using it only in dark mode, only as a line, keeps the risk small but real."""),
"marigold":("Marigold","marigold",
"""**Why it works.** This is the most emotional and the most Indian option: marigold garlands, saffron, festival light. In Uzbekistan it maps to apricots and sun. The light mode is warm and distinctive, and the route passes at 3.19:1, the smallest margin of the five.

**Risks, stated honestly.**
- **Warm crowding.** An orange brand leaves no room for a conventional amber warning or a red danger. I moved warning to olive-gold (`#7A5C00` / `#E8E05A`) and danger to crimson (`#BE185D` / `#FF5C8A`). They now pass ΔE00 ≥ 20, but under simulated protan vision the highlight and warning are only 7.0 (light) and 7.9 (dark) apart. Warning must never rely on colour alone.
- **Brand adjacency.** Swiggy orange (`#FC8019`) owns orange on Indian phones, and the dark-mode `#FF9F43` button sits near Yandex Go's yellow-orange in Uzbekistan. Rapido `#FFCC0F` is yellower. The deep saffron light ink `#B8430A` is safer than the dark ink.
- The light ink only passes 5.46:1 with white. That is fine, but it leaves little room for a lighter tweak."""),
"bukhara-copper":("Bukhara Copper","copper",
"""**Why it works.** This is the premium option. Buttons are graphite, and one warm copper signature is used for the route, the selection and the dark-mode ink. It has the least visual noise, and dark mode (copper button, 7.34:1) looks rich.

**Risks, stated honestly.**
- **Light mode is Uber's look**: a black pill button on white. With the Road-V logo recoloured, the brand is carried only by the route and the selection outline.
- **Copper is next to amber.** Before retuning, the light highlight `#B4541E` was ΔE **2.9** from the old warning, so I moved warning to `#7A6200` and danger to crimson. Under simulated protan vision the light highlight and warning are still only **1.9** apart, which means indistinguishable, so warning needs an icon and a label.
- Dark copper sits close to Marigold's dark mode. They are not really two different directions."""),
"anor-garnet":("Anor (Pomegranate) Garnet","garnet",
"""**Why it works.** The pomegranate (*anor*) is a strong Central Asian symbol, and garnet is rich and unlike any ride competitor. Light mode reads like a premium lifestyle brand.

**Risks, stated honestly. This is why it ranks last.**
- **A red-family brand in a safety app.** SOS and destructive actions are red by rule. I moved danger to orange-red (`#C2410C` / `#FF6A3D`) and warning to olive-gold to keep ΔE00 ≥ 20, but under simulated deutan vision brand and danger are only 17–19 apart. An SOS button must never look like a booking button.
- The dark-mode pink (`#FF6B94`) reads as Lyft or a dating app. Lyft does not operate in these markets, but the association is common.
- "Red car" and "red button" also carry cultural weight (danger, stop) that works against "confirm your ride"."""),
}
ORDER=["ikat-indigo","registan-lapis","marigold","bukhara-copper","anor-garnet"]

out=[]
A=out.append
A("""# RideVela colour palette options (beyond Samarkand Turquoise)

*Prepared 2026-09-24 for the owner. This is a design proposal only: **no code or existing files were changed.** Every contrast number here was computed by a script (WCAG 2.x relative luminance), not estimated; the scripts sit next to the mocks (see "Reproduce"). The mock PNGs are in the session scratchpad, not in the repo.*

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

Contact sheet (current turquoise baseline at top-left, then the five): `""" + SP + """/all.png`

![all palettes](""" + SP + """/all.png)
""")
for i,n in enumerate(ORDER,1):
    title,flag,body=INFO[n]
    A(f"""### {i}. {title}: `THEME={flag}`

*{P[n]['story']}*

Mock: `{SP}/{n}.png`

![{title}]({SP}/{n}.png)

{body}

**Tokens**

{tokens(n)}

**Computed contrast (WCAG ratio)**

{contrast(n)}

**Build it as a theme variant.** Snippet only, not applied. It follows the existing const-conditional mechanism on `AppColors.variant` in `packages/design_system/lib/src/theme/app_colors.dart`:

{snip(flag)}
""")
A(f"""## 4. What else a new variant touches (outside `app_colors.dart`)

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

{deltae}

Simulated colour-vision deficiency (Machado 2009, severity 1.0). Values below ~10 mean the pair is effectively the same colour for that viewer:

{cvd}

**Takeaway:** the warm options (Marigold, Copper, Lapis-dark gold) cannot use colour alone to tell "your route / selected" apart from "warning" for colour-blind riders; about 8 % of men have red-green CVD. Indigo, and Lapis in light mode, stay above 39 in every case. Whatever palette is picked, warnings and SOS should always carry an icon and a text label. The app largely does this already.

## 6. Reproduce

All inputs and scripts are in `{SP}/`:
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
""")
open('/home/nova-robotics/ubernav/docs/plans/colour-palette-options.md','w').write("\n".join(out))
print("written")
