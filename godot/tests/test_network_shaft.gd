## The Network's shafts, straight highways, side roads and driving partner, through the view (Luke: "a
## vertical shaft that turns over on itself and enters the same road it came from"; "some of the highways
## ... completely straight from edge to edge"; "different shapes, that would reasonably cause the person to
## actually shift"; "a 'driving partner', that stays around your speed and just generally does what you do"):
##   straight   E2, N2 and E3 are dead straight, end to end
##   ends       every highway end, both ends, has a shaft: twelve, none of them a road in plan you steer
##   shape      the world's shape from the road: level at its feet on the highway's line, the way out and
##              the way back on opposite sides of it, straight up, the top 41,000 ft up, upside down there
##   ride       flown hands-off at 4,000 mph through the view: the craft is drawn up the wall, over the
##              top with its up pointing down, the right way up again, the frame never jumps (no step
##              between frames over ~1.5x the speed), and it comes out on the same highway the other way
##   stall      no throttle at 300 mph: gravity stops it on the climb and it slides back
##   sides      twelve side roads, every one with corners a board names (a speed and a gear), at least
##              two gears' worth on each, none slower than second
##   partner    on E2 at 4,000 mph: it holds station within ~120 m without a hand on it, on the road; you
##              brake, it comes back a little and stays with you; it goes up the shaft with you
##   menu       the main menu toggles it, saved; a new view has it; the flight waits while the menu's open
##   cockpit    the headset's rig: upside down over the top with the pod where it should be, level on the
##              way out; its menu has the partner, the controls and the next track, its panel shows
## Prints NETWORK SHAFT PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_network_shaft.gd -- --mute
extends SceneTree

const ViewScript := preload("res://view/craft_view.gd")
const VrScript := preload("res://vr/vr_cockpit.gd")
const MPH := 2.236936
const CHECKS := 12
var fails := 0
var passed := 0
var v
var frames := 0


func _initialize() -> void:
	ViewScript.track_override = "network"
	ViewScript.job_override = "none"
	ViewScript.best_dir = OS.get_user_data_dir().path_join("test_network_shaft_")
	DirAccess.remove_absolute(ViewScript.best_dir + "network.json")
	DirAccess.remove_absolute(ViewScript.best_dir + "settings.json")
	v = ViewScript.new()
	root.add_child(v)


func _road(name: String) -> int:
	for r in v.sim.roads.size():
		if v.sim.roads[r].name == name:
			return r
	return -1


func _process(_d: float) -> bool:
	frames += 1
	if frames != 3:
		return false
	var sim = v.sim
	_straight(sim)
	_shape(sim)
	_ride(sim)
	_stall(sim)
	_sides(sim)
	_partner(sim)
	_menu(sim)
	_cockpit()
	var good: bool = fails == 0 and passed == CHECKS
	print("NETWORK SHAFT ", "PASS" if good else "FAIL (%d failed, %d of %d passed)" % [fails, passed, CHECKS])
	quit(0 if good else 1)
	return false


func _straight(sim) -> void:
	var worst := 0.0
	for name in ["E2", "N2", "E3"]:
		var R = sim.roads[_road(name)]
		for i in range(0, R.N, 500):
			worst = maxf(worst, absf(R.tx[i] * R.tx[0] + R.ty[i] * R.ty[0] - 1.0))
			var dx: float = R.px[i] - R.px[0]
			var dy: float = R.py[i] - R.py[0]
			worst = maxf(worst, absf(-dx * R.ty[0] + dy * R.tx[0]) / 1000.0)
	var bent := 0
	for name in ["E1", "N1", "N3"]:
		var R = sim.roads[_road(name)]
		for i in range(0, R.N - 1, 200):
			if absf(R.tx[i] * R.ty[0] - R.ty[i] * R.tx[0]) > 0.05:
				bent += 1
				break
	_check("straight: E2, N2 and E3 within %.6f of a ruler (a km off in the worst place reads 1.0); the other %d still bend" % [worst, bent], worst < 1e-4 and bent == 3)


