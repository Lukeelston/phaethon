## The Network's flow gate (view/craft_view.gd on track "network"):
##   start      a first launch (no saved file) starts at Eridanus' terminal; the target is the nearest
##              city not found (Glacier) and the dash reads "GLACIER  x mi   AT ERIDANUS"
##   cycle      the target cycles round the other cities, never the one you're at
##   arrive     tools/record_network.js's drive to Glacier (replay/network_inputs.json) through the
##              view: the dash flashes ARRIVED GLACIER with a new best; the file (in a redirected
##              best_dir) holds Glacier found, the last city Glacier and the best ERIDANUS>GLACIER;
##              the next target isn't Glacier
##   persist    a new view starts at Glacier, with what was found
##   reset      a reset puts you at the last city's terminal
##   cycle VR   the menu hold's cycle: range -> gp -> eridanus -> emergency -> network -> range
## Prints NETWORK FLOW PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_network_flow.gd -- --mute
extends SceneTree

const ViewScript := preload("res://view/craft_view.gd")
const VrScript := preload("res://vr/vr_cockpit.gd")
const CHECKS := 6
const ASK := ["", "speed", "starfighter"]
var fails := 0
var passed := 0
var v
var v2
var frames := 0


func _initialize() -> void:
	ViewScript.track_override = "network"
	ViewScript.job_override = "none"
	ViewScript.best_dir = OS.get_user_data_dir().path_join("test_network_flow_")
	DirAccess.remove_absolute(ViewScript.best_dir + "network.json")
	v = ViewScript.new()
	root.add_child(v)


func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		var sim = v.sim
		var e: Dictionary = sim.cities[0]
		var q := Vector2(sim.roads[e.road].px[e.i], sim.roads[e.road].py[e.i])
		var at := Vector2(sim.pod.x, sim.pod.y).distance_to(q)
		v.flash_until = -1.0
		var dash: String = v._progress_text()
		_check("start: at %s's terminal (%.1f m off it), the target %s; the dash \"%s\"" % [e.name, at, sim.cities[v.net_target].name if v.net_target >= 0 else "none", dash],
			at < 3.0 and v.net_target >= 0 and sim.cities[v.net_target].name == "GLACIER" and dash.begins_with("GLACIER  ") and dash.contains(" mi") and dash.contains("AT ERIDANUS"))
		var seen := []
		for k in 8:
			v.net_cycle_target()
			seen.append(v.net_target)
		var ok_cycle: bool = not seen.has(int(sim.net.from)) and seen.slice(0, 4).duplicate().size() == 4
		var distinct := {}
		for t in seen.slice(0, 4):
			distinct[t] = true
		_check("cycle: the targets %s, never %s, all four others" % [seen, sim.cities[int(sim.net.from)].name], ok_cycle and distinct.size() == 4)
		while v.net_target != 2:
			v.net_cycle_target()
		# the drive
		var X: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/network_expected.json"))
		var inputs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/network_inputs.json"))
		sim.respawn_on(int(X.start[0]), int(X.start[1]), int(X.start[2]))
		var flash := ""
		for f in inputs.size():
			var u: Array = inputs[f]
			v.inp = {"thrL": float(u[0]), "thrR": float(u[1]), "brkL": float(u[2]), "brkR": float(u[3]), "repair": false, "reignite": true}
			v.handling_ask = ASK[int(u[4])] if int(u[4]) > 0 else ""
			for k in 8:
				v._sim_step()
			if v.flash_msg.begins_with("ARRIVED") and flash == "":
				flash = v.flash_msg
		var saved = JSON.parse_string(FileAccess.get_file_as_string(ViewScript.best_dir + "network.json")) if FileAccess.file_exists(ViewScript.best_dir + "network.json") else {}
		var best: Dictionary = saved.get("best", {}) if saved is Dictionary else {}
		var found: Array = saved.get("found", []) if saved is Dictionary else []
		_check("arrive: \"%s\"; saved found %s, last %s, best %s; the next target %s" % [flash, found, saved.get("last", "-") if saved is Dictionary else "-", best, sim.cities[v.net_target].name],
			flash.begins_with("ARRIVED GLACIER") and flash.contains("NEW BEST") and found.has(2.0) and int(saved.get("last", -1)) == 2
			and best.has("ERIDANUS>GLACIER") and absf(float(best["ERIDANUS>GLACIER"]) - float(X.arrivals[0][3])) < 0.01 and v.net_target != 2)
		v2 = ViewScript.new()
		root.add_child(v2)
		return false
	if frames == 5:
		var s2 = v2.sim
		var g: Dictionary = s2.cities[2]
		var q := Vector2(s2.roads[g.road].px[g.i], s2.roads[g.road].py[g.i])
		_check("persist: a new view starts at %s (%.1f m off its terminal), found %s" % [s2.cities[int(s2.net.from)].name, Vector2(s2.pod.x, s2.pod.y).distance_to(q), v2.net_found.keys()],
			int(s2.net.from) == 2 and Vector2(s2.pod.x, s2.pod.y).distance_to(q) < 3.0 and v2.net_found.has(2) and v2.net_found.has(0))
		var sim = v.sim
		sim.respawn_on(0, 3000, 1)
		v._respawn()
		var c: Dictionary = sim.cities[int(sim.net.from)]
		var cq := Vector2(sim.roads[c.road].px[c.i], sim.roads[c.road].py[c.i])
		_check("reset: back at %s's terminal (%.1f m off it)" % [c.name, Vector2(sim.pod.x, sim.pod.y).distance_to(cq)], c.name == "GLACIER" and Vector2(sim.pod.x, sim.pod.y).distance_to(cq) < 3.0)
		var cyc := ["range"]
		for k in 5:
			cyc.append(VrScript.next_track(cyc[-1]))
		_check("cycle VR: %s" % " -> ".join(cyc), cyc == ["range", "gp", "eridanus", "emergency", "network", "range"] and VrScript.overrides_for("network") == ["network", "none"])
		var good: bool = fails == 0 and passed == CHECKS
		print("NETWORK FLOW ", "PASS" if good else "FAIL (%d failed, %d of %d passed)" % [fails, passed, CHECKS])
		quit(0 if good else 1)
	return false


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
