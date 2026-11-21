## Helios (Luke: "an area of the map that just climbs an unreasonably large mountain. Pilot should be
## able to see the surrounding world as they ascend or descend"; view/helios.gd, tools/design_network.py):
##   mirrored   the road SHelios lies on the mountain the views draw (the designer's helios_z), over its summit
##   lookup     the sim's height lookup, now a search, gives what walking the keys gave, on every road
##   bench      the terrain's grid lies under the road's deck and under the road's own land beside it
##   mountain   away from the road the terrain is the mountain: never under its surface, ridged a little over it
##   far        the whole mountain as one mesh for beyond the tiles; its colours: rock, then snow; nothing grows high up
##   view       the road's downhill edge is open (see-through) most of the way; the air thins with height
##   named      its signs and its two start points
## Prints HELIOS PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Helios := preload("res://view/helios.gd")
const Outlook := preload("res://view/outlook.gd")
const UI := preload("res://release/release_config.gd")
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


## The sim's lookup as it was: the keys walked from the start.
func _walked(sim, road: int, i: float) -> float:
	var keys: Array = sim._net_h.get(road, [])
	for k in range(0, keys.size() - 1):
		var a: Array = keys[k]
		var b: Array = keys[k + 1]
		if i >= float(a[0]) and i <= float(b[0]):
			var n := maxi(1, int(b[0]) - int(a[0]))
			var u := (i - float(a[0])) / float(n)
			var d: float = float(n) * float(sim.NET_STEP)
			var u2 := u * u
			var u3 := u2 * u
			return (2.0 * u3 - 3.0 * u2 + 1.0) * float(a[1]) + (u3 - 2.0 * u2 + u) * d * float(a[2]) + (-2.0 * u3 + 3.0 * u2) * float(b[1]) + (u3 - u2) * d * float(b[2])
	return 0.0


