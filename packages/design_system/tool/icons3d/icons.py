"""The icon names and code points the 3D font covers, read from
lib/src/theme/phosphor_icons.dart (Regular + Fill classes; Light is left
alone — it is the ink build's own weight)."""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(os.path.dirname(HERE))
DART = os.path.join(PKG, 'lib', 'src', 'theme', 'phosphor_icons.dart')

_CONST = re.compile(r'static const IconData (\w+) = IconData\((0x[0-9a-fA-F]+)')


def load():
    """[(class, name, codepoint)] for PhosphorIconsRegular and PhosphorIconsFill."""
    out = []
    cls = None
    for line in open(DART, encoding='utf-8'):
        m = re.match(r'abstract final class (\w+)', line)
        if m:
            cls = m.group(1)
            continue
        m = _CONST.search(line)
        if m and cls in ('PhosphorIconsRegular', 'PhosphorIconsFill'):
            out.append((cls, m.group(1), int(m.group(2), 16)))
    return out


def by_codepoint():
    """codepoint -> preferred PNG names (Regular name first, then Fill)."""
    cps = {}
    for cls, name, cp in load():
        names = cps.setdefault(cp, [])
        if cls == 'PhosphorIconsRegular':
            names.insert(0, name)
        elif name not in names:
            names.append(name)
    return cps
