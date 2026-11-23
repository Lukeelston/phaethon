## The Network's banked bends (Luke, 2026-11-22: "I think most roads would benefit from being at least
## slightly banked on curves, just so that the pilot can see what's coming"; tools/design_network.py
## bank_table, CraftSim.NET_BANKS, net_bank_lift):
##   flat      no bank on a shaft's road, a jump's or a leap's, an on-ramp, Mount Hyperion's, the Aurora
##             tube, a straight highway; through every junction zone and physical overlap and four samples
##             past it; in a city; round every starting pad; through a recovery roll
##   banked    most of the bends are: how many roads, how many km, what share. Each run's middle, where it
##             is long enough to have all of it, leans the way its bend turns by 2 degrees times the root
##             of 45 km over its radius, 6 at most: the highways' sweepers 2.00, a ring 3.87, a 6 km bend 5.48
##   eased     no sample's bank differs from the next's by more than a reversal's eased step, nor its
##             change from the next change by more than that step's own: the horizon never snaps
##   both sims the bank at every recorded sample is the JavaScript sim's (replay/network_expected.json)
##   the deck  a bend pivots on its inside edge: that edge where it was, the outside one 2 x half-width x
##             tan(bank) up. A craft set down across it, and flown round it hands off at 3,000 mph, rides
##             that deck: never over it, never in it; the views' surface is the same deck and its lean
##   the road  the chunk's own mesh there is that deck (every vertex), its walls stand on the deck's edges,
##             a banked flyover's pillars reach its underside, the far ribbon lies under it as it does
##             under a flat road; a chunk with a bank in it reuses no flat furniture
##   traffic   what the sim is given of a vehicle on a banked bend stands on the deck where the vehicle is
##   the switch CraftSim.net_banks off: a Network with no bank at all (the pictures' "before")
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_network_banks.gd -- --mute
## Prints NETWORK BANKS PASS.
extends SceneTree

const Sim := preload("res://sim/craft_sim.gd")
const World := preload("res://view/network_world.gd")
const View := preload("res://view/craft_view.gd")
const Traffic := preload("res://view/network_traffic.gd")
const Release := preload("res://release/release_config.gd")
const DT := 1.0 / 480.0
const MPH := 2.236936
var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	checks += 1
	print(("  ok   " if passed else "  FAIL ") + label)
	failures += int(not passed)


static func _target(kap: float) -> float:
	return minf(6.0, 2.0 * sqrt(45000.0 * absf(kap)))


func _road(sim, road_name: String) -> int:
	for r in sim.roads.size():
		if String(sim.roads[r].name) == road_name:
			return r
	return -1


## The first run of road r that is long enough to hold all of its bank: [first, last, degrees] ([] for none).
func _full_run(r: int) -> Array:
	for row in Sim.NET_BANKS:
		if int(row[0]) == r:
			for run in row[2]:
				if int(run[1]) - int(run[0]) > 4 * int(row[1]) + 8:
					return run
	return []


