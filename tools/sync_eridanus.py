"""Write Eridanus' solved segments (tools/design_eridanus.py) into both sims, so the design and the
two copies of ERI_SEGS (sim-core.js, godot/sim/craft_sim.gd) can't drift apart.
Usage: python tools/sync_eridanus.py
"""
import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import design_gp as dg
import design_eridanus as de

solved, turn = dg.solve(de.as_plain(de.SEGS))
segs = [(s[0], sv[1], s[2], s[3]) for s, sv in zip(de.SEGS, solved)]
assert abs(turn - 360) < 1e-6
pts, _ = dg.walk(de.as_plain(segs))
km = sum(((pts[(i + 1) % len(pts)][0] - pts[i][0]) ** 2 + (pts[(i + 1) % len(pts)][1] - pts[i][1]) ** 2) ** 0.5 for i in range(len(pts))) / 1000


def num(v):
    return repr(round(float(v), 3)).rstrip('0').rstrip('.') if float(v) != int(v) else str(int(v))


def js_list():
    items = [f"['{k}', {num(a)}, {num(b)}, '{m}']" for (k, a, b, m) in segs]
    lines, line = [], '  const ERI_SEGS = ['
    for it in items:
        if len(line) + len(it) > 120:
            lines.append(line)
            line = '    '
        line += it + ', '
    lines.append(line.rstrip(', ') + '];')
    return '\n'.join(lines)


def gd_list():
    def f(v):
        v = round(float(v), 3)
        return repr(v)
    items = [f'["{k}", {f(a)}, {f(b)}, "{m}"]' for (k, a, b, m) in segs]
    lines, line = [], 'const ERI_SEGS := ['
    for it in items:
        if len(line) + len(it) > 120:
            lines.append(line)
            line = '\t'
        line += it + ', '
    lines.append(line.rstrip(', ') + ']')
    return '\n'.join(lines)


_pts, _ = dg.walk(de.as_plain(segs))
shade, pad = de.design_shade(segs, _pts)
ramps = de.design_ramps(segs, _pts)


def shade_js():
    items = [f"['{k}', {num(a)}, {num(b)}, '{m}']" for (k, a, b, m) in shade['segs']]
    roll = ', '.join(f"[{r[0]}, {r[1]}, {num(r[2])}, {num(r[3])}]" for r in shade['roll'])
    return ('  // <shade> written by tools/sync_eridanus.py: the shade line (a private covered STARFIGHTER line\n'
            '  // into the start town, tools/design_eridanus.py) and the lake town\'s medical pad\n'
            f"  const SHADE_SEGS = [{', '.join(items)}];\n"
            f"  const ERI_SHADE = {{ name: 'shade', segs: SHADE_SEGS, from: {shade['from']}, join: {shade['join']}, width: {num(shade['width'])}, "
            f"jz: {shade['jz']}, covered: [{shade['covered'][0]}, {shade['covered'][1]}], roll: [{roll}], height: {num(de.CANOPY_H)} }};\n"
            f"  const ERI_PAD = {pad};\n"
            f"  const ERI_RAMPS = {ramps};   // the covered ramps at each end of each town: [first, last] main samples\n"
            '  // </shade>')


def shade_gd():
    def f(v):
        return repr(round(float(v), 3))
    items = [f'["{k}", {f(a)}, {f(b)}, "{m}"]' for (k, a, b, m) in shade['segs']]
    roll = ', '.join(f"[{r[0]}, {r[1]}, {f(r[2])}, {f(r[3])}]" for r in shade['roll'])
    return ('# <shade> written by tools/sync_eridanus.py: the shade line (a private covered STARFIGHTER line\n'
            '# into the start town, tools/design_eridanus.py) and the lake town\'s medical pad\n'
            f"const SHADE_SEGS := [{', '.join(items)}]\n"
            f'const ERI_SHADE := {{"name": "shade", "segs": SHADE_SEGS, "from": {shade["from"]}, "join": {shade["join"]}, "width": {f(shade["width"])}, '
            f'"jz": {shade["jz"]}, "covered": [{shade["covered"][0]}, {shade["covered"][1]}], "roll": [{roll}], "height": {f(de.CANOPY_H)}}}\n'
            f"const ERI_PAD := {pad}\n"
            f"const ERI_RAMPS := {ramps}   # the covered ramps at each end of each town: [first, last] main samples\n"
            '# </shade>')


