#!/usr/bin/env python3
"""Icon inventory for the audit 2.1 icon system.

Scans every Phosphor icon reference in packages/*/lib and apps/*/lib, resolves
the size it actually renders at, its colour role and its container, and writes:

  * packages/design_system/test/icon_inventory_data.dart — the data the
    `icon_inventory_sheet_test.dart` renders into icon-inventory.png and
    checks against the eight rules;
  * a Markdown table on stdout (pasted into docs/plans/icon-audit-*.md).

Run from the repo root:
  python3 docs/brand/research/icon_inventory.py > /tmp/inventory.md
  cd packages/design_system && ICON_SHEET_OUT=../../docs/brand/research/icon-inventory.png \\
      flutter test test/icon_inventory_sheet_test.dart

Sizes are resolved statically: an explicit `size:` wins; a shared widget
(AppIconBadge, _Item, PrimaryButton…) uses its own fixed size; an unsized
Icon inside a `*Button.icon` gets the theme's button iconSize (20); any other
unsized Icon gets the theme's IconTheme size (24).
"""
import glob
import os
import re
import sys

ROOT = os.environ.get('ICON_ROOT') or os.path.abspath(
    os.path.join(os.path.dirname(__file__), '..', '..', '..'))
PAT = re.compile(r'PhosphorIcons(Regular|Fill)\.(\w+)')

# Screen group per source file (first match wins).
SCREENS = [
    ('apps/rider_app/lib/home_page', 'Rider · map chrome'),
    ('apps/rider_app/lib/features/trip/sheets/where_to_sheet', 'Rider · where to'),
    ('apps/rider_app/lib/features/trip/destination_search', 'Rider · search'),
    ('apps/rider_app/lib/features/trip/map_picker', 'Rider · search'),
    ('apps/rider_app/lib/features/trip/location_banner', 'Rider · search'),
    ('apps/rider_app/lib/features/trip/price_comparison', 'Rider · price comparison'),
    ('apps/rider_app/lib/features/trip/sheets/ride_options', 'Rider · choose a ride'),
    ('apps/rider_app/lib/features/trip/sheets/pre_book', 'Rider · pre-book'),
    ('apps/rider_app/lib/features/trip/sheets/completed', 'Rider · trip complete'),
    ('apps/rider_app/lib/features/trip/sheets/ride_details', 'Rider · ride details'),
    ('apps/rider_app/lib/features/trip/sheets/', 'Rider · live ride'),
    ('apps/driver_app/lib/features/driver/location_priming', 'Driver · location priming'),
    ('apps/driver_app/lib/features/account', 'Driver · profile'),
    ('apps/driver_app/lib/home_page', 'Driver · home & trip'),
    ('apps/admin_app/', 'Admin console'),
    ('packages/core/lib/src/safety', 'Shared · safety'),
    ('packages/core/lib/src/account/account_menu', 'Shared · account menu'),
    ('packages/core/lib/src/account/delete_account', 'Shared · delete account'),
    ('packages/core/lib/src/account', 'Shared · account pages'),
    ('packages/core/lib/', 'Shared · auth, chat, theme, debug'),
    ('packages/design_system/', 'Design system widgets'),
]

# Shared widgets that decide the size/container of the icon they are given.
# callee -> (size, container)
CALLEES = {
    'AppIconBadge': (20, 'badge'),
    'AppIconBadge.danger': (20, 'badge'),
    '_QuickActionCard': (20, 'badge'),
    '_Reason': (20, 'badge'),
    '_StatCard': (20, 'badge'),
    'EmptyState': (32, 'medallion'),
    'AsyncContent': (32, 'medallion'),
    '?': (32, 'medallion'),  # AsyncContent(emptyIcon: …) named-arg calls
    '_Item': (24, 'plain'),
    '_Fact': (24, 'plain'),
    '_PreBookRow': (24, 'plain'),
    'AppCircleButton': (24, 'map button'),
    '_RideDetailRow': (20, 'plain'),
    '_Notice': (20, 'plain'),
    '_Headline': (20, 'plain'),
    '_point': (20, 'plain'),
    '_PayChip': (20, 'plain'),
    'PrimaryButton': (20, 'plain'),
    'SecondaryButton': (20, 'plain'),
    '_RidePill': (16, 'plain'),
}

