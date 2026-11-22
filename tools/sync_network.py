"""Write the Network (tools/design_network.py) into both sims: a <network> block in sim-core.js and
in godot/sim/craft_sim.gd (roads as segment lists walked from their poses, the junction table, the
cities, the roads' heights (keys [sample, m, slope], Hermite between: real in both sims, the deck
lock), the jumps and the on-ramps from the open ground).

Usage: python tools/sync_network.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import design_network as dn

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

roads, J, cities, H, ok, jumps, onramps, shafts, overlaps, twists = dn.main()
assert ok, "the design isn't OK: fix it before syncing"
scenic = dn.scenic_table(roads)
widths = dn.width_table(roads)
decks = dn.deck_table(roads)
tube = next((i, *r.tube_span) for i, r in enumerate(roads) if r.kind == "tube")


def scenic_rows(indent):
    return ["%s[%d, %d, [%s]]," % (indent, r, sea, ", ".join("[%d, %s]" % (int(k[0]), ", ".join(num(v) for v in k[1:])) for k in rows))
            for r, sea, rows in scenic]


def num(v):
    return repr(float(v))


def seg(s, q):
    """A segment as both sims read it: [kind, length or radius, degrees, mode], and for a vertical arc ("V") the
    pitch it ends at (q: the quote mark)."""
    more = f", {num(s[4])}" if len(s) > 4 else ""
    return f"[{q}{s[0]}{q}, {num(s[1])}, {num(s[2])}, {q}{s[3]}{q}{more}]"


def js_block():
    out = ["  // <network> (tools/sync_network.py from tools/design_network.py: don't edit by hand)",
           f"  const NET_STEP = {num(dn.STEP)};",
           "  // [name, x, y, heading deg, width, [[kind, length or radius, deg, mode], ...]]",
           "  const NET_ROADS = ["]
    for R in roads:
        segs = ", ".join(seg(s, "'") for s in R.segs)
        out.append(f"    ['{R.name}', {num(R.x0)}, {num(R.y0)}, {num(R.hdeg)}, {num(R.width)}, [{segs}]],")
    out.append("  ];")
    out.append("  // [parent road, a0, a1, child road, b0, b1, sense]: the two roads are one through these samples")
    out.append("  const NET_JUNCTIONS = [")
    for k in range(0, len(J), 6):
        out.append("    " + ", ".join(f"[{', '.join(str(int(v)) for v in j)}]" for j in J[k:k + 6]) + ",")
    out.append("  ];")
    out.append("  // Physical pavement unions only; route choices remain in NET_JUNCTIONS.")
    out.append("  const NET_OVERLAPS = [" + ", ".join(str(j) for j in overlaps) + "];")
    out.append("  const NET_TWISTS = [" + ", ".join(str(j) for j in twists) + "];")
    out.append(f"  const NET_PRESSURE = [{tube[0]}, {tube[1]}, {tube[2]}];")
    out.append("  const NET_JUMP_PROFILES = [" + ", ".join(repr(roads[j[0]].profile) for j in jumps) + "];")
    out.append("  // [name, biome, centre x, centre y, road, terminal sample]")
    out.append("  const NET_CITIES = [")
    for c in cities:
        out.append(f"    ['{c[0]}', '{c[1]}', {num(c[2])}, {num(c[3])}, {c[4]}, {c[5]}],")
    out.append("  ];")
    out.append("  // the roads' heights: [road, [[sample, m, slope], ...]], Hermite between keys (flyovers, jumps)")
    out.append("  const NET_HEIGHTS = [")
    for r, keys in H:
        out.append("    [%d, [%s]]," % (r, ", ".join("[%d, %s, %s]" % (int(k[0]), num(k[1]), num(k[2])) for k in keys)))
    out.append("  ];")
    out.append("  // [launch road (its end is a lip), catch deck, the slowest that lands (mph)]")
    out.append("  const NET_JUMPS = [" + ", ".join("[%d, %d, %s]" % (j[0], j[1], num(j[2])) for j in jumps) + "];")
    out.append("  // [city, road]: the on-ramps from the open ground (their start is open)")
    out.append("  const NET_ONRAMPS = [" + ", ".join("[%d, %d]" % (o[0], o[1]) for o in onramps) + "];")
    out.append("  // [road, pull-up sample, landing sample, R, V]: the shafts (their bulb carries you round; view/network_shaft.gd)")
    out.append("  const NET_SHAFTS = [" + ", ".join("[%d, %d, %d, %s, %s]" % (j[0], j[1], j[2], num(j[3]), num(j[4])) for j in shafts) + "];")
    out.append("  // [road, sea side, [[sample, left m, its run m, right m, its run m, gap m], ...]]: the land beside the scenic roads (the views' only)")
    out.append("  const NET_SCENIC = [")
    out += scenic_rows("    ")
    out.append("  ];")
    out.append("  // [road, [[sample, width m], ...]]: the roads whose width changes along them (a straight line from key to key)")
    out.append("  const NET_WIDTHS = [" + ", ".join("[%d, [%s]]" % (r, ", ".join("[%d, %s]" % (k[0], num(k[1])) for k in keys)) for r, keys in widths) + "];")
    out.append("  // the roads sampled every NET_STEP of their deck, flown at the speed along it (Mount Hyperion's)")
    out.append("  const NET_DECK = [" + ", ".join(str(r) for r in decks) + "];")
    out.append("  // </network>")
    return "\n".join(out)


def gd_block():
    out = ["# <network> (tools/sync_network.py from tools/design_network.py: don't edit by hand)",
           f"const NET_STEP := {num(dn.STEP)}",
           "# [name, x, y, heading deg, width, [[kind, length or radius, deg, mode], ...]]",
           "const NET_ROADS := ["]
    for R in roads:
        segs = ", ".join(seg(s, '"') for s in R.segs)
        out.append(f'\t["{R.name}", {num(R.x0)}, {num(R.y0)}, {num(R.hdeg)}, {num(R.width)}, [{segs}]],')
    out.append("]")
    out.append("# [parent road, a0, a1, child road, b0, b1, sense]: the two roads are one through these samples")
    out.append("const NET_JUNCTIONS := [")
    for k in range(0, len(J), 6):
        out.append("\t" + ", ".join(f"[{', '.join(str(int(v)) for v in j)}]" for j in J[k:k + 6]) + ",")
    out.append("]")
    out.append("# Physical pavement unions only; route choices remain in NET_JUNCTIONS.")
    out.append("const NET_OVERLAPS := [" + ", ".join(str(j) for j in overlaps) + "]")
    out.append("const NET_TWISTS := [" + ", ".join(str(j) for j in twists) + "]")
    out.append(f"const NET_PRESSURE := [{tube[0]}, {tube[1]}, {tube[2]}]")
    out.append("const NET_JUMP_PROFILES := [" + ", ".join('"' + roads[j[0]].profile + '"' for j in jumps) + "]")
    out.append("# [name, biome, centre x, centre y, road, terminal sample]")
    out.append("const NET_CITIES := [")
    for c in cities:
        out.append(f'\t["{c[0]}", "{c[1]}", {num(c[2])}, {num(c[3])}, {c[4]}, {c[5]}],')
    out.append("]")
    out.append("# the roads' heights: [road, [[sample, m, slope], ...]], Hermite between keys (flyovers, jumps)")
    out.append("const NET_HEIGHTS := [")
    for r, keys in H:
        out.append("\t[%d, [%s]]," % (r, ", ".join("[%d, %s, %s]" % (int(k[0]), num(k[1]), num(k[2])) for k in keys)))
    out.append("]")
    out.append("# [launch road (its end is a lip), catch deck, the slowest that lands (mph)]")
    out.append("const NET_JUMPS := [" + ", ".join("[%d, %d, %s]" % (j[0], j[1], num(j[2])) for j in jumps) + "]")
    out.append("# [city, road]: the on-ramps from the open ground (their start is open)")
    out.append("const NET_ONRAMPS := [" + ", ".join("[%d, %d]" % (o[0], o[1]) for o in onramps) + "]")
    out.append("# [road, pull-up sample, landing sample, R, V]: the shafts (their bulb carries you round; view/network_shaft.gd)")
    out.append("const NET_SHAFTS := [" + ", ".join("[%d, %d, %d, %s, %s]" % (j[0], j[1], j[2], num(j[3]), num(j[4])) for j in shafts) + "]")
    out.append("# [road, sea side, [[sample, left m, its run m, right m, its run m, gap m], ...]]: the land beside the scenic roads (the views' only)")
    out.append("const NET_SCENIC := [")
    out += scenic_rows("	")
    out.append("]")
    out.append("# [road, [[sample, width m], ...]]: the roads whose width changes along them (a straight line from key to key)")
    out.append("const NET_WIDTHS := [" + ", ".join("[%d, [%s]]" % (r, ", ".join("[%d, %s]" % (k[0], num(k[1])) for k in keys)) for r, keys in widths) + "]")
    out.append("# the roads sampled every NET_STEP of their deck, flown at the speed along it (Mount Hyperion's)")
    out.append("const NET_DECK := [" + ", ".join(str(r) for r in decks) + "]")
    out.append("# </network>")
    return "\n".join(out)


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
s = put_block(s, js_block(), '// <network>', '// </network>', '  // The courses: straights and exact arcs')
open(p, 'w', encoding='utf-8').write(s)
p = os.path.join(ROOT, 'godot', 'sim', 'craft_sim.gd')
s = open(p, encoding='utf-8').read()
s = put_block(s, gd_block(), '# <network>', '# </network>', '# The courses: widths per mode')
open(p, 'w', encoding='utf-8').write(s)
print(f"synced {len(scenic)} scenic roads' land,", end=" ")
print(f"synced {len(roads)} roads, {len(J)} route junctions, {len(overlaps)} physical overlaps, {len(twists)} twists, {len(cities)} cities, {len(H)} height profiles, {len(jumps)} jumps, {len(onramps)} on-ramps, {len(shafts)} shafts")
