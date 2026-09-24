"""Plan E ("Ink & Paper") line-art renders of the clay vehicle models.

  blender -b -P render_ink.py -- OUTDIR [side|top|both] vehicle [vehicle ...]

Same models and cameras as render.py (common.setup_camera for the 3/4 view,
common.setup_top_camera for the map marker). Two Eevee passes per view,
1024x1024:

  OUTDIR/<view>/<v>_id.png    every shader region (body, glass, lamps, grille,
                              tyres, rim slots...) as a flat, unlit ID colour
  OUTDIR/<view>/<v>_line.png  Freestyle ink (silhouette, external contour,
                              border, crease) over flat white surfaces
  OUTDIR/<view>/<v>_roles.json  ID colour -> role (paper / glass / dark)

The clay bodies draw glass, doors, lamps and grille in the *shader*, not the
mesh, so Freestyle alone cannot see them; export_ink.py traces the ID-colour
boundaries in 2D for those, unions them with the Freestyle strokes and fills
the regions (paper, pale glass, solid ink for tyres / grille / black trim).
"""
import colorsys
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
import common  # noqa: E402

argv = sys.argv[sys.argv.index('--') + 1:]
outdir, views, vehicles = argv[0], argv[1], argv[2:]
views = {'both': ['side', 'top']}.get(views, [views])
RES = 1024
# Freestyle ink width in px at RES. Side art ships at 256 (1x): 6 px here is
# 1.5 px on screen. Markers ship at 128: 14 px here is ~1.75 px, and the 2D
# region lines are added at the same weight in export_ink.py.
THICK = {'side': 6.0, 'top': 14.0}
CREASE = float(os.environ.get('CREASE', '120'))

# Near-black clay colours that read as solid ink in a pen drawing: tyres,
# wheel wells, grille, alloy slots, the auto's black lower body and cabin,
# seats. Everything else is paper (outlined), glass is a pale wash.
DARK = {'#2B2E34', '#141619', '#23262B', '#2E3238', '#2A2D33'}
# Large black panels (the auto-rickshaw's lower body and cabin) as solid ink
# swallow the drawing; they get a mid-tone wash instead, still outlined.
SHADE = {'#2A2C31', '#25282D'}

_roles = {}   # id hex -> role
_ids = {}     # source key -> id hex


def _id_for(key, role):
    if key not in _ids:
        n = len(_ids)
        # Well-separated hues/values so neighbouring regions never collide.
        h = (n * 0.61803398875) % 1.0
        v = 0.55 + 0.4 * ((n * 0.37) % 1.0)
        r, g, b = colorsys.hsv_to_rgb(h, 0.85, v)
        hx = '#%02X%02X%02X' % (int(r * 255), int(g * 255), int(b * 255))
        _ids[key] = hx
        _roles[hx] = role
    return _ids[key]


def _hex_of(lin):
    def to8(c):
        s = c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055
        return int(round(max(0.0, min(1.0, s)) * 255))
    return '#%02X%02X%02X' % tuple(to8(c) for c in lin[:3])


def _emission(nt, hexc):
    em = nt.nodes.new('ShaderNodeEmission')
    em.inputs['Color'].default_value = common.hexcol(hexc)
    em.inputs['Strength'].default_value = 1.0
    return em.outputs[0]


def _patched_bsdf(self, col, *a, **k):
    """NB.bsdf replacement: an unlit flat ID colour per distinct clay colour
    (a linked colour is the glass ramp)."""
    if isinstance(col, tuple):
        hx = _hex_of(col)
        role = 'dark' if hx in DARK else 'shade' if hx in SHADE else 'paper'
        key = hx
    else:
        role, key = 'glass', 'glass'
    return _emission(self.nt, _id_for(key, role))


common.NB.bsdf = _patched_bsdf


def build(name):
    if name == 'auto':
        import auto
        auto.build()
    elif name == 'bike':
        import bike
        bike.build()
    else:
        import cars
        cars.build(name)


def white_everything():
    mat = bpy.data.materials.new('white')
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    nt.links.new(_emission(nt, '#FFFFFF'), out.inputs[0])
    for ob in bpy.context.scene.objects:
        if ob.type != 'MESH':
            continue
        if ob.material_slots:
            for s in ob.material_slots:
                s.material = mat
        else:
            ob.data.materials.append(mat)


def base_render(sc):
    sc.render.engine = 'BLENDER_EEVEE_NEXT'
    sc.eevee.taa_render_samples = 1
    sc.render.filter_size = 0.0
    sc.render.film_transparent = True
    sc.render.resolution_x = RES
    sc.render.resolution_y = RES
    sc.view_settings.view_transform = 'Standard'
    sc.render.use_freestyle = False


def freestyle(sc, thick):
    sc.eevee.taa_render_samples = 16
    sc.render.filter_size = 1.5
    sc.render.use_freestyle = True
    sc.render.line_thickness_mode = 'ABSOLUTE'
    vl = sc.view_layers[0]
    vl.use_freestyle = True
    fs = vl.freestyle_settings
    fs.crease_angle = math.radians(CREASE)
    for ls in list(fs.linesets):
        fs.linesets.remove(ls)
    ls = fs.linesets.new('ink')
    ls.select_by_visibility = True
    ls.visibility = 'VISIBLE'
    ls.select_by_edge_types = True
    ls.select_silhouette = True
    ls.select_border = True
    ls.select_crease = True
    ls.select_external_contour = True
    ls.edge_type_combination = 'OR'
    st = ls.linestyle
    st.color = (0, 0, 0)
    st.thickness = thick
    st.thickness_position = 'CENTER'
    st.caps = 'ROUND'


for v in vehicles:
    for view in views:
        _roles.clear()
        _ids.clear()
        sc = common.reset()
        build(v)
        if view == 'top':
            common.setup_top_camera()
        else:
            common.setup_camera()
        d = os.path.join(outdir, view)
        os.makedirs(d, exist_ok=True)
        base_render(sc)
        sc.render.filepath = os.path.join(d, v + '_id.png')
        bpy.ops.render.render(write_still=True)
        with open(os.path.join(d, v + '_roles.json'), 'w') as fh:
            json.dump(_roles, fh, indent=1)
        white_everything()
        freestyle(sc, THICK[view])
        sc.render.filepath = os.path.join(d, v + '_line.png')
        bpy.ops.render.render(write_still=True)
        print('RENDERED', v, view)
