## The Network's city GPs (tools/sync_gp_variants.py: the grand prix four ways, one per city):
##   parity      each builds as sim-core.js does (samples, length) and replays tools/record_gp.js's
##               autopilot lap (replay/<gp>_*.json) within 0.5%, the finish within 1 m
##   variants    each a closed 29.3 km loop; the mirrored ones turn the other way round
##   landscape   a city's GP stands in its landscape (Glacier: the ground all ice, the ice haze) with
##               its towers round the circuit
##   entry       on the Network the city's GP is on offer in its STARFIGHTER zone, nowhere else
##   back        the menu hold from a city GP goes back to the Network; each keeps its own lap record
## Prints CITY GPS PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_city_gps.gd -- --mute
extends SceneTree

const CraftSimScript := preload("res://sim/craft_sim.gd")
const ViewScript := preload("res://view/craft_view.gd")
const VrScript := preload("res://vr/vr_cockpit.gd")
const DT := 1.0 / 480.0
const SUB := 8
const GPS := ["gp_dunes", "gp_glacier", "gp_basalt", "gp_mesa"]
const CHECKS := 8
var fails := 0
var passed := 0
var v
var frames := 0
var stage := 0


func _initialize() -> void:
	var turns := {}
	for gp in GPS:
		var X: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/%s_expected.json" % gp))
		var inputs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/%s_inputs.json" % gp))
		var sim = CraftSimScript.new({"track": gp})
		var lap := -1.0
		for u in inputs:
			var inp := {"thrL": u[0], "thrR": u[1], "brkL": u[2], "brkR": u[3], "repair": false, "reignite": true}
			for k in SUB:
				sim.step(inp, DT)
				for e in sim.events:
					if e.type == "lap" and lap < 0.0:
						lap = e.t
				sim.events.clear()
				if lap >= 0.0:
					break
			if lap >= 0.0:
				break
		var ref: float = X.lap_time
		var err: float = absf(lap - ref) / ref * 100.0 if lap > 0.0 else 100.0
		var dp := Vector2(sim.pod.x - float(X.final_pod[0]), sim.pod.y - float(X.final_pod[1])).length()
		_check("%s: %d samples (js %d), %.3f km; a lap %.3f s (js %.3f, %.3f%%), the finish %.3f m off" % [gp, sim.N, int(X.track_samples), sim.track_length / 1000.0, lap, ref, err, dp],
			sim.N == int(X.track_samples) and absf(sim.track_length - float(X.track_length)) < 0.01 and lap > 0.0 and err <= 0.5 and dp <= 1.0 and sim.P.handling == "starfighter")
		var t := 0.0
		for i in sim.N:
			var j: int = (i + 1) % sim.N
			t += atan2(sim.ttx[i] * sim.tty[j] - sim.tty[i] * sim.ttx[j], sim.ttx[i] * sim.ttx[j] + sim.tty[i] * sim.tty[j])
		turns[gp] = rad_to_deg(t)
	_check("variants: the turning round each loop %s (the mirrored ones the other way)" % [turns],
		absf(turns.gp_dunes - 360.0) < 1.0 and absf(turns.gp_glacier + 360.0) < 1.0 and absf(turns.gp_basalt + 360.0) < 1.0 and absf(turns.gp_mesa - 360.0) < 1.0)
	ViewScript.track_override = "gp_glacier"
	ViewScript.job_override = "none"
	v = ViewScript.new()
	root.add_child(v)


func _process(_d: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	if stage == 0:
		var ice: float = v.ground_mat.get_shader_parameter("ice")
		var towers: int = v.gp_skyline.get_child(0).multimesh.instance_count if v.gp_skyline else 0
		_check("landscape: Glacier's GP on the ice (ground %.1f ice), its haze %s, %d towers round it; its record %s" % [ice, v.BIOME_HAZE.ice, towers, v._best_path()],
			ice == 1.0 and towers > 300 and v._best_path() == "user://gp_glacier_best_%s.json" % v.sim.P.handling)
		v.queue_free()
		ViewScript.track_override = "network"
		ViewScript.best_dir = OS.get_user_data_dir().path_join("test_city_gps_")
		DirAccess.remove_absolute(ViewScript.best_dir + "network.json")
		v = ViewScript.new()
		root.add_child(v)
		stage = 1
		frames = 0
		return false
	if stage == 1:
		var sim = v.sim
		var g := -1
		for k in sim.cities.size():
			if sim.cities[k].name == "GLACIER":
				g = k
		sim.respawn(g)
		var at_terminal: String = v.net_city_gp()
		v.flash_until = -1.0
		var dash: String = v._progress_text()
		var e2 := -1
		for r in sim.roads.size():
			if sim.roads[r].name == "E2":
				e2 = r
		sim.respawn_on(e2, 5000, 1)
		var on_hwy: String = v.net_city_gp()
		sim.respawn(0)
		var at_eridanus: String = v.net_city_gp()
		_check("entry: at Glacier's terminal \"%s\" (the dash \"%s\"); on E2 \"%s\"; at Eridanus \"%s\"" % [at_terminal, dash, on_hwy, at_eridanus],
			at_terminal == "gp_glacier" and dash.contains("HOLD A: GLACIER GP") and on_hwy == "" and at_eridanus == "")
		var back := []
		for gp in GPS:
			back.append(VrScript.next_track(gp))
		_check("back: the menu hold from each city GP goes to %s; the main cycle still range -> %s" % [back, VrScript.next_track("range")],
			back == ["network", "network", "network", "network"] and VrScript.next_track("range") == "gp")
		var good: bool = fails == 0 and passed == CHECKS
		print("CITY GPS ", "PASS" if good else "FAIL (%d failed, %d of %d passed)" % [fails, passed, CHECKS])
		quit(0 if good else 1)
		stage = 2
	return false


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
