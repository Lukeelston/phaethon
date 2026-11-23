## Mount Hyperion (Luke, 2026-11-21: "add another one ... 3 times - it should be inconceivable. Then it
## should have a steadily steepening ramp until it's basically straight up, then a braking section to
## crest over the top, enjoy the view from the top, then creep over a cliff and scream down the other
## side. It should be wide and imposing."; view/hyperion.gd, tools/design_network.py):
##   designed   the road SHyperion: its summit 48 km up; its parts where the designer put them; every sample of
##              the mountain 24 m of deck from the next; its width; no corner under second gear
##   ramp       its pitch rises by the same angle every sample from level to the wall's 88 degrees, with no
##              step; over the crest it falls as evenly to level; the lip and the run-out likewise
##   mirrored   the road lies on the mountain the views draw (the designer's hyperion_z)
##   deck       the sim carries a craft along it at its speed along the deck: each part of the mountain takes
##              the time its length says; the craft's height is the road's own; the view's pitch is the deck's
##   lip        a craft crept over the lip stays on the road, its pitch turning smoothly to 88 degrees down;
##              one that takes the crest and the lip flat out stays on it too; one that brakes at the braking
##              section stops short of the lip, one that does not cannot
##   untouched  Helios's road and surface are bit for bit what they were before this mountain (recorded on
##              b4c7878 by the same arithmetic); flights on E3, past the road's mouth on E2 and up Helios's Face
##              end bit for bit where they do with the deck rule switched off (the sims as they were), and
##              with it off Hyperion's wall passes at the map's speed, as Helios's does
##   land       the terrain's grid lies under the mountain; the mountain is its own mesh, to its summit; the
##              road's own land beside it; nothing grows on it
##   named      its signs and boards, its two start points, the craft laid along the slope
##   seated     on the wall what stands over the deck stands square to it (the pilot's eye is not in the road);
##              high on the mountain the world is drawn below its true height and the camera reaches further
## Prints HYPERION PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Sim := preload("res://sim/craft_sim.gd")
const Hyperion := preload("res://view/hyperion.gd")
const Helios := preload("res://view/helios.gd")
const Outlook := preload("res://view/outlook.gd")
const UI := preload("res://release/release_config.gd")
const DT := 1.0 / 480.0
const MPH := 2.236936
# The designer's own account of the road (tools/design_network.py prints these):
const AT := {"ramp": 1874, "wall": 4754, "crest": 4824, "summit": 5016, "centre": 5116, "lip": 5216, "drop": 5235, "runout": 6580, "end": 7604}
const WIDE := [764, 7624]       # the deck is 800 m wide from here to here: the approach, the whole mountain and 20 samples past the run-out's end
const WIDE_ON := [9319, 12125]  # ... and from here to here, the far straight (it was 800 m from 764 to 12125 before the leaps: tests/test_hyperion_leaps.gd)
const BESIDE := [8224, 9099]    # between, beside the cliff's leap lane, it is 280 m: the plain way through
# As recorded on b4c7878, before this mountain (the same arithmetic: _helios_road, _helios_surface). Its road's
# samples and its surface are not to change (Luke: "Keep it as it is"); if they are ever changed on purpose,
# this test prints the new figures.
const HELIOS_ROAD := "059a8079b28a3130f826fb7fc541987dd06433ade9dbc5c7681ab2934636ee96"
const HELIOS_SURFACE := "d03690894f3c7b0b5647d39ff7dcba4b713bec67bf41cf78b17159efd3a6a608"
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _road(sim, road_name: String) -> int:
	for k in sim.roads.size():
		if String(sim.roads[k].name) == road_name:
			return k
	return -1


## The deck's pitch at sample f of road r, degrees (+ climbing the way its samples run).
func _pitch(sim, r: int, f: float) -> float:
	return rad_to_deg(asin(clampf(sim.net_slope(r, f) / float(sim.NET_STEP), -1.0, 1.0)))


## A craft put on road r at sample i going `mph` the way the samples run, every body level with the pod.
func _put(sim, r: int, i: int, mph: float) -> void:
	sim.respawn_on(r, i, 1)
	_hold(sim, r, i, mph)


## ... and held to that speed along the road (the sim's own thrust and drag left out: what is timed is the travel alone).
func _hold(sim, r: int, i: int, mph: float) -> void:
	var R = sim.roads[r]
	for b in sim.bodies:
		b.vx = mph / MPH * R.tx[i]
		b.vy = mph / MPH * R.ty[i]
		b.w = 0.0
		b.th = atan2(R.ty[i], R.tx[i])


