## GP trackside gate: the dressing matches the track the sim drives. The corners found from the
## centreline are the designed arcs (CraftSim.GP_SEGS), in order, with their radii; every slow one
## has its three braking boards. Prints GP WORLD PASS when every check passes.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_gp_world.gd -- --track=gp --mute
extends SceneTree

const ViewScript := preload("res://view/craft_view.gd")
const Sim := preload("res://sim/craft_sim.gd")
var fails := 0
var passed := 0


var v


func _initialize() -> void:
	v = ViewScript.new()
	root.add_child(v)


func _process(_d: float) -> bool:
	_run()
	return true


func _run() -> void:
	var gp = v.gp_world
	_check("GP world built for --track=gp", gp != null)
	if gp == null:
		_done()
		return
	var arcs := []
	for sg in Sim.GP_SEGS:
		if sg[0] != "S":
			arcs.append(sg)
	var found: Array = gp.corners
	_check("%d corners found, %d designed" % [found.size(), arcs.size()], found.size() == arcs.size())
	var worst := 0.0
	var sides_ok := true
	for k in mini(found.size(), arcs.size()):
		var want: float = arcs[k][1]
		worst = maxf(worst, absf(found[k][4] - want) / want)
		sides_ok = sides_ok and int(found[k][3]) == (1 if arcs[k][0] == "L" else -1)
	_check("each corner's radius within 5%% of its design (worst %.1f%%: the run ends average in half a step) and turning the designed way" % (worst * 100.0), worst <= 0.05 and sides_ok)
	var slow := 0
	for c in found:
		if c[5] < gp.SLOW_MPH:
			slow += 1
	var boards := 0
	for ch in gp.get_children():
		if ch is Label3D and ch.text in ["1000", "2000", "3000"]:   # feet (they were 300 / 600 / 1000 m)
			boards += 1
	_check("%d slow corners, %d braking boards (3 each)" % [slow, boards], slow >= 4 and boards == slow * 3)
	# tall walls that show where the track goes
	var flags: PackedInt32Array = gp._chevron_flags()
	var lead_ok := true
	for c in found:
		var outside := -int(c[3])
		lead_ok = lead_ok and flags[posmod(c[0] - gp.CHEVRON_LEAD, gp.sim.N)] == outside and flags[c[1]] == outside
	_check("chevrons on the outside wall of all %d corners, from %d m before each (%d chevrons)" % [found.size(), gp.CHEVRON_LEAD * 12, gp.chevrons],
		lead_ok and gp.chevrons >= found.size() * 8)
	var n_masts: int = 2 * int(ceil(float(gp.sim.N) / gp.MAST_EVERY))
	_check("walls %.1f m tall with a lit strip, a lit mast every %d m on both (%d masts)" % [gp.FENCE_H + gp.STRIP_H, gp.MAST_EVERY * 12, gp.masts],
		gp.FENCE_H >= 5.0 and gp.masts == n_masts)
	var low := 0
	for ch in gp.get_children():
		if ch is Label3D and (ch.text in ["1000", "2000", "3000"] or ch.text.begins_with("T")):
			if ch.position.y < gp.FENCE_H + gp.STRIP_H + 1.5:
				low += 1
	_check("every braking board and turn number stands clear above the tall walls (%d hidden)" % low, low == 0)
	# wider and banked: corners tilt to their inside, pivoting on the inside edge
	var sim = gp.sim
	var big: Array = found[0]
	for c in found:
		if (c[2] - c[0]) * (1.0 if c[4] > 600.0 else 0.0) > (big[2] - big[0]) * (1.0 if big[4] > 600.0 else 0.0):
			big = c
	var apex: int = big[1]
	var bk: float = sim.tb[apex]
	var hw: float = sim.tw[apex] / 2.0
	var inner: Vector3 = gp._edge(apex, signf(bk) * hw)
	var outer: Vector3 = gp._edge(apex, -signf(bk) * hw)
	var flat := 0.0
	for c in found:   # the middle of the longest straight: no bank
		pass
	var mid_straight := int(sim.N * (1400.0 / sim.track_length))   # 1.4 km down the start straight
	flat = absf(rad_to_deg(sim.tb[mid_straight]))
	_check("96 m wide; T%d banked %.1f deg toward its inside (sign %s), inside edge at %.1f m, outside at %.1f m; mid-straight %.2f deg" % [
		big[6], rad_to_deg(absf(bk)), "ok" if signf(bk) == big[3] else "WRONG", inner.y, outer.y, flat],
		sim.tw[apex] == 96.0 and absf(rad_to_deg(absf(bk)) - sim.GP_BANK) < 1.0 and signf(bk) == big[3] and absf(inner.y) < 0.01 and absf(outer.y - 96.0 * tan(absf(bk))) < 0.5 and flat < 0.01)
	var probe: Vector3 = gp._edge(apex, -signf(bk) * (hw - 3.0))   # 3 m in from the outside wall
	var sf: Vector2 = sim.surface_at(sim.tpx[apex] + sim.tnx[apex] * (-signf(bk) * (hw - 3.0)), sim.tpy[apex] + sim.tny[apex] * (-signf(bk) * (hw - 3.0)), apex)
	_check("the craft rides the same surface the trackside is built on (%.2f vs %.2f m), with an earth berm behind the high walls (%d samples)" % [sf.x, probe.y, gp.berm_samples],
		absf(sf.x - probe.y) < 0.5 and gp.berm_samples > 200)
	# the craft tilts with it: pitched up climbing onto a bank's outside line, level on a straight
	var CMs := preload("res://view/craft_model.gd")
	var climb := -1.0
	for i in range(1, sim.N):
		if absf(sim.tb[i]) > deg_to_rad(5.0) and absf(sim.tb[i - 1]) <= deg_to_rad(5.0):
			var out_off: float = -signf(sim.tb[i]) * (sim.tw[i] / 2.0 - 4.0)
			var th := atan2(sim.tty[i], sim.ttx[i])
			sim.pod.hint = i   # the view looks the surface up near the pod: put it here
			climb = rad_to_deg(CMs.slope_pitch(v, sim.tpx[i] + sim.tnx[i] * out_off, sim.tpy[i] + sim.tny[i] * out_off, th, 4.0))
			break
	var ms := int(sim.N * (1400.0 / sim.track_length))
	sim.pod.hint = ms
	var level: float = rad_to_deg(CMs.slope_pitch(v, sim.tpx[ms], sim.tpy[ms], atan2(sim.tty[ms], sim.ttx[ms]), 4.0))
	_check("the craft pitches with the banking: %.1f deg nose-up climbing onto a bank's outside line, %.2f on a straight" % [climb, level],
		climb > 1.0 and absf(level) < 0.01)
	_done()


func _done() -> void:
	var good: bool = fails == 0 and passed == 10
	print("GP WORLD ", "PASS" if good else "FAIL (%d failed, %d passed)" % [fails, passed])
	quit(0 if good else 1)


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
