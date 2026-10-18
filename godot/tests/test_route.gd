## Route gate: overpasses and landmarks are placed where they belong. Every overpass clears the
## twisty lane, the mile signs and the countdown boards, and flies over the telegraph line;
## every landmark keeps off every lane, corridor and sign, and off every other feature; and the
## real chunks' rocks and spires stay out of every footprint. Prints ROUTE PASS when all pass.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_route.gd -- --track=range --mute
extends SceneTree

const ViewScript := preload("res://view/craft_view.gd")
const Route := preload("res://view/route_features.gd")
const RW := preload("res://view/range_world.gd")
const Sim := preload("res://sim/craft_sim.gd")
const MILE := 1609.344
var fails := 0
var passed := 0
var v
var frames := 0


func _initialize() -> void:
	var r = Route.new()
	print("  overpasses at miles: %s" % [r.overpass_x.map(func(x): return snappedf(x / MILE, 0.01))])
	_check("8 overpasses", r.overpass_x.size() == 8)
	var boards := []
	for mi in RW.COUNTDOWN_MI:
		boards.append(Sim.BOX_X - mi * MILE)
	for m in RW.COUNTDOWN_M:
		boards.append(Sim.BOX_X - m)
	var worst_twist := -INF
	var worst_sign := INF
	for o in r.overpass_x:
		for s in range(-30, 31, 5):
			worst_twist = maxf(worst_twist, RW.twist_y(o + s) + RW.TWIST_HALF)
		worst_sign = minf(worst_sign, absf(o - round(o / MILE) * MILE))
		for b in boards:
			worst_sign = minf(worst_sign, absf(o - b))
	_check("every overpass ramp ends clear of the twisty lane (its nearest edge %.0f m, ramp ends at %.0f)" % [worst_twist, -Route.RAMP_END_Y],
		worst_twist <= -Route.RAMP_END_Y - 20.0)
	_check("every overpass stands clear of the mile signs and countdown boards (nearest %.0f m)" % worst_sign, worst_sign >= 150.0)
	_check("deck underside %.1f m clears the telegraph poles (11 m) and anything on the runway" % (Route.DECK_TOP - Route.DECK_T),
		Route.DECK_TOP - Route.DECK_T >= 11.5)
	var pier_ok := true
	for py in Route.PIER_Y:
		pier_ok = pier_ok and absf(py) >= RW.RUNWAY_HALF + 10.0 and absf(py - RW.POLE_Y) >= 10.0 and absf(absf(py) - RW.POST_Y) >= 5.0
	_check("piers stand off the runway, the marker poles and the telegraph line", pier_ok)

	# landmarks vs the lanes, corridors and signs
	var clash := []
	for b in r.blockers:
		var kind: String = b[4]
		if kind == "overpass":
			continue
		var bands := [[Sim.JUMP_Y - Sim.JUMP_W / 2.0 - 20.0, Sim.JUMP_Y + Sim.JUMP_W / 2.0 + 60.0, "jump lane"],
			[RW.RAIL_Y - 30.0, RW.RAIL_Y + 30.0, "railway"], [RW.HWY_Y - 40.0, RW.HWY_Y + 40.0, "highway"]]
		if kind != "gantry":   # the gantry spans the runway by design
			bands.append([-RW.RUNWAY_HALF - 20.0, RW.RUNWAY_HALF + 20.0, "runway"])
			bands.append([RW.POLE_Y - 10.0, RW.POLE_Y + 10.0, "telegraph line"])
		for band in bands:
			if b[3] > band[0] and b[2] < band[1]:
				clash.append("%s on the %s" % [kind, band[2]])
		var x: float = b[0]
		while x <= b[1]:
			var ty := RW.twist_y(x)
			if b[3] > ty - RW.TWIST_HALF - 30.0 and b[2] < ty + RW.TWIST_HALF + 30.0:
				clash.append("%s on the twisty lane" % kind)
				break
			x += 20.0
		var m := ceilf(b[0] / MILE)
		while m * MILE < b[1]:
			if b[2] < 90.0 + 20.0 and b[3] > 90.0 - 20.0:
				clash.append("%s on the mile %d sign" % [kind, m])
			m += 1.0
	for i in r.blockers.size():
		for j in range(i + 1, r.blockers.size()):
			var a: Array = r.blockers[i]
			var c: Array = r.blockers[j]
			if a[0] < c[1] and c[0] < a[1] and a[2] < c[3] and c[2] < a[3]:
				clash.append("%s overlaps %s" % [a[4], c[4]])
	_check("landmarks keep off every lane, corridor, sign and each other %s" % ["" if clash.is_empty() else str(clash)], clash.is_empty())

	# the real chunks: their rocks and spires stay out of every footprint
	v = ViewScript.new()
	root.add_child(v)


func _process(_d: float) -> bool:
	frames += 1
	if frames < 2:
		return false
	var rw = v.range_world
	var r = rw.route
	var idxs := {}
	for b in r.blockers:
		for i in range(int(floor((b[0] - 300.0) / RW.CHUNK)), int(floor((b[1] + 300.0) / RW.CHUNK)) + 1):
			idxs[i] = true
	var bad := 0
	var checked := 0
	var why := ""
	for i in idxs:
		var node: Node3D = rw._make_chunk(i)
		var cx: float = i * RW.CHUNK
		var x0 := maxf(0.0, cx) - cx
		var x1 := minf(Sim.RANGE_LEN + Sim.OVERRUN, cx + RW.CHUNK) - cx
		if x1 > x0:   # rocks from the placement function (headless MultiMeshes don't keep transforms)
			for xf in rw.rock_xforms(i, cx, x0, x1):
				var p: Vector3 = xf.origin
				checked += 1
				if r.blocked(cx + p.x, -p.z, 0.0):
					bad += 1
					why = "rock at (%.0f, %.0f) chunk %d in %s" % [cx + p.x, -p.z, i, _which(r, cx + p.x, -p.z)]
		for ch in node.get_children():
			if ch is MeshInstance3D and ch.material_override == rw.mats.strata:
				for p in (ch.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
					checked += 1
					if r.blocked(cx + p.x, -p.z, 0.0):
						bad += 1
						why = "spire vertex at (%.0f, %.0f) chunk %d in %s" % [cx + p.x, -p.z, i, _which(r, cx + p.x, -p.z)]
		node.queue_free()
	_check("rocks and spires stay out of every footprint (%d checked in %d chunks, %d inside%s)" % [checked, idxs.size(), bad, "" if why == "" else ", e.g. " + why], bad == 0 and checked > 1000)
	var good: bool = fails == 0 and passed == 7
	print("ROUTE ", "PASS" if good else "FAIL (%d failed, %d passed)" % [fails, passed])
	quit(0 if good else 1)
	return true


static func _which(r, x: float, y: float) -> String:
	for b in r.blockers:
		if x > b[0] and x < b[1] and y > b[2] and y < b[3]:
			return b[4]
	return "?"


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
