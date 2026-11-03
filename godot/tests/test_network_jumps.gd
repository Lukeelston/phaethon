## The Network's jumps and open ground through the view (view/craft_view.gd, view/network_world.gd;
## Luke: "taking a massive interchange and using it as a ramp to jump 2 miles and 1500' up to the
## entrance of the next ramp"; "Missing a jump drops the pod to the ground, where it will look for a
## city for an onramp or just reset"):
##   board      each launch spur's exit has its board on the highway: "JUMP", its window ("3,000+ MPH")
##   airborne   off the lip at 4,000 mph the dash reads "AIRBORNE  x.x s  y FT"
##   caught     caught by the deck: the dash flashes "CAUGHT  x.x s IN THE AIR  y MPH"; on the deck
##              (~3,500 ft up) the craft is drawn at the pod's own height (the roads' heights are the
##              sims' now: not lifted twice)
##   missed     at 2,500 mph, turned down under the deck onto the open ground: the dash points to the
##              nearest city's on-ramp ("OFF THE ROAD  <CITY> ON-RAMP  x mi"), the minimap's target is
##              that on-ramp
##   restart    a restart: back at the last city, on the road, the minimap's target the city again
##   traffic    no vehicle can take a jump or an on-ramp (their junctions aren't traffic's)
## Prints NETWORK JUMPS PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_network_jumps.gd -- --mute
extends SceneTree

const ViewScript := preload("res://view/craft_view.gd")
const CraftModelScript := preload("res://view/craft_model.gd")
const MPH := 2.236936
const CHECKS := 6
var fails := 0
var passed := 0
var v
var frames := 0


func _initialize() -> void:
	ViewScript.track_override = "network"
	ViewScript.job_override = "none"
	ViewScript.best_dir = OS.get_user_data_dir().path_join("test_network_jumps_")
	DirAccess.remove_absolute(ViewScript.best_dir + "network.json")
	v = ViewScript.new()
	root.add_child(v)


## On launch spur k, 300 samples short of its lip, every body at mph along it.
func _line_up(k: int, mph: float) -> void:
	var sim = v.sim
	var l: int = int(sim.jumps[k][0])
	var R = sim.roads[l]
	var i: int = R.N - 1 - 300
	sim.respawn_on(l, i, 1)
	for b in sim.bodies:
		b.vx = mph / MPH * R.tx[i]
		b.vy = mph / MPH * R.ty[i]
	v.flash_until = -1.0


func _run(secs: float, lev: float, each: Callable) -> void:
	v.inp = {"thrL": lev, "thrR": lev, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
	for f in int(secs * 60.0):
		for k in 8:
			v._sim_step()
		each.call()


func _process(_d: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	if frames > 3:
		return false
	var sim = v.sim
	# the boards
	var boards := []
	for key in v.network_world._signs:
		for spec in v.network_world._signs[key]:
			if spec[2] == "jump":
				boards.append(spec[3])
	_check("board: %d jump boards %s" % [boards.size(), boards.slice(0, 1)], boards.size() == sim.jumps.size() and boards.all(func(b): return b[0] == "JUMP" and b[1] == "3,000+ MPH"))
	# a jump at 4,000 mph
	_line_up(0, 4000.0)
	var st := {"air": "", "caught": "", "off": ""}   # (a Dictionary: lambdas capture locals by value)
	_run(10.0, 0.87, func():
		var t: String = v._progress_text()
		if t.begins_with("AIRBORNE") and st.air == "":
			st.air = t
		if v.flash_msg.begins_with("CAUGHT") and st.caught == "":
			st.caught = v.flash_msg)
	var air: String = st.air
	var caught: String = st.caught
	_check("airborne: \"%s\"" % air, air.begins_with("AIRBORNE") and air.contains(" s ") and air.ends_with(" FT"))
	v._follow_origin()
	v.craft.sync(sim, v.inp, 1.0 / 72.0)
	var drawn: float = v.craft.pod.position.y
	var own: float = sim.pod.z - 0.2 + CraftModelScript.POD_LIFT
	_check("caught: \"%s\"; on %s at %.0f ft, the pod drawn at %.1f m (its own height %.1f m)" % [caught, sim.roads[sim.pod.path].name, sim.pod.z / 0.3048, drawn, own],
		caught.begins_with("CAUGHT") and caught.contains("IN THE AIR") and sim.roads[sim.pod.path].role == "catch" and sim.pod.z > 900.0 and absf(drawn - own) < 1.0)
	# missed at 2,500 mph: the open ground
	_line_up(0, 2500.0)
	_run(40.0, 0.3, func():
		var t: String = v._progress_text()
		if t.begins_with("OFF THE ROAD") and t.contains("ON-RAMP") and t.contains(" mi"):   # (past the flash)
			st.off = t)
	var off: String = st.off
	var wp: Dictionary = v.minimap.waypoint
	_check("missed: \"%s\"; the minimap's target %s; off the roads %s" % [off, wp.get("name", "-"), sim.pod.off_road],
		off.contains("ON-RAMP") and off.contains(" mi") and String(wp.get("name", "")).ends_with("ON-RAMP") and sim.pod.off_road)
	v._respawn()
	var c: Dictionary = sim.cities[int(sim.net.from)]
	var cq := Vector2(sim.roads[c.road].px[c.i], sim.roads[c.road].py[c.i])
	_check("restart: back at %s (%.1f m off its terminal), on the road %s, the minimap's target %s" % [c.name, Vector2(sim.pod.x, sim.pod.y).distance_to(cq), not sim.pod.off_road, v.minimap.waypoint],
		Vector2(sim.pod.x, sim.pod.y).distance_to(cq) < 3.0 and not sim.pod.off_road and v.minimap.waypoint.is_empty())
	# traffic
	var T = v.traffic_net
	var onto := 0
	if T:
		for r in T._switch.size():
			for sp in T._switch[r]:
				if sim.roads[int(sp[2])].role != "":
					onto += 1
	_check("traffic: %d of its switches onto a jump or an on-ramp (traffic %s)" % [onto, T != null], T != null and onto == 0)
	var good: bool = fails == 0 and passed == CHECKS
	print("NETWORK JUMPS ", "PASS" if good else "FAIL (%d failed, %d of %d passed)" % [fails, passed, CHECKS])
	quit(0 if good else 1)
	return false


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