## The sample of road r the pod is over (the nearest by its place along the straight the mountain is on).
func _pod_f(sim, r: int) -> float:
	var R = sim.roads[r]
	var k := maxi(0, int(sim.pod.hint) - 3)
	while k < R.N - 2 and (sim.pod.x - R.px[k + 1]) * R.tx[k] + (sim.pod.y - R.py[k + 1]) * R.ty[k] >= 0.0:
		k += 1
	return float(k) + clampf(((sim.pod.x - R.px[k]) * R.tx[k] + (sim.pod.y - R.py[k]) * R.ty[k]) / R.len[k], 0.0, 1.0)


func _helios_road(s) -> String:
	var r := _road(s, "SHelios")
	var R = s.roads[r]
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var heights := PackedFloat64Array()
	for i in R.N:
		heights.append(s.net_height(r, float(i)))
		heights.append(s.net_height(r, float(i) + 0.5))
	for a in [R.px, R.py, R.tx, R.ty, R.len, R.w, heights]:
		ctx.update((a as PackedFloat64Array).to_byte_array())
	return ctx.finish().hex_encode()


func _helios_surface() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261121
	var surf := PackedFloat64Array()
	for k in 4000:
		var a := rng.randf() * TAU
		var p: Vector2 = Helios.CENTRE + Vector2(cos(a), sin(a)) * sqrt(rng.randf()) * Helios.FOOT * 1.05
		surf.append(Helios.height(p))
		surf.append(Helios.land(p))
	ctx.update(surf.to_byte_array())
	return ctx.finish().hex_encode()


## A scripted flight: from sample i of road r at mph, the levers weaving (or held), for `seconds`. -> the three
## bodies' x, y, z, vx, vy, vz, th, w at the end, as the bytes of their doubles in hex.
func _flight(s, r: int, i: int, mph: float, seconds: float, weave: bool) -> String:
	s.respawn_on(r, i, 1)
	for b in s.bodies:
		b.vx = mph / 2.236936 * s.roads[r].tx[i]
		b.vy = mph / 2.236936 * s.roads[r].ty[i]
	var steps := roundi(seconds / DT)
	for n in steps:
		var t := float(n + 1) * DT
		var inp := {"thrL": 0.9, "thrR": 0.9, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "handling": "speed"}
		if weave:
			inp.thrL = 0.8 + 0.2 * sin(t * 1.3)
			inp.thrR = 0.8 - 0.2 * sin(t * 1.3)
			inp.brkL = 0.6 if t > 14.0 and t < 16.0 else 0.0
			inp.brkR = 0.3 if t > 14.0 and t < 16.0 else 0.0
		s.step(inp, DT)
	var out := PackedFloat64Array()
	for b in s.bodies:
		out.append_array(PackedFloat64Array([b.x, b.y, b.z, b.vx, b.vy, b.vz, b.th, b.w]))
	return out.to_byte_array().hex_encode()


