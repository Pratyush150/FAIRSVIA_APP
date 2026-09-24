"""Four-wheel RideVela vehicles: economy, comfort, xl, premium, driver.

Front of every vehicle points to +X, its left side faces +Y (the camera side).
Units are metres; proportions are real-ish but chunkier (bigger wheels,
shorter overhangs, more tumblehome) so they read at 64 px.
"""
from common import (loft_body, body_material, simple_mat, rbox, wheel, cyl, rim_mat,
                    shade, add_bevel)

TYRE = '#2B2E34'
RIM = '#C9CED5'
HUB = '#8C939C'

SPECS = {
    # Swift-like hatch: short nose, tall cabin, steep hatch, thick C-pillar.
    'economy': dict(
        col='#2BC4C4', x0=-1.85, x1=1.85, W=1.80, zc=0.30,
        wheels=[(-1.22, 0.39), (1.24, 0.39)],
        top=[(-1.85, 1.00), (-1.80, 1.14), (-1.62, 1.42), (-1.42, 1.53),
             (0.05, 1.56), (0.28, 1.52), (0.98, 1.04), (1.55, 0.94), (1.85, 0.82)],
        belt=[(-1.85, 1.06), (0.98, 0.96), (1.85, 0.90)],
        pillars=[(-0.13, -0.05), (-1.9, -1.02)],
        doors=[0.93, -0.09, -1.05], handles=[(0.07, 0.885), (-0.9, 0.905)],
        headlamp=(0.60, 0.71, 0.22, 0.075), grille=(0.36, 0.45, 0.62),
        taillamp=(0.68, 1.02, 0.12, 0.13), tumble=0.18, r_roof=0.17,
        dark_pillars=True,
        glass_span=(0.2, 2.4),
    ),
    # Dzire/City-like notchback sedan.
    'comfort': dict(
        col='#5B6B80', x0=-2.15, x1=2.15, W=1.80, zc=0.30,
        wheels=[(-1.36, 0.385), (1.36, 0.385)],
        top=[(-2.15, 0.94), (-2.07, 1.03), (-1.62, 1.07), (-1.28, 1.13),
             (-0.72, 1.46), (-0.35, 1.50), (0.28, 1.49), (1.08, 1.01),
             (1.82, 0.91), (2.15, 0.79)],
        belt=[(-2.15, 1.01), (1.08, 0.95), (2.15, 0.87)],
        pillars=[(-0.08, 0.01)],
        doors=[1.03, -0.04, -1.08], handles=[(0.12, 0.88), (-0.93, 0.89)],
        headlamp=(0.60, 0.68, 0.25, 0.07), grille=(0.42, 0.44, 0.60),
        intake=(0.55, 0.35, 0.40),
        taillamp=(0.62, 0.91, 0.20, 0.07), tumble=0.17,
        glass_span=(0.0, 2.6),
    ),
    # Ertiga/Innova-like MPV: long flat roof, upright tailgate, 3 side windows.
    'xl': dict(
        col='#E8D5B5', x0=-2.25, x1=2.25, W=1.84, zc=0.33,
        wheels=[(-1.42, 0.41), (1.45, 0.41)],
        top=[(-2.25, 1.02), (-2.21, 1.28), (-2.12, 1.66), (-1.95, 1.77),
             (0.30, 1.80), (0.58, 1.74), (1.22, 1.13), (1.85, 1.00), (2.25, 0.86)],
        belt=[(-2.25, 1.12), (1.22, 1.03), (2.25, 0.93)],
        pillars=[(0.05, 0.14), (-1.07, -0.98), (-2.3, -1.98)],
        doors=[1.17, 0.095, -1.03], handles=[(0.24, 0.94), (-0.88, 0.955)],
        headlamp=(0.60, 0.80, 0.23, 0.08), grille=(0.44, 0.52, 0.72),
        intake=(0.52, 0.38, 0.44),
        taillamp=(0.72, 1.18, 0.11, 0.15), tumble=0.16, r_roof=0.18,
        glass_span=(0.2, 2.9),
    ),
    # Long, low executive saloon: long hood, fastback-ish rear glass.
    'premium': dict(
        col='#3A3D42', x0=-2.45, x1=2.50, W=1.86, zc=0.28,
        wheels=[(-1.55, 0.395), (1.47, 0.395)],
        top=[(-2.45, 0.92), (-2.36, 1.01), (-1.86, 1.05), (-1.42, 1.13),
             (-0.80, 1.43), (-0.40, 1.47), (0.22, 1.47), (1.06, 0.99),
             (2.15, 0.91), (2.50, 0.84)],
        belt=[(-2.45, 0.99), (1.06, 0.94), (2.50, 0.87)],
        pillars=[(-0.26, -0.17)],
        doors=[1.01, -0.215, -1.38], handles=[(-0.05, 0.86), (-1.20, 0.87)],
        headlamp=(0.64, 0.73, 0.24, 0.055), grille=(0.34, 0.42, 0.72),
        intake=(0.62, 0.33, 0.38),
        taillamp=(0.60, 0.90, 0.26, 0.05), tumble=0.18, r_roof=0.15,
        glass_span=(-0.2, 2.6), chrome=True,
    ),
}
SPECS['driver'] = dict(SPECS['comfort'], col='#D3D7DD')


def build(name):
    spec = SPECS[name]
    col = spec['col']
    body_mat = body_material(name + '_body', col, spec, spec['glass_span'])
    body = loft_body(name + '_body', spec, body_mat)
    tyre = simple_mat('tyre', TYRE, rough=0.75, spec=0.25)
    rim = rim_mat('rim', RIM, rr=spec['wheels'][0][1] * 0.64)
    hub = simple_mat('hub', HUB, rough=0.4, spec=0.4)
    well = simple_mat('well', '#141619', rough=0.9, spec=0.1)
    W2 = spec['W'] / 2
    for i, (wx, wr) in enumerate(spec['wheels']):
        for side in (1, -1):
            yc = side * (W2 + 0.005 - 0.15)
            wheel('w%d%d' % (i, side), wx, yc, wr, 0.30, tyre, rim, side=side,
                  hub_mat=hub)
        rbox('well%d' % i, (2 * wr, spec['W'] - 0.34, 1.4 * wr), (wx, 0, wr * 1.2),
             well, bevel=0.0)
    # side mirrors (body colour) at the windscreen base
    xm = [k for k in spec['top'] if k[1] < 1.2 and k[0] > 0][0][0] - 0.12
    zb = spec['belt'][1][1]
    mm = simple_mat('mirror', col, rough=0.5, spec=0.4)
    for side in (1, -1):
        m = rbox('mirror', (0.16, 0.13, 0.11), (xm, side * (W2 + 0.02), zb + 0.08),
                 mm, bevel=0.045)
        rbox('mstalk', (0.08, 0.10, 0.04), (xm + 0.02, side * (W2 - 0.05), zb + 0.05),
             mm, bevel=0.015)
    return body
