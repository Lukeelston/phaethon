## The traffic's feed of obstacles to the sim (view/network_traffic.gd `_feed`, `feed_reach`): with
## OBSTACLE COLLISIONS on, the sim is given only what the craft can reach before the next feed, a
## frame from now, where it was given every vehicle within 2,500 m and every pillar within 1,000 m.
## (Luke's sixteenth and seventeenth flights ran 82 fps for 94: he had the setting on, and those
## 400 circles, tested against three bodies 480 times a second, doubled the sim's cost.)
##   reach     grows with the craft's speed, covers the 0.05 s of the longest frame twice over, and
##             never passes the old field
##   at rest   at the Eridanus pad: everything fed is within reach; nothing within reach is left
##             out (pillars, and every part of every vehicle); a fraction of what the old field held
##   at speed  the same at 4,000 mph, with more of the road ahead fed
##   cost      a sim step with the feed against one with no obstacles at all, at the pad
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_traffic_feed.gd -- --mute
## Prints TRAFFIC FEED PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Traffic := preload("res://view/network_traffic.gd")
const DT := 1.0 / 480.0
var v
var failures := 0
var checks := 0


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_traffic_feed_")
	v = View.new()
	root.add_child(v)
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	checks += 1
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


## What the old field held, counted the way the feed counts: pillars within 1,000 m, and two circles
## for every unit of every vehicle within R_FIELD.
func _old_count(T, px: float, py: float) -> int:
	var n: int = v.network_world.obstacles_near(px, py).size()
	for c in T.cars:
		if Vector2(c.x - px, c.y - py).length() <= Traffic.R_FIELD:
			n += 2 * (Traffic.TRAIN if c.kind == Traffic.TRANSPORT else 1)
	return n


## The feed as it stands, looked over: [count, the farthest fed (m), pillars within reach left out, vehicles'
## leads well within reach with no part fed].
func _survey(T, reach: float) -> Array:
	var sim = v.sim
	var px: float = sim.pod.x
	var py: float = sim.pod.y
	var far := 0.0
	var ids := {}
	for o in sim.obstacles:
		far = maxf(far, Vector2(o.x - px, o.y - py).length() - float(o.get("halfSize", 0.0)))
		ids[o.get("id", -1)] = true
	var pillars_out := 0
	for pillar in v.network_world.obstacles_near(px, py, reach):
		pillars_out += int(not sim.obstacles.has(pillar))
	var cars_out := 0
	for c in T.cars:
		if Vector2(c.x - px, c.y - py).length() < reach - 20.0 and not (ids.has(c.id * 32) or ids.has(c.id * 32 + 1)):
			cars_out += 1
	return [sim.obstacles.size(), far, pillars_out, cars_out]


func _step_cost(inp: Dictionary) -> float:
	var best := 1e9
	for rep in 3:
		var t := Time.get_ticks_usec()
		for k in 1200:
			v.sim.step(inp, DT)
		best = minf(best, float(Time.get_ticks_usec() - t) / 1200.0)
	v.sim.events.clear()
	return best


func _run() -> void:
	var until := Time.get_ticks_msec() + 6000      # the pad's traffic spawns round the craft
	while Time.get_ticks_msec() < until:
		await process_frame
	v.set_process(false)
	var T = v.traffic_net
	var sim = v.sim
	var at_rest: float = Traffic.feed_reach(0.0)
	var fast: float = Traffic.feed_reach(4470.0)
	_check("the reach: %.0f m at rest, %.0f m at 4,000 mph, %.0f m at 10,000 mph; it covers the longest frame's flying twice over and never passes the old field (%.0f m)" % [
		at_rest, Traffic.feed_reach(1788.0), fast, Traffic.R_FIELD],
		at_rest >= 100.0 and at_rest <= 200.0 and fast >= 2.0 * 0.05 * 4470.0 and fast <= Traffic.R_FIELD
		and Traffic.feed_reach(1788.0) > at_rest and Traffic.feed_reach(1e6) == Traffic.R_FIELD)
	T.collide = false
	sim.P.obstacleCollisions = false
	T._feed()
	_check("with the setting off nothing is fed", sim.obstacles.is_empty())
	T.collide = true
	sim.P.obstacleCollisions = true
	var px: float = sim.pod.x
	var py: float = sim.pod.y
	var old := _old_count(T, px, py)
	sim.pod.vx = 0.0
	sim.pod.vy = 0.0
	T._feed()
	var rest := _survey(T, at_rest)
	_check("standing on the pad among %d vehicles: %d circles fed (the old field held %d), the farthest %.0f m off within the %.0f m reach; no pillar within reach left out (%d), no vehicle (%d)" % [
		T.cars.size(), rest[0], old, rest[1], at_rest, rest[2], rest[3]],
		T.cars.size() > 40 and int(rest[0]) * 4 <= old and float(rest[1]) <= at_rest + 1.0 and int(rest[2]) == 0 and int(rest[3]) == 0)
	var inp := {"thrL": 0.0, "thrR": 0.0, "brkL": 1.0, "brkR": 1.0, "repair": false, "reignite": false}
	var fed := _step_cost(inp)
	var kept: Array = sim.obstacles
	sim.obstacles = []
	var bare := _step_cost(inp)
	sim.obstacles = kept
	_check("a sim step standing on the pad: %.0f us with the feed's obstacles, %.0f us with none (the old field's cost as much again)" % [fed, bare], fed < 1.3 * bare + 10.0)
	# at 4,000 mph along the road
	var R = sim.roads[sim.pod.path]
	var i: int = clampi(int(sim.pod.hint), 0, int(R.N) - 1)
	sim.pod.vx = 1788.0 * float(R.tx[i])
	sim.pod.vy = 1788.0 * float(R.ty[i])
	T._feed()
	var reach: float = Traffic.feed_reach(1788.0)
	var quick := _survey(T, reach)
	_check("the same place at 4,000 mph: %d circles fed, the farthest %.0f m off within the %.0f m reach; no pillar within reach left out (%d), no vehicle (%d)" % [
		quick[0], quick[1], reach, quick[2], quick[3]],
		int(quick[0]) >= int(rest[0]) and float(quick[1]) <= reach + 1.0 and int(quick[2]) == 0 and int(quick[3]) == 0)
	sim.pod.vx = 0.0
	sim.pod.vy = 0.0
	v.queue_free()
	await process_frame
	print("TRAFFIC FEED %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