func _shape(sim) -> void:
	var shaft = v.network_world.shaft
	var ends := {}
	for sh in sim.shafts:
		ends[sim.roads[int(sh[0])].name] = true
	_check("ends: %d shafts on %d highway ends %s" % [sim.shafts.size(), 12, ends.keys().slice(0, 2)], sim.shafts.size() == 12 and ends.has("TE2+") and ends.has("TN1-"))
	var sh: Array = sim.shafts[0]
	for q in sim.shafts:
		if int(q[0]) == _road("TE2+"):
			sh = q
	var r := int(sh[0])
	var R = sim.roads[r]
	var i0 := int(sh[1])
	var i1 := int(sh[2])
	var H = sim.roads[_road("E2")]
	var a0: Array = shaft.at(r, float(i0) + 0.01)
	var a1: Array = shaft.at(r, float(i1) - 0.01)
	var feet: float = Vector2(float(a0[0]) - R.px[i0], float(a0[1]) - R.py[i0]).length() + Vector2(float(a1[0]) - R.px[i1], float(a1[1]) - R.py[i1]).length()
	var lat0: float = float(a0[1]) - H.py[0]
	var lat1: float = float(a1[1]) - H.py[0]
	var top := 0.0
	var vert := 1.0
	var at_top := []
	for i in range(i0, i1, 4):
		var A: Array = shaft.at(r, float(i))
		if float(A[2]) > top:
			top = A[2]
			at_top = A
		vert = minf(vert, absf(absf((A[3] as Vector3).y) - 1.0))
	_check("shape: its feet on the road (%.1f m off), the way out %.0f m and the way back %.0f m off the highway's line; straight up (%.4f off vertical); the top at %.0f ft, up there the road's up points %.2f" % [feet, lat0, lat1, vert, top / 0.3048, (at_top[5] as Vector3).y],
		feet < 3.0 and lat0 < -90.0 and lat1 > 90.0 and vert < 1e-3 and top / 0.3048 > 35000.0 and (at_top[5] as Vector3).y < -0.99)


