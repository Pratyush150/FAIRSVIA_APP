"""Step 2: build + render the 3D clay icons (Blender 4.2, headless).

  blender -b -P render.py -- RAWDIR [light|dark|both] [name ...]

Reads glyphs.json (extract.py) and roles.json (roles.py). For each icon:
filled 2D curve from the Phosphor FILL outline -> extruded with a round
bevel (soft clay, not a sharp extrusion) -> mesh, smooth shaded. Every icon
uses the same object transform, camera and light rig (reused from the clay
vehicle look in docs/brand/vehicles/clay/common.py), so size/weight/lighting
are consistent across the set.

Writes 512x512 RGBA masters:
  RAWDIR/light/<name>.png   light-mode body
  RAWDIR/shadow/<name>.png  contact-shadow pass (object invisible, catcher)
  RAWDIR/dark/<name>.png    dark-mode body (brighter clay, rim lights)
composite.py turns these into png/{light,dark}/<name>.png at 256.
"""
import json
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'vehicles', 'clay'))
import bpy  # noqa: E402
from mathutils import Euler, Matrix, Vector  # noqa: E402
import common  # noqa: E402  (hexcol, shade, set_world, area, NB)

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
RAW = argv[0] if argv else os.path.join(HERE, 'raw')
MODES = {'both': ['light', 'dark']}.get(argv[1] if len(argv) > 1 else 'both',
                                         [argv[1] if len(argv) > 1 else 'both'])
ONLY = argv[2:]
SAMPLES = int(os.environ.get('SAMPLES', '48'))
RES = int(os.environ.get('RES', '512'))

GLYPHS = json.load(open(os.path.join(HERE, 'glyphs.json')))
ROLES = json.load(open(os.path.join(HERE, 'roles.json')))['icons']

# ---------------------------------------------------------------- geometry
SIZE = 2.0          # em square -> 2 world units (Phosphor live area 224/256 = 1.75)
EXTRUDE = 0.055     # half-thickness of the straight wall
BEVEL = 0.058       # round bevel radius  -> total depth ~0.23 = 13% of live area
OFFSET = -0.058     # == -BEVEL: silhouette stays exactly the designed outline
INLAY = '#FFF6E9'   # warm cream set into enclosed counters (light)
INLAY_DARK = '#FFF6E9'
TILT_BACK = 12.0    # degrees the camera looks down (== icon tilted back)
TURN = 15.0         # degrees the camera is turned round the icon
EXPOSURE = {'light': float(os.environ.get('EXP_L', '0.9')),
            'dark': float(os.environ.get('EXP_D', '1.9'))}
PUFF = int(os.environ.get('PUFF', '24'))
VOXEL = float(os.environ.get('VOXEL', '0.008'))
FILL = float(os.environ.get('FILL', '0.84'))   # live area / frame width of the MASTER;
# composite.py scales it up to TARGET (0.92) with per-icon clamp so nothing clips
# 'chrome' role: modelled from the Regular stroke (widened a little), thinner
# slab, so nav glyphs recede next to meaningful icons
CHROME_WIDEN = 7.0 / 256   # em; Regular 16-unit stroke -> 30 units (bolder than Bold 24)
CHROME_HALF = 0.06         # half thickness (body is EXTRUDE + BEVEL = 0.113)
LIFT = 0.10         # icon floats this far above the floor (world units)

# per-icon tweaks for thin-stroke glyphs (scale-up so they don't vanish)
THIN = {}


def _area(c):
    return 0.5 * sum(c[i][0] * c[i - 1][1] - c[i - 1][0] * c[i][1] for i in range(len(c)))


def _inside(pt, c):
    x, y = pt
    ins = False
    for i in range(len(c)):
        (x1, y1), (x2, y2) = c[i - 1], c[i]
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            ins = not ins
    return ins


def holes(contours):
    """Contours at odd nesting depth = counters cut out of the body."""
    out = []
    for i, c in enumerate(contours):
        # a point just inside c: centroid of first triangle-ish probe
        probe = c[0]
        depth = sum(1 for j, o in enumerate(contours) if j != i and _inside(probe, o))
        if depth % 2 == 1:
            out.append(c)
    return out


