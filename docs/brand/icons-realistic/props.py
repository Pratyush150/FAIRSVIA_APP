"""Realistic props for the Home tiles: prebook, someone_else, saved, add_stop,
coins, star, tag. Units ~ decimetres; all subjects ~1-2 units tall.

Textures come from textures.py (run first, into RV_TEX, default
~/.cache/ridevela-3d/tex).
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'vehicles', 'clay'))
from common import rounded_poly  # noqa: E402

import rcommon as rc  # noqa: E402

TEX = os.environ.get('RV_TEX', os.path.expanduser('~/.cache/ridevela-3d/tex'))
AZ = 30.0


def tex(name):
    return os.path.join(TEX, name)


# ---------------------------------------------------------------- helpers
def slab(name, pts2d, t, mat, bevel=0.012, seg=3, uv_box=None):
    """Extrude a closed 2D polygon (XY) by t along +Z; planar UVs from XY."""
    bm = bmesh.new()
    vs = [bm.verts.new((p[0], p[1], 0.0)) for p in pts2d]
    f = bm.faces.new(vs)
    if f.normal.z < 0:
        f.normal_flip()
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    top = [e for e in ext['geom'] if isinstance(e, bmesh.types.BMVert)]
    for v in top:
        v.co.z += t
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    xs = [p[0] for p in pts2d]
    ys = [p[1] for p in pts2d]
    x0, x1, y0, y1 = uv_box or (min(xs), max(xs), min(ys), max(ys))
    uvl = bm.loops.layers.uv.new('UVMap')
    for face in bm.faces:
        for lp in face.loops:
            co = lp.vert.co
            lp[uvl].uv = ((co.x - x0) / (x1 - x0), (co.y - y0) / (y1 - y0))
    ob = rc.obj_from_bm(bm, name, mat, smooth=False)
    if bevel:
        m = ob.modifiers.new('bv', 'BEVEL')
        m.width = bevel
        m.segments = seg
        m.limit_method = 'ANGLE'
        m.harden_normals = True
    ob.data.shade_smooth()
    ob.data.set_sharp_from_angle(angle=math.radians(40))
    return ob


def rrect(w, h, r, kc=10, ke=3):
    c = [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]
    return [tuple(p) for p in rounded_poly(c, [r] * 4, kc, ke)]


def group(name, objs):
    e = rc.link(bpy.data.objects.new(name, None))
    for o in objs:
        o.parent = e
    return e


def teal_paint(name='teal', col=rc.TEAL):
    return rc.pbsdf(name, col, rough=0.35, coat=0.7, coat_rough=0.06, spec=0.5)


def finish(az=AZ, fill=rc.FILL, lens=70, scale=1.0, elev=None, **kw):
    cam, c, dist = rc.setup_camera(az=az, fill=fill, lens=lens, elev=elev)
    rc.studio(cam, c, scale, **kw)
    return cam, c, dist


# ---------------------------------------------------------------- prebook
def prebook():
    W, H, T = 1.6, 1.3, 0.05
    tilt = math.radians(14)             # lean back from vertical
    board = rc.pbsdf('board', '#2B2F34', rough=0.45, coat=0.3)
    page = rc.image_mat('page', tex('calendar_page.png'), rough=0.55, sss=0.02)
    rc.add_noise_bump(page, scale=400, strength=0.03)
    stack = rc.pbsdf('stack', '#F1F0EC', rough=0.7)
    rc.add_noise_bump(stack, scale=900, strength=0.15)
    chrome = rc.pbsdf('ring', '#D9DDE2', rough=0.1, metal=1.0)
    objs = []
    # stiff back board (dark) and page stack in front
    b = slab('board', rrect(W + 0.06, H + 0.04, 0.05), 0.04, board, bevel=0.01)
    objs.append(b)
    s = slab('stack', rrect(W, H - 0.04, 0.03), 0.07, stack, bevel=0.006)
    s.location.z = 0.04
    objs.append(s)
    p = slab('page', rrect(W, H - 0.04, 0.03), 0.012, page, bevel=0.004)
    p.location.z = 0.11
    objs.append(p)
    # spiral rings along the top edge
    for i in range(14):
        x = -W / 2 + 0.14 + i * (W - 0.28) / 13
        bpy.ops.mesh.primitive_torus_add(major_radius=0.055, minor_radius=0.011,
                                         major_segments=32, minor_segments=12,
                                         location=(x, H / 2 - 0.03, 0.06),
                                         rotation=(0, math.pi / 2, 0))
        tor = bpy.context.active_object
        tor.data.materials.append(chrome)
        tor.data.shade_smooth()
        objs.append(tor)
    front = group('front', objs)
    # stand the panel up: local +Z (page normal) -> toward camera side (+Y)
    front.rotation_euler = (math.pi / 2 - tilt, 0, math.pi)
    front.location = (0, 0, (H / 2) * math.cos(tilt) + 0.02)
    # rear easel leg
    leg = slab('leg', rrect(W * 0.9, H * 0.95, 0.04), 0.03, board, bevel=0.008)
    leg.rotation_euler = (math.pi / 2 + math.radians(26), 0, math.pi)
    leg.location = (0, -0.47, 0.70)
    root = group('cal', [front, leg])
    root.rotation_euler = (0, 0, math.radians(-14))
    bpy.context.view_layer.update()
    return finish(fill=0.70)


# ---------------------------------------------------------------- phone
def someone_else():
    W, H, T = 0.78, 1.60, 0.10
    frame = rc.pbsdf('frame', '#BFC4CA', rough=0.22, metal=1.0)
    glass = rc.pbsdf('glass', '#050607', rough=0.02, coat=1.0, coat_rough=0.0,
                     spec=0.8)
    screen = rc.image_mat('screen', tex('phone_screen.png'), rough=0.05, coat=1.0,
                          emit_s=0.9)
    lens = rc.pbsdf('lens', '#0A0C10', rough=0.05, coat=1.0)
    body = slab('phone', rrect(W, H, 0.12, kc=16), T, frame, bevel=0.034, seg=6)
    front = slab('glass', rrect(W - 0.012, H - 0.012, 0.115, kc=16), 0.006, glass,
                 bevel=0.004)
    front.location.z = T
    scr = slab('screen', rrect(W - 0.07, H - 0.07, 0.085, kc=16), 0.002, screen,
               bevel=0.0)
    scr.location.z = T + 0.0045
    # front camera punch-hole
    cam = rc.cyl('fcam', 0.017, 0.004, (0, H / 2 - 0.085, T + 0.007), lens, verts=32)
    # side buttons
    btn1 = rc.rbox('btn', (0.012, 0.16, 0.03), (W / 2 + 0.004, 0.30, T / 2), frame,
                   bevel=0.005)
    btn2 = rc.rbox('btn2', (0.012, 0.10, 0.03), (W / 2 + 0.004, 0.10, T / 2), frame,
                   bevel=0.005)
    ph = group('ph', [body, front, scr, cam, btn1, btn2])
    tilt = math.radians(12)
    ph.rotation_euler = (math.pi / 2 - tilt, 0, math.pi)
    ph.location = (0, 0, H / 2 * math.cos(tilt) + T * math.sin(tilt))
    root = group('root', [ph])
    # turned ~3/4 so the aluminium side edge and thickness read
    root.rotation_euler = (0, 0, math.radians(14))
    bpy.context.view_layer.update()
    return finish(fill=0.88)


# ---------------------------------------------------------------- pins
def pin_mesh(name, mat, h=1.5, a=0.5):
    """Teardrop pin, tip at origin, axis +Z, height h (head radius a)."""
    zc = h - a
    d = zc
    alpha = math.acos(a / d)
    prof = []
    n = 40
    # from top of head around to the tangent point
    ang_end = math.pi / 2 + (math.pi / 2 - alpha)  # measured from +Z downwards
    for i in range(n + 1):
        t = ang_end * i / n
        prof.append((a * math.sin(t) + 1e-4 * (i == 0), zc + a * math.cos(t)))
    tx, tz = prof[-1]
    for i in range(1, 12):
        u = i / 12
        prof.append((tx * (1 - u) + 0.012 * u, tz * (1 - u) + 0.02 * u))
    prof.append((0.0, 0.0))
    prof[0] = (0.0, h)
    return rc.lathe(name, prof, mat, seg=96)


def pin(name, face_dir, badge=False):
    teal = teal_paint()
    white = rc.pbsdf('white', '#F7F8F8', rough=0.25, coat=0.8)
    p = pin_mesh(name, teal)
    # inset white "eye" facing the camera
    eye = rc.lathe(name + '_eye', [(0.0, 0.035), (0.15, 0.035), (0.175, 0.02),
                                   (0.18, -0.03)], white, seg=64)
    dz = Vector(face_dir).normalized()
    eye.rotation_euler = dz.to_track_quat('Z', 'Y').to_euler()
    eye.location = Vector((0, 0, 1.0)) + dz * 0.452
    objs = [p, eye]
    if badge:
        bw = rc.pbsdf('badge', '#FFFFFF', rough=0.2, coat=1.0)
        b = rc.lathe('badge', [(0.0, 0.07), (0.20, 0.07), (0.235, 0.045),
                               (0.245, 0.0), (0.235, -0.045), (0.20, -0.07),
                               (0.0, -0.07)], bw, seg=64)
        pl = teal_paint('plus', rc.hexcol(rc.TEAL_LIGHT))
        h1 = rc.rbox('ph', (0.22, 0.055, 0.05), (0, 0, 0.075), pl, bevel=0.015)
        h2 = rc.rbox('pv', (0.055, 0.22, 0.05), (0, 0, 0.075), pl, bevel=0.015)
        bg = group('badge_g', [b, h1, h2])
        bg.rotation_euler = dz.to_track_quat('Z', 'Y').to_euler()
        side = dz.cross(Vector((0, 0, 1))).normalized()
        bg.location = Vector((0, 0, 1.28)) - side * 0.50 + dz * 0.35
        objs.append(bg)
    return objs


def cam_face_dir(az=AZ):
    a = math.radians(az)
    return (math.sin(a), math.cos(a), 0.12)


def paper_map():
    m = rc.image_mat('map', tex('map.png'), rough=0.6, sss=0.02)
    rc.add_noise_bump(m, scale=500, strength=0.05)
    # 4 accordion panels along X, folds alternating up/down
    Wt, Hm, n = 2.2, 1.5, 4
    pw = Wt / n
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    zs = [0.0, 0.07, 0.0, 0.07, 0.0]
    cols = []
    for i in range(n + 1):
        x = -Wt / 2 + i * pw
        cols.append((bm.verts.new((x, -Hm / 2, zs[i])), bm.verts.new((x, Hm / 2, zs[i]))))
    for i in range(n):
        a, b = cols[i], cols[i + 1]
        f = bm.faces.new((a[0], b[0], b[1], a[1]))
        for lp in f.loops:
            co = lp.vert.co
            lp[uvl].uv = ((co.x + Wt / 2) / Wt, (co.y + Hm / 2) / Hm)
    ob = rc.obj_from_bm(bm, 'map', m, smooth=False)
    sol = ob.modifiers.new('sol', 'SOLIDIFY')
    sol.thickness = 0.008
    ob.rotation_euler = (0, 0, math.radians(-12))
    return ob


def saved():
    mp = paper_map()
    objs = pin('pin', cam_face_dir())
    g = group('pin_g', objs)
    g.scale = (1.6, 1.6, 1.6)
    g.location = (0.05, 0.0, 0.07)
    bpy.context.view_layer.update()
    return finish(fill=0.86)


def add_stop():
    objs = pin('pin', cam_face_dir(), badge=True)
    bpy.context.view_layer.update()
    return finish(fill=0.78)


# ---------------------------------------------------------------- coins
def coin(name, gold, r=0.5, t=0.085):
    h = t / 2
    prof = [(0.0, h - 0.012), (r * 0.52, h - 0.012), (r * 0.54, h - 0.004),
            (r * 0.58, h - 0.004), (r * 0.60, h - 0.012), (r * 0.84, h - 0.012),
            (r * 0.86, h), (r * 0.97, h), (r, h - 0.01), (r, -h + 0.01),
            (r * 0.97, -h), (r * 0.86, -h), (r * 0.84, -h + 0.012), (0.0, -h + 0.012)]
    c = rc.lathe(name, prof, gold, seg=128)
    return c


def coins():
    gold = rc.pbsdf('gold', '#E9B949', rough=0.2, metal=1.0)
    # reeded edge: fine radial bump
    rc.add_noise_bump(gold, scale=600, strength=0.02)
    objs = []
    t = 0.085
    offs = [(0, 0), (0.02, -0.015), (-0.015, 0.01), (0.01, 0.02), (-0.02, -0.01),
            (0.015, 0.005)]
    for i, (dx, dy) in enumerate(offs):
        c = coin('c%d' % i, gold)
        c.location = (dx - 0.28, dy - 0.1, t / 2 + i * t)
        c.rotation_euler = (0, 0, i * 0.7)
        objs.append(c)
    # second shorter stack
    for i in range(3):
        c = coin('d%d' % i, gold)
        c.location = (0.55 + 0.01 * i, -0.45 - 0.01 * i, t / 2 + i * t)
        objs.append(c)
    # one coin standing, leaning on the tall stack, face toward camera
    c = coin('lean', gold)
    a = math.radians(AZ)
    fd = Vector((math.sin(a), math.cos(a), 0.0))
    c.rotation_euler = fd.to_track_quat('Z', 'Y').to_euler()
    c.rotation_euler.rotate_axis('X', math.radians(-14))
    c.location = Vector((-0.28, -0.1, 0.49)) + fd * 0.56 + Vector((0.12, -0.05, 0))
    bpy.context.view_layer.update()
    return finish(fill=0.90)


# ---------------------------------------------------------------- star
def star():
    gold = rc.pbsdf('gold', '#EDBE4E', rough=0.16, metal=1.0)
    R, r, d = 1.0, 0.43, 0.26
    bm = bmesh.new()
    ring = []
    for k in range(10):
        ang = math.pi / 2 + k * math.pi / 5
        rad = R if k % 2 == 0 else r
        ring.append(bm.verts.new((rad * math.cos(ang), 0.0, rad * math.sin(ang))))
    fcen = bm.verts.new((0, d, 0))
    bcen = bm.verts.new((0, -d, 0))
    for k in range(10):
        a, b = ring[k], ring[(k + 1) % 10]
        bm.faces.new((a, b, fcen))
        bm.faces.new((b, a, bcen))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = rc.obj_from_bm(bm, 'star', gold, smooth=False)
    m = ob.modifiers.new('bv', 'BEVEL')
    m.width = 0.018
    m.segments = 3
    m.harden_normals = True
    # stand on two lower points, turned toward camera
    lowest = R * math.sin(math.pi / 2 + 3 * math.pi / 5 * 1)  # not used
    zmin = min(v.co.z for v in ob.data.vertices)
    ob.location = (0, 0, -zmin + 0.01)
    ob.rotation_euler = (math.radians(-4), 0, math.radians(-(AZ - 14)))
    bpy.context.view_layer.update()
    return finish(fill=0.90)


# ---------------------------------------------------------------- tag
def tag():
    W, H = 0.9, 1.5
    card = rc.image_mat('card', tex('tag_print.png'), rough=0.65, sss=0.03)
    rc.add_noise_bump(card, scale=300, strength=0.06)
    corners = [(-W / 2, -H / 2), (W / 2, -H / 2), (W / 2, H / 2 - 0.32),
               (0.18, H / 2), (-0.18, H / 2), (-W / 2, H / 2 - 0.32)]
    pts = [tuple(p) for p in rounded_poly(corners, [0.07, 0.07, 0.06, 0.07, 0.07, 0.06],
                                          10, 4)]
    c = slab('card', pts, 0.022, card, bevel=0.004,
             uv_box=(-W / 2, W / 2, -H / 2, H / 2))
    # hole
    hy = H / 2 - 0.2
    cutter = rc.cyl('cut', 0.075, 0.3, (0, hy, 0), None, verts=48)
    bo = c.modifiers.new('hole', 'BOOLEAN')
    bo.object = cutter
    bo.operation = 'DIFFERENCE'
    c.modifiers.move(c.modifiers.find('hole'), 0)
    cutter.hide_render = True
    cutter['nofit'] = True
    brass = rc.pbsdf('brass', '#C9A45C', rough=0.22, metal=1.0)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.098, minor_radius=0.026,
                                     major_segments=48, minor_segments=16,
                                     location=(0, hy, 0.011))
    gr = bpy.context.active_object
    gr.scale = (1, 1, 0.55)
    gr.data.materials.append(brass)
    gr.data.shade_smooth()
    # string: through the hole, looping up and off to the right
    string = rc.pbsdf('string', rc.TEAL, rough=0.7, sheen=0.4)
    cu = bpy.data.curves.new('str', 'CURVE')
    cu.dimensions = '3D'
    cu.bevel_depth = 0.018
    cu.bevel_resolution = 4
    sp = cu.splines.new('BEZIER')
    P = [(-0.02, hy, 0.12), (0.0, hy + 0.02, -0.06), (0.06, hy + 0.18, -0.05),
         (0.16, hy + 0.40, 0.04), (0.10, hy + 0.62, 0.12), (-0.12, hy + 0.66, 0.10),
         (-0.18, hy + 0.48, 0.06), (0.02, hy + 0.12, 0.10)]
    sp.bezier_points.add(len(P) - 1)
    for bp, p in zip(sp.bezier_points, P):
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = 'AUTO'
    so = rc.link(bpy.data.objects.new('string', cu))
    so.data.materials.append(string)
    g = group('tag', [c, gr, so, cutter])
    tilt = math.radians(14)
    g.rotation_euler = (math.pi / 2 - tilt, math.radians(-14), math.pi + math.radians(-12))
    bpy.context.view_layer.update()
    zmin = min((o.matrix_world @ v.co).z for o in (c,) for v in o.data.vertices)
    g.location.z = -zmin + 0.01
    bpy.context.view_layer.update()
    return finish(fill=0.90)


BUILD = dict(prebook=prebook, someone_else=someone_else, saved=saved,
             add_stop=add_stop, coins=coins, star=star, tag=tag)
