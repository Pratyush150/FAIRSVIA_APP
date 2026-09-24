"""Commuter motorcycle taxi (Splendor/Shine-like), teal tank and panels.

Front points to +X, the camera sees the left (+Y) side.
"""
import math
import bmesh
from mathutils import Vector
from common import (simple_mat, rbox, wheel, cyl, rim_mat, tube, sphere,
                    obj_from_bm, add_bevel)

TEAL = '#2BC4C4'


def arc_shell(name, c, r, width, thick, a0, a1, mat, n=32):
    """Mudguard: a curved strip around an axle at c (x, z), angles in degrees
    measured from +X toward +Z."""
    bm = bmesh.new()
    rings = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        ca, sa = math.cos(a), math.sin(a)
        ring = []
        for (rr, yy) in ((r, -width / 2), (r, width / 2), (r + thick, width / 2),
                         (r + thick, -width / 2)):
            ring.append(bm.verts.new((c[0] + rr * ca, yy, c[1] + rr * sa)))
        rings.append(ring)
    for a, b in zip(rings[:-1], rings[1:]):
        for j in range(4):
            bm.faces.new((a[j], a[(j + 1) % 4], b[(j + 1) % 4], b[j]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = obj_from_bm(bm, name, mat)
    add_bevel(ob, min(thick, width) * 0.45, 3)
    return ob


def build():
    teal = simple_mat('teal', TEAL, rough=0.5, spec=0.4, coat=0.1)
    seat = simple_mat('seat', '#2A2D33', rough=0.75, spec=0.2)
    frame = simple_mat('frame', '#34373D', rough=0.5, spec=0.3)
    metal = simple_mat('metal', '#9CA3AC', rough=0.35, spec=0.5, metal=0.2)
    chrome = simple_mat('chrome', '#C6CCD3', rough=0.22, spec=0.6, metal=0.4)
    tyre = simple_mat('tyre', '#2B2E34', rough=0.75, spec=0.25)
    R = 0.31
    rim = rim_mat('rim', '#C9CED5', n=5, rr=R * 0.70)
    hub = simple_mat('hub', '#8C939C', rough=0.4, spec=0.4)
    lamp = simple_mat('lamp', '#F4F6F8', rough=0.2, spec=0.6, coat=0.5,
                      emit='#FFF6E0', emit_s=0.4)
    tail = simple_mat('tail', '#C8323C', rough=0.3, spec=0.5, emit='#E0404A', emit_s=0.2)

    xf, xr = 0.68, -0.66
    wheel('fw', xf, 0.0, R, 0.12, tyre, rim, side=1, rim_frac=0.70, hub_mat=hub)
    wheel('rw', xr, 0.0, R, 0.14, tyre, rim, side=1, rim_frac=0.70, hub_mat=hub)
    # mudguards (teal)
    arc_shell('fguard', (xf, R), R + 0.04, 0.15, 0.035, 20, 140, teal)
    arc_shell('rguard', (xr, R), R + 0.05, 0.17, 0.035, 45, 170, teal)
    # front fork + headstock
    for s in (1, -1):
        tube('fork', [(xf, s * 0.085, R), (0.50, s * 0.085, 0.98)], 0.032, chrome)
    # headlamp cowl + lamp facing forward
    hc = rbox('cowl', (0.22, 0.26, 0.24), (0.55, 0, 1.03), teal, bevel=0.08,
              rot=(0, math.radians(-18), 0))
    cyl('headlamp', 0.085, 0.05, (0.665, 0, 1.03), lamp, axis='X', bevel=0.02,
        rot=(0, math.radians(72), 0))
    # handlebar + grips + mirrors
    tube('bar', [(0.42, -0.36, 1.14), (0.48, -0.20, 1.12), (0.48, 0.20, 1.12),
                 (0.42, 0.36, 1.14)], 0.018, chrome)
    for s in (1, -1):
        cyl('grip', 0.028, 0.12, (0.41, s * 0.37, 1.14), seat, axis='Y')
        tube('mstalk', [(0.46, s * 0.22, 1.13), (0.43, s * 0.27, 1.36)], 0.009, chrome)
        m = sphere('mirror', 0.06, (0.43, s * 0.28, 1.38), frame, scale=(0.35, 1.1, 0.8))
    # frame spine
    tube('spine', [(0.48, 0, 0.98), (0.25, 0, 0.78), (0.05, 0, 0.55)], 0.04, frame)
    tube('rail', [(-0.10, 0, 0.82), (-0.70, 0, 0.86)], 0.035, frame)
    # fuel tank (teal) with a knee-recess feel
    t = sphere('tank', 0.5, (0.20, 0, 0.93), teal, scale=(0.62, 0.36, 0.26))
    t.rotation_euler = (0, math.radians(10), 0)
    # tank badge stripe
    stripe = simple_mat('stripe', '#F2F4F6', rough=0.45, spec=0.4)
    s2 = sphere('tankstripe', 0.5, (0.21, 0, 0.935), stripe, scale=(0.30, 0.365, 0.05))
    s2.rotation_euler = (0, math.radians(10), 0)
    # seat (long commuter seat, pillion included)
    rbox('seat', (0.74, 0.28, 0.11), (-0.33, 0, 0.95), seat, bevel=0.05,
         rot=(0, math.radians(3), 0))
    # side panel + tail cowl (teal)
    rbox('sidepanel', (0.36, 0.24, 0.20), (-0.22, 0, 0.77), teal, bevel=0.07)
    rbox('tailcowl', (0.42, 0.20, 0.12), (-0.68, 0, 0.89), teal, bevel=0.05,
         rot=(0, math.radians(-8), 0))
    rbox('taillamp', (0.06, 0.14, 0.07), (-0.89, 0, 0.89), tail, bevel=0.025)
    rbox('grab', (0.30, 0.30, 0.03), (-0.55, 0, 1.01), frame, bevel=0.012)
    # engine block + cylinder fins
    rbox('crank', (0.36, 0.26, 0.26), (0.02, 0, 0.44), metal, bevel=0.06)
    rbox('cyl', (0.22, 0.20, 0.24), (0.20, 0, 0.62), metal, bevel=0.04,
         rot=(0, math.radians(-25), 0))
    for k in range(4):
        rbox('fin', (0.26, 0.24, 0.018), (0.215 - 0.025 * k, 0, 0.56 + 0.045 * k),
             frame, bevel=0.006, rot=(0, math.radians(-25), 0))
    rbox('cover', (0.20, 0.03, 0.18), (0.02, 0.14, 0.44), chrome, bevel=0.03)
    # swingarm + chain guard + rear shocks
    tube('swing', [(-0.05, 0.10, 0.42), (xr, 0.10, R)], 0.025, frame)
    rbox('chainguard', (0.60, 0.04, 0.09), (-0.34, 0.11, 0.40), frame, bevel=0.02,
         rot=(0, math.radians(8), 0))
    for s in (1, -1):
        tube('shock', [(xr + 0.06, s * 0.12, R + 0.05), (-0.46, s * 0.12, 0.86)], 0.028,
             chrome)
    # exhaust (left side here for readability)
    tube('header', [(0.20, 0.08, 0.50), (0.14, 0.15, 0.30), (-0.10, 0.17, 0.28)], 0.03,
         chrome)
    cyl('muffler', 0.055, 0.50, (-0.38, 0.17, 0.33), chrome, axis='X', bevel=0.02,
        r2=0.045, rot=(0, math.radians(95), 0))
    # footrests
    for s in (1, -1):
        cyl('peg', 0.02, 0.12, (-0.02, s * 0.18, 0.36), seat, axis='Y')
