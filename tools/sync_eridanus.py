"""Write Eridanus' solved segments (tools/design_eridanus.py) into both sims, so the design and the
two copies of ERI_SEGS (sim-core.js, godot/sim/craft_sim.gd) can't drift apart.
Usage: python tools/sync_eridanus.py
"""
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


p = os.path.join(ROOT, 'sim-core.js')
s = open(p, encoding='utf-8').read()
s2 = re.sub(r"  const ERI_SEGS = \[.*?\];", js_list().replace('\\', '\\\\'), s, count=1, flags=re.S)
s2 = re.sub(r'turns"\): \d+ km, tools/design_eridanus.py', f'turns"): {km:.0f} km, tools/design_eridanus.py', s2, count=1)
assert s2 != s or 'ERI_SEGS' in s
open(p, 'w', encoding='utf-8').write(s2)

p = os.path.join(ROOT, 'godot', 'sim', 'craft_sim.gd')
s = open(p, encoding='utf-8').read()
s2 = re.sub(r"const ERI_SEGS := \[.*?\]\]", gd_list().replace('\\', '\\\\'), s, count=1, flags=re.S)
s2 = re.sub(r'\(tools/design_eridanus.py\), \d+ km\.', f'(tools/design_eridanus.py), {km:.0f} km.', s2, count=1)
open(p, 'w', encoding='utf-8').write(s2)
print(f'synced {len(segs)} segments, {km:.1f} km')
