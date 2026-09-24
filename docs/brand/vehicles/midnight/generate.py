#!/usr/bin/env python3
"""RideVela Plan A 'Midnight Teal' vehicle illustrations.

Each car is a tiny 3D model (extruded side profiles, planar faces) projected
with one fixed orthographic 3/4 camera, then drawn as flat-shaded SVG. The
shared camera, light, stroke widths and framing are what keep the set
consistent; the per-car profiles are what make the tiers read differently.
"""
import math, os, sys

OUT = sys.argv[1] if len(sys.argv) > 1 else '.'

# ---------------------------------------------------------------- camera
AZ = math.radians(58)   # 0 = looking at the nose, 90 = pure side view
EL = math.radians(21)   # camera elevation above the ground plane
C = (math.cos(EL) * math.cos(AZ), math.cos(EL) * math.sin(AZ), math.sin(EL))
F = (-C[0], -C[1], -C[2])
def norm(v):
    l = math.sqrt(sum(a * a for a in v)); return tuple(a / l for a in v)
def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def dot(a, b): return sum(x*y for x, y in zip(a, b))
RIGHT = norm(cross(F, (0, 0, 1)))
UP = cross(RIGHT, F)
LIGHT = norm((0.30, 0.75, 0.85))

W_CANVAS, H_CANVAS = 512, 320
BASELINE = 268          # screen y of the lowest tyre contact
FILL_W = 0.80           # subject width as a fraction of canvas
OUTLINE_W = 2.6         # silhouette stroke (px @1x)
LINE_W = 1.1            # interior detail lines

def raw(p):
    return (dot(p, RIGHT), -dot(p, UP))

# ---------------------------------------------------------------- colour
def hx(c): return tuple(int(c[i:i+2], 16) for i in (1, 3, 5))
def tohex(t): return '#%02X%02X%02X' % tuple(max(0, min(255, round(v))) for v in t)
def mix(a, b, t):
    a, b = hx(a), hx(b); return tohex(tuple(a[i] + (b[i]-a[i]) * t for i in range(3)))

# ---------------------------------------------------------------- geometry
def newell(poly):
    n = [0.0, 0.0, 0.0]
    for i in range(len(poly)):
        a, b = poly[i], poly[(i+1) % len(poly)]
        n[0] += (a[1]-b[1])*(a[2]+b[2]); n[1] += (a[2]-b[2])*(a[0]+b[0]); n[2] += (a[0]-b[0])*(a[1]+b[1])
    return norm(n)

def centroid(pts): return tuple(sum(p[i] for p in pts)/len(pts) for i in range(len(pts[0])))

def solid(profile, wfun, tags=None):
    """Extrude an (x,z) CCW profile across y with half-width wfun(z).
    Returns visible faces [(pts3d, normal, tag)]."""
    P = [(x, wfun(x, z)/2, z) for x, z in profile]
    M = [(x, -wfun(x, z)/2, z) for x, z in profile]
    faces = [(P[::-1], 'side'), (M, 'farside')]
    n = len(profile)
    for i in range(n):
        j = (i+1) % n
        faces.append(([P[i], P[j], M[j], M[i]], (tags or {}).get(i, 'body')))
    cen = centroid(P + M)
    out = []
    for pts, tag in faces:
        nn = newell(pts)
        if dot(nn, tuple(a-b for a, b in zip(centroid(pts), cen))) < 0:
            nn = tuple(-a for a in nn)
        if dot(nn, C) > 1e-6:
            out.append((pts, nn, tag))
    return out

def inset(poly, ds):
    """Offset a CCW convex polygon inward; ds[i] is the inset for edge i."""
    n = len(poly); lines = []
    for i in range(n):
        a, b = poly[i], poly[(i+1) % n]
        dx, dy = b[0]-a[0], b[1]-a[1]; l = math.hypot(dx, dy)
        nx, ny = -dy/l, dx/l
        d = ds[i]
        lines.append(((a[0]+nx*d, a[1]+ny*d), (dx, dy)))
    out = []
    for i in range(n):
        (p1, d1), (p2, d2) = lines[i-1], lines[i]
        den = d1[0]*d2[1]-d1[1]*d2[0]
        t = ((p2[0]-p1[0])*d2[1]-(p2[1]-p1[1])*d2[0]) / den
        out.append((p1[0]+d1[0]*t, p1[1]+d1[1]*t))
    return out