func _run() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("hyperion_test_")
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	var v = View.new()
	root.add_child(v)
	v.set_process(false)
	var sim = v.sim
	var land = v.landscape
	var world = v.network_world
	var scenic = world.scenic if world != null else null
	var r := _road(sim, "SHyperion")
	if r < 0 or land == null or scenic == null or not scenic.roads.has(r) or not Hyperion.ready:
		_check("the road SHyperion is on the Network, with its mountain and its land", false)
		quit(1)
		return
	var R = sim.roads[r]
	var step: float = sim.NET_STEP

	# designed
	var top := 0.0
	var level := true
	for i in range(AT.summit, AT.lip + 1):
		top = maxf(top, sim.net_height(r, float(i)))
		level = level and absf(sim.net_height(r, float(i)) - Hyperion.HEIGHT) < 0.001
	var parts_ok := true
	for key in AT:
		parts_ok = parts_ok and int(Hyperion.at.get(key, -1)) == int(AT[key])
	_check("the summit stands %.2f m up (%.2f times Helios's %.0f), level over its %d samples; the mountain's parts are where the designer put them (%s)" % [
			top, top / Helios.HEIGHT, Helios.HEIGHT, AT.lip - AT.summit, Hyperion.at],
		absf(top - 48000.0) < 0.01 and level and parts_ok and top / Helios.HEIGHT > 2.9)
	var chord_lo := INF
	var chord_hi := 0.0
	var plan := 0.0
	for i in range(AT.ramp, AT.end):
		var dz: float = sim.net_height(r, float(i + 1)) - sim.net_height(r, float(i))
		var chord := sqrt(R.len[i] * R.len[i] + dz * dz)
		chord_lo = minf(chord_lo, chord)
		chord_hi = maxf(chord_hi, chord)
		plan += R.len[i]
	var deck_m := float(AT.end - AT.ramp) * step
	_check("every sample of the mountain is %.0f m of deck from the next (%.3f to %.3f m along the chord): %.2f km of deck over %.2f km of map; the ramp %.2f km, the braking section (wall and crest) %.2f km, the summit %.2f km, the drop %.2f km" % [
			step, chord_lo, chord_hi, deck_m / 1000.0, plan / 1000.0, (AT.wall - AT.ramp) * step / 1000.0, (AT.summit - AT.wall) * step / 1000.0,
			(AT.lip - AT.summit) * step / 1000.0, (AT.end - AT.lip) * step / 1000.0],
		chord_lo > step - 0.05 and chord_hi < step + 0.001 and bool(R.deck) and deck_m > 137000.0 and plan < 71000.0)
	var narrow := INF
	var mouth := 0.0
	for wide in [WIDE, WIDE_ON]:
		for i in range(wide[0], wide[1] + 1):
			narrow = minf(narrow, R.w[i])
	var beside := 0.0
	var beside_least := INF
	for i in range(BESIDE[0], BESIDE[1] + 1):
		beside = maxf(beside, R.w[i])
		beside_least = minf(beside_least, R.w[i])
	for i in [0, 100, R.N - 1]:
		mouth = maxf(mouth, R.w[i])
	var e3 := _road(sim, "E3")
	_check("the deck is %.0f m wide from sample %d (%.1f km before the ramp's foot) to %d (past the run-out's end) and from %d to %d, twice a highway's %.0f; %.0f m beside the cliff's leap lane between (samples %d to %d); %.0f m at its mouths" % [
			narrow, WIDE[0], (AT.ramp - WIDE[0]) * step / 1000.0, WIDE[1], WIDE_ON[0], WIDE_ON[1], sim.roads[e3].w[100], beside, BESIDE[0], BESIDE[1], mouth],
		narrow >= 800.0 and narrow >= 2.0 * float(sim.roads[e3].w[100]) and mouth == 200.0 and WIDE[0] < AT.ramp - 1000 and WIDE[1] > AT.end and WIDE_ON[1] > AT.end + 4000
			and beside == 280.0 and beside_least == 280.0)
	var tightest := INF
	for i in R.N:
		if R.kap[i] != 0.0:
			tightest = minf(tightest, 1.0 / absf(R.kap[i]))
	var corner_mph := sqrt(world.CORNER_G * 9.81 * tightest) * MPH
	_check("its tightest corner is %.1f km in radius: %d mph at %.0f g, gear %d (second gear wants 5.9 km)" % [tightest / 1000.0, roundi(corner_mph), world.CORNER_G, world.gear_for(corner_mph)],
		tightest >= 5900.0 and world.gear_for(corner_mph) >= 2)

	# ramp
	var steps_up := PackedFloat64Array()
	for i in range(AT.ramp, AT.wall):
		steps_up.append(_pitch(sim, r, float(i + 1)) - _pitch(sim, r, float(i)))
	var up_lo := INF
	var up_hi := 0.0
	for d in steps_up:
		up_lo = minf(up_lo, d)
		up_hi = maxf(up_hi, d)
	var wall_pitch := _pitch(sim, r, float(AT.wall))
	var wall_spread := 0.0
	for i in range(AT.wall, AT.crest + 1):
		wall_spread = maxf(wall_spread, absf(_pitch(sim, r, float(i)) - wall_pitch))
	var over_lo := INF
	var over_hi := -INF
	for i in range(AT.crest, AT.summit):
		var d := _pitch(sim, r, float(i + 1)) - _pitch(sim, r, float(i))
		over_lo = minf(over_lo, d)
		over_hi = maxf(over_hi, d)
	# ... and between the samples, where a craft is: the pitch a tenth of a sample at a time, the biggest change in one
	var jump := 0.0
	var f := float(AT.ramp)
	var was := _pitch(sim, r, f)
	while f < float(AT.end):
		f += 0.1
		var now := _pitch(sim, r, f)
		jump = maxf(jump, absf(now - was))
		was = now
	_check("the ramp's pitch rises from %.3f to %.3f degrees by %.5f to %.5f degrees every sample (a quarter of a circle %.1f km in radius: no step); the wall holds it within %.4f; over the crest it falls %.4f to %.4f a sample to %.3f at the summit; nowhere on the mountain does it change by more than %.3f degrees in a tenth of a sample" % [
			_pitch(sim, r, float(AT.ramp)), wall_pitch, up_lo, up_hi, step / deg_to_rad((up_lo + up_hi) / 2.0) / 1000.0, wall_spread, -over_hi, -over_lo, _pitch(sim, r, float(AT.summit)), jump],
		absf(_pitch(sim, r, float(AT.ramp))) < 0.001 and wall_pitch > 87.5 and wall_pitch < 88.5 and up_lo > 0.0 and up_hi - up_lo < 0.002 * up_hi
			and wall_spread < 0.01 and over_hi < 0.0 and over_lo - over_hi > -0.002 * absf(over_lo) and absf(_pitch(sim, r, float(AT.summit))) < 0.001 and jump < 0.6)
	var drop_pitch := _pitch(sim, r, float(AT.drop))
	_check("the lip turns it to %.3f degrees down in %d samples (%.0f m of deck, a radius of %.0f m), the wall down holds that for %.2f km, the run-out brings it level over %.2f km (%.3f at its end)" % [
			-drop_pitch, AT.drop - AT.lip, (AT.drop - AT.lip) * step, (AT.drop - AT.lip) * step / deg_to_rad(-drop_pitch), (AT.runout - AT.drop) * step / 1000.0,
			(AT.end - AT.runout) * step / 1000.0, _pitch(sim, r, float(AT.end))],
		drop_pitch < -87.5 and drop_pitch > -88.5 and absf(_pitch(sim, r, float(AT.runout)) - drop_pitch) < 0.01 and absf(_pitch(sim, r, float(AT.end))) < 0.001
			and (AT.runout - AT.drop) * step > 0.6 * 48000.0)

	# mirrored
	var off := 0.0
	var off_at := -1
	for i in R.N:
		var gap := absf(sim.net_height(r, float(i)) - Hyperion.height_xy(R.px[i], R.py[i]))
		if gap > off:
			off = gap
			off_at = i
	var D: Dictionary = scenic.roads[r]
	# (... and as the views themselves ask, by a Vector2: its place on the map is kept to 3 cm there, which is up to a metre of an 88 degree wall)
	var off32 := 0.0
	for i in R.N:
		off32 = maxf(off32, absf(sim.net_height(r, float(i)) - Hyperion.height(Vector2(R.px[i], R.py[i]))) * cos(deg_to_rad(_pitch(sim, r, float(i)))))
	_check("the road lies on the mountain the views draw: at most %.3f m off it (at sample %d) over all %d samples, the places in doubles; by a Vector2's place, %.3f m from its surface at most; its summit %.0f m from the mountain's middle at %.3f, %.3f km; its land runs from sample %d to %d" % [
			off, off_at, R.N, off32, Vector2(R.px[AT.centre], R.py[AT.centre]).distance_to(Hyperion.centre), Hyperion.centre.x / 1000.0, Hyperion.centre.y / 1000.0, int(D.first), int(D.last)],
		off < 0.1 and off32 < 0.1 and bool(D.get("mountain", false)) and int(D.first) <= AT.ramp and int(D.last) >= AT.end and absf(Hyperion.height(Hyperion.centre) - 48000.0) < 0.001)

	# deck
	var s = Sim.new({"track": "network", "handling": "speed"})
	var hands_off := {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "handling": "speed"}
	var marks := [AT.ramp, AT.wall, AT.crest, AT.summit, AT.lip, AT.drop, AT.runout, AT.end]
	var passed := {}
	var start := AT.ramp - 40
	_put(s, r, start, 3000.0)
	var t := 0.0
	var speed := 3000.0 / MPH
	var worst_z := 0.0
	var stayed := true
	var steepest := 0.0
	var view_pitch_err := 0.0
	while t < 200.0 and _pod_f(s, r) < float(AT.end + 40):
		s.step(hands_off, DT)
		_hold(s, r, start, 3000.0)
		t += DT
		var at := _pod_f(s, r)
		stayed = stayed and not s.pod.off_road and int(s.pod.path) == r
		worst_z = maxf(worst_z, absf(float(s.pod.z) - (s.net_height(r, s.deck_f(r, at)) + float(s.P.rideH))))      # (its place along the deck: the heights' keys are laid along it, CraftSim.deck_f)
		steepest = maxf(steepest, absf(rad_to_deg(s.deck_pitch(s.pod))))
		view_pitch_err = maxf(view_pitch_err, absf(rad_to_deg(s.deck_pitch(s.pod)) - _pitch(s, r, s.deck_f(r, s._road_f(s.pod)))))
		for m in marks:
			if not passed.has(m) and at >= float(m):
				passed[m] = t - (at - float(m)) * step / speed
	var timing := []
	var timed_ok := passed.size() == marks.size()
	if timed_ok:
		for k in marks.size() - 1:
			var took: float = float(passed[marks[k + 1]]) - float(passed[marks[k]])
			var says: float = float(marks[k + 1] - marks[k]) * step / speed
			timing.append("%s %.2f s (%.2f)" % [["ramp", "wall", "crest", "summit", "lip", "wall down", "run-out"][k], took, says])
			timed_ok = timed_ok and absf(took - says) < maxf(0.004 * says, 0.02)
	_check("held at 3,000 mph, each part of the mountain takes the time its deck's length says: %s; the climb in all %.2f s, the drop %.2f s; the pod within %.3f m of the road's own height throughout; its pitch as the views take it up to %.2f degrees, within %.3f of the deck's" % [
			", ".join(timing), float(passed.get(AT.summit, 0.0)) - float(passed.get(AT.ramp, 0.0)), float(passed.get(AT.end, 0.0)) - float(passed.get(AT.lip, 0.0)), worst_z, steepest, view_pitch_err],
		stayed and timed_ok and worst_z < 0.05 and steepest > 87.5 and steepest < 88.5 and view_pitch_err < 0.01)
	# (what the map's speed would have made of the wall: 1,680 m of it in the time 58 m takes)
	var wall_plan := 0.0
	for i in range(AT.wall, AT.crest):
		wall_plan += R.len[i]
	_check("the wall is %.0f m of deck over %.1f m of map: at the map's speed it would pass in %.3f s; it takes %.3f" % [(AT.crest - AT.wall) * step, wall_plan, wall_plan / speed,
			float(passed.get(AT.crest, 0.0)) - float(passed.get(AT.wall, 0.0))], wall_plan < 62.0 and float(passed.get(AT.crest, 0.0)) - float(passed.get(AT.wall, 0.0)) > 1.2)
	# stopped on the wall: the craft's pitch is the deck's, and its engines are laid up the slope from the pod
	sim.respawn_on(r, AT.wall + 30, 1)
	for b in sim.bodies:
		b.vx = 0.0
		b.vy = 0.0
	sim.step(hands_off, DT)
	var still_pitch := rad_to_deg(sim.deck_pitch(sim.pod))
	var pod_at: Vector3 = v.wz(sim.pod.x, sim.pod.y, sim.pod.z)
	var engine_at: Vector3 = v.body_place(sim.eL)
	var lead := engine_at - pod_at
	var lead_plan: float = Vector2(sim.eL.x - sim.pod.x, sim.eL.y - sim.pod.y).length()
	var lead_pitch := rad_to_deg(atan2(lead.y, Vector2(lead.x, lead.z).length()))
	_check("stopped on the wall the craft is pitched %.2f degrees (the deck's %.2f); its engine is drawn %.1f m from the pod (%.1f m apart in the sim), %.1f degrees up from it" % [
			still_pitch, _pitch(sim, r, sim._road_f(sim.pod)), lead.length(), lead_plan, lead_pitch],
		absf(still_pitch - _pitch(sim, r, sim._road_f(sim.pod))) < 0.01 and still_pitch > 87.0 and absf(lead.length() - lead_plan) < 0.2 * lead_plan and lead_pitch > 75.0)

	# seated: 1.2 m over the pod on the wall is 1.2 m out from the wall, not 1.2 m up it
	var above: Vector3 = v.wz(sim.pod.x, sim.pod.y, sim.pod.z + 1.2) - pod_at
	var wall_up := Vector3(-sin(deg_to_rad(still_pitch)) * R.tx[AT.wall], cos(deg_to_rad(still_pitch)), sin(deg_to_rad(still_pitch)) * R.ty[AT.wall])
	var deck_at: Vector3 = v.wz(sim.pod.x, sim.pod.y, sim.pod.z - float(sim.P.rideH))
	var pod_off := (pod_at - deck_at).dot(wall_up)
	# ... and the world's lift, there and on Helios's summit
	v._aloft_world()
	var lift_wall: float = v.lift
	var reach_wall: float = v.reach
	var sunk: float = v.position.y
	var helios_r := _road(sim, "SHelios")
	sim.respawn_on(helios_r, 7244, 1)
	v._aloft_world()
	var lift_helios: float = v.lift
	sim.respawn_on(e3, 9000, 1)
	v._aloft_world()
	_check("on the wall 1.2 m over the pod is %.2f m out from the wall (%.1f degrees from square to it); the pod rides %.2f m off the deck, square to it (its ride height %.1f); %.0f m up the world is drawn %.0f m below its height (this node at %.0f) and the camera reaches %.0f km; on Helios's summit the lift is %.0f, on E3 %.0f and the reach %.0f km" % [
			above.length(), rad_to_deg(above.angle_to(wall_up)), pod_off, float(sim.P.rideH), float(sim.net_height(r, float(AT.wall + 30))), lift_wall, sunk, reach_wall / 1000.0, lift_helios, float(v.lift), float(v.reach) / 1000.0],
		absf(above.length() - 1.2) < 0.01 and rad_to_deg(above.angle_to(wall_up)) < 0.5 and absf(pod_off - float(sim.P.rideH)) < 0.02
			and lift_wall > 40000.0 and is_equal_approx(sunk, -lift_wall) and reach_wall > 400000.0 and lift_helios == 0.0 and v.lift == 0.0 and v.reach == 120000.0 and v.position.y == 0.0)

	# lip
	var creep := 40.0
	_put(s, r, AT.lip - 12, creep)
	var pitch_was: float = s.deck_pitch(s.pod)
	var snap := 0.0
	var on_road := true
	var lip_z := 0.0
	t = 0.0
	while t < 120.0 and _pod_f(s, r) < float(AT.drop + 12):
		s.step(hands_off, DT)
		_hold(s, r, AT.lip - 12, creep)
		t += DT
		var p_now: float = s.deck_pitch(s.pod)
		snap = maxf(snap, absf(rad_to_deg(p_now - pitch_was)))
		pitch_was = p_now
		on_road = on_road and not s.pod.off_road and int(s.pod.path) == r
		lip_z = maxf(lip_z, absf(float(s.pod.z) - (s.net_height(r, s.deck_f(r, _pod_f(s, r))) + float(s.P.rideH))))
	_check("crept over the lip at %.0f mph the craft stays on the road: %.1f s from 12 samples short of it to 12 past its foot, its pitch turned to %.2f degrees down by at most %.4f degrees a step, %.3f m from the road's height at most" % [
			creep, t, -rad_to_deg(pitch_was), snap, lip_z], on_road and rad_to_deg(pitch_was) < -87.5 and snap < 0.05 and lip_z < 0.05 and t > 20.0)
	# flat out over the crest, the summit and the lip, the levers shut
	_put(s, r, AT.wall, 5000.0)
	var fast_ok := true
	var fast_rate := 0.0
	pitch_was = s.deck_pitch(s.pod)
	var at_lip_mph := 0.0
	t = 0.0
	while t < 40.0 and _pod_f(s, r) < float(AT.drop + 40):
		s.step(hands_off, DT)
		t += DT
		fast_ok = fast_ok and not s.pod.off_road and int(s.pod.path) == r and s.crash_t <= 0.0
		fast_rate = maxf(fast_rate, absf(rad_to_deg(float(s.deck_pitch(s.pod)) - pitch_was)) / DT)
		pitch_was = s.deck_pitch(s.pod)
		if at_lip_mph == 0.0 and _pod_f(s, r) >= float(AT.lip):
			at_lip_mph = Vector2(s.pod.vx, s.pod.vy).length() * MPH
	_check("taken flat out (5,000 mph into the braking section, levers shut, no brakes) the craft is carried over the crest, across the summit and over the lip on the road: still doing %.0f mph at the lip %.1f s on, its pitch turning %.0f degrees a second at the most (the lip), no crash" % [
			at_lip_mph, t, fast_rate], fast_ok and at_lip_mph > 2500.0)
	# braking from the board at the wall's foot
	var full_brake := {"thrL": 0.0, "thrR": 0.0, "brkL": 1.0, "brkR": 1.0, "repair": false, "reignite": true, "handling": "speed"}
	var stops := []
	var all_stop := true
	for from_mph in [3000.0, 5000.0]:
		_put(s, r, AT.wall, from_mph)
		t = 0.0
		while t < 60.0 and Vector2(s.pod.vx, s.pod.vy).length() * MPH > 3.0:
			s.step(full_brake, DT)
			t += DT
		var stopped_at := _pod_f(s, r)
		stops.append("from %.0f mph it stops in %.1f s at sample %.0f, %.2f km on (%s), %.2f km short of the lip" % [from_mph, t, stopped_at, (stopped_at - AT.wall) * step / 1000.0,
			"on the summit" if stopped_at >= float(AT.summit) else "on the crest, %.0f degrees from level" % _pitch(s, r, stopped_at), (AT.lip - stopped_at) * step / 1000.0])
		all_stop = all_stop and stopped_at < float(AT.lip) and not s.pod.off_road
	_check("braked from the braking section's first board: %s" % ["; ".join(stops)], all_stop)

	# untouched
	var fresh = Sim.new({"track": "network", "handling": "speed"})
	var plain = Sim.new({"track": "network", "handling": "speed"})
	plain.deck_rule = false      # (the sims as they were before there was a deck road)
	var road_print := _helios_road(fresh)
	var surface_print := _helios_surface()
	var others := 0
	for k in fresh.roads.size():
		others += int(bool(fresh.roads[k].deck))
	_check("Helios's road is sample for sample what it was (its 13,549 samples' places, tangents, lengths, widths and heights: %s), and its surface (%s); %d road is a deck road" % [
			"the same" if road_print == HELIOS_ROAD else road_print, "the same" if surface_print == HELIOS_SURFACE else surface_print, others],
		road_print == HELIOS_ROAD and surface_print == HELIOS_SURFACE and others == 1 and fresh.deck_sine(_road(fresh, "SHelios"), 7000.5) == 0.0)
	var flights := []
	var flights_same := true
	for flown in [["E3", 9000, 3000.0, 20.0, true], ["E2", 4300, 4000.0, 12.0, false], ["SHelios", 6700, 2500.0, 20.0, false], ["N2", 9000, 3000.0, 12.0, true]]:
		var with_rule := _flight(fresh, _road(fresh, flown[0]), int(flown[1]), float(flown[2]), float(flown[3]), bool(flown[4]))
		var without := _flight(plain, _road(plain, flown[0]), int(flown[1]), float(flown[2]), float(flown[3]), bool(flown[4]))
		flights.append("%s from sample %d at %.0f mph for %.0f s (%d steps): %s" % [flown[0], int(flown[1]), float(flown[2]), float(flown[3]), roundi(float(flown[3]) / DT),
			"the same" if with_rule == without else "DIFFERS"])
		flights_same = flights_same and with_rule == without and with_rule.length() == 384
	# ... and with the rule off Hyperion's own wall passes at the map's speed
	_put(plain, r, AT.wall - 2, 3000.0)
	var plain_t := 0.0
	var wall_in := -1.0
	var wall_out := -1.0
	while plain_t < 5.0 and wall_out < 0.0:
		plain.step(hands_off, DT)
		_hold(plain, r, AT.wall - 2, 3000.0)
		plain_t += DT
		if wall_in < 0.0 and _pod_f(plain, r) >= float(AT.wall):
			wall_in = plain_t
		if _pod_f(plain, r) >= float(AT.crest):
			wall_out = plain_t
	_check("with the deck rule switched off (the sims as they were) every body of the craft ends each of these flights where it does with it on, bit for bit (x, y, z, their speeds, heading and spin): %s; and Hyperion's wall then passes in %.3f s at 3,000 mph (the map's speed: %.3f s), not the %.3f its deck's length says" % [
			"; ".join(flights), wall_out - wall_in, wall_plan / speed, (AT.crest - AT.wall) * step / speed],
		flights_same and wall_in > 0.0 and wall_out - wall_in < 0.08)

	# land
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261121
	var over := 0
	var asked := 0
	var nearest_under := INF
	for k in 3000:
		var a := rng.randf() * TAU
		var p: Vector2 = Hyperion.centre + Vector2(cos(a), sin(a)) * sqrt(rng.randf()) * (Hyperion.reach - 2500.0)
		if not Hyperion.on(p):
			continue
		var q := Vector2(Vector2i(roundi(p.x / 512.0), roundi(p.y / 512.0))) * 512.0
		# the grid is flat between its corners: its highest corner round q against the surface's lowest there
		var grid_top := -INF
		var surface_low := INF
		var whole := true
		for dx in [0.0, 512.0]:
			for dy in [0.0, 512.0]:
				grid_top = maxf(grid_top, land.height_at(q + Vector2(dx, dy)))
				whole = whole and Hyperion.on(q + Vector2(dx, dy))
		if not whole:
			continue      # (a square across the foot: the plain's own corners are no part of this)
		for dx in [0.0, 128.0, 256.0, 384.0, 512.0]:
			for dy in [0.0, 128.0, 256.0, 384.0, 512.0]:
				surface_low = minf(surface_low, Hyperion.land(q + Vector2(dx, dy)))
		asked += 1
		over += int(grid_top > surface_low - 1.0)
		nearest_under = minf(nearest_under, surface_low - grid_top)
	var body: MeshInstance3D = land.hyperion
	var arrays: Array = body.mesh.surface_get_arrays(0) if body != null and body.mesh != null else []
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if not arrays.is_empty() else PackedVector3Array()
	var tris: int = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if not arrays.is_empty() else 0
	var peak := -INF
	var low := INF
	var widest := 0.0
	for vert in verts:
		peak = maxf(peak, vert.y)
		low = minf(low, vert.y)
		if vert.y > -10.0:
			widest = maxf(widest, Vector2(vert.x, vert.z).length())
	var trees := 0
	for key in [Vector2i(floori(Hyperion.centre.x / 8192.0), floori(Hyperion.centre.y / 8192.0)), Vector2i(floori((Hyperion.centre.x + 30000.0) / 8192.0), floori(Hyperion.centre.y / 8192.0))]:
		trees += land.prop_records(key).size()
	_check("the terrain's grid lies under the mountain: of %d squares on it, %d come within a metre of the surface (the nearest %.1f m under); the mountain is one mesh of %d corners and %d triangles, %.0f m at its top and %.0f at its buried foot, %.1f km from its middle at the furthest; nothing stands on it (%d things in two of its tiles)" % [
			asked, over, nearest_under, verts.size(), tris, peak, low, widest / 1000.0, trees],
		asked > 1500 and over == 0 and verts.size() > 10000 and absf(peak - (48000.0 - Hyperion.FACE_SINK)) < 60.0 and low < -30.0 and widest > 50000.0 and trees == 0
			and land.hyperion_summit != null and land.hyperion_summit.get_child_count() == 3 and land.hyperion_summit.get_node("lights") is MeshInstance3D)
	# the road's own land beside the deck: on the mountain's surface 600 m out, on the ramp, the wall and the wall down
	var flank_off := 0.0
	for i in [AT.ramp + 1500, AT.wall + 30, AT.runout - 600, AT.end - 300]:
		for left in [true, false]:
			var pairs: PackedFloat32Array = scenic.row(r, i, left)
			var sgn := 1.0 if left else -1.0
			for m in range(4, pairs.size() / 2 - 2):
				var out: float = pairs[m * 2]
				var q := Vector2(R.px[i] + R.nx[i] * sgn * out, R.py[i] + R.ny[i] * sgn * out)
				flank_off = maxf(flank_off, absf(pairs[m * 2 + 1] - Hyperion.land(q)) - 28.0)      # (its ridges: up to 26 m over the surface)
	_check("the road's own land beside the deck is the mountain's surface (within %.2f m of it and its ridges, from 260 m out to 1,300); no edge of the road is open on it" % [maxf(flank_off, 0.0)],
		flank_off < 1.0 and not scenic.open(r, AT.wall + 30, true) and not scenic.open(r, AT.ramp + 2000, false))

	# named
	var starts := []
	var starts_ok := true
	for entry in UI.INSERTIONS:
		if String(entry[2]).begins_with("SHyperion"):
			var spot: Array = View.start_spot(entry[2])
			var where := int(spot[1]) if spot.size() == 3 else -1
			starts.append("%s: sample %d, %.0f m up" % [entry[1], where, sim.net_height(r, float(where)) if where >= 0 else -1.0])
			starts_ok = starts_ok and spot.size() == 3 and int(spot[0]) == r and ((where > AT.centre and where < AT.lip - Hyperion.STOP_SHORT) or (where < AT.ramp and where > AT.ramp - 200))
	var boards := []
	var braking := 0
	for key in world._signs:
		if not (key is Vector2i) or key.x != r:
			continue
		for spec in world._signs[key]:
			boards.append("%d %s" % [int(spec[0]), String(spec[3][0])])
			braking += int(int(spec[1]) == 1 and int(spec[0]) >= AT.wall and int(spec[0]) < AT.summit)
	boards.sort()
	_check("its signs say %s, route %s; it has %d start points (%s); %d boards stand along it, %d of them in the braking section (%s)" % [
			world.SCENIC_NAMES.get("SHyperion", "?"), world.SCENIC_ROUTES.get("SHyperion", "?"), starts.size(), starts, boards.size(), braking, boards],
		world.SCENIC_NAMES.get("SHyperion", "") == "MOUNT HYPERION" and world.SCENIC_ROUTES.get("SHyperion", "") == "S22" and starts.size() == 2 and starts_ok
			and boards.size() >= 14 and braking >= 4)
	v.free()
	print("HYPERION %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
