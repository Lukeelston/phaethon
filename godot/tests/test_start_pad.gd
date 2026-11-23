## The starting pad (Luke: "personal starting pads for each insertion point - something that lets the
## pilot run through a preflight"; view/start_pad.gd, CraftSim.net_home and net_pad_right):
##   off        a flight not chosen from a menu starts on the centre line, as it always did, with no pad
##   asked      a menu's flight starts in a bay at the right-hand roadside: on the flat inside the edge
##              ramp, facing up the road, at rest, with the pad built round it
##   everywhere at every start point the bay is on the flat, clear of the wall, inside the outermost
##              lane's reach (its traffic moves over for the parked craft) and outside the next lane's
##   back       a crash puts the craft back on the pad; reach a city and the pad is at that city's terminal
##   follows    the pad's lamps, gate and ground power follow the start-up: held and red from cold, a
##              lamp for each step, green with the gate up and the lead away once the craft may go
##   traffic    parked on a pad, the craft's way is the way it faces and nothing comes at it on its road
## Prints START PAD PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Sim := preload("res://sim/craft_sim.gd")
const Startup := preload("res://vr/startup_sequence.gd")
const UI := preload("res://release/release_config.gd")
const Outlook := preload("res://view/outlook.gd")
const Livery := preload("res://view/livery.gd")
const Chase := preload("res://view/network_chase.gd")
var failures := 0


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_start_pad_")
	Outlook.pinned = true
	Livery.pinned = true
	Chase.pinned = true
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _view(spot: String, on_pad: bool):
	View.spot_override = spot
	View.pad_start = on_pad
	var v = View.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	return v


## How far the pod is to the right of its road's centre line, the way it faces.
func _right(sim) -> float:
	var R = sim.roads[sim.pod.path]
	var i: int = sim.pod.hint
	var way := 1.0 if cos(sim.pod.th) * R.tx[i] + sin(sim.pod.th) * R.ty[i] >= 0.0 else -1.0
	return -((sim.pod.x - R.px[i]) * R.nx[i] + (sim.pod.y - R.py[i]) * R.ny[i]) * way