def clip(subject, clipper):
    """Sutherland-Hodgman, clipper convex CCW."""
    def inside(p, a, b): return (b[0]-a[0])*(p[1]-a[1]) - (b[1]-a[1])*(p[0]-a[0]) >= 0
    def inter(p, q, a, b):
        x1, y1 = p; x2, y2 = q; x3, y3 = a; x4, y4 = b
        den = (x1-x2)*(y3-y4)-(y1-y2)*(x3-x4)
        t = ((x1-x3)*(y3-y4)-(y1-y3)*(x3-x4))/den
        return (x1+t*(x2-x1), y1+t*(y2-y1))
    out = subject
    for i in range(len(clipper)):
        a, b = clipper[i], clipper[(i+1) % len(clipper)]
        inp, out = out, []
        if not inp: break
        for k in range(len(inp)):
            p, q = inp[k], inp[(k+1) % len(inp)]
            if inside(q, a, b):
                if not inside(p, a, b): out.append(inter(p, q, a, b))
                out.append(q)
            elif inside(p, a, b):
                out.append(inter(p, q, a, b))
    return out

def xband(x0, x1, z0=-9, z1=9):
    return [(x0, z0), (x1, z0), (x1, z1), (x0, z1)][::-1]  # CCW with x forward=right? see below

def box_ccw(x0, x1, z0, z1):
    # CCW in (x,z) with x to the right, z up
    return [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]

# ---------------------------------------------------------------- palettes
PALETTES = {
    'silver': dict(hi='#F7F9FA', lo='#7E868F', glass_top='#3A4A52', glass_bot='#0F1519',
                   trim='#2A2E33', outline='#4B525A', accent='#2BC4C4', crease='#8C949C'),
    'graphite': dict(hi='#9AA2AA', lo='#33383E', glass_top='#2E3A40', glass_bot='#0B0F12',
                     trim='#1C1F23', outline='#2A2E33', accent='#2BC4C4', crease='#4D545B'),
    'neutral': dict(hi='#F2F3F4', lo='#8A8D91', glass_top='#3D4043', glass_bot='#141517',
                    trim='#2B2D30', outline='#55585C', accent=None, crease='#95989C'),
}

def shade(pal, n, bias=0.0):
    t = (dot(n, LIGHT) - 0.05) / 0.85 + bias
    return mix(pal['lo'], pal['hi'], max(0.0, min(1.0, t)))

# ---------------------------------------------------------------- car specs
# x forward (nose = +x), z up, metres. Profiles are CCW in (x, z).
def mk(L, W, H, R, fa_off, wb, belt, a_base, c_base, lower, green, glass_edges, ds,
       splits, doors, headlight_z, tail_z):
    xf, xr = L/2, -L/2
    return dict(L=L, W=W, lower=lower, lower_tags={2: 'fascia'}, green=green,
                green_tags={e: 'glass' for e in glass_edges}, belt=belt, roof=H,
                wheels=[xf - fa_off, xf - fa_off - wb], R=R, a_base=a_base, c_base=c_base,
                ds=ds, splits=splits, doors=doors,
                headlight=(xf - 0.03, headlight_z), tail=(xr + 0.01, tail_z))