func _run() -> void:
	var sim = Sim.new({"track": "network", "handling": "speed"})
	var banked := {}
	var box := {}
	for row in Sim.NET_BANKS:
		banked[int(row[0])] = row[2]
		box[int(row[0])] = int(row[1])

	# ---- flat
	var wrong: Array[String] = []
	var kinds := 0
	for r in sim.roads.size():
		var R = sim.roads[r]
		var must_be_flat: bool = R.shaft or R.role != "" or R.deck or r == int(Sim.NET_PRESSURE[0]) or String(R.name) in ["E2", "N2", "E3"]
		if must_be_flat:
			kinds += 1
			if R.banked or banked.has(r):
				wrong.append("%s is banked" % R.name)
		if not R.banked:
			for i in R.N:
				if R.bank[i] != 0.0:
					wrong.append("%s has a bank and is not marked" % R.name)
					break
			continue
		for i in R.N:
			if R.mode[i] == 0 and R.bank[i] != 0.0:
				wrong.append("%s banked in its city at %d" % [R.name, i])
				break
		if R.bank[0] != 0.0 or R.bank[R.N - 1] != 0.0:
			wrong.append("%s banked at an end" % R.name)
	var zones := 0
	for J in sim.surface_junctions:
		for e in [[int(J[0]), int(J[1]), int(J[2])], [int(J[3]), int(J[4]), int(J[5])]]:
			var R = sim.roads[e[0]]
			zones += 1
			for i in range(maxi(0, e[1] - 4), mini(R.N - 1, e[2] + 4) + 1):
				if R.bank[i] != 0.0:
					wrong.append("%s banked in a junction zone at %d" % [R.name, i])
					break
	for roll in sim.twists:
		var R = sim.roads[int(roll[0])]
		for i in range(int(roll[1]), int(roll[2]) + 1):
			if R.bank[i] != 0.0:
				wrong.append("%s banked in its roll at %d" % [R.name, i])
				break
	var pads := 0
	for entry in Release.INSERTIONS:
		var spot: Array = View.start_spot(String(entry[2]))
		var at := []
		if spot.size() == 1:
			at = [int(sim.cities[int(spot[0])].road), int(sim.cities[int(spot[0])].i)]
		elif spot.size() == 3:
			at = [int(spot[0]), int(spot[1])]
		if at.is_empty():
			continue
		pads += 1
		var R = sim.roads[at[0]]
		for i in range(maxi(0, at[1] - 20), mini(R.N - 1, at[1] + 20) + 1):
			if R.bank[i] != 0.0:
				wrong.append("%s banked at the %s pad (%d)" % [R.name, entry[0], i])
				break
	_check("flat where it must be: %d roads that may not bank (the shafts', the jumps' and leaps', the on-ramps, Hyperion's, the tube, the straight highways), %d junction zones and overlaps and 4 samples past each, the cities, %d rolls, %d starting pads and 20 samples either side: %d wrong %s" % [
		kinds, zones, sim.twists.size(), pads, wrong.size(), str(wrong.slice(0, 4))], wrong.is_empty() and kinds > 60 and pads >= 15)

	# ---- banked: how much, and each run's size
	var bends := 0.0
	var leaning := 0.0
	var road_km := 0.0
	var most := 0.0
	for r in sim.roads.size():
		var R = sim.roads[r]
		for i in R.N - 1:
			var lean := absf(rad_to_deg(R.bank[i]))
			most = maxf(most, lean)
			if lean >= 0.25:
				road_km += R.len[i] / 1000.0
			if R.kap[i] != 0.0 and not R.shaft:
				bends += R.len[i] / 1000.0
				if lean >= 0.25:
					leaning += R.len[i] / 1000.0
	var runs := 0
	var full := 0
	var off := 0
	for r in banked:
		var R = sim.roads[r]
		for run in banked[r]:
			runs += 1
			var first := int(run[0])
			var last := int(run[1])
			if last - first <= 4 * int(box[r]) + 2:
				continue
			full += 1
			var mid := (first + last) / 2
			var deg := rad_to_deg(R.bank[mid])
			if absf(deg - float(run[2])) > 1e-9 or signf(deg) != signf(R.kap[mid]) or absf(absf(deg) - _target(R.kap[mid])) > 1e-9:
				off += 1
	var e1 := _road(sim, "E1")
	var ring := _road(sim, "R00WN")
	var s2 := _road(sim, "S2")
	var run_e1 := _full_run(e1)
	var run_ring := _full_run(ring)
	var run_s2: Array = []
	for run in banked.get(s2, []):      # (S2's 6 km bends: the first that has all of its bank)
		if absf(float(run[2])) > 5.4 and int(run[1]) - int(run[0]) > 4 * int(box[s2]) + 8:
			run_s2 = run
			break
	var mid_e1: int = (int(run_e1[0]) + int(run_e1[1])) / 2 if not run_e1.is_empty() else 0
	var mid_ring: int = (int(run_ring[0]) + int(run_ring[1])) / 2 if not run_ring.is_empty() else 0
	var mid_s2: int = (int(run_s2[0]) + int(run_s2[1])) / 2 if not run_s2.is_empty() else 0
	var lean_e1 := rad_to_deg(sim.roads[e1].bank[mid_e1])
	var lean_ring := rad_to_deg(sim.roads[ring].bank[mid_ring])
	var lean_s2 := rad_to_deg(sim.roads[s2].bank[mid_s2])
	_check("banked: %d roads, %d runs; %.0f km of the %.0f km of bends lean 0.25 degrees or more (%.0f%%; the shafts' loops not counted), %.0f km of road in all; never more than %.2f degrees" % [
		banked.size(), runs, leaning, bends, 100.0 * leaning / bends, road_km, most],
		banked.size() >= 60 and leaning / bends > 0.5 and most <= 6.0 + 1e-9)
	_check("its size: each of the %d runs long enough to hold all of its bank leans the way its bend turns by 2 degrees x the root of 45 km over its radius, 6 at most (%d do not); E1's first sweeper (45 km) %+.3f at sample %d, the ring R00WN (12 km) %+.3f at %d, S2's 6 km bend %+.3f at %d" % [
		full, off, lean_e1, mid_e1, lean_ring, mid_ring, lean_s2, mid_s2],
		full > 100 and off == 0 and absf(lean_e1 - 2.0) < 1e-6 and absf(lean_ring - 3.8730) < 1e-3 and absf(absf(lean_s2) - 5.4772) < 1e-3)

	# ---- eased
	var steep := 0
	var worst_hwy := 0.0
	var worst_other := 0.0
	for r in banked:
		var R = sim.roads[r]
		var b: int = box[r]
		var step := deg_to_rad(12.0) / float(2 * b + 1)      # a reversal between two 6 degree bends, eased
		var worst := 0.0
		for i in range(1, R.N - 1):
			var d: float = R.bank[i + 1] - R.bank[i]
			worst = maxf(worst, absf(d))
			if absf(d) > step * 1.000001 or absf(d - (R.bank[i] - R.bank[i - 1])) > 2.0 * step / float(2 * b + 1) * 1.000001 + 1e-15:
				steep += 1
		if b > 40:
			worst_hwy = maxf(worst_hwy, worst)
		else:
			worst_other = maxf(worst_other, worst)
	var per_s := 3000.0 / MPH / 24.0      # samples a second at 3,000 mph
	_check("eased: no bank changes faster along its road than a reversal's eased step, nor in a jerk (%d samples that do); the fastest any highway's rolls is %.4f degrees a sample (%.1f degrees a second at 3,000 mph, %.1f at 5,000), any other road's %.3f (%.1f a second at 3,000 mph)" % [
		steep, rad_to_deg(worst_hwy), rad_to_deg(worst_hwy) * per_s, rad_to_deg(worst_hwy) * per_s * 5.0 / 3.0, rad_to_deg(worst_other), rad_to_deg(worst_other) * per_s],
		steep == 0 and rad_to_deg(worst_hwy) * per_s * 5.0 / 3.0 < 3.0 and rad_to_deg(worst_other) * per_s < 12.0)

	# ---- both sims
	var X: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/network_expected.json"))
	var compared := 0
	var leaned := 0
	var apart := 0.0
	for r in mini(sim.roads.size(), X.roads.size()):
		for smp in X.roads[r].samples:
			if smp.size() < 10:
				continue
			compared += 1
			leaned += int(float(smp[9]) != 0.0)
			apart = maxf(apart, absf(float(smp[9]) - float(sim.roads[r].bank[int(smp[0])])))
	_check("both sims: the bank at %d recorded samples (%d of them banked) is the JavaScript sim's to %.9f radians" % [compared, leaned, apart], compared > 4000 and leaned > 800 and apart < 1e-12)

	# ---- the deck
	var R1 = sim.roads[e1]
	var hw1: float = R1.w[mid_e1] / 2.0
	var inside := Sim.net_bank_lift(R1, mid_e1, 0.0, hw1 * signf(lean_e1))
	var outside := Sim.net_bank_lift(R1, mid_e1, 0.0, -hw1 * signf(lean_e1))
	var past := Sim.net_bank_lift(R1, mid_e1, 0.0, -(hw1 + 300.0) * signf(lean_e1))
	var gap := 0.0
	var lean_off := 0.0
	var place_off := 0.0
	var slack := 0.0
	var rode := 0
	var view_off := 0.0
	for lat: float in [-150.0, -60.0, 0.0, 60.0, 150.0]:
		for at: int in [mid_e1, int(run_e1[0]) - 40]:      # (all of the bank, and half way up its easing)
			var s = Sim.new({"track": "network", "handling": "speed"})
			var R = s.roads[e1]
			s.respawn_on(e1, at, 1, -lat)
			var stood: float = s.pod.z - s.P.rideH - s.net_height(e1, float(at)) - Sim.net_bank_lift(R, at, 0.0, lat)
			place_off = maxf(place_off, absf(stood))
			for b in s.bodies:
				b.vx = 3000.0 / MPH * R.tx[at]
				b.vy = 3000.0 / MPH * R.ty[at]
			for k in 480:
				s.step({"thrL": 0.6, "thrR": 0.6, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}, DT)
				s.events.clear()
				for b in s.bodies:
					s._nearest_on(e1, b.x, b.y, b.hint, 2)      # (the sample it is over now, as its hover finds it once it has moved)
					var i: int = s._n_i
					var f: float = float(i) + float(s._n_t)
					var across: float = (b.x - R.px[i]) * R.nx[i] + (b.y - R.py[i]) * R.ny[i]
					var deck: float = s.road_h(e1, f) + Sim.net_edge(R.w[i], across).x + Sim.net_bank_lift(R, i, f - float(i), across)
					gap = maxf(gap, absf(b.z - s.P.rideH - deck))
					slack = maxf(slack, 1.0 - b.grip)
					rode += int(b.off_road or b.lock)
			var p = s.pod
			var surface: Vector2 = s.surface_at(p.x, p.y, p.hint, p.path)
			var pi: int = p.hint
			var pf: float = s._road_f(p)
			var plat: float = (p.x - R.px[pi]) * R.nx[pi] + (p.y - R.py[pi]) * R.ny[pi]
			view_off = maxf(view_off, absf(surface.x + s.net_height(e1, pf) - (p.z - s.P.rideH)))
			lean_off = maxf(lean_off, absf(surface.y - (Sim.net_bank(R, pi, clampf(pf - float(pi), 0.0, 1.0)) - signf(plat) * Sim.net_edge(R.w[pi], plat).y)))
	_check("the deck: E1's sweeper pivots on its inside edge (%.3f m there), the outside edge %.3f m up (2 x %.0f m x tan %.2f deg = %.3f), the same %.3f m beyond it; set down across it a craft stands on it (%.9f m off), and flown along it hands off at 3,000 mph every body rides it for a second (%.9f m off at most, %d steps off the road or easing on, grip never under %.3f); the views' surface is that deck (%.3f m off) and its lean (%.9f rad off)" % [
		inside, outside, hw1, absf(lean_e1), 2.0 * hw1 * tan(deg_to_rad(absf(lean_e1))), past, place_off, gap, rode, 1.0 - slack, view_off, lean_off],
		absf(inside) < 1e-9 and absf(outside - 2.0 * hw1 * tan(deg_to_rad(absf(lean_e1)))) < 1e-9 and past == outside
		and place_off < 1e-9 and gap < 5e-3 and rode == 0 and slack == 0.0 and view_off < 0.05 and lean_off < 1e-6)      # (the views' surface is a Vector2: 32-bit)

	# ---- the road's own mesh
	var world = World.new()
	root.add_child(world)
	world.build(sim, null)
	var k: int = mid_e1 / World.CH
	world._build_chunk(e1, k)
	var entry: Array = world.chunks[Vector2i(e1, k)]
	var mesh: Mesh = entry[0].get_node("road").mesh
	var grid: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var cols := grid.size() / (World.CH + 1)
	var sec: Dictionary = world._section(R1.w[mid_e1])
	var mesh_off := 0.0
	for a in World.CH + 1:
		var i: int = k * World.CH + a
		for c in cols:
			var o: float = sec.o[c]
			mesh_off = maxf(mesh_off, absf(grid[a * cols + c].y - 0.02 - (sim.net_height(e1, float(i)) + Sim.net_edge(R1.w[i], o).x + Sim.net_bank_lift(R1, i, 0.0, o))))
	# its walls: the lowest thing along each edge is at the deck's edge there, on the ramp's top
	var foot := [INF, INF]
	var te: float = Sim.net_edge(R1.w[mid_e1], hw1).x
	for surface in range(1, mesh.get_surface_count()):
		var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for q in verts:
			sim._nearest_on(e1, q.x + float(entry[1]), float(entry[2]) - q.z, mid_e1, 44)
			var across: float = sim._n_lat
			if absf(across) < hw1 - 0.05 or absf(across) > hw1 + 1.2:
				continue
			var over: float = q.y - (sim.net_height(e1, float(sim._n_i) + float(sim._n_t)) + te + Sim.net_bank_lift(R1, int(sim._n_i), float(sim._n_t), across))
			if over > -0.5:      # (not the face under the raised edge, which goes down to the land)
				var side := 0 if across < 0.0 else 1
				foot[side] = minf(foot[side], over)
	# a banked flyover's pillars, the far ribbon
	var n1 := _road(sim, "N1")
	var run_n1 := _full_run(n1)
	var pillars := 0
	var pillar_off := 0.0
	var pillar_lift := 0.0
	if not run_n1.is_empty():
		var Rn = sim.roads[n1]
		for i in range(int(run_n1[0]), int(run_n1[1])):
			for pillar in world.pillar_specs(n1, i):
				var across: float = (float(pillar.x) - Rn.px[i]) * Rn.nx[i] + (float(pillar.y) - Rn.py[i]) * Rn.ny[i]
				var lift := Sim.net_bank_lift(Rn, i, 0.0, across)
				pillars += 1
				pillar_lift = maxf(pillar_lift, lift)
				pillar_off = maxf(pillar_off, absf(float(pillar.zMax) - (sim.net_height(n1, float(i)) - World.DECK + lift)))
	var ribbon_off := INF
	for piece in world.far_roads.pieces:
		if int(piece[2]) != e1 or mid_e1 < int(piece[3]) or mid_e1 >= int(piece[4]):
			continue
		var row: int = (mid_e1 - int(piece[3])) / int(piece[5])
		var i: int = int(piece[3]) + row * int(piece[5])
		var verts: PackedVector3Array = (piece[0] as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		ribbon_off = 0.0
		for side in 2:
			var o: float = (-1.0 if side == 0 else 1.0) * R1.w[i] / 2.0
			ribbon_off = maxf(ribbon_off, absf(verts[row * 2 + side].y - (sim.net_height(e1, float(i)) - 8.0 + Sim.net_bank_lift(R1, i, 0.0, o))))
	var eased_k: int = int(run_e1[1]) / World.CH + 1      # (the first whole chunk of straight after the bend: the bank still easing out along it)
	world._start_chunk(e1, eased_k)
	var reused: bool = String(world._job.template_key) != ""
	var eased_lean: float = rad_to_deg(R1.bank[eased_k * World.CH + World.CH / 2])
	var flat_k: int = 2000 / World.CH
	world._job = {}
	world._start_chunk(e1, flat_k)
	var flat_reused: bool = String(world._job.template_key) != ""
	world._job = {}
	_check("the road: chunk %d of E1 (samples %d to %d, %.2f degrees) is the sims' deck at every one of its %d points (%.4f m off at most); its walls' feet stand on the deck's edges (%.3f m over the right one, %.3f over the left); N1's banked flyover: %d pillars reach its underside (%.4f m off, the bank lifting it up to %.1f m); the far ribbon lies 8 m under the deck's edges as it leans (%.4f m off); chunk %d, on the straight after the bend with the bank easing out (%.2f degrees), reuses no flat furniture (%s) where one out on the straight does (%s)" % [
		k, k * World.CH, (k + 1) * World.CH, lean_e1, grid.size(), mesh_off, foot[0], foot[1], pillars, pillar_off, pillar_lift, ribbon_off, eased_k, eased_lean, reused, flat_reused],
		eased_lean > 0.05 and mesh_off < 0.005 and absf(float(foot[0])) < 0.03 and absf(float(foot[1])) < 0.03 and pillars > 10 and pillar_off < 1e-6 and pillar_lift > 5.0 and ribbon_off < 0.005 and not reused and flat_reused)
	world.free()

	# ---- the switch
	Sim.net_banks = false
	var plain = Sim.new({"track": "network", "handling": "speed"})
	Sim.net_banks = true
	var still := 0
	for R in plain.roads:
		still += int(R.banked)
	_check("the switch: with CraftSim.net_banks off a Network has no banked road (%d), and E1's sweeper's outside edge is where it was (%.3f m up)" % [still, Sim.net_bank_lift(plain.roads[e1], mid_e1, 0.0, -hw1)],
		still == 0 and Sim.net_bank_lift(plain.roads[e1], mid_e1, 0.0, -hw1) == 0.0)

	# ---- traffic on a banked bend
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_network_banks_")
	var v = View.new()
	root.add_child(v)
	v.sim.respawn_on(e1, mid_e1, 1)
	var until := Time.get_ticks_msec() + 6000      # the traffic spawns round the craft
	while Time.get_ticks_msec() < until:
		await process_frame
	v.set_process(false)
	var T = v.traffic_net
	var vs = v.sim
	T.collide = true
	vs.P.obstacleCollisions = true
	vs.respawn_on(e1, mid_e1, 1)
	vs.pod.vx = 4000.0 * float(vs.roads[e1].tx[mid_e1])      # (fast: the feed reaches furthest)
	vs.pod.vy = 4000.0 * float(vs.roads[e1].ty[mid_e1])
	T._feed()
	var fed := {}
	for o in vs.obstacles:
		fed[int(o.get("id", -1))] = o
	var on_bank := 0
	var car_off := 0.0
	var car_lift := 0.0
	for c in T.cars:
		if not fed.has(c.id * 32) or not vs.roads[c.road].banked:
			continue
		var half: float = (4.5 if c.kind == Traffic.TRANSPORT else (4.0 if c.kind == Traffic.SLOW else 3.5)) * Traffic.SCALE
		var f: float = clampf(c.f - c.dir * half / 24.0, 0.0, vs.roads[c.road].N - 1.0)
		var lift: float = vs.net_deck(c.road, f, c.lat) - vs.net_height(c.road, f)
		if lift <= 0.0:
			continue
		on_bank += 1
		car_lift = maxf(car_lift, lift)
		car_off = maxf(car_off, absf(float(fed[c.id * 32].zMin) - vs.net_deck(c.road, f, c.lat)))
	_check("traffic: of %d vehicles, %d fed to the sim on the banked bend stand on its deck where they are (%.4f m off at most; the bank lifts them up to %.1f m)" % [T.cars.size(), on_bank, car_off, car_lift],
		on_bank >= 1 and car_off < 0.01 and car_lift > 0.5)
	v.queue_free()
	await process_frame
	print("NETWORK BANKS %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
