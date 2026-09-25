# UI plans (candidates — owner decides after trying builds on real phones)

| Plan | File | Status |
|---|---|---|
| Audit — path to 10/10 (bugs, trust, tokens, motion) | [ui-10-audit-plan.md](ui-10-audit-plan.md) | Shared foundation — being implemented for every direction |
| Visual Direction v2 — A Midnight Teal / B Daylight 3D / C Day & Night | [visual-direction-v2.md](visual-direction-v2.md) | Each direction built as a separate test build (`--dart-define=THEME=...`) for side-by-side phone trials |

More plans from the owner are added here; nothing is final until chosen.

## Added 2026-09-24 — more options to choose from

| File | What |
|---|---|
| `visual-direction-v3-research.md` | Plans **D Local Colour** (India-vivid), **E Ink & Paper** (editorial premium), **F Map Glass** (map-first translucent), from research on Uber/Ola/Rapido/Bolt/Yandex Go/inDrive… with sources |
| `colour-palette-options.md` | Five palettes with computed contrast: **Ikat Indigo** (top pick), Registan Lapis & Gold, Marigold, Bukhara Copper, Anor Garnet — mocks in `docs/brand/research/` |
| `icons-and-illustration-options.md` | Icon families, 3D/vehicle art sources + licences, commissioning cost (~₹0.6–2 lakh, 3–5 weeks) |

Built and on the Realme today: turquoise (current), A Midnight, B Daylight,
C Day&Night. D/E/F and the new palettes are proposals — each can become a
`THEME=` build in about a day once picked.

**Finding to act on regardless of the pick:** the shipped light route colour
#0FA3A8 is only 2.49:1 against the light map (target 3:1); success/warning
text colours are under 4.5:1 — see colour-palette-options.md.

## DECISION 2026-09-25 — final look: Plan F "Map Glass"

The owner picked **F (Map Glass)** after comparing all looks on a real phone.
It is now the default build (`AppColors.variant` defaults to `glass`); git tag
**`ui-final-glass-v2.0.0`** marks the baseline we iterate on. Other looks stay
in code behind `THEME=` (turquoise = the previous default) but are not shipped.
Appearance switching is no longer held during a ride (owner: it must change
whenever the user wants, without affecting anything else).