def spec(kind):
    if kind in ('comfort', 'driver'):     # Honda City / Dzire: three-box sedan
        L, W, H = 4.44, 1.73, 1.49; xf, xr = L/2, -L/2
        a, c = 1.10, -1.28
        lower = [(xr+0.08, 0.24), (xf-0.12, 0.24), (xf, 0.40), (xf-0.03, 0.60), (xf-0.22, 0.70),
                 (xf-0.60, 0.78), (a, 0.86), (c, 0.93), (xr+0.25, 0.94), (xr+0.02, 0.86), (xr-0.01, 0.44)]
        green = [(c, 0.93), (a, 0.86), (0.48, 1.37), (0.15, 1.47), (-0.25, 1.49), (-0.53, 1.43), (-0.93, 1.23)]
        return mk(L, W, H, 0.31, 0.86, 2.60, 0.88, a, c, lower, green, [1, 2],
                  [0.035, 0.07, 0.06, 0.06, 0.06, 0.12, 0.13], [-0.02], [1.06, -0.02, -1.05], 0.56, 0.82)
    if kind == 'premium':                 # Superb / Camry: long, low, fastback roof
        L, W, H = 4.87, 1.86, 1.46; xf, xr = L/2, -L/2
        a, c = 1.135, -1.55
        lower = [(xr+0.08, 0.24), (xf-0.12, 0.24), (xf, 0.40), (xf-0.03, 0.57), (xf-0.25, 0.67),
                 (xf-0.70, 0.76), (a, 0.84), (c, 0.93), (xr+0.25, 0.94), (xr+0.02, 0.85), (xr-0.01, 0.44)]
        green = [(c, 0.93), (a, 0.84), (0.40, 1.32), (0.05, 1.43), (-0.45, 1.46), (-0.85, 1.41),
                 (-1.20, 1.23)]
        return mk(L, W, H, 0.33, 0.92, 2.84, 0.87, a, c, lower, green, [1, 2],
                  [0.035, 0.07, 0.06, 0.06, 0.06, 0.12, 0.13], [0.00], [1.10, 0.0, -1.20], 0.54, 0.81) | {'chrome': True}
    if kind == 'economy':                 # Swift / i20: short hatchback
        L, W, H = 3.86, 1.74, 1.52; xf, xr = L/2, -L/2
        a = 0.91
        lower = [(xr+0.08, 0.24), (xf-0.12, 0.24), (xf, 0.40), (xf-0.03, 0.62), (xf-0.22, 0.72),
                 (xf-0.55, 0.80), (a, 0.88), (xr+0.10, 0.97), (xr+0.01, 0.88), (xr-0.01, 0.44)]
        green = [(xr+0.10, 0.97), (a, 0.88), (0.29, 1.36), (-0.01, 1.48), (-0.45, 1.52),
                 (-1.12, 1.47), (-1.50, 1.32), (-1.74, 1.08)]
        return mk(L, W, H, 0.30, 0.78, 2.45, 0.90, a, xr+0.10, lower, green, [1, 2],
                  [0.035, 0.07, 0.06, 0.06, 0.06, 0.16, 0.20, 0.20], [-0.04], [0.87, -0.04, -1.05], 0.58, 0.90)
    if kind == 'xl':                      # Innova / Ertiga: tall 7-seat MPV
        L, W, H = 4.74, 1.83, 1.80; xf, xr = L/2, -L/2
        a = 1.19
        lower = [(xr+0.08, 0.26), (xf-0.12, 0.26), (xf, 0.44), (xf-0.03, 0.72), (xf-0.25, 0.84),
                 (xf-0.65, 0.93), (a, 0.99), (xr+0.06, 1.05), (xr+0.01, 0.94), (xr-0.01, 0.46)]
        green = [(xr+0.06, 1.05), (a, 0.99), (0.47, 1.56), (0.09, 1.74), (-0.36, 1.80),
                 (-2.07, 1.78), (-2.23, 1.66), (-2.29, 1.30)]
        return mk(L, W, H, 0.33, 0.88, 2.75, 1.00, a, xr+0.06, lower, green, [1, 2],
                  [0.04, 0.07, 0.07, 0.07, 0.07, 0.12, 0.12, 0.12], [0.14, -0.98], [1.15, 0.14, -0.98], 0.66, 1.00) | {'rails': True}
    raise ValueError(kind)

PAL_OF = {'economy': 'silver', 'comfort': 'silver', 'xl': 'silver',
          'premium': 'graphite', 'driver': 'neutral'}

