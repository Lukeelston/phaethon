## The Network's world gate (view/network_world.gd, track "network"):
##   set up      the grid, the signs and five skylines in under 2 s (1,000+ towers), no chunk yet
##   streaming   round Eridanus' terminal every chunk within VIS built in a few frames, each in under
##               8 ms; 60 km away, none left past DROP (plus a chunk) and the new place built
##   halls       a hall over every city's terminal (the Network's tunnels), built round Eridanus' with its
##               roof clear of the terminal's gantry; in it the course audio hears the enclosure, 60 km
##               out on E2 it doesn't
##   flyovers    N2's deck 100+ m over the centre crossing, and on it the view rides the deck (the
##               pod's height in the view is the deck's)
##   junctions   walls open where a ramp joins (on its side, inside the zone), shut on the other side
##   boards      a board before every ramp's and bypass's mouth naming a city and its miles, END OF
##               THE ROAD before each turnaround, each terminal named both ways
##   landscapes  at Glacier the ground is 90%+ ice; halfway to Mesa it's ice and mesa together
##   minimap     the whole country: every road on the panel, the jumps, the four GPs, the cities and
##               their on-ramps marked, the craft where it is (the middle at the centre crossing), the target
## Prints NETWORK WORLD PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_network_world.gd -- --mute
extends SceneTree

const ViewScript := preload("res://view/craft_view.gd")
const MiniMap := preload("res://view/minimap.gd")
const CHECKS := 9
var fails := 0
var passed := 0
var v
var frames := 0
var stage := 0
var t_setup := 0
var mark := {}


func _initialize() -> void:
	ViewScript.track_override = "network"
	ViewScript.job_override = "none"
	ViewScript.best_dir = OS.get_user_data_dir().path_join("test_network_world_")
	DirAccess.remove_absolute(ViewScript.best_dir + "network.json")
	var t0 := Time.get_ticks_msec()
	v = ViewScript.new()
	root.add_child(v)
	t_setup = Time.get_ticks_msec() - t0


func _road(name: String) -> int:
	for r in v.sim.roads.size():
		if v.sim.roads[r].name == name:
			return r
	return -1


func _settle(n: int) -> void:
	for k in n:
		v.network_world.sync(v.org_x, v.org_y)


