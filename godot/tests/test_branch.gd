## Branch roads (the shade line): GDScript CraftSim builds the same branch as sim-core.js and
## replays tools/branch_test.js's scripted drives at the split (replay/branch_expected.json), which
## must come out the same: locked outside the job (the main wall holds), open on the job (every
## body onto the branch inside the junction zone and back at the join), shut when the craft reaches
## the zone over 1,250 mph, never on it straight down the main road; restart and respawn put every
## body back on the main road. Plus the view's side: the corkscrews' roll (paced <= 90 deg/s at
## 1,200 mph) and the road's height under the canopy.
## Prints BRANCH PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_branch.gd
extends SceneTree

const CraftSimScript := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0
const SUB := 8
const MPH := 2.236936
const NAMES := ["L", "R", "pod"]


func _initialize() -> void:
	var X: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/branch_expected.json"))
	var fails := 0
	var sim = CraftSimScript.new({"track": "eridanus"})
	fails += _check("one branch on Eridanus, locked outside the job (%d, open %s); the job opens it; none on the GP" % [sim.branches.size(), sim.branches[0].open if sim.branches.size() else "-"],
		sim.branches.size() == 1 and not sim.branches[0].open and CraftSimScript.new({"track": "eridanus", "job": "emergency"}).branches[0].open
		and CraftSimScript.new({"track": "gp"}).branches.is_empty())
	var B = sim.branches[0]
	var xb: Dictionary = X.branch
	var err := 0.0
	if B.N == int(xb.N):
		for i in B.N:
			for pair in [[B.px, xb.px], [B.py, xb.py], [B.tx, xb.tx], [B.ty, xb.ty], [B.nx, xb.nx], [B.ny, xb.ny], [B.len, xb.len], [B.w, xb.w]]:
				err = maxf(err, absf(pair[0][i] - float(pair[1][i])))
	fails += _check("the same branch: %d samples (js %d), from %d to %d, jz %d, covered %s; worst difference %.9f m" % [B.N, int(xb.N), B.from_i, B.join_i, B.jz, B.covered, err],
		B.N == int(xb.N) and B.from_i == int(xb.from) and B.join_i == int(xb.join) and B.jz == int(xb.jz) and err < 1e-6
		and B.covered == Vector2i(int(xb.covered[0]), int(xb.covered[1])))

	for d in X.drives:
		var r := _drive(d, d.inputs.size())
		var sw_ok: bool = r.switches.size() == d.switches.size()
		if sw_ok:
			for k in r.switches.size():
				var a: Array = r.switches[k]
				var b: Array = d.switches[k]
				sw_ok = sw_ok and a[0] == int(b[0]) and a[1] == b[1] and a[2] == int(b[2]) and a[3] == int(b[3])
		var g_ok: bool = r.gates.size() == d.gates.size()
		if g_ok:
			for k in r.gates.size():
				g_ok = g_ok and int(r.gates[k][0]) == int(d.gates[k][0]) and str(r.gates[k][1]) == str(d.gates[k][1])   # true / false / <null>
		var dp := Vector2(r.pod.x - float(d.pod[0]), r.pod.y - float(d.pod[1])).length()
		print("  %s: switches %s (js %s), walls %s (js %s), gates %s (js %s), pod %.4f m from js" % [d.name, r.switches, d.switches, r.walls, d.walls, r.gates, d.gates, dp])
		fails += _check("%s: the same drive (switches, walls, gates) and the pod within 0.1 m (as the course parity: float drift through wall hits)" % d.name,
			sw_ok and g_ok and r.walls.hit == int(d.walls.hit) and r.walls.scrape == int(d.walls.scrape) and dp < 0.1)
	# the outcomes themselves, on the GD side
	var by := {}
	for d in X.drives:
		by[d.name] = d
	var lk: Dictionary = _drive(by.locked, by.locked.inputs.size())
	fails += _check("locked: the main wall holds, every body stays on the main road", lk.walls.hit + lk.walls.scrape > 0 and lk.switches.is_empty() and lk.paths == [0, 0, 0])
	var op: Dictionary = _drive(by.open, by.open.inputs.size())
	var ins: Array = op.switches.filter(func(s): return s[2] == 1)
	var outs: Array = op.switches.filter(func(s): return s[2] == 0)
	fails += _check("open: all three onto the branch inside the junction zone %s and back at the join %s, clean" % [ins, outs],
		ins.size() == 3 and ins.all(func(s): return s[3] < B.jz) and outs.size() == 3 and outs.all(func(s): return absi(s[3] - B.join_i) <= B.jz)
		and op.walls.hit + op.walls.scrape == 0 and op.paths == [0, 0, 0])
	var fs: Dictionary = _drive(by.fast, by.fast.inputs.size())
	fails += _check("fast: over 1,250 mph at the zone the gate stays shut %s, the main wall holds" % [fs.gates],
		not fs.gates.is_empty() and fs.gates[0][1] == false and fs.switches.is_empty() and fs.walls.hit + fs.walls.scrape > 0)
	var sr: Dictionary = _drive(by.straight, by.straight.inputs.size())
	fails += _check("straight: past the split on the main road, never on the branch", sr.switches.is_empty() and sr.walls.hit + sr.walls.scrape == 0)

	var mid := int(X.restart_at)
	var h1: Dictionary = _drive(by.open, mid)
	var on_it: bool = h1.paths == [1, 1, 1]
	h1.sim.restart()
	var rs_ok := true
	for b in h1.sim.bodies:
		rs_ok = rs_ok and b.path == 0 and b.hint == 0
	fails += _check("restart on the branch (frame %d, on it: %s): every body on the main road at the start" % [mid, on_it], on_it and rs_ok)
	var h2: Dictionary = _drive(by.open, mid)
	h2.sim.respawn()
	var s2 = h2.sim
	var cpi: int = int(round(float(s2.checkpoint) * s2.N / s2.checkpoints)) % s2.N
	var rp_ok := true
	for b in s2.bodies:
		rp_ok = rp_ok and b.path == 0 and b.hint == cpi
	fails += _check("respawn on the branch: every body on the main road at checkpoint %d's sample" % s2.checkpoint, rp_ok)

	# the view's side: the corkscrews turn the road over and back, never faster than 90 deg/s at 1,200 mph
	var peak := 0.0
	for i in B.N - 1:
		peak = maxf(peak, absf(sim.roll_at(1, i + 1) - sim.roll_at(1, i)) / B.len[i] * 1200.0 / MPH)
	var mid_c: int = (B.covered.x + B.covered.y) / 2
	var sf: Vector2 = sim.surface_at(B.px[mid_c], B.py[mid_c], mid_c, 1)
	fails += _check("corkscrews: upright at the split (%.1f deg), over at the canopy's middle (%.1f), upright at the join (%.1f); peak %.1f deg/s at 1,200 mph" % [
		rad_to_deg(sim.roll_at(1, 0)), rad_to_deg(sim.roll_at(1, mid_c)), rad_to_deg(sim.roll_at(1, B.N - 1)), rad_to_deg(peak)],
		sim.roll_at(1, 0) == 0.0 and absf(sim.roll_at(1, mid_c) - PI) < 1e-9 and sim.roll_at(1, B.N - 1) == 0.0 and rad_to_deg(peak) <= 90.0)
	fails += _check("the road under the canopy: %.1f m up (want %.0f), unbanked; the main road's surface unchanged at the split (%s)" % [sf.x, B.height, sim.surface_at(B.px[0], B.py[0], B.from_i)],
		absf(sf.x - B.height) < 1e-6 and sf.y == 0.0 and sim.roll_at(0, 100) == 0.0)
	print("BRANCH PASS" if fails == 0 else "BRANCH FAIL (%d)" % fails)
	quit(1 if fails else 0)