# ---------------------------------------------------------------- build
def build(kind):
    s = spec(kind); pal = PALETTES[PAL_OF[kind]]
    W = s['W']; R = s['R']; belt = s['belt']; roof = s['roof']
    xf_, xr_ = s['L']/2, -s['L']/2
    def lower_w(x, z=0):
        tf = max(0.0, min(1.0, (x - (xf_ - 0.55)) / 0.55))
        tr = max(0.0, min(1.0, ((xr_ + 0.40) - x) / 0.40))
        return W - 0.30*tf**2 - 0.16*tr**2
    gw_b, gw_r = W - 0.14, W - 0.58
    green_w0 = lambda z: gw_b + (gw_r - gw_b) * (z - belt) / (roof - belt)
    green_w = lambda x, z: green_w0(z)
    items = []  # (kind, pts3d or screen-later, style)

    def poly3(pts, fill, extra=''):
        items.append(('poly', pts, fill, extra))

    def side_pt(x, z, y=None): return (x, (lower_w(x) / 2 if y is None else y - W/2 + lower_w(x)/2) + 0.004, z)
    def green_pt(x, z, off=0.004): return (x, green_w0(z)/2 + off, z)

    def circle3(xc, y, zc, r, n=72):
        return [(xc + r*math.cos(t), y, zc + r*math.sin(t))
                for t in (2*math.pi*k/n for k in range(n))]

    # --- far wheels (only the bits under the body will show)
    for xw in s['wheels']:
        items.append(('tyre', (xw, -W/2 + 0.03, R, R), pal, 'far'))

    # --- silhouette outline pass is generated at render time from body faces
    lower = solid(s['lower'], lower_w, s['lower_tags'])
    green = solid(s['green'], green_w, s['green_tags'])
    body_faces = []
    for pts, n, tag in lower:
        if tag == 'side':
            body_faces.append((pts, 'grad-side', n))
        elif tag == 'fascia':
            body_faces.append((pts, shade(pal, n, -0.06), n))
        else:
            body_faces.append((pts, shade(pal, n), n))
    gfaces = []
    for pts, n, tag in green:
        if tag == 'glass':
            gfaces.append((pts, 'url(#glassW)', n))
        elif tag == 'side':
            gfaces.append((pts, shade(pal, n, -0.12), n))
        else:
            gfaces.append((pts, shade(pal, n, 0.04), n))
    items.append(('outline', [f[0] for f in body_faces] + [f[0] for f in gfaces], pal, None))
    for pts, fill, n in body_faces:
        items.append(('face', pts, fill, n))

    side_prof = s['lower']
    # side profile in (x,z) is CCW when viewed from +y? our profile is CCW with x right z up.
    # --- lower cladding / rocker
    xs = s['wheels']
    rock = clip(box_ccw(xs[1] + R*1.05, xs[0] - R*1.05, 0.0, 0.33), side_prof)
    if rock: poly3([side_pt(x, z) for x, z in rock], mix(pal['trim'], pal['lo'], 0.35))
    # --- bumper lower lips (front + rear) in trim
    xf = s['L']/2; xr = -s['L']/2
    lip = clip(box_ccw(xf-0.55, xf+0.1, 0.0, 0.33), side_prof)
    if lip: poly3([side_pt(x, z) for x, z in lip], mix(pal['trim'], pal['lo'], 0.35))
    lip = clip(box_ccw(xr-0.1, xr+0.45, 0.0, 0.33), side_prof)
    if lip: poly3([side_pt(x, z) for x, z in lip], mix(pal['trim'], pal['lo'], 0.35))

    # --- door shut lines
    for xd in s['doors']:
        items.append(('line', [side_pt(xd, belt - 0.03), side_pt(xd - 0.02, 0.36)], pal['crease'], LINE_W))
    # shoulder crease just under the belt
    items.append(('line', [side_pt(xf - 0.30, belt - 0.13), side_pt(xr + 0.12, belt - 0.07)], pal['crease'], LINE_W))

    # --- teal accent stripe (the one brand mark)
    if pal['accent']:
        z0 = belt - 0.25
        stripe = [(xr + 0.10, z0 + 0.035), (xf - 0.26, z0 - 0.02), (xf - 0.30, z0 + 0.035),
                  (xr + 0.10, z0 + 0.085)]
        stripe = clip(stripe, side_prof)
        if stripe: poly3([side_pt(x, z) for x, z in stripe], pal['accent'])

    # --- door handles
    for xd in s['doors'][:-1]:
        hx0 = xd - 0.22
        items.append(('line', [side_pt(hx0, belt - 0.12), side_pt(hx0 - 0.16, belt - 0.115)], pal['trim'], 2.2))

    # --- tail light sliver on the side, headlight wrap
    tx, tz = s['tail']
    tl = clip([(tx - 0.02, tz - 0.14), (tx + 0.30, tz - 0.10), (tx + 0.30, tz - 0.03), (tx - 0.02, tz + 0.01)], side_prof)
    if tl: poly3([side_pt(x, z) for x, z in tl], '#C8323C')
    hx_, hz = s['headlight']
    hl = clip([(hx_ - 0.36, hz + 0.03), (hx_ + 0.02, hz - 0.04), (hx_ + 0.02, hz + 0.05), (hx_ - 0.30, hz + 0.10)], side_prof)
    if hl: poly3([side_pt(x, z) for x, z in hl], '#EAF3F6', 'hl')

    # --- front fascia details: headlights both sides + grille
    lp = s['lower']
    i = 2
    a, b = lp[i], lp[i+1]  # fascia edge from (xf,z) up to nose top
    def fascia(u, v, out=0.006):
        x = a[0] + (b[0]-a[0])*v; z = a[1] + (b[1]-a[1])*v
        return (x + out, u * lower_w(x)/2, z)
    # fascia edge index 2 in lower is (xf-0.10,..)->(xf,0.38); edge 3 is (xf,0.38)->(xf-0.01,0.60)
    for sgn in (1, -1):
        pts = [fascia(sgn*0.97, 0.62), fascia(sgn*0.55, 0.70), fascia(sgn*0.52, 0.96), fascia(sgn*0.99, 0.99)]
        poly3(pts, '#EAF3F6', 'hl')
    poly3([fascia(-0.44, 0.12), fascia(0.44, 0.12), fascia(0.46, 0.60), fascia(-0.46, 0.60)], pal['trim'])
    # thin chrome/teal-free bar across grille
    items.append(('line', [fascia(-0.44, 0.40, 0.01), fascia(0.44, 0.40, 0.01)], mix(pal['trim'], pal['hi'], 0.45), 1.0))

    # --- wheel arches + near wheels
    for xw in xs:
        ra_ = R + 0.05
        arch = [(xw + ra_, 0.20)] + [(xw + ra_*math.cos(t), R + ra_*math.sin(t)) for t in (math.pi*k/36 for k in range(0, 37))] + [(xw - ra_, 0.20)]
        # wheel-well opening: the arch in the body plane plus its copy 0.14 m inboard, hulled
        items.append(('hullpoly', [side_pt(x, z, W/2 + 0.006) for x, z in arch] +
                      [(x, lower_w(x)/2 - 0.14, z) for x, z in arch], '#16181B', None))

    for pts, fill, n in gfaces:
        items.append(('face', pts, fill, n))

    # --- side glass
    g = s['green']
    ds = s['ds']
    win = inset(g, ds)
    edges = [s['a_base'] + 1] + list(s['splits']) + [-99]
    bp = 0.05  # half B-pillar width
    for k in range(len(edges) - 1):
        x_hi = edges[k] - (bp if k > 0 else 0)
        x_lo = edges[k+1] + (bp if k < len(edges) - 2 else 0)
        wpoly = clip(win, box_ccw(x_lo, x_hi, -9, 9))
        if wpoly:
            poly3([green_pt(x, z) for x, z in wpoly], 'url(#glassS)', 'glass')
    # B/C pillars in black gloss for the modern look
    for xs_ in s['splits']:
        bpoly = clip(win, box_ccw(xs_ - bp, xs_ + bp, -9, 9))
        if bpoly: poly3([green_pt(x, z) for x, z in bpoly], pal['trim'])

    # --- windshield reflection streak
    wf = [f for f in gfaces if f[1] == 'url(#glassW)']
    if wf:
        g0 = s['green']; a_b = g0[1]; w_t = g0[3]
        def wpt(u, v):  # u across width (-1..1), v from base to top
            x = a_b[0] + (w_t[0]-a_b[0])*v; z = a_b[1] + (w_t[1]-a_b[1])*v
            return (x + 0.01, u*green_w0(z)/2, z)
        items.append(('streak', [wpt(0.05, 0.05), wpt(0.32, 0.05), wpt(-0.05, 0.95), wpt(-0.22, 0.95)], None, None))
    if s.get('rails'):
        g0 = s['green']; zr = s['roof']
        xa, xb = g0[4][0] + 0.05, g0[5][0] + 0.05
        for sg in (-1, 1):
            yy = sg*(green_w0(zr)/2 - 0.07)
            items.append(('line', [(xa, yy, zr + 0.03), (xb, yy, zr + 0.035)], pal['trim'], 2.4))
    if s.get('chrome'):
        g0 = s['green']
        items.append(('line', [green_pt(g0[1][0] - 0.08, g0[1][1] + 0.035, 0.008), green_pt(g0[0][0] + 0.12, g0[0][1] + 0.035, 0.008)], '#D9DEE3', 1.3))

    # --- mirror at the A-pillar base
    ab = s['a_base']; yb = green_w0(belt)/2
    m = [(ab - 0.06, yb, belt + 0.02), (ab - 0.26, yb, belt + 0.03),
         (ab - 0.25, W/2 + 0.16, belt + 0.12), (ab - 0.10, W/2 + 0.16, belt + 0.16),
         (ab - 0.04, yb, belt + 0.14)]
    items.append(('mirror', m, pal, None))

    for xw in xs:
        items.append(('tyre', (xw, W/2 - 0.01, R, R), pal, 'near'))

    return s, pal, items