# Icons listed in a map/switch rather than passed to a widget: where they end up.
LITERALS = {
    'where_to_sheet': (20, 'badge', 'neutral'),
    'trip_history_page': (20, 'badge', 'brand'),
    'destination_search_page': (20, 'plain', 'default'),
    'saved_places_page': (24, 'plain', 'neutral'),
    'driver_payouts_page': (24, 'plain', 'default'),
    'appearance_sheet': (24, 'plain', 'default'),
}

# Deliberate exceptions to the 16/20/24 (+32/40/48 hero) scale.
EXCEPTIONS = {
    ('admin_app/lib/home_page.dart', 'circle'): 'status dot, 12 px by design',
    ('design_system/lib/src/widgets/app_avatar.dart', 'user'): 'avatar fallback: half the avatar size',
    ('design_system/lib/src/widgets/star_rating.dart', 'star'): 'rating input: StarRating(size:), default 40',
}


def enclosing(src, pos):
    depth = 0
    i = pos - 1
    while i >= 0:
        c = src[i]
        if c in ')]}':
            depth += 1
        elif c in '([{':
            if depth == 0 and c == '(':
                m = re.search(r'([\w.?]+)\s*$', src[:i])
                return i, (m.group(1) if m else '?')
            if depth > 0:
                depth -= 1
        i -= 1
    return None, None


def call_end(src, start):
    depth = 0
    for j in range(start, len(src)):
        if src[j] in '([{':
            depth += 1
        elif src[j] in ')]}':
            depth -= 1
            if depth == 0:
                return j
    return len(src)


def arg(body, name):
    depth = 0
    for m in re.finditer(r'[\(\[\{\)\]\}]|\b' + name + r'\s*:', body):
        t = m.group(0)
        if t in '([{':
            depth += 1
        elif t in ')]}':
            depth -= 1
        elif depth == 0:
            s = m.end()
            d = 0
            k = s
            while k < len(body):
                ch = body[k]
                if ch in '([{':
                    d += 1
                elif ch in ')]}':
                    if d == 0:
                        break
                    d -= 1
                elif ch == ',' and d == 0:
                    break
                k += 1
            return ' '.join(body[s:k].split())
    return ''


def role_of(color, tone, callee, icon):
    t = (tone or '').lower()
    for r in ('danger', 'success', 'warning', 'neutral'):
        if r in t:
            return r
    if callee == 'AppIconBadge.danger':
        return 'danger'
    c = color or ''
    if icon == 'signOut':
        return 'danger'
    if re.search(r'error|danger', c):
        return 'danger'
    if 'success' in c:
        return 'success'
    if 'warning' in c or '_activeTone' in c:
        return 'warning'
    if 'star' in c:
        return 'star'
    if re.search(r'white', c):
        return 'on-dark'
    if re.search(r'accent|highlight', c):
        return 'brand'
    if re.search(r'Tertiary|iconNeutral|onSurfaceVariant|outline|Secondary|muted', c):
        return 'neutral'
    if callee in ('_Item', '_Fact', '_RideDetailRow'):
        return 'neutral'
    if callee in ('_QuickActionCard', '_Reason', '_StatCard', 'AppIconBadge',
                  'EmptyState', 'AsyncContent', '?', '_point'):
        return 'brand'
    return 'default'