## One drive from the dump: respawned at main sample d.at, every body at d.mph along the track,
## the logged inputs replayed for `frames` frames (d.slow rescales every body's speed at a frame).
func _drive(d: Dictionary, frames: int) -> Dictionary:
	var over := {"track": "eridanus"}
	over.merge(d.over, true)
	var sim = CraftSimScript.new(over)
	var at := int(d.at)
	sim.respawn(-1, at)
	var v0: float = float(d.mph) / MPH
	for b in sim.bodies:
		b.vx = v0 * sim.ttx[at]
		b.vy = v0 * sim.tty[at]
	var switches := []
	var gates := []
	var walls := {"hit": 0, "scrape": 0}
	var gate = null
	for f in frames:
		if d.slow != null and f == int(d.slow[0]):
			var k: float = (float(d.slow[1]) / MPH) / sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
			for b in sim.bodies:
				b.vx *= k
				b.vy *= k
		var u: Array = d.inputs[f]
		var inp := {"thrL": u[0], "thrR": u[1], "brkL": u[2], "brkR": u[3], "repair": false, "reignite": true}
		for k in SUB:
			var was := [sim.eL.path, sim.eR.path, sim.pod.path]
			sim.step(inp, DT)
			for j in 3:
				var b = sim.bodies[j]
				if b.path != was[j]:
					switches.append([f, NAMES[j], b.path, b.hint])
			if sim.gate[0] != gate:
				gate = sim.gate[0]
				gates.append([f, gate])
			for e in sim.events:
				if walls.has(e.type):
					walls[e.type] += 1
			sim.events.clear()
	return {"sim": sim, "switches": switches, "gates": gates, "walls": walls, "pod": Vector2(sim.pod.x, sim.pod.y),
		"paths": [sim.eL.path, sim.eR.path, sim.pod.path]}


func _check(label: String, ok: bool) -> int:
	print(("  ok   " if ok else "  FAIL ") + label)
	return 0 if ok else 1