def tyre_polys(xw, y, zc, R, pal, which):
    n = 72
    face = [(xw + R*math.cos(t), y, zc + R*math.sin(t)) for t in (2*math.pi*k/n for k in range(n))]
    back = [(xw + R*math.cos(t), y - 0.14, zc + R*math.sin(t)) for t in (2*math.pi*k/n for k in range(n))]
    rim = [(xw + R*0.66*math.cos(t), y + 0.005, zc + R*0.66*math.sin(t)) for t in (2*math.pi*k/n for k in range(n))]
    rim2 = [(xw + R*0.56*math.cos(t), y + 0.006, zc + R*0.56*math.sin(t)) for t in (2*math.pi*k/n for k in range(n))]
    hub = [(xw + R*0.16*math.cos(t), y + 0.007, zc + R*0.16*math.sin(t)) for t in (2*math.pi*k/n for k in range(n))]
    spokes = []
    for k in range(5):
        t = 2*math.pi*k/5 + 0.3
        spokes.append([(xw + R*0.16*math.cos(t), y + 0.008, zc + R*0.16*math.sin(t)),
                       (xw + R*0.56*math.cos(t), y + 0.008, zc + R*0.56*math.sin(t))])
    return face, back, rim, rim2, hub, spokes

def hull(pts):
    pts = sorted(set(pts))
    if len(pts) < 3: return pts
    def cr(o, a, b): return (a[0]-o[0])*(b[1]-o[1]) - (a[1]-o[1])*(b[0]-o[0])
    lo, up = [], []
    for p in pts:
        while len(lo) >= 2 and cr(lo[-2], lo[-1], p) <= 0: lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(up) >= 2 and cr(up[-2], up[-1], p) <= 0: up.pop()
        up.append(p)
    return lo[:-1] + up[:-1]

