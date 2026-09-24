"""Entry point. Usage (headless):

  blender -b -P render.py -- OUTDIR [light|dark|both] vehicle [vehicle ...]

Writes OUTDIR/light/<vehicle>.png and OUTDIR/dark/<vehicle>.png at 512x512.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
import common  # noqa: E402

argv = sys.argv[sys.argv.index('--') + 1:]
outdir, modes, vehicles = argv[0], argv[1], argv[2:]
modes = {'both': ['light', 'dark'], 'all': ['light', 'dark', 'top']}.get(modes, [modes])
samples = int(os.environ.get('SAMPLES', '96'))


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


for v in vehicles:
    for mode in modes:
        sc = common.reset()
        sc.cycles.samples = samples
        build(v)
        if mode == 'top':
            cam, target = common.setup_top_camera()
            common.top_lights(target)
        else:
            cam, target = common.setup_camera()
            common.lights(cam, target, mode)
        os.makedirs(os.path.join(outdir, mode), exist_ok=True)
        sc.render.filepath = os.path.join(outdir, mode, v + '.png')
        bpy.ops.render.render(write_still=True)
        if mode == 'light':
            common.shadow_pass(os.path.join(outdir, 'shadow', v + '.png'))
        print('RENDERED', v, mode)