def main():
    files = sorted(
        f for f in glob.glob(ROOT + '/packages/*/lib/**/*.dart', recursive=True)
        + glob.glob(ROOT + '/apps/*/lib/**/*.dart', recursive=True)
        if 'phosphor_icons.dart' not in f)
    rows = []
    for f in files:
        rel = os.path.relpath(f, ROOT)
        screen = next((s for p, s in SCREENS if rel.startswith(p)), 'Other')
        src = open(f).read()
        for m in PAT.finditer(src):
            line = src.count('\n', 0, m.start()) + 1
            weight, icon = m.group(1), m.group(2)
            o, callee = enclosing(src, m.start())
            size = color = tone = ''
            if o is not None:
                body = src[o + 1:call_end(src, o)]
                size = arg(body, 'size')
                color = arg(body, 'color') or arg(body, 'iconColor')
                tone = arg(body, 'tone')
            container = 'plain'
            role_override = None
            lit = next((k for k in LITERALS if k in rel), None)
            if lit == 'appearance_sheet':
                callee = None  # a (mode, label, icon) record list, not a call
            if callee in CALLEES:
                s, container = CALLEES[callee]
                size = size if size.isdigit() else str(s)
            elif callee in (None, 'None'):
                key = next((k for k in LITERALS if k in rel), None)
                s, container, role_override = LITERALS.get(key, (24, 'plain', 'default'))
                size = str(s)
            elif not size:
                pre = src[max(0, m.start() - 300):m.start()]
                if re.search(r'Button\.icon\((?:(?!\bButton\b).)*icon:\s*(?:const\s+)?Icon\($', pre, re.S):
                    size = '20'
                else:
                    size = '24'
            if callee == 'Icon':
                pre = src[max(0, m.start() - 700):m.start()]
                if re.search(r'width:\s*(64|72)\b', pre[-500:]) and 'BoxShape.circle' in pre[-500:]:
                    container = 'medallion'
                elif re.search(r'width:\s*28\b', pre[-700:]) and 'BoxShape.circle' in pre[-700:]:
                    container = 'avatar disc'
            role = role_override or role_of(color, tone, callee, icon)
            exc = next((v for (p, i), v in EXCEPTIONS.items()
                        if rel.endswith(p) and i == icon), '')
            rows.append(dict(file=rel, line=line, screen=screen, weight=weight,
                             icon=icon, size=size, role=role,
                             container=container, exception=exc))

    # Markdown table (every reference). Rules checked per row: 1 library
    # (Phosphor), 2 size scale, 3 Fill only for a state, 5 container. Rules
    # 4/6/7/8 are colour/label/contrast/target checks made per screen and in
    # the sheet test, not derivable per reference from source.
    fill_states = {'star', 'heart', 'checkCircle', 'sealCheck', 'square',
                   'circle', 'toggleRight'}
    print('| file:line | icon | size | colour role | container | weight '
          '| 1 lib | 2 size | 3 fill | 5 container | note |')
    print('|---|---|---|---|---|---|---|---|---|---|---|')
    for r in rows:
        sz = r['size']
        util = sz in ('16', '20', '24')
        hero = sz in ('32', '40', '48') and r['container'] in ('medallion', 'plain')
        ok_size = util or hero or bool(r['exception'])
        ok_fill = r['weight'] == 'Regular' or r['icon'] in fill_states
        ok_cont = r['container'] in ('plain', 'badge', 'medallion', 'map button') \
            or bool(r['exception'])
        yes = lambda b: 'ok' if b else '**NO**'
        size_cell = 'ok' if (util or hero) else ('exc.' if r['exception'] else f'**NO ({sz})**')
        print(f"| {r['file']}:{r['line']} | {r['icon']} | {sz} | {r['role']} "
              f"| {r['container']} | {r['weight']} | ok | {size_cell} "
              f"| {yes(ok_fill)} | {yes(ok_cont)} | {r['exception']} |")

    # Dart data, deduplicated per screen.
    seen = set()
    out = ['// GENERATED by docs/brand/research/icon_inventory.py — do not edit.',
           '// Every Phosphor icon the apps render, per screen, at its real size.',
           "import 'package:design_system/design_system.dart';",
           "import 'package:flutter/widgets.dart';",
           '',
           'class InventoryIcon {',
           '  const InventoryIcon(this.screen, this.name, this.icon, this.fill,',
           '      this.size, this.role, this.container, this.exception, this.where);',
           '  final String screen;',
           '  final String name;',
           '  final IconData icon;',
           '  final bool fill;',
           '  final double size;',
           '  final String role;',
           '  final String container;',
           '  final String exception;',
           '  final String where;',
           '}',
           '',
           'const inventory = <InventoryIcon>[']
    for r in rows:
        if not r['size'].replace('.', '').isdigit():
            continue
        key = (r['screen'], r['icon'], r['weight'], r['size'], r['role'], r['container'])
        if key in seen:
            continue
        seen.add(key)
        where = f"{r['file'].split('/lib/')[-1]}:{r['line']}"
        out.append(
            f"  InventoryIcon('{r['screen']}', '{r['icon']}', "
            f"PhosphorIcons{r['weight']}.{r['icon']}, {str(r['weight'] == 'Fill').lower()}, "
            f"{r['size']}, '{r['role']}', '{r['container']}', "
            f"'{r['exception']}', '{where}'),")
    out.append('];')
    dest = os.path.join(ROOT, 'packages/design_system/test/icon_inventory_data.dart')
    open(dest, 'w').write('\n'.join(out) + '\n')
    print(f'\n<!-- {len(rows)} references, {len(seen)} unique per screen -> {os.path.relpath(dest, ROOT)} -->',
          file=sys.stderr)


if __name__ == '__main__':
    main()
