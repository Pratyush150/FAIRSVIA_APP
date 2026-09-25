"""Realistic silver compact sedan for the Home "ride" tile.

Body shell: the lofted-section builder from docs/brand/vehicles/clay (same
proportions as the clay 'comfort' sedan, retuned lower/sleeker). Everything
else is new and physically based:
  * metallic silver paint with a clear-coat, panel gaps (door, hood, bumper),
  * near-black glass with real HDRI reflections (glossy, IOR 1.5),
  * headlamps with chrome reflector, projector lens and LED DRL strip,
  * gloss-black grille with horizontal slats + chrome surround, black cladding,
  * lathed tyres with rounded sidewalls, 5 twin-spoke machined alloys,
    brake discs, lug nuts, dark barrels; mirrors with black bases.
Front points to +X, the left side faces +Y (camera side).
"""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'vehicles', 'clay'))
from common import loft_body, NB  # noqa: E402  (clay shell builder, reused)

import rcommon as rc  # noqa: E402

SPEC = dict(
    x0=-2.15, x1=2.15, W=1.78, zc=0.27,
    wheels=[(-1.34, 0.36), (1.34, 0.36)],
    top=[(-2.15, 0.93), (-2.10, 1.02), (-1.70, 1.05), (-1.30, 1.08),
         (-0.74, 1.39), (-0.35, 1.43), (0.25, 1.42), (1.05, 0.98),
         (1.82, 0.89), (2.15, 0.76)],
    belt=[(-2.15, 0.90), (-1.3, 0.94), (1.05, 0.90), (2.15, 0.82)],
    pillars=[(-0.08, 0.01)],
    doors=[1.00, -0.04, -1.08], handles=[(0.10, 0.855), (-0.93, 0.865)],
    headlamp=(0.60, 0.685, 0.30, 0.055), grille=(0.50, 0.40, 0.61),
    intake=(0.62, 0.30, 0.365),
    taillamp=(0.62, 0.88, 0.20, 0.06), tumble=0.13, r_roof=0.15,
    arch_pad=0.045, flare=0.035, plan_taper=0.22, plan_len=0.95, sigma=0.10,
)

PAINT = '#AEB5BC'      # silver metallic
PAINT_DARK = '#1A1D21'


def _p(nb, col, rough, metal=0.0, coat=0.0, coat_rough=0.03, spec=0.5,
       emit=None, emit_s=0.0, ior=1.5, normal=None):
    nt = nb.nt
    p = nt.nodes.new('ShaderNodeBsdfPrincipled')
    if isinstance(col, str):
        p.inputs['Base Color'].default_value = rc.hexcol(col)
    else:
        nt.links.new(col, p.inputs['Base Color'])
    p.inputs['Roughness'].default_value = rough
    p.inputs['Metallic'].default_value = metal
    p.inputs['Coat Weight'].default_value = coat
    p.inputs['Coat Roughness'].default_value = coat_rough
    p.inputs['Specular IOR Level'].default_value = spec
    p.inputs['IOR'].default_value = ior
    if emit:
        p.inputs['Emission Color'].default_value = rc.hexcol(emit)
        p.inputs['Emission Strength'].default_value = emit_s
    if normal is not None:
        nt.links.new(normal, p.inputs['Normal'])
        nt.links.new(normal, p.inputs['Coat Normal'])
    return p.outputs[0]


