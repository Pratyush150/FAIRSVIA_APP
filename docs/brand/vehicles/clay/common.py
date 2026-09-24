"""Shared helpers for the RideVela clay vehicle set (Blender 4.2, bpy).

Scene, camera, lights, materials, lofted-body builder. Vehicles live in
cars.py / auto.py / bike.py; render.py is the entry point.
"""
import math
import bpy
import bmesh
import numpy as np
from mathutils import Vector


# ---------------------------------------------------------------- colour
def srgb_to_lin(c):
    c = c / 255.0 if c > 1 else c
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexcol(h, a=1.0):
    h = h.lstrip('#')
    return (srgb_to_lin(int(h[0:2], 16)), srgb_to_lin(int(h[2:4], 16)),
            srgb_to_lin(int(h[4:6], 16)), a)


def shade(h, f):
    """Darken (f<1) or lighten (f>1) a hex colour in sRGB space."""
    h = h.lstrip('#')
    rgb = [int(h[i:i + 2], 16) for i in (0, 2, 4)]
    if f < 1:
        rgb = [int(v * f) for v in rgb]
    else:
        rgb = [int(v + (255 - v) * (f - 1)) for v in rgb]
    return '#%02x%02x%02x' % tuple(rgb)


# ---------------------------------------------------------------- scene
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = 96
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = 'OPENIMAGEDENOISE'
    sc.cycles.max_bounces = 6
    sc.render.film_transparent = True
    sc.render.resolution_x = 512
    sc.render.resolution_y = 512
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    world = bpy.data.worlds.new('W')
    sc.world = world
    world.use_nodes = True
    return sc


def set_world(strength, col=(1, 1, 1, 1)):
    bg = bpy.context.scene.world.node_tree.nodes['Background']
    bg.inputs[0].default_value = col
    bg.inputs[1].default_value = strength


