## An exit's lane (Luke, after the eleventh flight: "each onramp/offramp should have some sort of
## accel/decel lane, so that exits are even harder to miss"; view/network_world.gd exit_lanes):
##   every     each ordinary exit has a lane on its parent road, ending at the ramp's mouth
##   long      it runs 8 km back the way an exiting craft comes (less only where the road itself ends)
##   placed    on the exit's own side, on the flat inside the edge ramp, clear of the centre line
##   painted   a chunk of road with a lane in it carries the lane's green rails and arrows
## Prints EXIT LANES PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Sim := preload("res://sim/craft_sim.gd")
const Outlook := preload("res://view/outlook.gd")
var failures := 0


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.spot_override = "E3@9000"
	View.best_dir = OS.get_user_data_dir().path_join("test_exit_lanes_")
	Outlook.pinned = true
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _run() -> void:
	var v = View.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	var sim = v.sim
	var W = v.network_world
	var lanes := 0
	var missing := []
	var short := []
	var misplaced := []
	var longest := 0.0
	var by_side := {-1: 0, 1: 0}
	for key in W._exits:
		var info: Dictionary = W._exits[key]
		var p: int = key.x
		var P = sim.roads[p]
		var mine := []
		for lane in W.exit_lanes.get(p, []):
			if int(lane[4]) == int(info.mouth) and int(lane[5]) == int(key.y):
				mine = lane
		if mine.is_empty():
			missing.append("%s to %s at %d" % [P.name, sim.roads[key.y].name, int(info.mouth)])
			continue
		lanes += 1
		var km: float = float(int(mine[1]) - int(mine[0])) * float(Sim.NET_STEP) / 1000.0
		longest = maxf(longest, km)
		var way := int(mine[2])
		var back: int = int(mine[0]) if way > 0 else int(mine[1])
		var at_road_end: bool = back == 0 or back == P.N - 1
		if km < 7.9 and not at_road_end:
			short.append("%s at %d: %.1f km" % [P.name, int(info.mouth), km])
		var mid: float = mine[3]
		var wide: float = P.w[int(info.mouth)]
		var flat: float = wide / 2.0 - Sim.net_edge_span(wide)
		# (side: -1 an exit to the left of the way travelled, 1 to the right; mid is metres LEFT of the centre line)
		var on_side: bool = (mid * way > 0.0) == (int(info.side) < 0) or absf(mid) < 1.0
		by_side[int(info.side)] = int(by_side[int(info.side)]) + 1
		if absf(mid) + W.LANE_HALF > flat or not on_side:
			misplaced.append("%s at %d: middle %.0f m, flat to %.0f, side %d way %d" % [P.name, int(info.mouth), mid, flat, int(info.side), way])
	_check("every ordinary exit has its lane: %d exits, %d lanes (missing: %s)" % [W._exits.size(), lanes, missing.slice(0, 4)], missing.is_empty() and lanes > 100)
	_check("each runs 8 km back from its mouth, or to its road's end (short: %s; the longest %.1f km)" % [short.slice(0, 4), longest], short.is_empty() and longest > 7.9 and longest < 8.2)
	_check("each lies on its exit's own side, on the flat inside the edge ramp (%d to the left, %d to the right; wrong: %s)" % [by_side[-1], by_side[1], misplaced.slice(0, 4)], misplaced.is_empty())
	# painted: build the chunk of E3 that holds a lane's middle and look for the lane's green in its lit paint
	var road := -1
	var pick := []
	for r in W.exit_lanes:
		if String(sim.roads[r].name) == "E3":
			road = r
			pick = W.exit_lanes[r][0]
	var mid_sample: int = (int(pick[0]) + int(pick[1])) / 2 if not pick.is_empty() else 0
	sim.respawn_on(road, mid_sample, int(pick[2]) if not pick.is_empty() else 1)
	for k in 4000:
		W.sync(sim.pod.x, sim.pod.y)
		if k > 400 and W.wanted == 0 and W._job.is_empty():
			break
	var green := 0
	var meshes := 0
	for node in W.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_COLOR] == null:
				continue
			meshes += 1
			for c: Color in arrays[Mesh.ARRAY_COLOR]:
				if absf(c.r - W.EXIT_GREEN.r) < 0.02 and absf(c.g - W.EXIT_GREEN.g) < 0.02 and absf(c.b - W.EXIT_GREEN.b) < 0.02:
					green += 1
	_check("road built round the middle of E3's lane (sample %d) carries its green paint: %d vertices in %d surfaces" % [mid_sample, green, meshes], green > 200)
	v.queue_free()
	print("EXIT LANES %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
