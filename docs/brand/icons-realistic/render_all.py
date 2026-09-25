"""Entry point: blender -b --factory-startup -P render_all.py -- <key> <out_dir> [samples]

Renders one 1024x1024 transparent master <out_dir>/<key>.png.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rcommon as rc  # noqa: E402

argv = sys.argv[sys.argv.index('--') + 1:]
key, out = argv[0], argv[1]
samples = int(argv[2]) if len(argv) > 2 else 256

rc.reset(samples)
if key == 'ride':
    import car
    car.build()
    # hero 3/4 front, low camera, car ~94% of the frame width
    cam, c, dist = rc.setup_camera(az=52.0, fill=0.92, lens=60, elev=12)
    rc.studio(cam, c, 3.0, key=1.15, key_col=(1.0, 0.90, 0.78))
else:
    import props
    cam, c, dist = props.BUILD[key]()
rc.shadow_catcher()
rc.render(os.path.join(out, key + '.png'))