def _curve_obj(name, contours, extrude, bevel, offset, s):
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '2D'
    cu.fill_mode = 'BOTH'
    cu.extrude = extrude
    cu.bevel_mode = 'ROUND'
    cu.bevel_depth = bevel
    cu.bevel_resolution = 6
    cu.offset = offset
    for c in contours:
        sp = cu.splines.new('POLY')
        sp.points.add(len(c) - 1)
        for p, (x, y) in zip(sp.points, c):
            p.co = ((x - 0.5) * s, (y - 0.5) * s, 0.0, 1.0)
        sp.use_cyclic_u = True
    ob = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(ob)
    ob.rotation_euler = (math.pi / 2, 0, 0)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.convert(target='MESH')
    ob = bpy.context.view_layer.objects.active
    bpy.ops.object.shade_smooth()
    return ob


def widen(contours, w):
    """Grow the ink by w (miter offset, clamped). Phosphor's winding is NOT
    consistent (dotsThree's dots are wound both ways), so direction comes
    from nesting: an outer contour (even depth) moves out of its interior,
    a counter (odd depth) moves into its own interior (shrinks the hole)."""
    out = []
    for i, c in enumerate(contours):
        n = len(c)
        outward = 1.0 if -_area(c) > 0 else -1.0   # standard CCW -> right normal is outward
        depth = sum(1 for j, o in enumerate(contours) if j != i and _inside(c[0], o))
        sgn = outward if depth % 2 == 0 else -outward
        res = []
        for i in range(n):
            a, b, d = c[i - 1], c[i], c[(i + 1) % n]
            e1 = (b[0] - a[0], b[1] - a[1])
            e2 = (d[0] - b[0], d[1] - b[1])
            l1 = math.hypot(*e1) or 1e-9
            l2 = math.hypot(*e2) or 1e-9
            n1 = (e1[1] / l1, -e1[0] / l1)
            n2 = (e2[1] / l2, -e2[0] / l2)
            m = (n1[0] + n2[0], n1[1] + n2[1])
            ml = math.hypot(*m) or 1e-9
            m = (m[0] / ml, m[1] / ml)
            k = min(2.0, 1.0 / max(0.2, m[0] * n1[0] + m[1] * n1[1]))
            res.append([b[0] + sgn * m[0] * w * k, b[1] + sgn * m[1] * w * k])
        out.append(res)
    return out


def build_icon(name):
    """-> (body, inlay or None). Body: the glyph as soft clay. Inlay: a cream
    plate filling each enclosed counter, recessed behind the body face, so a
    cut-out symbol (the tick in shieldCheck, the dot in mapPin) reads as a
    cream symbol on the coloured body at any size and on any background."""
    g = GLYPHS[name]
    s = SIZE * THIN.get(name, 1.0)
    chrome = ROLES[name]['role'] == 'chrome'
    contours = widen(g['contours_regular'], CHROME_WIDEN) if chrome else g['contours']
    half = CHROME_HALF if chrome else EXTRUDE + BEVEL
    if chrome:
        body = _curve_obj(name, contours, half, 0.0, 0.0, s)
    elif PUFF:
        # flat solid, no curve bevel: a curve bevel self-intersects on thin
        # strokes and sharp tips (spikes on broadcast/star); rounding is done
        # by voxel remesh + relax instead, which cannot self-intersect
        body = _curve_obj(name, contours, half, 0.0, 0.0, s)
    else:
        body = _curve_obj(name, g['contours'], EXTRUDE, BEVEL, OFFSET, s)
    if PUFF:
        # clay: voxel-remesh the bevelled solid then relax it, so every edge
        # (and every sharp tip the curve bevel pinches) rounds off softly
        rm = body.modifiers.new('remesh', 'REMESH')
        rm.mode = 'VOXEL'
        rm.voxel_size = VOXEL
        rm.use_smooth_shade = True
        sm = body.modifiers.new('smooth', 'CORRECTIVE_SMOOTH')
        sm.iterations = PUFF
        sm.factor = 0.5
        sm.smooth_type = 'SIMPLE'
        sm.use_only_smooth = True
        sm.use_pin_boundary = False
        bpy.ops.object.modifier_apply(modifier='remesh')
        bpy.ops.object.modifier_apply(modifier='smooth')
        bpy.ops.object.shade_smooth()
    hs = [] if chrome else holes(contours)
    inlay = None
    if hs:
        inlay = _curve_obj(name + '_inlay', hs, 0.02, 0.012, 0.004, s)
    return body, inlay