func _run() -> void:
	# off
	var v = await _view("city:GLACIER", false)
	_check("not asked: on the centre line (%.2f m right of it), no pad" % _right(v.sim), absf(_right(v.sim)) < 0.5 and v.pad == null and not bool(v.sim.P.get("pads", false)))
	v.queue_free()
	await process_frame

	# asked
	v = await _view("city:GLACIER", true)
	var sim = v.sim
	var R = sim.roads[sim.pod.path]
	var w: float = R.w[sim.pod.hint]
	var right := _right(sim)
	var road_h: float = sim.net_height(sim.pod.path, float(sim.pod.hint))
	var speed: float = Vector2(sim.pod.vx, sim.pod.vy).length()
	_check("asked: %.1f m right of the centre of a %.0f m road (the pad's place %.1f), on the flat (the ramp there %.2f m), %.2f m over the road, at rest (%.2f m/s); the menu's word used up (%s)" % [
			right, w, Sim.net_pad_right(w), sim.net_edge(w, right).x, sim.pod.z - road_h, speed, not View.pad_start],
		absf(right - Sim.net_pad_right(w)) < 0.5 and sim.net_edge(w, right).x == 0.0 and absf(sim.pod.z - road_h - float(sim.P.rideH)) < 0.01 and speed < 0.01 and not View.pad_start)
	var pad = v.pad
	v._sync_world()
	var sound = pad.audio
	var with_audio := "--mute" not in OS.get_cmdline_user_args()
	_check("the pad respects the flight audio setting", (sound != null) == with_audio)
	if sound:
		_check("hot entry is quiet; all four emitters are on their physical fittings",
			not sound.cart.playing and not sound.lead.playing and not sound.gate.playing and not sound.clearance.playing
			and sound.cart.global_position.is_equal_approx(pad.to_global(pad._cart() + Vector3.UP * 0.62))
			and sound.lead.global_position.is_equal_approx(pad.to_global(pad.PLUG))
			and sound.gate.global_position.is_equal_approx(pad.gate.global_position)
			and sound.clearance.global_position.is_equal_approx(pad.station_sign.global_position))
	var under: Vector3 = v.wz(sim.pod.x, sim.pod.y, road_h)
	var ahead_of: Vector3 = v.wz(sim.eL.x, sim.eL.y, road_h)
	var to_engines: Vector3 = pad.global_transform.affine_inverse() * ahead_of if pad else Vector3.ZERO
	_check("the pad is built round it: under the pod (%.2f m off), its front toward the engines (they stand %.1f m ahead and %.1f m to the left in its own frame), home %s" % [
			pad.global_position.distance_to(under) if pad else -1.0, -to_engines.z, -to_engines.x, pad.home if pad else []],
		pad != null and pad.global_position.distance_to(under) < 0.05 and absf(-to_engines.z - pad.ahead) < 0.3 and absf(absf(to_engines.x) - float(sim.P.engineGap) / 2.0) < 0.2 and pad.home == sim.net_home())
	var meshes: int = pad.find_children("*", "MeshInstance3D", true, false).size() if pad else 0
	var words: int = pad.find_children("*", "Label3D", true, false).size() if pad else 0
	_check("it is %d meshes and %d lines of lettering; its board reads %s" % [meshes, words, [pad.lines[0].text, pad.lines[1].text, pad.lines[2].text] if pad else []],
		meshes <= 16 and words == 8 and pad.lines[0].text == "GLACIER" and pad.lines[1].text.begins_with("PAD") and pad.lines[2].text.contains(String(pad.PilotCraft.NAMES[sim.P.vehicle]).to_upper()))      # (run with --vehicle=shrike it is the Shrike's own board)

	# back
	sim.pod.x += 400.0
	v._respawn()
	_check("a crash puts it back on the pad (%.1f m right, %.2f m/s)" % [_right(sim), Vector2(sim.pod.vx, sim.pod.vy).length()], absf(_right(sim) - Sim.net_pad_right(w)) < 0.5)
	var other: int = (int(sim.net.from) + 1) % int(sim.cities.size())
	sim.net.from = other
	sim.net["arrived"] = true
	pad.sync(0.016)
	var there: Dictionary = sim.cities[other]
	_check("reach another city and the pad stands at its terminal: %s (home %s)" % [pad.lines[0].text, pad.home],
		pad.station_id == String(there.name).to_lower() and pad.lines[0].text == String(there.name) and int(pad.home[0]) == int(there.road) and int(pad.home[1]) == int(there.i))

	# follows
	sim.respawn()      # (the craft on the pad where it now stands: far from it the pad is not drawn, nor its lamps worked)
	pad.sync(0.016)
	var seq = Startup.new()
	seq.cold()
	pad.show_startup(seq)
	pad.sync(0.016)
	_check("the first cold frame has the gate down", pad.gate_open == 0.0 and is_zero_approx(pad.gate.rotation.z))
	if sound:
		_check("cold entry starts only the cart, with a looping stream",
			sound.cart.playing and sound.cart.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD
			and not sound.lead.playing and not sound.gate.playing and not sound.clearance.playing)
	pad.sync(3.0)
	var held_red: bool = (pad.big_lamp.material_override as StandardMaterial3D).albedo_color.r > 2.0 and pad.gate_open == 0.0 and pad.lead.visible and absf(pad.gate.rotation.z) < 0.01
	var cold_steps: Array = pad.lit.duplicate()
	var first: int = pad.flashing
	seq.batt = true
	pad.show_startup(seq)
	var after_batt: Array = [pad.lit.duplicate(), pad.flashing]
	seq.stage[0] = "run"
	seq.stage[1] = "run"
	pad.show_startup(seq)
	pad.sync(.016)
	if sound:
		_check("both engines running drops the lead once and silences the cart while the gate holds",
			sound.lead.playing and not sound.cart.playing and not sound.gate.playing and not sound.clearance.playing)
		sound.lead.stop()
		pad.sync(.016)
		_check("running another frame leaves the plug on the ground", not sound.lead.playing)
	seq.hot()
	pad.show_startup(seq)
	pad.sync(.016)
	if sound:
		_check("release starts the lift; the crew waits until the boom is up", sound.gate.playing and not sound.clearance.playing)
	pad.sync(3.0)
	if sound:
		_check("the raised boom triggers the station call", sound.clearance.playing)
		sound.clearance.stop()
		pad.sync(.016)
		_check("a raised boom does not repeat the call", not sound.clearance.playing)
		seq.cold()
		pad.show_startup(seq)
		pad.sync(.016)
		var saved_x: float = sim.pod.x
		sim.pod.x += 220.0
		pad.sync(.016)
		var silent: bool = not sound.cart.playing and not sound.nearby
		seq.hot()
		pad.show_startup(seq)
		pad.sync(3.0)
		sim.pod.x = saved_x
		pad.sync(.016)
		_check("leaving earshot silences the cart; returning hot does not replay a departure",
			silent and not sound.lead.playing and not sound.gate.playing and not sound.clearance.playing)
	var free_green: bool = (pad.big_lamp.material_override as StandardMaterial3D).albedo_color.g > 2.0 and pad.gate_open == 1.0 and not pad.lead.visible and absf(pad.gate.rotation.z) > 1.3
	_check("from cold it is held: the big lamp red, the gate down, ground power on (%s), no step lit %s and the first flashing (%d); the battery on lights its lamp and the next flashes %s; running and released: green, the gate up, the lead away (%s), every step lit %s" % [
			held_red, cold_steps, first, after_batt, free_green, pad.lit],
		held_red and cold_steps == [false, false, false, false] and first == 0 and after_batt == [[true, false, false, false], 1] and free_green and pad.lit == [true, true, true, true])

	# traffic
	var T = v.traffic_net
	sim.respawn()
	T.update(0.016)
	var as_car = T._pod_as_car()
	_check("parked on the pad the craft's way is the way it faces (%d), and its road is cleared of what comes the other way (road %d, way %d)" % [as_car.dir, T.proad, T.pdir],
		as_car.dir == int(sim.net_home()[2]) and T.proad == sim.pod.path and T.pdir == as_car.dir)

	# Reuse the same live pad through all sixteen addresses. Compare the vertex positions (paint
	# alone cannot pass), the legends at each end of the preflight and the draw-surface budget.
	var station_node: MeshInstance3D = pad.station
	var shapes := {}
	var call_takes := {}
	var station_errors := []
	var max_triangles := 0
	var bays := 0   # the named start points (sixteen, and Mount Hyperion's two)
	for entry in UI.INSERTIONS:
		var spot: Array = View.start_spot(entry[2])
		if spot.is_empty():
			continue
		bays += 1
		var rd: int = sim.cities[spot[0]].road if spot.size() == 1 else int(spot[0])
		var index: int = sim.cities[spot[0]].i if spot.size() == 1 else int(spot[1])
		pad._move([rd, index, 1, Sim.net_pad_right(sim.roads[rd].w[index])])
		if sound and sound.clearance.stream:
			var take: AudioStreamWAV = sound.clearance.stream
			call_takes[hash(take.data)] = true
		var mesh := station_node.mesh as ArrayMesh
		if mesh == null or mesh.get_surface_count() != 2:
			station_errors.append(entry[0])
			continue
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		shapes[hash(vertices.to_byte_array())] = true
		max_triangles = maxi(max_triangles, (vertices.size() + mesh.surface_get_array_len(1)) / 3)
		seq.cold()
		pad.show_startup(seq)
		var shop: String = pad.station_sign.text
		seq.hot()
		pad.show_startup(seq)
		if pad.station != station_node or pad.station_id != entry[0] or pad.lines[0].text != String(entry[1]).to_upper() or shop == pad.station_sign.text:
			station_errors.append(entry[0])
	_check("one station node, %d distinct silhouettes at the %d named menu bays, two static draw surfaces, up to %d triangles, local shops acknowledge release (wrong: %s)" % [shapes.size(), bays, max_triangles, station_errors],
		shapes.size() == bays and bays >= 18 and station_errors.is_empty() and max_triangles < 8000)
	if sound:
		# (Codex's check, for sixteen; Mount Hyperion's two bays were given calls when her branch was merged)
		_check("every one of the %d addresses selects its own recorded local call (%d heard)" % [bays, call_takes.size()], call_takes.size() == bays)
	pad._move([int(there.road), int(there.i)+7, 1, 0.0])
	_check("a debug roadside bay outside the named insertions clears the old station", not station_node.visible and station_node.mesh == null)
	if sound:
		_check("moving to an unnamed bay cancels the previous horn and clears its call sign",
			not sound.clearance.playing and sound.clearance.stream == null)
	v.queue_free()
	await process_frame

	# everywhere
	var s = Sim.new({"track": "network", "handling": "speed", "pads": true})
	var bad := []
	var places := 0
	for entry in UI.INSERTIONS:
		var spot: Array = View.start_spot(entry[2])
		if spot.is_empty():
			continue
		var road: int = s.cities[spot[0]].road if spot.size() == 1 else int(spot[0])
		var at: int = s.cities[spot[0]].i if spot.size() == 1 else int(spot[1])
		var Rd = s.roads[road]
		var wide: float = Rd.w[mini(at, Rd.N - 1)]
		var off := Sim.net_pad_right(wide)
		var lanes: Array = [157.5, 112.5] if wide >= 300.0 else [75.0, 25.0]
		places += 1
		if s.net_edge(wide, off).x != 0.0 or off + 13.0 > wide / 2.0 - 8.0 or absf(lanes[0] - off) >= 22.0 or absf(lanes[1] - off) <= 22.0:
			bad.append("%s: %.0f m road, pad %.1f m right, ramp %.2f m, lanes %.1f and %.1f m off" % [entry[1], wide, off, s.net_edge(wide, off).x, absf(lanes[0] - off), absf(lanes[1] - off)])
	_check("at all %d start points the bay is on the flat, clear of the wall, within the outermost lane's reach and outside the next one's (wrong: %s)" % [places, bad], bad.is_empty() and places == UI.INSERTIONS.size() - 1)
	print("START PAD %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