# ---------------------------------------------------------------- render
def render(kind):
    s, pal, items = build(kind)
    # bounds from everything except shadow
    allp = []
    for it in items:
        if it[0] in ('poly', 'face', 'mirror'):
            allp += [raw(p) for p in it[1]]
        elif it[0] == 'outline':
            for f in it[1]: allp += [raw(p) for p in f]
        elif it[0] == 'tyre':
            xw, y, zc, R = it[1]
            for arr in tyre_polys(xw, y, zc, R, pal, it[3])[:2]: allp += [raw(p) for p in arr]
    minx = min(p[0] for p in allp); maxx = max(p[0] for p in allp)
    miny = min(p[1] for p in allp); maxy = max(p[1] for p in allp)
    # lowest tyre contact (near front wheel bottom)
    sc = FILL_W * W_CANVAS / (maxx - minx)
    top_room = BASELINE - 14
    if (maxy - miny) * sc > top_room:
        sc = top_room / (maxy - miny)
    ox = W_CANVAS/2 - sc*(minx + maxx)/2
    oy = BASELINE - sc*maxy
    def P(p):
        x, y = raw(p); return (ox + sc*x, oy + sc*y)
    def d(pts3, close=True):
        pts = [P(p) for p in pts3]
        return 'M' + ' L'.join('%.2f %.2f' % q for q in pts) + (' Z' if close else '')
    def d2(pts):
        return 'M' + ' L'.join('%.2f %.2f' % q for q in pts) + ' Z'

    out = []
    # shadow: projected ground ellipse, blurred
    L, W = s['L'], s['W']
    sh = [(0.0 + (L/2 + 0.22)*math.cos(t), (W/2 + 0.26)*math.sin(t), 0) for t in (2*math.pi*k/96 for k in range(96))]
    sh2 = [(0.0 + (L/2 - 0.05)*math.cos(t), (W/2 + 0.02)*math.sin(t), 0) for t in (2*math.pi*k/96 for k in range(96))]
    out.append('<path d="%s" fill="#000" opacity="0.22" filter="url(#soft)"/>' % d(sh))
    out.append('<path d="%s" fill="#000" opacity="0.38" filter="url(#tight)"/>' % d(sh2))

    ol = pal['outline']
    for it in items:
        k = it[0]
        if k == 'tyre':
            xw, y, zc, R = it[1]
            face, back, rim, rim2, hub, spokes = tyre_polys(xw, y, zc, R, pal, it[3])
            hp = hull([P(p) for p in face] + [P(p) for p in back])
            out.append('<path d="%s" fill="#121417" stroke="%s" stroke-width="%.2f" stroke-linejoin="round"/>' % (d2(hp), '#0A0B0D', OUTLINE_W*0.6))
            if it[3] == 'near':
                out.append('<path d="%s" fill="#1E2125"/>' % d(face))
                out.append('<path d="%s" fill="url(#rim)"/>' % d(rim))
                out.append('<path d="%s" fill="%s"/>' % (d(rim2), '#5C636B' if PAL_OF[kind] != 'neutral' else '#606366'))
                for sp in spokes:
                    out.append('<path d="%s" stroke="%s" stroke-width="%.2f" stroke-linecap="round"/>' % (d(sp, False), '#C9CFD5', sc*0.075))
                out.append('<path d="%s" fill="#D8DDE2" stroke="#5C636B" stroke-width="0.8"/>' % d(hub))
        elif k == 'outline':
            for f in it[1]:
                out.append('<path d="%s" fill="%s" stroke="%s" stroke-width="%.2f" stroke-linejoin="round"/>' % (d(f), ol, ol, OUTLINE_W*2))
        elif k == 'face':
            fill = it[2]
            if fill == 'grad-side':
                fill = 'url(#side)'
                out.append('<path d="%s" fill="%s" stroke="%s" stroke-width="0.6" stroke-linejoin="round"/>' % (d(it[1]), fill, shade(pal, it[3])))
            elif fill.startswith('url'):
                out.append('<path d="%s" fill="%s" stroke="url(#glassW)" stroke-width="0.8" stroke-linejoin="round"/>' % (d(it[1]), fill))
            else:
                out.append('<path d="%s" fill="%s" stroke="%s" stroke-width="0.9" stroke-linejoin="round"/>' % (d(it[1]), fill, fill))
        elif k == 'poly':
            extra = it[3]
            if extra == 'hl':
                out.append('<path d="%s" fill="%s" stroke="%s" stroke-width="1.1" stroke-linejoin="round"/>' % (d(it[1]), it[2], pal['trim']))
            elif extra == 'glass':
                out.append('<path d="%s" fill="%s" stroke="%s" stroke-width="0.8" stroke-linejoin="round"/>' % (d(it[1]), it[2], pal['glass_bot']))
            else:
                out.append('<path d="%s" fill="%s" stroke="%s" stroke-width="0.6" stroke-linejoin="round"/>' % (d(it[1]), it[2], it[2]))
        elif k == 'line':
            out.append('<path d="%s" fill="none" stroke="%s" stroke-width="%.2f" stroke-linecap="round"/>' % (d(it[1], False), it[2], it[3]))
        elif k == 'hullpoly':
            out.append('<path d="%s" fill="%s"/>' % (d2(hull([P(p) for p in it[1]])), it[2]))
        elif k == 'streak':
            out.append('<path d="%s" fill="#FFFFFF" opacity="0.10"/>' % d(it[1]))
        elif k == 'mirror':
            out.append('<path d="%s" fill="%s" stroke="%s" stroke-width="1.4" stroke-linejoin="round"/>' % (d(it[1]), pal['trim'], ol))

    # side gradient extents (screen-space vertical)
    side_face = [f for f in items if f[0] == 'face' and f[2] == 'grad-side'][0]
    sp = [P(p) for p in side_face[1]]
    y0 = min(p[1] for p in sp); y1 = max(p[1] for p in sp)
    nside = side_face[3]
    gl = [P(p) for f in items if f[0] == 'face' and f[2] == 'url(#glassW)' for p in f[1]]
    gx0 = min(p[0] for p in gl); gx1 = max(p[0] for p in gl); gy0 = min(p[1] for p in gl); gy1 = max(p[1] for p in gl)
    s_hi = shade(pal, nside, 0.28); s_mid = shade(pal, nside, 0.08); s_lo = shade(pal, nside, -0.22)
    defs = f'''<defs>
  <filter id="soft" x="-30%" y="-100%" width="160%" height="300%"><feGaussianBlur stdDeviation="{7*sc/88:.2f}"/></filter>
  <filter id="tight" x="-20%" y="-100%" width="140%" height="300%"><feGaussianBlur stdDeviation="{2.6*sc/88:.2f}"/></filter>
  <linearGradient id="side" gradientUnits="userSpaceOnUse" x1="0" y1="{y0:.1f}" x2="0" y2="{y1:.1f}">
    <stop offset="0" stop-color="{s_hi}"/><stop offset="0.45" stop-color="{s_mid}"/><stop offset="1" stop-color="{s_lo}"/>
  </linearGradient>
  <linearGradient id="glassS" x1="0" y1="0" x2="0.35" y2="1">
    <stop offset="0" stop-color="{pal['glass_top']}"/><stop offset="1" stop-color="{pal['glass_bot']}"/>
  </linearGradient>
  <linearGradient id="glassW" gradientUnits="userSpaceOnUse" x1="{gx0:.1f}" y1="{gy0:.1f}" x2="{gx1:.1f}" y2="{gy1:.1f}">
    <stop offset="0" stop-color="{pal['glass_bot']}"/><stop offset="0.55" stop-color="{pal['glass_top']}"/><stop offset="1" stop-color="{pal['glass_bot']}"/>
  </linearGradient>
  <radialGradient id="rim" cx="0.4" cy="0.35" r="0.7">
    <stop offset="0" stop-color="#E4E8EC"/><stop offset="1" stop-color="#8E959D"/>
  </radialGradient>
</defs>'''
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W_CANVAS}" height="{H_CANVAS}" '
           f'viewBox="0 0 {W_CANVAS} {H_CANVAS}">\n<!-- RideVela Plan A Midnight Teal: {kind} -->\n'
           + defs + '\n' + '\n'.join(out) + '\n</svg>\n')
    return svg, sc

if __name__ == '__main__':
    for kind in ['economy', 'comfort', 'xl', 'premium', 'driver']:
        svg, sc = render(kind)
        with open(os.path.join(OUT, kind + '.svg'), 'w') as f:
            f.write(svg)
        print(kind, 'px/m=%.1f' % sc)
