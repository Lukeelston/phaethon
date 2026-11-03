"""The Network's city GPs (docs/superpowers/specs/2026-10-19-network-design.md, phase 4): the tuned
STARFIGHTER grand prix (GP_SEGS in the sims, tools/design_gp.py) run four ways, one per city:
  gp_dunes     as designed
  gp_glacier   mirrored (every left a right)
  gp_basalt    reversed (the other way round: the segments backwards, each turn the other way)
  gp_mesa      mirrored and reversed
A closed loop stays closed under all four (the reversed ones are the same loop driven backwards,
turned 180 deg), each starts on a straight (the reversed ones on the old back straight, the longest),
and every corner keeps its radius and angle, so the GP's tuning (its banking, its corner speeds)
holds. Writes a <gp_variants> block of literal segment lists into sim-core.js and craft_sim.gd and
their COURSES and TRACKS entries (idempotent).
Usage: python tools/sync_gp_variants.py
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JS = os.path.join(ROOT, 'sim-core.js')
GD = os.path.join(ROOT, 'godot', 'sim', 'craft_sim.gd')


def gp_segs():
    s = open(JS, encoding='utf-8').read()
    m = re.search(r"const GP_SEGS = \[(.*?)\];", s, re.S)
    out = []
    for t in re.findall(r"\[([^\[\]]+)\]", m.group(1)):
        parts = [p.strip().strip("'") for p in t.split(',')]
        out.append([parts[0]] + [float(p) for p in parts[1:]])
    return out


def swap(sg):
    return [{'L': 'R', 'R': 'L'}.get(sg[0], sg[0])] + sg[1:]


def variant(segs, mirror, reverse):
    v = [list(sg) for sg in segs]
    if mirror:
        v = [swap(sg) for sg in v]
    if reverse:
        v = [swap(sg) for sg in reversed(v)]
        longest = max(range(len(v)), key=lambda k: v[k][1] if v[k][0] == 'S' else -1)
        v = v[longest:] + v[:longest]
    return v


VARIANTS = [("gp_dunes", False, False), ("gp_glacier", True, False), ("gp_basalt", False, True), ("gp_mesa", True, True)]


def num(x):
    return repr(float(x))


def js_block(segs):
    out = ["  // <gp_variants> (tools/sync_gp_variants.py: the city GPs, the grand prix four ways; don't edit by hand)"]
    for name, mi, rv in VARIANTS:
        v = variant(segs, mi, rv)
        body = ", ".join(f"['{s[0]}', {', '.join(num(x) for x in s[1:])}]" for s in v)
        out.append(f"  const {name.upper()}_SEGS = [{body}];")
    out.append("  // </gp_variants>")
    return "\n".join(out)


def gd_block(segs):
    out = ["# <gp_variants> (tools/sync_gp_variants.py: the city GPs, the grand prix four ways; don't edit by hand)"]
    for name, mi, rv in VARIANTS:
        v = variant(segs, mi, rv)
        body = ", ".join(f'["{s[0]}", {", ".join(num(x) for x in s[1:])}]' for s in v)
        out.append(f"const {name.upper()}_SEGS := [{body}]")
    out.append("# </gp_variants>")
    return "\n".join(out)


def put_block(s, block, start, end, after):
    if start in s:
        a = s.rfind('\n', 0, s.index(start)) + 1
        b = s.index(end, a) + len(end)
        return s[:a] + block + s[b:]
    i = s.index('\n', s.index(after)) + 1
    return s[:i] + block + '\n' + s[i:]


segs = gp_segs()
s = open(JS, encoding='utf-8').read()
s = put_block(s, js_block(segs), '// <gp_variants>', '// </gp_variants>', 'const GP_STEP = 12')
if 'gp_glacier:' not in s:
    s = s.replace("    gp: { segs: GP_SEGS, checkpoints: 12 },", "    gp: { segs: GP_SEGS, checkpoints: 12 },\n" + "".join(
        f"    {n}: {{ segs: {n.upper()}_SEGS, checkpoints: 12 }},\n" for n, _, _ in VARIANTS), 1)
    s = s.replace("    gp: { wallDmgMin: 25, damagePerMs: 0.004, wallMu: 0.22 },", "    gp: { wallDmgMin: 25, damagePerMs: 0.004, wallMu: 0.22 },\n" + "".join(
        f"    {n}: {{ wallDmgMin: 25, damagePerMs: 0.004, wallMu: 0.22 }},\n" for n, _, _ in VARIANTS), 1)
assert 'gp_glacier:' in s
open(JS, 'w', encoding='utf-8').write(s)

s = open(GD, encoding='utf-8').read()
s = put_block(s, gd_block(segs), '# <gp_variants>', '# </gp_variants>', '\t["S", 3200.0], ["L", 1300.0, 90.0]]')
if '"gp_glacier": {"segs"' not in s:
    s = s.replace('\t"gp": {"segs": GP_SEGS, "checkpoints": 12},', '\t"gp": {"segs": GP_SEGS, "checkpoints": 12},\n' + "".join(
        f'\t"{n}": {{"segs": {n.upper()}_SEGS, "checkpoints": 12}},\n' for n, _, _ in VARIANTS), 1)
    s = s.replace('\t"gp": {"wallDmgMin": 25.0, "damagePerMs": 0.004, "wallMu": 0.22},', '\t"gp": {"wallDmgMin": 25.0, "damagePerMs": 0.004, "wallMu": 0.22},\n' + "".join(
        f'\t"{n}": {{"wallDmgMin": 25.0, "damagePerMs": 0.004, "wallMu": 0.22}},\n' for n, _, _ in VARIANTS), 1)
assert '"gp_glacier": {"segs"' in s
open(GD, 'w', encoding='utf-8').write(s)
print("synced", ", ".join(f"{n} ({len(variant(segs, mi, rv))} segments, starts {variant(segs, mi, rv)[0]})" for n, mi, rv in VARIANTS))