func _run() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("helios_test_")
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	var v = View.new()
	root.add_child(v)
	v.set_process(false)
	var sim = v.sim
	var land = v.landscape
	var world = v.network_world
	var scenic = world.scenic
	var r := -1
	for k in sim.roads.size():
		if String(sim.roads[k].name) == "SHelios":
			r = k
	if r < 0 or land == null or scenic == null or not scenic.roads.has(r):
		_check("the road SHelios is on the Network, with its land", false)
		quit(1)
		return
	var R = sim.roads[r]
	var D: Dictionary = scenic.roads[r]

	# mirrored
	var off := 0.0
	var top := 0.0
	var top_at := -1
	var nearest_summit := INF
	for i in range(0, R.N, 5):
		var p := Vector2(R.px[i], R.py[i])
		var z: float = sim.net_height(r, float(i))
		off = maxf(off, absf(z - Helios.height(p)))
		if z > top:
			top = z
			top_at = i
		nearest_summit = minf(nearest_summit, p.distance_to(Helios.CENTRE))
	_check("the road lies on the mountain the views draw: at most %.2f m off it over %d samples; its top %.0f m at sample %d, %.0f m from the summit" % [off, R.N, top, top_at, nearest_summit],
		off < 0.5 and absf(top - Helios.HEIGHT) < 3.0 and nearest_summit < 60.0 and bool(D.get("mountain", false)))
	_check("its land starts and ends on level ground (%.1f m and %.1f m up at its first and last rows)" % [sim.net_height(r, float(D.first)), sim.net_height(r, float(D.last))],
		sim.net_height(r, float(D.first)) < 8.0 and sim.net_height(r, float(D.last)) < 8.0)

	# lookup
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261120
	var worst := 0.0
	var asked := 0
	for road in sim.roads.size():
		var N: int = sim.roads[road].N
		for k in 60:
			var i: float = rng.randf_range(-3.0, float(N) + 3.0) if k > 3 else float([0.0, float(N - 1), float(N / 2), -1.0][k])
			worst = maxf(worst, absf(sim.net_height(road, i) - _walked(sim, road, i)))
			asked += 1
		for key in sim._net_h.get(road, []):      # (and at every key itself, where two spans meet)
			worst = maxf(worst, absf(sim.net_height(road, float(key[0])) - _walked(sim, road, float(key[0]))))
			asked += 1
	var t0 := Time.get_ticks_usec()
	for k in 20000:
		sim.net_height(r, float(k % R.N) + 0.37)
	var each := float(Time.get_ticks_usec() - t0) / 20000.0
	_check("the height lookup's search gives what walking the keys gave: %d places on %d roads, %.9f m apart at most; %.2f us a lookup on this road's %d keys" % [
			asked, sim.roads.size(), worst, each, (sim._net_h[r] as Array).size()], worst == 0.0 and each < 25.0)

	# bench: the grid under the deck, and under the road's own land out to where the terrain takes over
	var over_deck := 0
	var over_land := 0
	var looked := 0
	var worst_land := -INF
	var worst_where := ""
	for i in range(int(D.first) + 3, int(D.last) - 2, 61):
		var h: float = sim.net_height(r, float(i))
		for lat in [-0.9, -0.45, 0.0, 0.45, 0.9]:
			var q := Vector2(R.px[i] + R.nx[i] * lat * float(D.hw), R.py[i] + R.ny[i] * lat * float(D.hw))
			looked += 1
			if land.surface_at(q) > h - 4.0:
				over_deck += 1
		for left in [true, false]:
			var pairs: PackedFloat32Array = scenic.row(r, i, left)
			var sgn := 1.0 if left else -1.0
			for m in range(0, pairs.size() / 2 - 2):
				for t in [0.0, 0.5]:
					var out: float = lerpf(pairs[m * 2], pairs[m * 2 + 2], t)
					var own: float = lerpf(pairs[m * 2 + 1], pairs[m * 2 + 3], t)
					var q := Vector2(R.px[i] + R.nx[i] * sgn * out, R.py[i] + R.ny[i] * sgn * out)
					# (inside a bend the rows fan in: a point may belong to another sample's row. Only where this sample is its nearest.)
					var mine: int = scenic._nearest_lap(r, q, Vector2i(int(floor(q.x / scenic.CELL)), int(floor(q.y / scenic.CELL))), scenic._nearest(R, D, q, i))
					if absi(mine - i) > 2:
						continue
					looked += 1
					var over: float = land.surface_at(q) - own
					if over > worst_land:
						worst_land = over
						worst_where = "sample %d %s, %.0f m out" % [i, "left" if left else "right", out]
					if over > -1.0:
						over_land += 1
	_check("the terrain's grid lies under the deck (%d over) and under the road's own land beside it (%d over; nearest %.1f m under, at %s): %d places" % [
			over_deck, over_land, -worst_land, worst_where, looked], over_deck == 0 and over_land == 0)

	# mountain: away from the road
	var under := 0
	var high := 0
	var away := 0
	var ridged := 0.0
	for k in 4000:
		var a := rng.randf() * TAU
		var p: Vector2 = Helios.CENTRE + Vector2(cos(a), sin(a)) * sqrt(rng.randf()) * Helios.FOOT * 0.98
		if scenic.land(Vector2i(roundi(p.x / 512.0), roundi(p.y / 512.0)), p).x >= 1.0:
			continue      # (the road's own land: the grid is sunk under it)
		var q := Vector2(Vector2i(roundi(p.x / 512.0), roundi(p.y / 512.0))) * 512.0      # at a vertex: between them the grid cuts corners
		away += 1
		var s: float = land.height_at(q)
		under += int(s < Helios.land(q) - 0.01)
		high += int(s > Helios.land(q) + Helios.RIDGE + 450.0)      # (a little of the snow country's own relief is left at its very foot)
		ridged = maxf(ridged, s - Helios.land(q))
	var summit: float = land.height_at(Helios.CENTRE + Vector2(3100.0, 2600.0))
	_check("away from the road the terrain is the mountain: %d vertices, %d under its surface, ridges up to %.0f m over it; %.0f m up 4 km from the summit" % [away, under, ridged, summit],
		away > 1500 and under == 0 and high == 0 and ridged > 100.0 and summit > 9000.0)

	# far: one mesh; colours; nothing grows high up
	var far: MeshInstance3D = land.far_helios
	var arrays: Array = far.mesh.surface_get_arrays(0) if far != null and far.mesh != null else []
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if not arrays.is_empty() else PackedVector3Array()
	var peak := -INF
	var low := INF
	for vert in verts:
		peak = maxf(peak, vert.y)
		low = minf(low, vert.y)
	land.sync(Helios.CENTRE.x - 90000.0, Helios.CENTRE.y - 60000.0)
	var placed: Vector3 = far.position if far != null else Vector3.ZERO
	_check("the mountain whole, for beyond the tiles: %d points, %.0f m at its top, %.1f m at its foot; from 108 km off it stands %.0f km east and %.0f km north of the craft" % [
			verts.size(), peak, low, placed.x / 1000.0, -placed.z / 1000.0],
		verts.size() == (Helios.RINGS + 1) * Helios.ROUND and absf(peak - Helios.HEIGHT) < 1.0 and absf(low + 4.0) < 0.5 and far.visible
			and absf(placed.x - 90000.0) < 1.0 and absf(placed.z + 60000.0) < 1.0)
	var at_top: Color = land.color_at(Helios.CENTRE + Vector2(900.0, 0.0), 10300.0)
	var at_mid: Color = land.color_at(Helios.CENTRE + Vector2(0.0, 23000.0), 3600.0)
	var at_foot: Color = land.color_at(Helios.CENTRE + Vector2(0.0, 35000.0), 20.0)
	var grows := {}
	var highest_tree := 0.0
	var highest := 0.0
	for key in [Vector2i(48, 67), Vector2i(46, 66), Vector2i(50, 69), Vector2i(48, 64), Vector2i(45, 67)]:      # tiles from the summit out to the foot
		for prop in land.prop_records(key):
			grows[prop.kind] = int(grows.get(prop.kind, 0)) + 1
			highest = maxf(highest, prop.height)
			if prop.kind != "rock":
				highest_tree = maxf(highest_tree, prop.height)
	_check("snow on its top (%.2f), bare rock half way (%.2f, %.2f, %.2f), the country's own colour at its foot (%.2f, %.2f, %.2f); what stands on it: %s, nothing but rock over %.0f m (highest other %.0f m), nothing over 5,200 (highest %.0f m)" % [
			minf(at_top.r, minf(at_top.g, at_top.b)), at_mid.r, at_mid.g, at_mid.b, at_foot.r, at_foot.g, at_foot.b, grows, Helios.TREE_LINE, highest_tree, highest],
		minf(at_top.r, minf(at_top.g, at_top.b)) > 0.75 and maxf(at_mid.r, maxf(at_mid.g, at_mid.b)) < 0.5 and absf(at_mid.r - at_mid.b) < 0.1
			and minf(at_foot.r, minf(at_foot.g, at_foot.b)) < 0.7 and highest_tree <= Helios.TREE_LINE and highest <= 5200.0)

	# view
	var open_one := 0
	var rows := 0
	for i in range(int(D.first), int(D.last) + 1, 20):
		rows += 1
		open_one += int(scenic.open(r, i, true) or scenic.open(r, i, false))
	var from_top := Outlook.air_between(Helios.HEIGHT, 0.0)
	var level_top := Outlook.air_between(Helios.HEIGHT, Helios.HEIGHT)
	Outlook.thin_air(1.0)
	Outlook.thin_air(from_top)
	_check("the road's downhill edge is open on %d of %d rows; the air between the summit and the plain is %.2f of the ground's, level at the summit %.2f, along the ground %.2f" % [
			open_one, rows, from_top, level_top, Outlook.air_between(0.0, 0.0)],
		float(open_one) / rows > 0.7 and from_top > 0.3 and from_top < 0.45 and level_top < 0.12 and Outlook.air_between(0.0, 0.0) == 1.0
			and Outlook.air_between(3000.0, 0.0) > from_top and is_equal_approx(Outlook._thin, from_top))
	Outlook.thin_air(1.0)

	# named
	var starts := []
	for entry in UI.INSERTIONS:
		if String(entry[2]).begins_with("SHelios"):
			var spot: Array = View.start_spot(entry[2])
			starts.append("%s: sample %d, %.0f m up" % [entry[1], int(spot[1]) if spot.size() == 3 else -1, sim.net_height(r, float(spot[1])) if spot.size() == 3 else -1.0])
	_check("its signs say %s, route %s; it has %d start points (%s)" % [world.SCENIC_NAMES.get("SHelios", "?"), world.SCENIC_ROUTES.get("SHelios", "?"), starts.size(), starts],
		world.SCENIC_NAMES.get("SHelios", "") == "MOUNT HELIOS" and world.SCENIC_ROUTES.get("SHelios", "") == "S21" and starts.size() == 2)
	v.free()
	print("HELIOS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