# ---------------------------------------------------------------- materials
class NB:
    """Tiny node-graph helper."""

    def __init__(self, mat):
        mat.use_nodes = True
        self.nt = mat.node_tree
        self.nt.nodes.clear()
        self.out = self.nt.nodes.new('ShaderNodeOutputMaterial')
        tc = self.nt.nodes.new('ShaderNodeTexCoord')
        sep = self.nt.nodes.new('ShaderNodeSeparateXYZ')
        self.nt.links.new(tc.outputs['Object'], sep.inputs[0])
        self.x, self.y, self.z = sep.outputs[0], sep.outputs[1], sep.outputs[2]

    def _in(self, sock, v):
        if isinstance(v, (int, float)):
            sock.default_value = v
        else:
            self.nt.links.new(v, sock)

    def m(self, op, a, b=0.0, c=None):
        n = self.nt.nodes.new('ShaderNodeMath')
        n.operation = op
        self._in(n.inputs[0], a)
        self._in(n.inputs[1], b)
        if c is not None:
            self._in(n.inputs[2], c)
        return n.outputs[0]

    def attr(self, name):
        n = self.nt.nodes.new('ShaderNodeAttribute')
        n.attribute_name = name
        return n.outputs['Fac']

    def gt(self, a, b):
        return self.m('GREATER_THAN', a, b)

    def lt(self, a, b):
        return self.m('LESS_THAN', a, b)

    def mul(self, *xs):
        r = xs[0]
        for v in xs[1:]:
            r = self.m('MULTIPLY', r, v)
        return r

    def add(self, a, b):
        return self.m('ADD', a, b)

    def sub(self, a, b):
        return self.m('SUBTRACT', a, b)

    def absv(self, a):
        return self.m('ABSOLUTE', a)

    def mx(self, a, b):
        return self.m('MAXIMUM', a, b)

    def inv(self, a):
        return self.m('SUBTRACT', 1.0, a)

    def ellipse(self, cy, cz, ry, rz, x0=None, sym=True, p=3.0):
        """Mask for a superellipse in the (|y|, z) plane."""
        yy = self.absv(self.y) if sym else self.y
        dy = self.absv(self.m('DIVIDE', self.sub(yy, cy), ry))
        dz = self.absv(self.m('DIVIDE', self.sub(self.z, cz), rz))
        r = self.add(self.m('POWER', dy, p), self.m('POWER', dz, p))
        return self.lt(r, 1.0)

    def box(self, y0, y1, z0, z1, sym=True):
        yy = self.absv(self.y) if sym else self.y
        return self.mul(self.gt(yy, y0), self.lt(yy, y1),
                        self.gt(self.z, z0), self.lt(self.z, z1))

    def bsdf(self, col, rough=0.55, spec=0.35, coat=0.0, emit=None, emit_s=0.0,
             metal=0.0):
        p = self.nt.nodes.new('ShaderNodeBsdfPrincipled')
        if isinstance(col, tuple):
            p.inputs['Base Color'].default_value = col
        else:
            self.nt.links.new(col, p.inputs['Base Color'])
        p.inputs['Roughness'].default_value = rough
        p.inputs['Specular IOR Level'].default_value = spec
        p.inputs['Metallic'].default_value = metal
        p.inputs['Coat Weight'].default_value = coat
        p.inputs['Coat Roughness'].default_value = 0.08
        if emit:
            p.inputs['Emission Color'].default_value = emit
            p.inputs['Emission Strength'].default_value = emit_s
        return p.outputs[0]

    def mix(self, fac, a, b):
        n = self.nt.nodes.new('ShaderNodeMixShader')
        self._in(n.inputs[0], fac)
        self.nt.links.new(a, n.inputs[1])
        self.nt.links.new(b, n.inputs[2])
        return n.outputs[0]

    def glass_col(self, t_lo, t_hi, dark='#0F141B', light='#2E3A48', k=0.55):
        """Dark glass with a soft diagonal reflection band."""
        t = self.add(self.z, self.m('MULTIPLY', self.x, k))
        mr = self.nt.nodes.new('ShaderNodeMapRange')
        self.nt.links.new(t, mr.inputs['Value'])
        mr.inputs['From Min'].default_value = t_lo
        mr.inputs['From Max'].default_value = t_hi
        cr = self.nt.nodes.new('ShaderNodeValToRGB')
        self.nt.links.new(mr.outputs[0], cr.inputs[0])
        el = cr.color_ramp.elements
        el[0].position = 0.0
        el[0].color = hexcol(dark)
        el[1].position = 1.0
        el[1].color = hexcol(dark)
        for pos, c in ((0.52, dark), (0.58, light), (0.66, light), (0.74, dark)):
            e = el.new(pos)
            e.color = hexcol(c)
        cr.color_ramp.interpolation = 'EASE'
        return cr.outputs[0]

    def done(self, shader):
        self.nt.links.new(shader, self.out.inputs[0])


def simple_mat(name, col, rough=0.55, spec=0.35, metal=0.0, coat=0.0,
               emit=None, emit_s=0.0):
    mat = bpy.data.materials.new(name)
    nb = NB(mat)
    nb.done(nb.bsdf(hexcol(col), rough, spec, coat, emit=hexcol(emit) if emit else None,
                    emit_s=emit_s, metal=metal))
    return mat


def rim_mat(name, col, n=5, rr=0.22):
    """Alloy face: n dark slots between spokes (object space, axis local Z)."""
    mat = bpy.data.materials.new(name)
    nb = NB(mat)
    ang = nb.m('ARCTAN2', nb.y, nb.x)
    wave = nb.m('SINE', nb.m('MULTIPLY', ang, float(n)))
    rad = nb.m('LENGTH_PLACEHOLDER', 0) if False else nb.m('SQRT', nb.add(
        nb.m('POWER', nb.x, 2.0), nb.m('POWER', nb.y, 2.0)))
    slot = nb.mul(nb.gt(wave, 0.35), nb.gt(rad, rr * 0.36), nb.lt(rad, rr * 0.84))
    ring = nb.mul(nb.gt(rad, rr * 0.90), nb.lt(rad, rr * 0.93))
    face = nb.bsdf(hexcol(col), rough=0.35, spec=0.5)
    dark = nb.bsdf(hexcol('#2E3238'), rough=0.6, spec=0.2)
    nb.done(nb.mix(nb.mx(slot, ring), face, dark))
    return mat


def glass_mat(name, span):
    mat = bpy.data.materials.new(name)
    nb = NB(mat)
    nb.done(nb.bsdf(nb.glass_col(*span), rough=0.12, spec=0.6, coat=0.6))
    return mat