def body_material(spec):
    mat = bpy.data.materials.new('paint')
    nb = NB(mat)
    x0, x1 = spec['x0'], spec['x1']
    ay = nb.absv(nb.y)
    zbelt, zwtop = nb.attr('zbelt'), nb.attr('zwtop')
    wt, slope, hw = nb.attr('wt'), nb.attr('slope'), nb.attr('hw')

    # glass areas
    side_raw = nb.mul(nb.gt(nb.z, nb.add(zbelt, 0.03)), nb.lt(nb.z, zwtop),
                      nb.gt(ay, 0.35))
    side = side_raw
    for (p0, p1) in spec['pillars']:
        side = nb.mul(side, nb.inv(nb.mul(nb.gt(nb.x, p0), nb.lt(nb.x, p1))))
    # black window surround (trim) just outside the glass
    outer = nb.mul(nb.gt(nb.z, nb.add(zbelt, 0.012)), nb.lt(nb.z, nb.add(zwtop, 0.02)),
                   nb.gt(ay, 0.35))
    trim = nb.mul(outer, nb.inv(side_raw))
    # B-pillar gloss black
    bp = nb.mul(side_raw, nb.inv(side))
    wind = nb.mul(nb.gt(slope, 0.36), nb.lt(ay, nb.sub(wt, 0.075)),
                  nb.gt(nb.z, nb.add(zbelt, 0.06)))
    glass = nb.mx(side, wind)
    blackout = nb.mx(trim, bp)

    # panel gaps: door shut lines, hood line, front/rear bumper split
    lw = 0.0035
    lower = nb.mul(nb.lt(nb.z, nb.add(zbelt, 0.015)), nb.gt(ay, nb.sub(hw, 0.08)))
    gap = 0.0
    for xd in spec['doors']:
        l = nb.lt(nb.absv(nb.sub(nb.x, xd)), lw)
        gap = l if isinstance(gap, float) else nb.mx(gap, l)
    gap = nb.mul(gap, lower, nb.gt(nb.z, spec['zc'] + 0.06))
    # hood shut line: along the top at |y| = wt - 0.10, front of the windscreen
    hood = nb.mul(nb.lt(nb.absv(nb.sub(ay, nb.sub(wt, 0.10))), lw * 1.2),
                  nb.gt(nb.x, 1.08), nb.lt(nb.x, x1 - 0.18),
                  nb.gt(nb.z, nb.sub(zbelt, 0.02)))
    # bumper split line (front + rear) on the sides, below the lamps
    fb = nb.mul(nb.lt(nb.absv(nb.sub(nb.x, x1 - 0.42)), lw),
                nb.lt(nb.z, 0.62), nb.gt(nb.z, spec['zc'] + 0.08), nb.gt(ay, nb.sub(hw, 0.08)))
    rb = nb.mul(nb.lt(nb.absv(nb.sub(nb.x, x0 + 0.40)), lw),
                nb.lt(nb.z, 0.70), nb.gt(nb.z, spec['zc'] + 0.08), nb.gt(ay, nb.sub(hw, 0.08)))
    gap = nb.mx(nb.mx(gap, hood), nb.mx(fb, rb))
    # chrome door handles
    handle = 0.0
    for (hx, hz) in spec['handles']:
        h = nb.mul(nb.lt(nb.absv(nb.sub(nb.x, hx)), 0.07),
                   nb.lt(nb.absv(nb.sub(nb.z, hz)), 0.012), nb.gt(ay, nb.sub(hw, 0.08)))
        handle = h if isinstance(handle, float) else nb.mx(handle, h)

    # lower black cladding (sills + under-bumpers)
    clad = nb.lt(nb.z, spec['zc'] + 0.06)

    # --- lamps
    hl = spec['headlamp']
    # swept headlamp: a band on the front corner that wraps onto the fender,
    # rising and narrowing toward the rear.
    back = nb.m('MAXIMUM', nb.sub(x1, nb.x), 0.0)          # distance from nose
    zlo = nb.add(hl[1] - hl[3], nb.mul(back, 0.20))
    zhi = nb.add(hl[1] + hl[3], nb.mul(back, 0.05))
    lamp = nb.mul(nb.gt(nb.x, x1 - 0.50), nb.gt(nb.z, zlo), nb.lt(nb.z, zhi),
                  nb.gt(nb.absv(nb.y), hl[0] - hl[2]))
    # inner detail: projector bowl (dark ring + bright lens), LED strip at bottom
    yy = nb.absv(nb.y)
    dproj = nb.m('SQRT', nb.add(nb.m('POWER', nb.sub(yy, hl[0] + 0.07), 2.0),
                                nb.m('POWER', nb.sub(nb.z, hl[1] + 0.005), 2.0)))
    proj_ring = nb.mul(nb.lt(dproj, 0.042), nb.gt(dproj, 0.028))
    proj_lens = nb.lt(dproj, 0.028)
    drl = nb.lt(nb.absv(nb.sub(nb.z, nb.add(zlo, 0.016))), 0.008)
    gr = spec['grille']
    front_face = nb.gt(nb.x, x1 - 0.12)
    grille = nb.mul(front_face, nb.box(-1, gr[0], gr[1], gr[2]))
    it = spec['intake']
    intake = nb.mul(front_face, nb.box(-1, it[0], it[1], it[2]))
    gsur = nb.mul(front_face, nb.box(-1, gr[0] + 0.02, gr[1] - 0.02, gr[2] + 0.02))
    gsur = nb.mul(gsur, nb.inv(grille))
    # horizontal slats
    slat = nb.gt(nb.m('SINE', nb.m('MULTIPLY', nb.z, 190.0)), 0.55)
    tl = spec['taillamp']
    tail = nb.mul(nb.lt(nb.x, x0 + 0.25), nb.ellipse(*tl))

    # --- shaders
    # shoulder character line: a soft ridge pressed into the doors
    zc_line = nb.sub(zbelt, 0.12)
    ridge = nb.mx(nb.sub(1.0, nb.m('DIVIDE', nb.absv(nb.sub(nb.z, zc_line)), 0.03)), 0.0)
    ridge = nb.mul(ridge, nb.gt(ay, nb.sub(hw, 0.12)), nb.lt(nb.x, x1 - 0.35),
                   nb.gt(nb.x, x0 + 0.3))
    bump = nb.nt.nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.6
    bump.inputs['Distance'].default_value = 0.01
    nb.nt.links.new(ridge, bump.inputs['Height'])
    paint = _p(nb, PAINT, 0.22, metal=0.8, coat=1.0, coat_rough=0.02,
               normal=bump.outputs['Normal'])
    black_gloss = _p(nb, '#07090B', 0.12, coat=1.0, coat_rough=0.02)
    black_satin = _p(nb, '#15171A', 0.55, spec=0.3)
    gapc = _p(nb, '#1E2226', 0.6, spec=0.2)
    chrome = _p(nb, '#E8ECF0', 0.08, metal=1.0)
    glassb = _p(nb, nb.glass_col(0.9, 2.1, dark='#0B1016', light='#44505D', k=0.35),
                0.03, spec=1.0, coat=1.0, coat_rough=0.0)
    reflector = _p(nb, '#D9DEE3', 0.14, metal=1.0, coat=1.0, coat_rough=0.0)
    lens = _p(nb, '#F4F7FA', 0.05, coat=1.0, emit='#EAF3FF', emit_s=2.0)
    ringb = _p(nb, '#2A2F35', 0.25, metal=0.6, coat=1.0)
    drlb = _p(nb, '#FFFFFF', 0.1, emit='#F2F8FF', emit_s=6.0)
    tailb = _p(nb, '#7A0E14', 0.08, coat=1.0, coat_rough=0.0, emit='#B0141C', emit_s=0.3)

    s = paint
    s = nb.mix(gap, s, gapc)
    s = nb.mix(handle, s, chrome)
    s = nb.mix(clad, s, black_satin)
    s = nb.mix(gsur, s, chrome)
    s = nb.mix(grille, s, nb.mix(slat, black_gloss, _p(nb, '#2B3036', 0.3, metal=0.8)))
    s = nb.mix(intake, s, black_satin)
    smoked = _p(nb, '#1C232B', 0.06, metal=0.3, coat=1.0, coat_rough=0.0)
    inner = nb.mul(nb.gt(nb.x, x1 - 0.10), nb.gt(nb.z, nb.add(zlo, 0.03)),
                   nb.lt(nb.z, nb.sub(zhi, 0.012)))
    lampsh = nb.mix(inner, smoked, reflector)
    lampsh = nb.mix(proj_ring, lampsh, ringb)
    lampsh = nb.mix(proj_lens, lampsh, lens)
    lampsh = nb.mix(drl, lampsh, drlb)
    s = nb.mix(lamp, s, lampsh)
    s = nb.mix(tail, s, tailb)
    s = nb.mix(blackout, s, black_gloss)
    s = nb.mix(glass, s, glassb)
    nb.done(s)
    return mat


