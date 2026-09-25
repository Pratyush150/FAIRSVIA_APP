"""RideVela realistic Home icons -- shared scene/render helpers (Blender 4.2).

Photographic product-render pipeline:
  * Cycles on the GPU (OptiX), OptiX denoiser, AgX view transform.
  * Poly Haven CC0 HDRI "studio_small_09" for reflections + a soft key area light.
  * Shadow-catcher floor -> transparent PNG that carries only a soft contact shadow.
  * One camera family for every asset: 3/4 view, elevation CAM_ELEV, 70 mm lens,
    auto-framed so the subject fills FILL of the frame.

Run one asset:  blender -b --factory-startup -P render_all.py -- <key> <out_dir>
"""
import math
import os
import bpy
import bmesh
import numpy as np
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
HDRI_NAME = 'studio_small_09'
HDRI = os.environ.get('RV_HDRI', os.path.expanduser(
    '~/.cache/ridevela-3d/%s_2k.hdr' % HDRI_NAME))
HDRI_URL = 'https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/2k/%s_2k.hdr' % HDRI_NAME


def ensure_hdri():
    if not os.path.exists(HDRI):
        import urllib.request
        os.makedirs(os.path.dirname(HDRI), exist_ok=True)
        urllib.request.urlretrieve(HDRI_URL, HDRI)
    return HDRI
FONT = '/usr/share/fonts/truetype/lato/Lato-Black.ttf'

TEAL = '#0B7A7B'
TEAL_LIGHT = '#1FA7A8'

CAM_ELEV = 18.0
FILL = 0.80
RES = 1024


# ---------------------------------------------------------------- colour
def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexcol(h, a=1.0):
    h = h.lstrip('#')
    return tuple(srgb_to_lin(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4)) + (a,)


# ---------------------------------------------------------------- scene
def reset(samples=256):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    prefs = bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type = 'OPTIX'
    prefs.get_devices()
    for d in prefs.devices:
        d.use = d.type == 'OPTIX'
    sc.cycles.device = 'GPU'
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = 'OPENIMAGEDENOISE'
    sc.cycles.denoising_prefilter = 'ACCURATE'
    sc.cycles.denoising_use_gpu = True
    sc.cycles.max_bounces = 12
    sc.cycles.glossy_bounces = 8
    sc.cycles.transmission_bounces = 12
    sc.render.film_transparent = True
    sc.render.resolution_x = RES
    sc.render.resolution_y = RES
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.image_settings.color_depth = '16'
    sc.view_settings.view_transform = 'AgX'
    sc.view_settings.look = 'AgX - Medium High Contrast'
    sc.view_settings.exposure = 0.0
    world = bpy.data.worlds.new('W')
    sc.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputWorld')
    bg = nt.nodes.new('ShaderNodeBackground')
    env = nt.nodes.new('ShaderNodeTexEnvironment')
    env.image = bpy.data.images.load(ensure_hdri())
    tc = nt.nodes.new('ShaderNodeTexCoord')
    mp = nt.nodes.new('ShaderNodeMapping')
    mp.inputs['Rotation'].default_value = (0, 0, math.radians(35))
    nt.links.new(tc.outputs['Generated'], mp.inputs['Vector'])
    nt.links.new(mp.outputs[0], env.inputs[0])
    nt.links.new(env.outputs[0], bg.inputs[0])
    bg.inputs[1].default_value = 1.0
    nt.links.new(bg.outputs[0], out.inputs[0])
    world['bg'] = bg.name
    return sc


def world_strength(s):
    bpy.context.scene.world.node_tree.nodes['Background'].inputs[1].default_value = s