# ---------------------------------------------------------------- meshes
def obj_from_bm(bm, name, mat=None, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if mat:
        me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = smooth
    return ob


def add_bevel(ob, width, seg=4, angle=None):
    mod = ob.modifiers.new('bevel', 'BEVEL')
    mod.width = width
    mod.segments = seg
    mod.limit_method = 'ANGLE'
    mod.angle_limit = math.radians(angle or 30)
    mod.harden_normals = False
    return mod


def rbox(name, size, loc, mat, bevel=0.03, seg=4, rot=(0, 0, 0)):
    """Rounded box."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    ob = obj_from_bm(bm, name, mat)
    ob.location = loc
    ob.rotation_euler = rot
    add_bevel(ob, bevel, seg)
    return ob


def cyl(name, r, depth, loc, mat, axis='Y', verts=48, bevel=0.0, seg=3,
        r2=None, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=verts,
                          radius1=r, radius2=r2 if r2 is not None else r,
                          depth=depth)
    ob = obj_from_bm(bm, name, mat)
    ob.location = loc
    if rot is not None:
        ob.rotation_euler = rot
    elif axis == 'Y':
        ob.rotation_euler = (math.pi / 2, 0, 0)
    elif axis == 'X':
        ob.rotation_euler = (0, math.pi / 2, 0)
    if bevel:
        add_bevel(ob, bevel, seg)
    return ob


def sphere(name, r, loc, mat, scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=48, v_segments=24, radius=r)
    ob = obj_from_bm(bm, name, mat)
    ob.location = loc
    ob.scale = scale
    return ob


def tube(name, pts, r, mat, verts=16):
    """Polyline tube (handlebars, frames): chain of cylinders + joint spheres."""
    obs = []
    for i in range(len(pts) - 1):
        a, b = Vector(pts[i]), Vector(pts[i + 1])
        d = b - a
        ob = cyl(name, r, d.length, (a + b) / 2, mat, verts=verts, rot=(0, 0, 0))
        ob.rotation_mode = 'QUATERNION'
        ob.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
        obs.append(ob)
    for p in pts[1:-1]:
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=verts, v_segments=verts // 2, radius=r)
        s = obj_from_bm(bm, name + 'j', mat)
        s.location = p
    return obs


def wheel(name, x, y, r, width, tyre_mat, rim_mat, side=1, rim_frac=0.64,
          hub_mat=None):
    """Chunky tyre + rim facing +/-Y. side=+1 means outer face at +y."""
    t = cyl(name + '_tyre', r, width, (x, y, r), tyre_mat, verts=64)
    add_bevel(t, width * 0.32, 5)
    rr = r * rim_frac
    rim = cyl(name + '_rim', rr, width * 1.0, (x, y + side * 0.008, r), rim_mat,
              verts=64)
    add_bevel(rim, 0.015, 3)
    if hub_mat:
        hub = cyl(name + '_hub', rr * 0.26, width * 1.0,
                  (x, y + side * 0.025, r), hub_mat, verts=32)
        add_bevel(hub, 0.012, 3)
    return t


# ---------------------------------------------------------------- loft body
def smooth_curve(xs, keys, sigma):
    kx = [k[0] for k in keys]
    kz = [k[1] for k in keys]
    z = np.interp(xs, kx, kz)
    if sigma <= 0:
        return z
    dx = xs[1] - xs[0]
    n = int(3 * sigma / dx)
    k = np.exp(-0.5 * (np.arange(-n, n + 1) * dx / sigma) ** 2)
    k /= k.sum()
    zp = np.pad(z, n, mode='edge')
    return np.convolve(zp, k, mode='valid')


def erode(xs, z, m):
    """Offset a top profile downward by distance m (perpendicular)."""
    dx = xs[1] - xs[0]
    n = int(m / dx)
    out = np.full_like(z, 1e9)
    for i in range(-n, n + 1):
        d = i * dx
        drop = math.sqrt(max(m * m - d * d, 0))
        sh = np.roll(z, -i)
        if i > 0:
            sh[-i:] = z[-1]
        elif i < 0:
            sh[:-i] = z[0]
        out = np.minimum(out, sh - drop)
    return out


def rounded_poly(corners, radii, kc=8, ke=5):
    """Closed polygon with rounded corners, fixed point count."""
    n = len(corners)
    pts = []
    C = [np.array(c, float) for c in corners]
    for i in range(n):
        p0, p1, p2 = C[i - 1], C[i], C[(i + 1) % n]
        e0 = p1 - p0
        e1 = p2 - p1
        l0 = np.linalg.norm(e0) + 1e-9
        l1 = np.linalg.norm(e1) + 1e-9
        r = min(radii[i], 0.49 * l0, 0.49 * l1)
        a = p1 - e0 / l0 * r
        b = p1 + e1 / l1 * r
        for k in range(kc):
            t = k / (kc - 1)
            pts.append((1 - t) ** 2 * a + 2 * (1 - t) * t * p1 + t * t * b)
        # straight edge samples toward next corner's start
        p3 = C[(i + 2) % n]
        e2 = p3 - p2
        l2 = np.linalg.norm(e2) + 1e-9
        r2 = min(radii[(i + 1) % n], 0.49 * l1, 0.49 * l2)
        a2 = p2 - e1 / l1 * r2
        for k in range(1, ke + 1):
            t = k / (ke + 1)
            pts.append(b + (a2 - b) * t)
    return pts


def loft_body(name, spec, mat):
    """Build a car body by lofting rounded cross-sections along X.

    spec keys: x0, x1 (rear/front ends), W (full width),
      top: [(x,z)] roof/hood/boot profile, belt: [(x,z)], bottom clearance zc,
      wheels: [(x, r)], tumble, r_end, sigma
    Writes per-vertex attributes used by the body shader:
      zbelt, zwtop (window-top boundary), wt (top half-width), slope.
    """
    x0, x1 = spec['x0'], spec['x1']
    dx = 0.01
    xs = np.arange(x0, x1 + 1e-6, dx)
    ztop = smooth_curve(xs, spec['top'], spec.get('sigma', 0.07))
    zbelt = smooth_curve(xs, spec['belt'], 0.05)
    zwtop = erode(xs, ztop, spec.get('pillar', 0.075))
    slope = np.abs(np.gradient(ztop, dx))
    W2 = spec['W'] / 2
    zc = spec.get('zc', 0.30)
    if 'bottom' in spec:
        zbot_curve = smooth_curve(xs, spec['bottom'], 0.04)
    tumble = spec.get('tumble', 0.17)
    r_end = spec.get('r_end', 0.13)
    arch_pad = spec.get('arch_pad', 0.06)
    kc, ke = 8, 5

    rings = []
    ring_attr = []
    for i, x in enumerate(xs):
        d = min(x - x0, x1 - x)
        # plan-view rounding of the corners
        pt = spec.get('plan_taper', 0.14)
        pl = spec.get('plan_len', 0.70)
        w = W2 - pt * max(0.0, 1 - d / pl) ** 2
        for (wx, wr) in spec['wheels']:
            u = (x - wx) / (wr + 0.25)
            if abs(u) < 1:
                w += spec.get('flare', 0.035) * (0.5 + 0.5 * math.cos(math.pi * u))
        zb = zc + spec.get('end_lift', 0.06) * max(0.0, 1 - d / 0.45) ** 2
        if 'bottom' in spec:
            zb = zbot_curve[i]
        for (wx, wr) in spec['wheels']:
            ra = wr + arch_pad
            if abs(x - wx) < ra:
                zb = max(zb, wr + math.sqrt(ra * ra - (x - wx) ** 2) * 1.0 - 0.02)
        zt = ztop[i]
        zbl = min(zbelt[i], zt - 0.002)
        g = max(0.0, min(1.0, (zt - zbl) / 0.25))
        g = g * g * (3 - 2 * g)
        wt = w - tumble * g
        # end rounding: inward offset (quarter circle)
        off = 0.0
        if d < r_end:
            off = r_end - math.sqrt(max(r_end ** 2 - (r_end - d) ** 2, 0))
        wo, wto, wbo = w - off, wt - off, w - 0.05 - off
        zbo, zto = zb + off, zt - off
        zblo = min(max(zbl, zbo + 0.02), zto - 0.001)
        corners = [(wbo, zbo), (wo, zblo), (wto, zto), (-wto, zto), (-wo, zblo), (-wbo, zbo)]
        radii = [0.10, spec.get('r_belt', 0.07), spec.get('r_roof', 0.16),
                 spec.get('r_roof', 0.16), spec.get('r_belt', 0.07), 0.10]
        pts = rounded_poly(corners, radii, kc, ke)
        rings.append([(x, p[0], p[1]) for p in pts])
        ring_attr.append((zbelt[i], zwtop[i], wt, slope[i], w))

    bm = bmesh.new()
    M = len(rings[0])
    vrings = []
    for ring in rings:
        vrings.append([bm.verts.new(p) for p in ring])
    for a, b in zip(vrings[:-1], vrings[1:]):
        for j in range(M):
            bm.faces.new((a[j], a[(j + 1) % M], b[(j + 1) % M], b[j]))
    capr = bm.faces.new(list(reversed(vrings[0])))
    capf = bm.faces.new(vrings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = obj_from_bm(bm, name, mat)
    me = ob.data
    me.polygons[-1].use_smooth = False
    me.polygons[-2].use_smooth = False
    names = ['zbelt', 'zwtop', 'wt', 'slope', 'hw']
    for k, nm in enumerate(names):
        at = me.attributes.new(nm, 'FLOAT', 'POINT')
        vals = []
        for ra in ring_attr:
            vals.extend([ra[k]] * M)
        at.data.foreach_set('value', vals)
    ob['spec_x'] = (x0, x1)
    return ob


def body_material(name, col, spec, glass_span):
    """Clay body with shader-drawn glass, door lines, lamps and grille."""
    mat = bpy.data.materials.new(name)
    nb = NB(mat)
    x0, x1 = spec['x0'], spec['x1']
    ay = nb.absv(nb.y)
    zbelt = nb.attr('zbelt')
    zwtop = nb.attr('zwtop')
    wt = nb.attr('wt')
    slope = nb.attr('slope')
    hw = nb.attr('hw')

    # --- side glass
    side = nb.mul(nb.gt(nb.z, nb.add(zbelt, 0.035)), nb.lt(nb.z, zwtop),
                  nb.gt(ay, 0.35))
    side_raw = side
    for (p0, p1) in spec.get('pillars', []):
        side = nb.mul(side, nb.inv(nb.mul(nb.gt(nb.x, p0), nb.lt(nb.x, p1))))
    if spec.get('dark_pillars'):
        side = side_raw  # Swift-style blacked-out pillars: floating roof
    chrome = None
    if spec.get('chrome'):
        outer = nb.mul(nb.gt(nb.z, nb.add(zbelt, 0.012)),
                       nb.lt(nb.z, nb.add(zwtop, 0.022)), nb.gt(ay, 0.35))
        chrome = nb.mul(outer, nb.inv(side_raw))
    # --- windscreen / rear glass
    s0 = spec.get('slope_glass', 0.5)
    wind = nb.mul(nb.gt(slope, s0), nb.lt(ay, nb.sub(wt, 0.085)),
                  nb.gt(nb.z, nb.add(zbelt, 0.07)))
    glass = nb.mx(side, wind)

    # --- door shut lines + handles (darker clay)
    line = 0.0
    lw = 0.0055
    below = nb.mul(nb.lt(nb.z, nb.add(zbelt, 0.02)), nb.gt(ay, nb.sub(hw, 0.06)))
    for xd in spec.get('doors', []):
        l = nb.lt(nb.absv(nb.sub(nb.x, xd)), lw)
        line = nb.mx(line, l) if not isinstance(line, float) else l
    if not isinstance(line, float):
        line = nb.mul(line, below, nb.gt(nb.z, spec.get('zc', 0.3) + 0.08))
    for (hx, hz) in spec.get('handles', []):
        h = nb.mul(nb.lt(nb.absv(nb.sub(nb.x, hx)), 0.075),
                   nb.lt(nb.absv(nb.sub(nb.z, hz)), 0.014), nb.gt(ay, nb.sub(hw, 0.06)))
        line = nb.mx(line, h) if not isinstance(line, float) else h

    # --- front lamps / grille, rear lamps
    front = nb.gt(nb.x, x1 - spec.get('lamp_depth', 0.30))
    rear = nb.lt(nb.x, x0 + 0.25)
    hl = spec['headlamp']  # (yc, zc, ry, rz)
    lamp = nb.mul(front, nb.ellipse(*hl))
    gr = spec['grille']  # (yhalf, z0, z1)
    grille = nb.mul(nb.gt(nb.x, x1 - 0.12), nb.box(-1, gr[0], gr[1], gr[2]))
    if 'intake' in spec:
        it = spec['intake']
        grille = nb.mx(grille, nb.mul(nb.gt(nb.x, x1 - 0.12), nb.box(-1, it[0], it[1], it[2])))
    tl = spec['taillamp']
    tail = nb.mul(rear, nb.ellipse(*tl))

    body = nb.bsdf(hexcol(col), rough=0.5, spec=0.4, coat=0.08)
    linec = nb.bsdf(hexcol(shade(col, 0.62)), rough=0.6, spec=0.2)
    glassb = nb.bsdf(nb.glass_col(*glass_span), rough=0.18, spec=0.45, coat=0.25)
    lampb = nb.bsdf(hexcol('#F4F6F8'), rough=0.2, spec=0.6, coat=0.5,
                    emit=hexcol('#FFF6E0'), emit_s=0.35)
    grb = nb.bsdf(hexcol('#23262B'), rough=0.55, spec=0.3)
    tailb = nb.bsdf(hexcol('#C8323C'), rough=0.3, spec=0.5, coat=0.5,
                    emit=hexcol('#E0404A'), emit_s=0.15)
    s = body
    if not isinstance(line, float):
        s = nb.mix(line, s, linec)
    s = nb.mix(grille, s, grb)
    s = nb.mix(lamp, s, lampb)
    s = nb.mix(tail, s, tailb)
    s = nb.mix(glass, s, glassb)
    if chrome is not None:
        chb = nb.bsdf(hexcol('#C9CFD6'), rough=0.2, spec=0.7, metal=0.5)
        s = nb.mix(chrome, s, chb)
        gch = nb.mul(nb.gt(nb.x, x1 - 0.10), nb.box(-1, spec['grille'][0] + 0.03,
                     spec['grille'][1] - 0.03, spec['grille'][2] + 0.03))
        gin = nb.mul(nb.gt(nb.x, x1 - 0.10), nb.box(-1, spec['grille'][0],
                     spec['grille'][1], spec['grille'][2]))
        s = nb.mix(nb.mul(gch, nb.inv(gin)), s, chb)
    nb.done(s)
    return mat


# ---------------------------------------------------------------- camera/light
CAM_ELEV = 30.0
CAM_AZ = 35.0  # degrees rotated from pure side view toward the front


def cam_dir():
    e, a = math.radians(CAM_ELEV), math.radians(CAM_AZ)
    return Vector((math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e)))


def mesh_points():
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for ob in bpy.context.scene.objects:
        if ob.type != 'MESH' or ob.get('nofit'):
            continue
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        mw = ob.matrix_world
        vs = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get('co', vs)
        vs = vs.reshape(-1, 3)
        M = np.array(mw)
        vs = vs @ M[:3, :3].T + M[:3, 3]
        pts.append(vs[:: max(1, len(vs) // 4000)])
        ev.to_mesh_clear()
    return np.concatenate(pts)


def setup_camera(fill=0.80, ground=0.17, lens=70):
    from bpy_extras.object_utils import world_to_camera_view
    sc = bpy.context.scene
    cd = bpy.data.cameras.new('Cam')
    cd.lens = lens
    cam = bpy.data.objects.new('Cam', cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    pts = mesh_points()
    c = Vector(((pts[:, 0].min() + pts[:, 0].max()) / 2,
                (pts[:, 1].min() + pts[:, 1].max()) / 2,
                (pts[:, 2].min() + pts[:, 2].max()) / 2))
    d = cam_dir()
    dist = 12.0
    for _ in range(6):
        cam.location = c + d * dist
        cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
        cd.shift_x = cd.shift_y = 0
        bpy.context.view_layer.update()
        pp = [world_to_camera_view(sc, cam, Vector(p)) for p in pts]
        xs = [p.x for p in pp]
        width = max(xs) - min(xs)
        dist *= width / fill
    cam.location = c + d * dist
    bpy.context.view_layer.update()
    pp = [world_to_camera_view(sc, cam, Vector(p)) for p in pts]
    xs = [p.x for p in pp]
    ys = [p.y for p in pp]
    cd.shift_x = ((min(xs) + max(xs)) / 2 - 0.5)
    cd.shift_y = (min(ys) - ground)
    return cam, c


def area(name, loc, target, energy, size, col=(1, 1, 1)):
    ld = bpy.data.lights.new(name, 'AREA')
    ld.energy = energy
    ld.size = size
    ld.color = col
    ob = bpy.data.objects.new(name, ld)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    return ob


def exclude_ground(light_ob, ground):
    """Key/fill light the car but not the shadow catcher: only the soft
    overhead light (and world) casts the contact shadow."""
    if ground is None:
        return
    coll = bpy.data.collections.get('no_ground')
    if coll is None:
        coll = bpy.data.collections.new('no_ground')
        coll.objects.link(ground)
        coll.collection_objects[0].light_linking.link_state = 'EXCLUDE'
    light_ob.light_linking.receiver_collection = coll


def lights(cam, target, mode, scale=1.0, ground=None):
    q = cam.matrix_world.to_3x3()
    R, U, B = q.col[0], q.col[1], q.col[2]
    t = Vector(target)
    s = scale
    if mode == 'light':
        set_world(0.30)
        area('Key', t + (-R * 4 + U * 6 + B * 2.5) * s, t, 450 * s * s, 4 * s)
        area('Fill', t + (R * 6 + U * 1.0 + B * 3) * s, t, 130 * s * s, 7 * s)
        area('Top', t + Vector((0, 0, 6)) * s, t, 120 * s * s, 6 * s)
    else:
        set_world(0.22, hexcol('#B8C2D0'))
        area('Key', t + (-R * 4 + U * 6 + B * 2.5) * s, t, 520 * s * s, 5 * s)
        area('Fill', t + (R * 6 + U * 1.5 + B * 3) * s, t, 90 * s * s, 7 * s)
        area('Rim', t + (R * 3.5 + U * 1.2 - B * 6) * s, t, 1000 * s * s, 0.8 * s,
             col=(0.85, 0.92, 1.0))
        area('Rim2', t + (-R * 4 + U * 1.2 - B * 6) * s, t, 650 * s * s, 0.8 * s,
             col=(0.85, 0.92, 1.0))


def shadow_pass(path):
    """Second render: only the soft overhead light + world, vehicle invisible
    to camera, onto a shadow catcher. Composited under the vehicle later so
    the contact shadow strength is controlled independently of the key."""
    sc = bpy.context.scene
    for ob in list(sc.objects):
        if ob.type == 'LIGHT' and ob.name != 'Top':
            ob.hide_render = True
        elif ob.type == 'MESH':
            ob.visible_camera = False
    shadow_catcher()
    sc.cycles.samples = 64
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def shadow_catcher(size=30):
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=size)
    ob = obj_from_bm(bm, 'Ground', None, smooth=False)
    ob.is_shadow_catcher = True
    ob['nofit'] = True
    return ob


def setup_top_camera(fill=0.88):
    """Map marker: orthographic, straight down, nose (+X) pointing up."""
    sc = bpy.context.scene
    cd = bpy.data.cameras.new('TopCam')
    cd.type = 'ORTHO'
    cam = bpy.data.objects.new('TopCam', cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    pts = mesh_points()
    cx = (pts[:, 0].min() + pts[:, 0].max()) / 2
    cy = (pts[:, 1].min() + pts[:, 1].max()) / 2
    L = pts[:, 0].max() - pts[:, 0].min()
    W = pts[:, 1].max() - pts[:, 1].min()
    cd.ortho_scale = max(L, W) / fill
    cam.location = (cx, cy, 20)
    cam.rotation_euler = (0, 0, -math.pi / 2)
    cd.clip_end = 100
    return cam, Vector((cx, cy, 0.8))


def top_lights(target, s=1.0):
    t = Vector(target)
    set_world(0.40)
    # key from the upper-left of the marker (front-left of the vehicle)
    area('Key', t + Vector((3, 3, 8)) * s, t, 700 * s * s, 4 * s)
    area('Fill', t + Vector((-3, -4, 5)) * s, t, 180 * s * s, 6 * s)