def wheel(name, x, side, R, W, rr, mats, yc):
    """Tyre (lathed, rounded sidewall) + 5 twin-spoke alloy, facing side*Y."""
    tyre_m, alloy_m, barrel_m, disc_m, nut_m, cal_m = mats
    hw = W / 2
    # tyre profile in (r, axial) -- axial +: outer face
    prof = [(rr - 0.005, -hw * 0.80), (rr + 0.015, -hw * 0.96), (R - 0.05, -hw),
            (R - 0.015, -hw * 0.86), (R, -hw * 0.55), (R + 0.002, 0.0),
            (R, hw * 0.55), (R - 0.015, hw * 0.86), (R - 0.05, hw),
            (rr + 0.015, hw * 0.96), (rr - 0.005, hw * 0.80)]
    parts = []
    parts.append(rc.lathe(name + '_tyre', prof, tyre_m, seg=128))
    # rim lip + dark barrel
    lip = [(rr - 0.022, hw * 0.70), (rr - 0.004, hw * 0.78), (rr + 0.004, hw * 0.83),
           (rr - 0.010, hw * 0.86), (rr - 0.024, hw * 0.80)]
    parts.append(rc.lathe(name + '_lip', lip, alloy_m, seg=128))
    barrel = [(rr - 0.02, hw * 0.75), (rr - 0.03, -hw * 0.8), (0.02, -hw * 0.8)]
    parts.append(rc.lathe(name + '_barrel', barrel, barrel_m, seg=96))
    # brake disc + caliper
    parts.append(rc.cyl(name + '_disc', rr * 0.78, 0.022, (0, 0, -hw * 0.25), disc_m,
                        verts=96))
    parts.append(rc.rbox(name + '_cal', (0.07, 0.10, 0.05), (rr * 0.55, 0, -hw * 0.05),
                         cal_m, bevel=0.012, rot=(0, 0, 0)))
    parts[-1].rotation_euler = (0, 0, math.radians(35))
    # spokes (concave: centre recessed)
    zf = hw * 0.72
    rh = 0.065
    L = rr - 0.02 - rh
    for k in range(5):
        a0 = 2 * math.pi * k / 5
        for da in (-0.13, 0.13):
            a = a0 + da
            sp = rc.rbox(name + '_sp', (L, 0.028, 0.030), (0, 0, 0), alloy_m,
                         bevel=0.009, seg=3)
            rm = (rh + rr - 0.02) / 2
            sp.location = (math.cos(a) * rm, math.sin(a) * rm, zf - 0.012)
            sp.rotation_euler = (0, 0, a)
            parts.append(sp)
    # hub + centre cap + lug nuts
    parts.append(rc.cyl(name + '_hub', rh + 0.012, 0.045, (0, 0, zf - 0.03), alloy_m,
                        verts=64, bevel=0.008))
    parts.append(rc.cyl(name + '_cap', 0.032, 0.05, (0, 0, zf - 0.02), nut_m,
                        verts=48, bevel=0.01))
    for k in range(5):
        a = 2 * math.pi * (k + 0.5) / 5
        parts.append(rc.cyl(name + '_nut', 0.009, 0.05, (math.cos(a) * 0.05,
                     math.sin(a) * 0.05, zf - 0.02), nut_m, verts=6, bevel=0.002))
    # parent everything to an empty and orient: local +Z -> world side*Y
    emp = rc.link(bpy.data.objects.new(name, None))
    for p in parts:
        p.parent = emp
    emp.rotation_euler = (-side * math.pi / 2, 0, 0)
    emp.location = (x, yc, R)
    return emp