# ---------------------------------------------------------------- materials
def pbsdf(name, col, rough=0.4, metal=0.0, coat=0.0, coat_rough=0.03, spec=0.5,
          ior=1.5, trans=0.0, emit=None, emit_s=0.0, sss=0.0, sheen=0.0, alpha=1.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    p = mat.node_tree.nodes['Principled BSDF']
    p.inputs['Base Color'].default_value = hexcol(col) if isinstance(col, str) else col
    p.inputs['Roughness'].default_value = rough
    p.inputs['Metallic'].default_value = metal
    p.inputs['Coat Weight'].default_value = coat
    p.inputs['Coat Roughness'].default_value = coat_rough
    p.inputs['Specular IOR Level'].default_value = spec
    p.inputs['IOR'].default_value = ior
    p.inputs['Transmission Weight'].default_value = trans
    p.inputs['Subsurface Weight'].default_value = sss
    p.inputs['Sheen Weight'].default_value = sheen
    p.inputs['Alpha'].default_value = alpha
    if emit:
        p.inputs['Emission Color'].default_value = hexcol(emit)
        p.inputs['Emission Strength'].default_value = emit_s
    return mat


def principled(mat):
    return mat.node_tree.nodes['Principled BSDF']


def add_noise_bump(mat, scale=40.0, strength=0.05, detail=6.0, dist=0.002):
    """Subtle micro-surface (paper grain, rubber, brushed metal) via bump."""
    nt = mat.node_tree
    p = principled(mat)
    n = nt.nodes.new('ShaderNodeTexNoise')
    n.inputs['Scale'].default_value = scale
    n.inputs['Detail'].default_value = detail
    b = nt.nodes.new('ShaderNodeBump')
    b.inputs['Strength'].default_value = strength
    b.inputs['Distance'].default_value = dist
    nt.links.new(n.outputs['Fac'], b.inputs['Height'])
    nt.links.new(b.outputs['Normal'], p.inputs['Normal'])
    return b


def image_mat(name, path, rough=0.5, coat=0.0, emit_s=0.0, sss=0.0):
    """Principled material driven by an image (UV)."""
    mat = pbsdf(name, '#FFFFFF', rough=rough, coat=coat, sss=sss)
    nt = mat.node_tree
    p = principled(mat)
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = bpy.data.images.load(path)
    tex.interpolation = 'Cubic'
    nt.links.new(tex.outputs['Color'], p.inputs['Base Color'])
    if emit_s:
        nt.links.new(tex.outputs['Color'], p.inputs['Emission Color'])
        p.inputs['Emission Strength'].default_value = emit_s
    return mat


# ---------------------------------------------------------------- meshes
def link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def obj_from_bm(bm, name, mat=None, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    if mat:
        me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = smooth
    return ob


def lathe(name, prof, mat, seg=96, smooth=True, cap=False):
    """Surface of revolution about local +Z from profile [(r, z)]."""
    bm = bmesh.new()
    rings = []
    for k in range(seg):
        a = 2 * math.pi * k / seg
        ca, sa = math.cos(a), math.sin(a)
        rings.append([bm.verts.new((r * ca, r * sa, z)) for (r, z) in prof])
    n = len(prof)
    for k in range(seg):
        A, B = rings[k], rings[(k + 1) % seg]
        for j in range(n - 1):
            vs = (A[j], B[j], B[j + 1], A[j + 1])
            try:
                bm.faces.new(vs)
            except ValueError:
                pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = obj_from_bm(bm, name, mat, smooth)
    ob.data.shade_smooth()
    return ob


def rbox(name, size, loc, mat, bevel=0.02, seg=4, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    ob = obj_from_bm(bm, name, mat, smooth=False)
    ob.location = loc
    ob.rotation_euler = rot
    if bevel:
        m = ob.modifiers.new('bv', 'BEVEL')
        m.width = bevel
        m.segments = seg
        m.harden_normals = True
        ob.data.shade_smooth()
    return ob


def cyl(name, r, depth, loc, mat, verts=64, bevel=0.0, seg=3, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=verts, radius1=r, radius2=r,
                          depth=depth)
    ob = obj_from_bm(bm, name, mat, smooth=False)
    ob.location = loc
    ob.rotation_euler = rot
    if bevel:
        m = ob.modifiers.new('bv', 'BEVEL')
        m.width = bevel
        m.segments = seg
        m.limit_method = 'ANGLE'
        m.harden_normals = True
        ob.data.shade_smooth()
    else:
        ob.data.shade_smooth()
        ob.data.set_sharp_from_angle(angle=math.radians(35))
    return ob


def text_obj(name, body, size, mat, extrude=0.0, bevel=0.0, font=FONT, align='CENTER'):
    cu = bpy.data.curves.new(name, 'FONT')
    cu.body = body
    cu.font = bpy.data.fonts.load(font)
    cu.size = size
    cu.extrude = extrude
    cu.bevel_depth = bevel
    cu.bevel_resolution = 3
    cu.align_x = align
    cu.align_y = 'CENTER'
    ob = link(bpy.data.objects.new(name, cu))
    ob.data.materials.append(mat)
    return ob


def subsurf(ob, lv=2):
    m = ob.modifiers.new('ss', 'SUBSURF')
    m.levels = lv
    m.render_levels = lv
    return m


# ---------------------------------------------------------------- camera
def cam_dir(az, elev=None):
    e, a = math.radians(CAM_ELEV if elev is None else elev), math.radians(az)
    return Vector((math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e)))


def mesh_points():
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for ob in bpy.context.scene.objects:
        if ob.type not in ('MESH', 'FONT', 'CURVE') or ob.get('nofit') or ob.hide_render:
            continue
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        if me is None or len(me.vertices) == 0:
            continue
        vs = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get('co', vs)
        vs = vs.reshape(-1, 3)
        M = np.array(ob.matrix_world)
        vs = vs @ M[:3, :3].T + M[:3, 3]
        pts.append(vs)
        ev.to_mesh_clear()
    return np.concatenate(pts)


def _project(cam, pts):
    """Exact numpy projection of world points to normalised frame coords
    (square render, sensor fit AUTO), ignoring lens shift."""
    M = np.array(cam.matrix_world.inverted())
    P = pts @ M[:3, :3].T + M[:3, 3]
    k = cam.data.lens / cam.data.sensor_width
    x = P[:, 0] / -P[:, 2] * k + 0.5
    y = P[:, 1] / -P[:, 2] * k + 0.5
    return x, y


def setup_camera(az=35.0, fill=FILL, lens=70, ground=0.13, elev=None, lift=0.03):
    """Frame the subject so its larger screen extent is `fill` of the frame,
    centred, then nudged up by `lift` to leave room for the contact shadow."""
    sc = bpy.context.scene
    cd = bpy.data.cameras.new('Cam')
    cd.lens = lens
    cd.clip_end = 500
    cam = link(bpy.data.objects.new('Cam', cd))
    sc.camera = cam
    pts = mesh_points()
    c = Vector(((pts[:, 0].min() + pts[:, 0].max()) / 2,
                (pts[:, 1].min() + pts[:, 1].max()) / 2,
                (pts[:, 2].min() + pts[:, 2].max()) / 2))
    d = cam_dir(az, elev)
    dist = 20.0 * max(np.ptp(pts, axis=0))
    for _ in range(12):
        cam.location = c + d * dist
        cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
        bpy.context.view_layer.update()
        xs, ys = _project(cam, pts)
        ext = max(xs.max() - xs.min(), ys.max() - ys.min())
        dist *= ext / fill
    cam.location = c + d * dist
    bpy.context.view_layer.update()
    xs, ys = _project(cam, pts)
    cd.shift_x = (xs.min() + xs.max()) / 2 - 0.5
    cd.shift_y = (ys.min() + ys.max()) / 2 - 0.5 - lift
    return cam, c, dist


def area(name, loc, target, energy, size, col=(1, 1, 1), shape='DISK'):
    ld = bpy.data.lights.new(name, 'AREA')
    ld.energy = energy
    ld.size = size
    ld.shape = shape
    ld.color = col
    ob = link(bpy.data.objects.new(name, ld))
    ob.location = loc
    ob.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    return ob


def studio(cam, target, scale, key=1.0, rim=1.0, world=0.9, strips=1.0,
           key_col=(1.0, 0.97, 0.92)):
    """HDRI + big soft overhead key (slightly camera-left, so the contact shadow
    stays tight) + two long strip softboxes (the long highlight lines seen in
    car / product photography) + faint cool rim from behind."""
    world_strength(world)
    q = cam.matrix_world.to_3x3()
    R, U, B = q.col[0], q.col[1], q.col[2]
    t = Vector(target)
    s = scale
    up = Vector((0, 0, 1))
    area('Key', t + (up * 5 - R * 1.6 + B * 1.2) * s, t, 420 * s * s * key, 4.0 * s,
         col=key_col)
    if strips:
        for i, off in enumerate((-1.0, 1.0)):
            L = area('Strip%d' % i, t + (up * 3.5 + R * off * 1.4 - B * 0.6) * s, t,
                     140 * s * s * strips, 1.0, shape='RECTANGLE')
            L.data.size = 6.0 * s
            L.data.size_y = 0.35 * s
    area('Rim', t + (R * 2.5 + up * 2.0 - B * 4) * s, t, 160 * s * s * rim, 2.5 * s,
         col=(0.92, 0.96, 1.0))
    # contact-shadow light: straight overhead, large -> soft, tight shadow.
    area('ShadowTop', t + up * 4 * s, t + up * -1, 60 * s * s, 5.0 * s)


def link_shadow(ground):
    """Only the HDRI and 'ShadowTop' light reach the shadow catcher, so the
    floor carries a soft contact shadow, not long key/strip shadows."""
    coll = bpy.data.collections.new('ground_only')
    coll.objects.link(ground)
    coll.collection_objects[0].light_linking.link_state = 'EXCLUDE'
    for ob in bpy.context.scene.objects:
        if ob.type == 'LIGHT' and ob.name != 'ShadowTop':
            ob.light_linking.receiver_collection = coll


def shadow_catcher(z=0.0, size=200):
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=size)
    ob = obj_from_bm(bm, 'Ground', pbsdf('ground', '#6A6E73', rough=0.6),
                     smooth=False)
    ob.location.z = z
    ob.is_shadow_catcher = True
    ob['nofit'] = True
    link_shadow(ob)
    return ob


def render(path, shadow=0.55):
    """Two passes, composited with PIL:
      A) subject only (floor hidden from camera but still seen in reflections),
      B) floor-only shadow catcher lit by 'ShadowTop' alone (world off), so the
         contact shadow is soft and tight and its opacity is set independently.
    """
    sc = bpy.context.scene
    ground = bpy.data.objects.get('Ground')
    base = path[:-4]
    if ground:
        ground.visible_camera = False
    sc.render.filepath = base + '_obj.png'
    bpy.ops.render.render(write_still=True)
    if ground is None:
        return
    ground.visible_camera = True
    ground.light_linking.receiver_collection = None
    for ob in sc.objects:
        if ob.type == 'LIGHT':
            ob.hide_render = ob.name != 'ShadowTop'
            ob.light_linking.receiver_collection = None
        elif ob.type in ('MESH', 'FONT', 'CURVE') and ob is not ground:
            ob.visible_camera = False
            ob.visible_glossy = False
            ob.visible_diffuse = False
    top = sc.objects['ShadowTop']
    top.data.energy *= 3
    world_strength(0.0)
    sc.cycles.samples = 96
    sc.render.filepath = base + '_shd.png'
    bpy.ops.render.render(write_still=True)
    # composited outside Blender (no PIL in Blender's Python): export.py