# ---------------------------------------------------------------- material
def clay_mat(hexc, mode, lo=0.86, hi=1.14):
    """Matte clay; faces toward the viewer (object -Y) a touch lighter, and a
    soft top->bottom gradient so the front face reads as the 'top' face."""
    mat = bpy.data.materials.new('clay_' + hexc + mode)
    nb = common.NB(mat)
    nt = nb.nt
    tc = [n for n in nt.nodes if n.bl_idname == 'ShaderNodeTexCoord'][0]
    sepn = nt.nodes.new('ShaderNodeSeparateXYZ')
    nt.links.new(tc.outputs['Normal'], sepn.inputs[0])
    front = nb.m('MAXIMUM', sepn.outputs[2], 0.0)       # local +Z = face toward camera
    front = nb.m('POWER', front, 4.0)
    vert = nb.m('MULTIPLY', nb.add(nb.y, 1.0), 0.5)     # local +Y = up; 0 bottom..1 top
    fac = nb.add(nb.m('MULTIPLY', front, 0.55), nb.m('MULTIPLY', vert, 0.35))
    fac = nb.m('MINIMUM', fac, 1.0)
    mix = nt.nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    nb._in(mix.inputs['Factor'], fac)
    mix.inputs[6].default_value = common.hexcol(common.shade(hexc, lo))
    mix.inputs[7].default_value = common.hexcol(common.shade(hexc, hi))
    p = nt.nodes.new('ShaderNodeBsdfPrincipled')
    nt.links.new(mix.outputs[2], p.inputs['Base Color'])
    p.inputs['Roughness'].default_value = 0.5
    p.inputs['Specular IOR Level'].default_value = 0.32
    p.inputs['Coat Weight'].default_value = 0.12
    p.inputs['Coat Roughness'].default_value = 0.25
    p.inputs['Subsurface Weight'].default_value = 0.06
    p.inputs['Subsurface Radius'].default_value = (0.05, 0.05, 0.05)
    nb.done(p.outputs[0])
    return mat