func _fly(lev: float, frames_n: int, each: Callable) -> void:
	v.inp = {"thrL": lev, "thrR": lev, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
	for f in frames_n:
		for k in 8:
			v._sim_step()
		v._follow_origin()
		v.craft.sync(v.sim, v.inp, 1.0 / 60.0)
		each.call(f)


func _ride(sim) -> void:
	var r := _road("TE2+")
	var R = sim.roads[r]
	var sh: Array = []
	for q in sim.shafts:
		if int(q[0]) == r:
			sh = q
	var start: int = int(sh[1]) - 200
	sim.respawn_on(r, start, 1)
	for b in sim.bodies:
		b.vx = 4000.0 / MPH * R.tx[start]
		b.vy = 4000.0 / MPH * R.ty[start]
	var st := {"prev": Vector3.INF, "worst": 0.0, "top": 0.0, "up_top": 1.0, "vert": 0.0, "out": "", "t": 0.0, "up_end": 0.0, "scr": 0, "ox": v.org_x, "oy": v.org_y}
	# the world position: the drawn pod plus the floating origin (its jumps are the view's own)
	_fly(0.87, 60 * 40, func(_f):
		var P = sim.pod
		var world: Vector3 = Vector3(v.org_x, 0.0, -v.org_y) + v.craft.pod.position
		if st.prev != Vector3.INF:
			st.worst = maxf(st.worst, world.distance_to(st.prev))
		st.prev = world
		var up: Vector3 = v.craft.pod.basis * Vector3.UP
		var fw: Vector3 = v.craft.pod.basis * Vector3.FORWARD
		if world.y > st.top:
			st.top = world.y
			st.up_top = up.y
		st.vert = maxf(st.vert, fw.y)
		st.t += 1.0 / 60.0
		if P.path != r and st.t > 3.0 and st.out == "":
			st.out = sim.roads[P.path].name
			st.up_end = up.y
			st.along = P.vx * sim.roads[P.path].tx[P.hint] + P.vy * sim.roads[P.path].ty[P.hint]
		for e in sim.events:
			pass)
	var E2 = sim.roads[_road("E2")]
	var step_limit: float = 5000.0 / MPH / 60.0 * 1.5
	_check("ride: up to %.0f ft, nose %.2f up at the steepest, its up %.2f over the top; the worst frame's move %.1f m (limit %.1f)" % [st.top / 0.3048, st.vert, st.up_top, st.worst, step_limit],
		st.top / 0.3048 > 35000.0 and st.vert > 0.97 and st.up_top < -0.9 and st.worst < step_limit)
	_check("ride: out on %s after the shaft, the right way up (%.2f), going back the way it came (%.0f m/s along E2)" % [st.out, st.up_end, st.get("along", 0.0)],
		st.out == "E2" and st.up_end > 0.9 and float(st.get("along", 0.0)) * E2.tx[0] < -500.0)


func _stall(sim) -> void:
	var r := _road("TE2+")
	var R = sim.roads[r]
	var sh: Array = []
	for q in sim.shafts:
		if int(q[0]) == r:
			sh = q
	var start: int = int(sh[1]) - 40
	sim.respawn_on(r, start, 1)
	for b in sim.bodies:
		b.vx = 300.0 / MPH * R.tx[start]
		b.vy = 300.0 / MPH * R.ty[start]
	var st := {"top": 0.0, "back": false}
	_fly(0.0, 60 * 40, func(_f):
		st.top = maxf(st.top, sim.pod.z)
		if sim.pod.vx * R.tx[start] + sim.pod.vy * R.ty[start] < -5.0:
			st.back = true)
	_check("stall: no throttle at 300 mph: up %.0f ft, then sliding back (%s)" % [st.top / 0.3048, st.back], st.top < 700.0 and st.back)


func _sides(sim) -> void:
	var W = v.network_world
	var roads := {}
	var gears := {}
	for key in W._signs:
		for spec in W._signs[key]:
			if spec[2] == "corner":
				var nm: String = sim.roads[key.x].name
				if not gears.has(nm):
					gears[nm] = {}
				gears[nm][spec[3][1]] = true
				roads[nm] = true
	var n_side := 0
	var shifts := true
	for r in sim.roads:
		if r.name.begins_with("S"):
			n_side += 1
			var gs: Dictionary = gears.get(r.name, {})
			shifts = shifts and not gs.is_empty() and not gs.has("GEAR 1")
	var two := 0
	for nm in gears:
		if gears[nm].size() >= 2:
			two += 1
	_check("sides: %d side roads, all with corner boards (%d); %d with two gears' worth of corners; none in first (%s); e.g. %s" % [n_side, roads.size(), two, shifts, gears.get("S0", {}).keys()],
		n_side == 12 and roads.size() == 12 and two == 12 and shifts and W.gear_for(2100.0) == 2 and W.gear_for(3000.0) == 3)


func _partner(sim) -> void:
	v.set_partner(true)
	var p = v.partner
	var e2 := _road("E2")
	var R = sim.roads[e2]
	var i: int = R.N / 3
	sim.respawn_on(e2, i, 1)
	for b in sim.bodies:
		b.vx = 4000.0 / MPH * R.tx[i]
		b.vy = 4000.0 / MPH * R.ty[i]
	v._follow_origin()
	p.placed = false
	p.update(1.0 / 60.0)
	var st := {"far": 0.0, "off": 0.0, "near": 1e9, "drop": 0.0}
	_fly(0.87, 60 * 12, func(_f):
		p.update(1.0 / 60.0)
		var d := Vector2(p.x - sim.pod.x, p.y - sim.pod.y).length()
		st.far = maxf(st.far, d)
		st.near = minf(st.near, d)
		var q: int = sim.pod.hint
		st.off = maxf(st.off, absf((p.x - R.px[q]) * R.nx[q] + (p.y - R.py[q]) * R.ny[q])))
	_check("partner: at 4,000 mph it holds %.0f-%.0f m off you, at most %.0f m off the centreline (the wall at %.0f)" % [st.near, st.far, st.off, R.w[i] / 2.0], st.far < 120.0 and st.near > 15.0 and st.off < R.w[i] / 2.0)
	# you brake: it falls in behind and stays with you
	v.inp = {"thrL": 0.0, "thrR": 0.0, "brkL": 1.0, "brkR": 1.0, "repair": false, "reignite": true}
	var fw0 := Vector2(R.tx[i], R.ty[i])
	var ahead := 0.0
	for f in 60 * 6:
		for k in 8:
			v._sim_step()
		v._follow_origin()
		p.update(1.0 / 60.0)
		ahead = maxf(ahead, Vector2(p.x - sim.pod.x, p.y - sim.pod.y).dot(fw0))
	var sp := Vector2(sim.pod.vx, sim.pod.vy).length()
	var dv: float = absf(p.lag.length() - sp)
	_check("partner: you brake to %.0f mph: it runs on at most %.0f m ahead and comes back, its speed within %.0f mph of yours" % [sp * MPH, ahead, dv * MPH], ahead < 400.0 and dv * MPH < 150.0 and Vector2(p.x - sim.pod.x, p.y - sim.pod.y).length() < 120.0)
	# up the shaft with you
	var r := _road("TE2+")
	var sh: Array = []
	for q in sim.shafts:
		if int(q[0]) == r:
			sh = q
	var Rs = sim.roads[r]
	var start: int = int(sh[1]) - 60
	sim.respawn_on(r, start, 1)
	for b in sim.bodies:
		b.vx = 2500.0 / MPH * Rs.tx[start]
		b.vy = 2500.0 / MPH * Rs.ty[start]
	v._follow_origin()
	p.placed = false
	p.update(1.0 / 60.0)
	var gap := 0.0
	var high := 0.0
	v.inp = {"thrL": 0.8, "thrR": 0.8, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
	for f in 60 * 16:
		for k in 8:
			v._sim_step()
		v._follow_origin()
		v.craft.sync(sim, v.inp, 1.0 / 60.0)
		p.update(1.0 / 60.0)
		gap = maxf(gap, (p._pod.position as Vector3).distance_to(v.craft.pod.position))
		high = maxf(high, (p._pod.position as Vector3).y)
	_check("partner: up the shaft with you: to %.0f ft, never more than %.0f m from you" % [high / 0.3048, gap], high / 0.3048 > 30000.0 and gap < 200.0)
	v.set_partner(false)


func _menu(sim) -> void:
	v.menu_open(true)
	var txt: String = v.menu.text()
	var on_before: bool = v.partner_on
	sim.respawn(0)
	var t0: float = sim.time
	v._process(0.1)   # the flight waits
	var waited: bool = sim.time == t0
	v.menu.at = 0
	v.menu_choose()
	var saved: Dictionary = v._load_settings()
	var v2 = ViewScript.new()
	root.add_child(v2)
	var carried: bool = v2.partner_on and v2.partner != null
	v.menu_choose()   # and off again
	var off_saved: bool = v._load_settings().get("partner", true) == false
	v.menu.at = v.menu.items.size() - 1
	v.menu_choose()
	v2.queue_free()
	_check("menu: \"%s\"; the flight waits (%s); DRIVING PARTNER on (was %s), saved %s, a new view has it (%s); off again saved (%s); RESUME closes it (%s)" % [txt.replace("\n", " / "), waited, on_before, saved, carried, off_saved, not v.menu.open],
		txt.contains("DRIVING PARTNER") and waited and not on_before and saved.get("partner", false) == true and carried and off_saved and not v.menu.open)


func _cockpit() -> void:
	var c = VrScript.new()
	root.add_child(c)
	var sim = c.sim
	var r := -1
	for k in sim.roads.size():
		if sim.roads[k].name == "TE2+":
			r = k
	var sh: Array = []
	for q in sim.shafts:
		if int(q[0]) == r:
			sh = q
	var q: float = PI * float(sh[3]) / 2.0
	sim.respawn_on(r, int(sh[1]) + roundi((2.0 * q + float(sh[4])) / 24.0), 1)   # the apex
	c._follow_origin()
	c.craft.sync(sim, c.inp, 1.0 / 60.0)
	for k in 30:
		c._place_camera(1.0)
	var up_top: float = (c.rig.basis * Vector3.UP).y
	var off: float = (c.rig.position - c.craft.pod.position).length()
	var high: float = c.rig.position.y
	sim.respawn_on(r, int(sh[2]) + 20, 1)
	c._follow_origin()
	c._ride.clear()
	c._place_camera(1.0)
	var up_out: float = (c.rig.basis * Vector3.UP).y
	c.menu_open(true)
	var keys := []
	for it in c.menu.items:
		keys.append(it.key)
	var shown: bool = c.menu_panel.visible and (c.menu_panel.get_node("words") as Label3D).text.contains("DRIVING PARTNER")
	var was: String = c.quest.scheme
	c.menu.at = keys.find("scheme")
	c.menu_choose()
	var cycled: bool = c.quest.scheme != was
	c.quest.scheme = was
	c.menu_open(false)
	var hidden: bool = not c.menu_panel.visible
	c.queue_free()
	_check("cockpit: over the top at %.0f ft its up is %.2f, %.1f m from the pod's place; on the way out %.2f; the menu %s, shown %s, CONTROLS cycles %s, closed hides it %s" % [high / 0.3048, up_top, off, up_out, keys, shown, cycled, hidden],
		high / 0.3048 > 35000.0 and up_top < -0.95 and off < 6.0 and up_out > 0.95 and keys.has("partner") and keys.has("scheme") and keys.has("track") and shown and cycled and hidden)


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