def put_block(s, block, start, end, before):
    """Replace the marked block, or insert it ahead of the line holding `before`."""
    if start in s:
        a = s.index(start)
        a = s.rfind('\n', 0, a) + 1
        b = s.index(end, a) + len(end)
        return s[:a] + block + s[b:]
    i = s.rfind('\n', 0, s.index(before)) + 1
    return s[:i] + block + '\n' + s[i:]


p = os.path.join(ROOT, 'sim-core.js')
s = open(p, encoding='utf-8').read()
s2 = re.sub(r"  const ERI_SEGS = \[.*?\];", js_list().replace('\\', '\\\\'), s, count=1, flags=re.S)
s2 = re.sub(r'turns"\): \d+ km, tools/design_eridanus.py', f'turns"): {km:.0f} km, tools/design_eridanus.py', s2, count=1)
assert s2 != s or 'ERI_SEGS' in s
s2 = put_block(s2, shade_js(), '// <shade>', '// </shade>', '  // The courses: straights and exact arcs')
dawn_dir = round(math.radians(de.DAWN_DIR_DEG), 6)
s2, nd = re.subn(r'(wallMu: 0\.22,\s+)dawnDir: -?[\d.]+, dawnT0: -?[\d.]+', lambda m: f'{m.group(1)}dawnDir: {dawn_dir}, dawnT0: {de.DAWN_T0}', s2)   # TRACKS.eridanus
assert nd == 1, 'the dawn in TRACKS.eridanus'
if 'branches: [ERI_SHADE]' not in s2:
    a = s2.index("eridanus: { segs: ERI_SEGS")
    b = s2.index('\n', a)
    line = s2[a:b]
    assert line.endswith(' }'), line
    s2 = s2[:a] + line[:-2] + ', branches: [ERI_SHADE], pad: ERI_PAD }' + s2[b:]
if 'ramps: ERI_RAMPS' not in s2:
    s2 = s2.replace('branches: [ERI_SHADE], pad: ERI_PAD }', 'branches: [ERI_SHADE], pad: ERI_PAD, ramps: ERI_RAMPS }', 1)
    assert 'ramps: ERI_RAMPS' in s2
open(p, 'w', encoding='utf-8').write(s2)

p = os.path.join(ROOT, 'godot', 'sim', 'craft_sim.gd')
s = open(p, encoding='utf-8').read()
s2 = re.sub(r"const ERI_SEGS := \[.*?\]\]", gd_list().replace('\\', '\\\\'), s, count=1, flags=re.S)
s2 = re.sub(r'\(tools/design_eridanus.py\), \d+ km\.', f'(tools/design_eridanus.py), {km:.0f} km.', s2, count=1)
s2 = put_block(s2, shade_gd(), '# <shade>', '# </shade>', '# The courses: widths per mode')
s2, nd = re.subn(r'("wallMu": 0\.22,\s+)"dawnDir": -?[\d.]+, "dawnT0": -?[\d.]+', lambda m: f'{m.group(1)}"dawnDir": {dawn_dir}, "dawnT0": {float(de.DAWN_T0)}', s2)
assert nd == 1, 'the dawn in TRACKS["eridanus"]'
if '"branches": [ERI_SHADE]' not in s2:
    a = s2.index('"eridanus": {"segs": ERI_SEGS')
    b = s2.index('},\n', s2.index('"bank_r"', a)) + 1
    s2 = s2[:a] + s2[a:b - 1] + ', "branches": [ERI_SHADE], "pad": ERI_PAD}' + s2[b:]
if '"ramps": ERI_RAMPS' not in s2:
    s2 = s2.replace('"branches": [ERI_SHADE], "pad": ERI_PAD}', '"branches": [ERI_SHADE], "pad": ERI_PAD, "ramps": ERI_RAMPS}', 1)
    assert '"ramps": ERI_RAMPS' in s2
open(p, 'w', encoding='utf-8').write(s2)
print(f'synced {len(segs)} segments, {km:.1f} km + shade line ({len(shade["segs"])} segments), the pad at {pad}, ramps {ramps}, '
      f'the dawn {de.DAWN_DIR_DEG} deg at {de.DAWN_T0} s')
