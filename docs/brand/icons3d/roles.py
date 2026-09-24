"""Colour roles for the 3D icon set -> roles.json (see PALETTE.md).

  python3 roles.py
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))

# role -> (light-mode body hex, dark-mode body hex)
ROLES = {
    'brand':   ('#1FA7A8', '#2CC0C1'),  # default: teal clay
    'chrome':  ('#A8A29B', '#8A8580'),  # quiet nav chrome: warm grey, thin Regular-weight model
    'neutral': ('#3C4046', '#A9AFB8'),  # UI objects; graphite -> silver in dark
    'danger':  ('#E5484D', '#F0605F'),
    'success': ('#2BAA6B', '#38C27F'),
    'warning': ('#F2A93B', '#F6B84F'),
    'rating':  ('#F5C542', '#F7CF5A'),
    'love':    ('#E8577A', '#F06E8D'),
    'money':   ('#3DBE8B', '#4CD39C'),
}

MAP = {
    'chrome': ['arrowClockwise', 'arrowUpRight', 'arrowsLeftRight', 'arrowLeft', 'arrowRight',
               'caretDown', 'caretRight', 'caretUp', 'caretLeft', 'dotsThree', 'list', 'x', 'plus'],
    'neutral': ['copy', 'export', 'signOut',
                'pencilSimple', 'magnifyingGlass', 'squaresFour', 'square', 'circle', 'circleHalf',
                'toggleLeft', 'wrench', 'ruler', 'note', 'tray', 'chatCircleSlash', 'moon'],
    'danger': ['siren', 'warningCircle', 'calendarX', 'trash', 'userMinus', 'record'],
    'success': ['check', 'checks', 'checkCircle', 'sealCheck', 'calendarCheck', 'shieldCheck',
                'toggleRight'],
    'warning': ['warning', 'lightning', 'gpsSlash', 'cloudSlash', 'hourglass'],
    'rating': ['star', 'sun', 'moonStars'],
    'love': ['heart', 'handHeart', 'heartbeat'],
    'money': ['money', 'cashRupee', 'coins', 'wallet', 'piggyBank', 'bank', 'creditCard', 'cards',
              'receipt', 'tag', 'percent', 'ticket', 'chartLineUp', 'trendUp'],
}


def main():
    names = sorted(json.load(open(os.path.join(HERE, 'glyphs.json'))))
    inv = {}
    for role, ns in MAP.items():
        for n in ns:
            assert n in names, n
            assert n not in inv, n
            inv[n] = role
    out = {'roles': {r: {'light': l, 'dark': d} for r, (l, d) in ROLES.items()},
           'icons': {}}
    for n in names:
        r = inv.get(n, 'brand')
        out['icons'][n] = {'role': r, 'hex': ROLES[r][0], 'hex_dark': ROLES[r][1]}
    json.dump(out, open(os.path.join(HERE, 'roles.json'), 'w'), indent=1)
    from collections import Counter
    print(len(names), Counter(v['role'] for v in out['icons'].values()))


if __name__ == '__main__':
    main()