func _process(_d: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	var W = v.network_world
	var sim = v.sim
	if stage == 0:
		_check("set up: %d ms, %d skylines, %d towers, %d signs planned" % [W.setup_ms, W.skylines.size(), W.towers, _signs(W)],
			W.setup_ms < 2000 and W.skylines.size() == 5 and W.towers > 1000 and _signs(W) > 100)
		# streaming round Eridanus' terminal
		sim.respawn(0)
		v._follow_origin()
		_settle(80)
		var missing := _missing(W)
		var near_ms: float = W.build_ms_max
		# the halls
		var ca = load("res://audio/course_audio.gd").new()
		root.add_child(ca)
		ca.setup(sim)
		ca.net_halls = W.halls
		var in_hall: bool = ca.enclosed()
		var e2 := _road("E2")
		sim.respawn_on(e2, 2000, 1)   # ~60 km west
		v._follow_origin()
		_settle(60)
		var far := 0
		for key in W.chunks:
			var R = sim.roads[key.x]
			var c0: int = key.y * W.CH
			var c1: int = mini(c0 + W.CH, R.N - 1)
			var d := Vector2((R.px[c0] + R.px[c1]) / 2.0 - v.org_x, (R.py[c0] + R.py[c1]) / 2.0 - v.org_y).length()
			if d > W.DROP + W.CH * 24.0 + 1.0:
				far += 1
		var out_hall: bool = ca.enclosed()
		_check("halls: %d of %d cities' terminals under one, %d samples built round Eridanus' (the roof %.0f m, the gantry's top %.0f); enclosed in it %s, 60 km out %s" % [W.halls.size(), sim.cities.size(), W.hall_samples, W.HALL_H, W.BOARD_CLEAR + W.BOARD_H + 8.0, in_hall, out_hall],
			W.halls.size() == sim.cities.size() and W.hall_samples > 100 and W.HALL_H > W.BOARD_CLEAR + W.BOARD_H + 8.0 and in_hall and not out_hall)
		_check("streaming: at Eridanus %d chunks wanted but missing after 80 frames, the slowest chunk %.1f ms; 60 km on %d missing, %d past DROP, %d dropped, the slowest %.1f ms" % [missing, near_ms, _missing(W), far, W.dropped, W.build_ms_max],
			missing == 0 and _missing(W) == 0 and far == 0 and W.dropped > 0 and W.build_ms_max < 8.0)
		# flyovers: N2 over the centre crossing
		var n2 := _road("N2")
		var R2 = sim.roads[n2]
		var ic := 0
		var bd := INF
		for i in range(0, R2.N, 2):
			var d := absf(R2.py[i] - 300000.0)
			if d < bd:
				bd = d
				ic = i
		sim.respawn_on(n2, ic, 1)
		v._follow_origin()
		_settle(30)
		var deck: float = sim.net_height(n2, float(ic))
		var ride: float = v.surface(sim.pod.x, sim.pod.y).x
		_check("flyovers: N2's deck %.0f m over the centre crossing; the view rides it at %.1f m" % [deck, ride], deck >= 100.0 and absf(ride - deck) < 0.5)
		# the edges' ramps (Luke: "make the walls ramp up on the sides rather that a hard stop"): the view
		# rides up them, rolled toward the middle, and the road's grid carries them
		var Rn = sim.roads[n2]
		var wn: float = Rn.w[ic]
		var off := wn / 2.0 - 10.0
		var up_l: Vector2 = v.surface(sim.pod.x + Rn.nx[ic] * off, sim.pod.y + Rn.ny[ic] * off)
		var up_r: Vector2 = v.surface(sim.pod.x - Rn.nx[ic] * off, sim.pod.y - Rn.ny[ic] * off)
		var want: float = CraftSim.net_edge(wn, off).x
		var ckey := Vector2i(n2, ic / W.CH)
		var pts := 0
		if W.chunks.has(ckey):
			var rmi := (W.chunks[ckey][0] as Node3D).get_node_or_null("road") as MeshInstance3D
			if rmi:
				pts = (rmi.mesh as ArrayMesh).surface_get_array_len(0)
		var per_row: int = 2 * W.EDGE_SEGS + 2
		_check("edges: 10 m in from N2's left wall the view rides %.1f m up its ramp (want %.1f), rolled %.1f deg toward the middle (at the right %.1f); the chunk's road grid %d points (%d a row)" % [up_l.x - deck, want, rad_to_deg(up_l.y), rad_to_deg(up_r.y), pts, per_row],
			absf(up_l.x - deck - want) < 0.5 and want > 3.0 and up_l.y < -0.1 and up_r.y > 0.1 and pts > 0 and pts % per_row == 0)
		# junction walls: a ramp's mouth on E2 at the centre crossing
		var J: Array = []
		for j in sim.junctions:
			if int(j[0]) == _road("E2") and sim.roads[int(j[3])].name.begins_with("R11E"):
				J = j
				break
		var mid := (int(J[1]) + int(J[2])) / 2
		var C = sim.roads[int(J[3])]
		var Ep = sim.roads[int(J[0])]
		# the ramp's side: where its centreline lies off E2's
		var cb: int = 0 if int(J[4]) == 0 else C.N - 1
		var side := signf((C.px[cb] - Ep.px[mid]) * Ep.nx[mid] + (C.py[cb] - Ep.py[mid]) * Ep.ny[mid])
		var open_side: bool = W._open(int(J[0]), mid, side)
		var shut_side: bool = W._open(int(J[0]), mid, -side) and not _other_side_joined(sim, int(J[0]), mid, -side)
		_check("junctions: E2's wall at %s's mouth open on its side (%s), and on the other side only where another road joins (%s); %d wall runs left open so far" % [C.name, open_side, not shut_side, W.walls_open],
			open_side and not shut_side and W.walls_open > 0)
		# boards
		var kinds := {}
		var bad := []
		for key in W._signs:
			for spec in W._signs[key]:
				kinds[spec[2]] = kinds.get(spec[2], 0) + 1
				if spec[2] == "exit" and not (spec[3].size() >= 2 and String(spec[3][1]).ends_with(" MI")):
					bad.append(spec[3])
		_check("boards: %s; every exit names a city and its miles (%d don't)" % [kinds, bad.size()],
			kinds.get("exit", 0) >= 70 and kinds.get("city", 0) >= 9 and kinds.get("end", 0) == 12 and kinds.get("terminal", 0) == 10 and kinds.get("brake", 0) >= 20 and bad.is_empty())
		# landscapes
		var g: Dictionary = sim.cities[2]
		sim.respawn(2)
		v._follow_origin()
		v._net_biome()
		var at_g: Dictionary = v.biome.duplicate()
		var m: Dictionary = sim.cities[4]
		v.org_x = (g.cx + m.cx) / 2.0
		v.org_y = (g.cy + m.cy) / 2.0
		v._net_biome()
		var half: Dictionary = v.biome.duplicate()
		_check("landscapes: at %s the ground is %.0f%% ice; halfway to %s %.0f%% ice, %.0f%% mesa" % [g.name, at_g.ice * 100.0, m.name, half.ice * 100.0, half.mesa * 100.0],
			at_g.ice >= 0.9 and half.ice > 0.25 and half.mesa > 0.25)
		# the minimap: the whole country (Luke: "make the minimap the whole extents")
		sim.respawn_on(n2, ic - 300, 1)
		v._follow_origin()
		var mm = v.minimap
		var f: Dictionary = mm.update(PI / 2.0, 0.0)
		var l := MiniMap.layout(f, 300.0, 300.0, 10.0, 30.0)
		var mkinds := {}
		for mark in l.marks:
			mkinds[mark[1]] = int(mkinds.get(mark[1], 0)) + 1
		# the craft at the centre crossing: the middle of the map (the country's middle)
		var map_mid := Vector2(0.0, (-140.0 + 110.0) / 2.0)
		var map_in := true
		for seg in l.segs:
			for q in [seg[0], seg[1]]:
				map_in = map_in and absf(q.x) <= 140.0 + 0.01 and q.y >= -140.0 - 0.01 and q.y <= 110.0 + 0.01
		_check("minimap: the whole country, %d roads (%d segments, all on the panel %s); marks %s; the craft %.1f from the middle; the target %s" % [f.get("lines_w", []).size(), l.segs.size(), map_in, mkinds, (l.craft as Vector2).distance_to(map_mid), f.get("target", {}).get("name", "none")],
			f.has("whole") and f.lines_w.size() == sim.roads.size() and map_in and mkinds.get("jump", 0) == sim.jumps.size() and mkinds.get("gp", 0) == 4
			and mkinds.get("city", 0) == sim.cities.size() and mkinds.get("ramp", 0) == sim.onramps.size() and (l.craft as Vector2).distance_to(map_mid) < 8.0 and l.target != null)
		var good: bool = fails == 0 and passed == CHECKS
		print("NETWORK WORLD ", "PASS" if good else "FAIL (%d failed, %d of %d passed)" % [fails, passed, CHECKS])
		quit(0 if good else 1)
		stage = 1
	return false


func _signs(W) -> int:
	var n := 0
	for key in W._signs:
		n += W._signs[key].size()
	return n


## Chunks within VIS of the origin not built.
func _missing(W) -> int:
	var n := 0
	for cell in W.grid:
		for e in W.grid[cell]:
			var d: float = Vector2(e[2] - v.org_x, e[3] - v.org_y).length() - e[4]
			if d < W.VIS and not W.chunks.has(Vector2i(e[0], e[1])):
				n += 1
	return n / 1 if n == 0 else n


## Another junction on road r at sample i, on side sgn (a ramp across the road there too).
func _other_side_joined(sim, r: int, i: int, sgn: float) -> bool:
	var R = sim.roads[r]
	for k in R.jx:
		var J: Array = sim.junctions[k]
		if int(J[0]) != r or i < int(J[1]) or i > int(J[2]):
			continue
		var C = sim.roads[int(J[3])]
		var cb: int = 0 if int(J[4]) == 0 else C.N - 1
		if signf((C.px[cb] - R.px[i]) * R.nx[i] + (C.py[cb] - R.py[i]) * R.ny[i]) == sgn:
			return true
	return false


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
