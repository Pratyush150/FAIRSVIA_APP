"""Indian auto-rickshaw (Bajaj RE-like), Pune black + yellow livery.

Front points to +X. Lower tub and front cowl are lofted like the cars;
the canopy is a lofted yellow hood whose rear quarters drop to the tub.
"""
import math
from common import (loft_body, simple_mat, rbox, wheel, cyl, rim_mat, tube,
                    NB, hexcol, add_bevel, glass_mat)
import bpy

BLACK = '#2A2C31'
YELLOW = '#F5C542'


def lamp_mat():
    return simple_mat('lamp', '#F4F6F8', rough=0.2, spec=0.6, coat=0.5,
                      emit='#FFF6E0', emit_s=0.4)


def stripe_m():
    return simple_mat('stripe2', YELLOW, rough=0.55, spec=0.35)


def build():
    tub_m = simple_mat('tub', BLACK, rough=0.5, spec=0.4, coat=0.08)
    can_m = simple_mat('canopy', YELLOW, rough=0.55, spec=0.35, coat=0.05)
    dark = simple_mat('interior', '#25282D', rough=0.9, spec=0.1)
    seat = simple_mat('seat', '#4A3B33', rough=0.7, spec=0.2)
    tyre = simple_mat('tyre', '#2B2E34', rough=0.75, spec=0.25)
    rim = rim_mat('rim', '#C9CED5', n=4, rr=0.26 * 0.6)
    hub = simple_mat('hub', '#8C939C', rough=0.4, spec=0.4)
    glass = glass_mat('glass', (0.9, 2.0))
    chrome = simple_mat('chrome', '#B8BEC6', rough=0.25, spec=0.6, metal=0.3)

    # lower passenger tub (rear) -- wide, with rear wheel arches
    tub = dict(x0=-1.30, x1=0.45, W=1.30, zc=0.34,
               wheels=[(-0.86, 0.265)],
               top=[(-1.30, 0.80), (0.45, 0.80)],
               belt=[(-1.30, 0.78), (0.45, 0.78)],
               tumble=0.0, r_roof=0.10, r_belt=0.05, r_end=0.10,
               plan_taper=0.10, plan_len=0.5, flare=0.0, arch_pad=0.05)
    loft_body('tub', tub, tub_m)
    # front cowl: narrow nose with the headlamp, over the single front wheel
    cowl = dict(x0=0.10, x1=1.22, W=0.86, zc=0.40,
                wheels=[(0.98, 0.25)],
                top=[(0.10, 1.06), (0.55, 1.06), (0.95, 1.02), (1.22, 0.96)],
                belt=[(0.10, 0.98), (1.22, 0.92)],
                bottom=[(0.10, 0.36), (0.60, 0.36), (0.70, 0.56), (1.22, 0.56)],
                tumble=0.06, r_roof=0.10, r_belt=0.06, r_end=0.12,
                plan_taper=0.20, plan_len=0.55, flare=0.0, arch_pad=0.04)
    loft_body('cowl', cowl, tub_m)
    # canopy: yellow hood, rear quarters come down to the tub
    can = dict(x0=-1.36, x1=0.72, W=1.40, zc=1.42,
               wheels=[],
               top=[(-1.36, 1.50), (-1.20, 1.70), (-0.9, 1.76), (0.40, 1.76),
                    (0.72, 1.64)],
               belt=[(-1.36, 1.48), (0.72, 1.48)],
               bottom=[(-1.36, 0.78), (-0.74, 0.78), (-0.56, 1.34),
                       (-0.45, 1.44), (0.72, 1.44)],
               tumble=0.16, r_roof=0.24, r_belt=0.08, r_end=0.10,
               plan_taper=0.06, plan_len=0.4, flare=0.0, end_lift=0.0)
    loft_body('canopy', can, can_m)
    # dark open cabin + bench seat seen through the side opening
    rbox('cabin', (1.05, 1.16, 0.60), (-0.12, 0, 1.08), dark, bevel=0.02)
    rbox('bench', (0.34, 1.10, 0.14), (-0.50, 0, 0.87), seat, bevel=0.05)
    rbox('backrest', (0.12, 1.10, 0.40), (-0.66, 0, 1.08), seat, bevel=0.05)
    # windscreen (slightly raked) and black pillars
    ws = rbox('windscreen', (0.03, 0.96, 0.40), (0.64, 0, 1.25), glass,
              bevel=0.012, rot=(0, math.radians(-8), 0))
    for s in (1, -1):
        tube('pillar', [(0.55, s * 0.50, 1.02), (0.64, s * 0.52, 1.40)], 0.028, tub_m)
        tube('rpillar', [(-0.60, s * 0.66, 0.80), (-0.52, s * 0.66, 1.38)], 0.025, tub_m)
    # handlebar just visible behind the screen
    tube('bar', [(0.42, -0.40, 1.12), (0.48, -0.30, 1.10), (0.48, 0.30, 1.10),
                 (0.42, 0.40, 1.12)], 0.022, chrome)
    # headlamp + indicators on the cowl nose
    cyl('headlamp_rim', 0.13, 0.06, (1.19, 0, 0.82), stripe_m(), axis='X', bevel=0.02)
    cyl('headlamp', 0.10, 0.05, (1.22, 0, 0.82), lamp_mat(), axis='X', bevel=0.02)
    ind = simple_mat('ind', '#F29A2E', rough=0.3, spec=0.5, emit='#F29A2E', emit_s=0.2)
    for s in (1, -1):
        rbox('ind', (0.05, 0.08, 0.05), (1.10, s * 0.33, 0.95), ind, bevel=0.018)
    # yellow belt stripe on the cowl + tub (Pune/Mumbai style trim)
    stripe = simple_mat('stripe', YELLOW, rough=0.55, spec=0.35)
    rbox('tubtrim', (1.62, 1.32, 0.05), (-0.43, 0, 0.78), stripe, bevel=0.02)
    # wheels
    wheel('fw', 0.98, 0.0, 0.25, 0.17, tyre, rim, side=1, rim_frac=0.6, hub_mat=hub)
    for s in (1, -1):
        wheel('rw', -0.86, s * 0.53, 0.265, 0.19, tyre, rim, side=s, rim_frac=0.6,
              hub_mat=hub)
    # front mudguard
    rbox('guard', (0.46, 0.22, 0.05), (0.98, 0, 0.555), tub_m, bevel=0.02)