def build():
    spec = SPEC
    body = loft_body('body', spec, body_material(spec))
    tyre = rc.pbsdf('tyre', '#161718', rough=0.62, spec=0.35, sheen=0.15)
    rc.add_noise_bump(tyre, scale=300, strength=0.08)
    alloy = rc.pbsdf('alloy', '#C4C9CE', rough=0.18, metal=1.0, coat=0.6)
    barrel = rc.pbsdf('barrel', '#1A1C1F', rough=0.5, metal=0.5)
    disc = rc.pbsdf('disc', '#6E7278', rough=0.35, metal=1.0)
    rc.add_noise_bump(disc, scale=80, strength=0.1)
    nut = rc.pbsdf('nut', '#D5D9DE', rough=0.12, metal=1.0)
    cal = rc.pbsdf('cal', '#2A2D31', rough=0.4, metal=0.3, coat=0.5)
    well = rc.pbsdf('well', '#0B0C0D', rough=0.9)
    mats = (tyre, alloy, barrel, disc, nut, cal)
    W2 = spec['W'] / 2
    R = 0.345
    for i, (wx, _) in enumerate(spec['wheels']):
        for side in (1, -1):
            yc = side * (W2 - 0.12)
            wheel('w%d%d' % (i, side), wx, side, R, 0.21, 0.225, mats, yc)
        rc.rbox('well%d' % i, (0.78, spec['W'] - 0.30, 0.5), (wx, 0, 0.55), well,
                bevel=0.0)
    # mirrors: paint cap + gloss-black base
    paint_m = rc.pbsdf('mirror', PAINT, rough=0.32, metal=0.85, coat=1.0)
    blk = rc.pbsdf('mblk', '#08090A', rough=0.2, coat=1.0)
    xm, zb = 0.93, spec['belt'][1][1]
    for side in (1, -1):
        m = rc.rbox('mirror', (0.17, 0.13, 0.10), (xm, side * (W2 + 0.04), zb + 0.09),
                    paint_m, bevel=0.04, seg=5)
        m.rotation_euler = (0, 0, math.radians(-side * 8))
        rc.rbox('mbase', (0.10, 0.10, 0.04), (xm + 0.02, side * (W2 - 0.02), zb + 0.04),
                blk, bevel=0.012)
    # shark-fin antenna
    return body