# ---------------------------------------------------------------- scene
def setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    prefs = bpy.context.preferences.addons['cycles'].preferences
    dev = 'CPU'
    for kind in ('OPTIX', 'CUDA'):
        try:
            prefs.compute_device_type = kind
            prefs.get_devices()
            if any(d.type == kind for d in prefs.devices):
                for d in prefs.devices:
                    d.use = d.type == kind
                dev = 'GPU'
                break
        except TypeError:
            pass
    sc.cycles.device = dev
    print('DEVICE', dev, prefs.compute_device_type)
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = 'OPENIMAGEDENOISE'
    sc.cycles.max_bounces = 6
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = RES
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    w = bpy.data.worlds.new('W')
    sc.world = w
    w.use_nodes = True

    # camera: perspective long lens, looking down TILT_BACK, turned TURN
    cd = bpy.data.cameras.new('Cam')
    cd.lens = 85
    cd.sensor_fit = 'HORIZONTAL'
    cam = bpy.data.objects.new('Cam', cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    e, a = math.radians(TILT_BACK), math.radians(TURN)
    d = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
    # live area 1.75 -> FILL of the frame
    frame_w = 1.75 / FILL
    dist = frame_w / (2 * 18 / 85)
    cam.location = d * dist
    cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
    cd.clip_end = 100
    # optical centre: sit the icon a hair high so the shadow has room
    cd.shift_y = -0.012

    q = cam.matrix_world.to_3x3()
    R, U, B = q.col[0], q.col[1], q.col[2]
    t = Vector((0, 0, 0))
    s = 0.55
    L = {}
    # light mode (clay rig, scaled)
    L['light'] = [
        common.area('Key', t + (-R * 3 + U * 4 + B * 5) * s, t, 520 * s * s, 4 * s),
        common.area('Fill', t + (R * 5 + U * 0.5 + B * 4) * s, t, 170 * s * s, 7 * s),
        common.area('Top', t + Vector((0, 0, 6)) * s, t, 140 * s * s, 6 * s),
        common.area('Rim', t + (R * 3.5 + U * 2 - B * 4) * s, t, 300 * s * s, 1.5 * s),
    ]
    L['dark'] = [
        common.area('DKey', t + (-R * 3 + U * 4 + B * 5) * s, t, 600 * s * s, 4 * s),
        common.area('DFill', t + (R * 5 + U * 0.5 + B * 4) * s, t, 170 * s * s, 7 * s),
        common.area('DTop', t + Vector((0, 0, 6)) * s, t, 120 * s * s, 6 * s),
        common.area('DRim', t + (R * 3.5 + U * 1.5 - B * 5) * s, t, 1100 * s * s, 0.8 * s,
                    col=(0.85, 0.92, 1.0)),
        common.area('DRim2', t + (-R * 4 + U * 1.5 - B * 5) * s, t, 700 * s * s, 0.8 * s,
                    col=(0.85, 0.92, 1.0)),
    ]
    # shadow pass: one big soft overhead light
    L['shadow'] = [common.area('Shadow', t + Vector((0.4, -0.3, 5)), t, 260, 4.5)]
    # floor / shadow catcher
    import bmesh
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=20)
    ground = common.obj_from_bm(bm, 'Ground', None, smooth=False)
    ground.is_shadow_catcher = True
    return sc, L, ground


def set_mode(sc, L, ground, parts, mode):
    for k, ls in L.items():
        for l in ls:
            l.hide_render = (k != mode)
    ground.hide_render = mode != 'shadow'
    for ob in parts:
        ob.visible_camera = mode != 'shadow'
    sc.view_settings.exposure = EXPOSURE.get(mode, 0.0)
    if mode == 'light':
        common.set_world(0.38)
    elif mode == 'dark':
        common.set_world(0.20, common.hexcol('#B8C2D0'))
    else:
        common.set_world(0.25)
    sc.cycles.samples = SAMPLES if mode != 'shadow' else max(16, SAMPLES // 2)


def main():
    sc, L, ground = setup_scene()
    names = ONLY or sorted(GLYPHS)
    mats = {}
    t0 = time.time()
    for n in names:
        ob, inlay = build_icon(n)
        parts = [ob] + ([inlay] if inlay else [])
        zmin = min((ob.matrix_world @ v.co).z for v in ob.data.vertices)
        ground.location = (0, 0, zmin - LIFT)
        for mode in MODES:
            role = ROLES[n]
            hexc = role['hex'] if mode == 'light' else role['hex_dark']
            ih = INLAY if mode == 'light' else INLAY_DARK
            blo, bhi = (0.74, 0.96) if role['role'] == 'chrome' and mode == 'light' else (0.86, 1.14)
            for part, hx, lo, hi in ((ob, hexc, blo, bhi), (inlay, ih, 0.93, 1.0)):
                if part is None:
                    continue
                key = (hx, mode, lo)
                if key not in mats:
                    mats[key] = clay_mat(hx, mode, lo, hi)
                part.data.materials.clear()
                part.data.materials.append(mats[key])
            passes = [mode] + (['shadow'] if mode == 'light' else [])
            for p in passes:
                set_mode(sc, L, ground, parts, p)
                os.makedirs(os.path.join(RAW, p), exist_ok=True)
                sc.render.filepath = os.path.join(RAW, p, n + '.png')
                bpy.ops.render.render(write_still=True)
        for part in parts:
            me = part.data
            bpy.data.objects.remove(part)
            bpy.data.meshes.remove(me)
        print('ICON', n, '%.1fs' % (time.time() - t0), flush=True)
    print('DONE', len(names), 'icons in %.1fs' % (time.time() - t0))


main()
