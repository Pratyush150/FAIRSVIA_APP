"""RideVela glyph sources — Phosphor 256 grid, y down. See build.py."""


def circle(cx, cy, r):
    return (f"M{cx - r},{cy} A{r},{r} 0 1 0 {cx + r},{cy} "
            f"A{r},{r} 0 1 0 {cx - r},{cy} Z")


# ---------------------------------------------------------------- autoRickshaw
# Side-on, facing right like Phosphor's motorcycle/scooter/van. Reads as an
# auto by: domed canvas canopy, tall body on small wheels, open side down to
# the floor, no bonnet, handlebar behind the windshield, rear passenger panel.
# (Side-on shows one rear wheel; a front view with all three was tried and
# read as a bus shelter, not a vehicle.)
AUTO_WHEEL_R = 20
AUTO_WHEELS = [(60, 188), (208, 188)]
# The canopy's front visor overhangs a raked windshield; below it the nose
# bulges forward (no bonnet) and drops onto the single front wheel. The rear
# is one rounded canopy-to-body curve; the floor runs rear to front wheel.
AUTO_BODY = ("M230,166 C238,160 242,150 240,140 C238,128 230,120 216,116 "
             "L184,56 L192,44 C150,38 110,38 72,42 C40,46 20,70 20,104 V174 "
             "C20,184 28,188 40,188 H188")
AUTO_PANEL = "M20,124 H76 C92,124 104,136 104,152 V188"
AUTO_BAR = "M216,116 L182,124"

auto_regular = (
    [("stroke", AUTO_BODY), ("stroke", AUTO_PANEL), ("stroke", AUTO_BAR)]
    + [("stroke", circle(x, y, AUTO_WHEEL_R)) for x, y in AUTO_WHEELS]
    + [("cut", circle(x, y, AUTO_WHEEL_R - 8)) for x, y in AUTO_WHEELS]
)
auto_fill = (
    [("stroke", AUTO_BODY), ("stroke", AUTO_PANEL), ("stroke", AUTO_BAR),
     ("fill", AUTO_PANEL + " H40 C28,188 20,184 20,174 Z"),
     ("fill", "M20,104 C20,70 40,46 72,42 C110,38 150,38 194,44 L186,54 L196,72 H30 Z")]
    + [("stroke", circle(x, y, AUTO_WHEEL_R)) for x, y in AUTO_WHEELS]
    + [("cut", circle(x, y, AUTO_WHEEL_R - 8)) for x, y in AUTO_WHEELS]
)

# Light weight (Plan E "Ink & Paper", THEME=ink): Phosphor Light draws on
# the same grid with a 12-unit stroke, so the rings cut 6 in from the centre
# line instead of 8.
auto_light = (
    [("stroke", AUTO_BODY, 12), ("stroke", AUTO_PANEL, 12), ("stroke", AUTO_BAR, 12)]
    + [("stroke", circle(x, y, AUTO_WHEEL_R), 12) for x, y in AUTO_WHEELS]
    + [("cut", circle(x, y, AUTO_WHEEL_R - 6)) for x, y in AUTO_WHEELS]
)

GLYPHS = [
    {"name": "autoRickshaw", "codepoint": 0xF8F0,
     "regular": auto_regular, "fill": auto_fill, "light": auto_light},
]

# ------------------------------------------------------------------- bikeTaxi
# Not added. Trials (Phosphor's motorcycle + a helmet; + a seated rider in
# person-simple-bike style; a rider + pillion on a drawn bike) all collapse
# into a blob at 20-24 px where the cue meets the frame — see
# docs/brand/research/glyphs-biketaxi-trials.png. Use Phosphor `motorcycle`.

# ------------------------------------------------------------------ cashRupee
# Banknote (frame like Phosphor's `money`, a little taller so the ₹ fits at
# full stroke weight) with a ₹ drawn on the grid in Phosphor's currency-inr
# construction: two bars, a half-round bowl, a diagonal leg.
NOTE = "M24,48 H232 A8,8 0 0 1 240,56 V200 A8,8 0 0 1 232,208 H24 A8,8 0 0 1 16,200 V56 A8,8 0 0 1 24,48 Z"
RUPEE = [
    "M100,80 H160",
    "M100,108 H160",
    "M100,80 H116 A28,28 0 0 1 116,136 H100 L148,176",
]


# Corner flourishes, as on Phosphor's `money`, so it reads as a note.
CORNERS = [
    "M16,88 A40,40 0 0 0 56,48", "M200,48 A40,40 0 0 0 240,88",
    "M240,168 A40,40 0 0 0 200,208", "M56,208 A40,40 0 0 0 16,168",
]


CORNER_FILLS = [
    "M16,48 H56 A40,40 0 0 1 16,88 Z", "M240,48 V88 A40,40 0 0 1 200,48 Z",
    "M240,208 H200 A40,40 0 0 1 240,168 Z", "M16,208 V168 A40,40 0 0 1 56,208 Z",
]


def _cash(fill):
    ops = [("stroke", NOTE)] + [("stroke", d) for d in RUPEE + CORNERS]
    if fill:
        # Phosphor money-fill's language: solid corners, open field, solid
        # mark (the ₹ where money has its coin). A solid note with a
        # knocked-out ₹ was ~1.9x money-fill's ink.
        ops += [("fill", d) for d in CORNER_FILLS]
    return ops


def _cash_light():
    return [("stroke", NOTE, 12)] + [("stroke", d, 12) for d in RUPEE + CORNERS]


GLYPHS.append({"name": "cashRupee", "codepoint": 0xF8F2,
               "regular": _cash(False), "fill": _cash(True),
               "light": _cash_light()})
