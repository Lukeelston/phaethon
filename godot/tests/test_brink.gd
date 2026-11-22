## Over Mount Hyperion's lip, slowly (Luke, 2026-11-22, flying it: "Hyperion looks very cool, but going over
## the edge slowly goes in chunks rather than just smoothly rolling over"; sim/craft_sim.gd deck_sine and
## deck_f, view/craft_view.gd body_place). The craft is held to a speed along the deck from three samples
## short of the lip to three down the wall (the sim's own thrust and drag left out, as test_hyperion.gd holds
## it) and read a 90 Hz frame at a time, as the view steps the sim: 5 or 6 steps of 1/480 s a frame.
##   pitch     at 20, 80 and 250 mph the pitch the views are given changes by no more than 0.022, 0.088 and
##             0.275 degrees a frame (six steps of a steady roll round the lip's 297 m, and 2% over), and
##             from the lip's first sample to its last it turns at one rate, the speed over the radius, within 1%
##   path      the pod moves along its path at the held speed within half a per cent, and is never a centimetre
##             from the circle the lip was designed as, nor from the mountain the views draw
##   seat      from the production cockpit, the same frames: its pitch changes by no more than the same amounts
##             a frame; over any tenth of a second the pilot's eye moves at the held speed within 3% (its place is
##             kept to 4 mm up there, which is a twentieth of a frame's travel at 20 mph: see `lift` in
##             view/craft_view.gd); the left engine is drawn within 15 cm of where it was the frame before, from
##             the cockpit, and stays between 2 and 9 degrees under the nose
##   crest     over the crest at 1,000 mph, the same of the pitch's rate and the pod's speed
##   samples   at its samples the road is where it was: the deck's place there is the sample's own, its height the
##             keys', its pitch theirs; on a road that is no deck road nothing is asked of any of it
##   twins     sim-core.js flies the same runs to the same places (tests/replay/brink_expected.json, recorded by
##             tools/record_brink.js: four runs, the last at 3,000 mph from the crest)
## Prints BRINK PASS.
extends SceneTree

const ViewScript := preload("res://view/craft_view.gd")
const VrScript := preload("res://vr/vr_cockpit.gd")
const Sim := preload("res://sim/craft_sim.gd")
const Hyperion := preload("res://view/hyperion.gd")
const Outlook := preload("res://view/outlook.gd")
const Settings := preload("res://release/game_settings.gd")
const DT := 1.0 / 480.0
const HZ := 90.0
const MPH := 2.236936
# mph: the most the pitch may change in a frame, degrees
const A_FRAME := {20.0: 0.022, 80.0: 0.088, 250.0: 0.275}
var fails := 0
var c
var frames := 0
var _prefs_existed := false
var _prefs_bytes := PackedByteArray()
var _vr_prefs_existed := false
var _vr_prefs_bytes := PackedByteArray()


func _initialize() -> void:
	ViewScript.track_override = "network"
	ViewScript.job_override = "none"
	ViewScript.best_dir = OS.get_user_data_dir().path_join("test_brink_%d_" % Time.get_ticks_usec())
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	_prefs_existed = FileAccess.file_exists(Settings.PREFS)
	if _prefs_existed:
		_prefs_bytes = FileAccess.get_file_as_bytes(Settings.PREFS)
	_vr_prefs_existed = FileAccess.file_exists(VrScript.PREFS)
	if _vr_prefs_existed:
		_vr_prefs_bytes = FileAccess.get_file_as_bytes(VrScript.PREFS)
	Settings.set_driving_partner(false)
	VrScript.camera = "cockpit"
	VrScript._camera_loaded = true
	c = VrScript.new()
	root.add_child(c)
	c.set_process(false)


func _check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	fails += int(not ok)


## Where along its deck the place f over the map is (f itself in a sim from before there was such a thing).
func _deck_f(sim, r: int, f: float) -> float:
	return sim.deck_f(r, f) if sim.has_method("deck_f") else f


## Every body of the craft held to mph along road R's sample i.
func _hold(sim, R, i: int, mph: float) -> void:
	for b in sim.bodies:
		b.vx = mph / MPH * R.tx[i]
		b.vy = mph / MPH * R.ty[i]
		b.w = 0.0
		b.th = atan2(R.ty[i], R.tx[i])


## The sample of road R the pod is over, and how far along its chord over the map (the road is straight there).
func _pod_f(sim, R) -> float:
	var k := maxi(0, int(sim.pod.hint) - 3)
	while k < R.N - 2 and (sim.pod.x - R.px[k + 1]) * R.tx[k] + (sim.pod.y - R.py[k + 1]) * R.ty[k] >= 0.0:
		k += 1
	return float(k) + clampf(((sim.pod.x - R.px[k]) * R.tx[k] + (sim.pod.y - R.py[k]) * R.ty[k]) / R.len[k], 0.0, 1.0)


## A frame's nose (its -Z) against the level, degrees (+ up), in the upright plane road R runs in at sample i.
func _nose(b: Basis, R, i: int) -> float:
	var ahead := -b.z.normalized()
	return rad_to_deg(atan2(ahead.y, ahead.dot(Vector3(R.tx[i], 0.0, -R.ty[i]))))


## The craft held to mph from sample `from` until the pod is past sample `to` of road r, a frame at a time.
## Between samples `first` and `last` (an arc of the road's profile `radius` m round, its top or its foot at
## sample `level`): the most the pitch changes in a frame, the least and the most of its rate and of the
## pod's speed along its path, how far the pod gets from that circle. With `seat`, the cockpit's too.
func _roll(sim, r: int, mph: float, from: int, to: int, first: int, last: int, radius: float, level: int, seat) -> Dictionary:
	var R = sim.roads[r]
	var v := mph / MPH
	var ride: float = sim.P.rideH
	var hands_off := {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "handling": "speed"}
	# the circle's centre: under (or over) the level sample, `radius` from it
	var top: float = sim.net_height(r, float(level))
	var below := signf(sim.net_height(r, float(level)) - sim.net_height(r, float((first + last) / 2)))      # +1: the arc falls away from `level` (a crest, the lip)
	var out := {"frame": 0.0, "rate_lo": INF, "rate_hi": 0.0, "speed_lo": INF, "speed_hi": 0.0, "circle": 0.0, "surface": 0.0, "frames": 0, "on": true,
		"seat_frame": 0.0, "eye_lo": INF, "eye_hi": 0.0, "engine_step": 0.0, "engine_lo": INF, "engine_hi": -INF}
	sim.respawn_on(r, from, 1)
	_hold(sim, R, from, mph)
	if seat != null:
		seat._ride.clear()
	var acc := 0.0
	var f_was := float(from)
	var pitch_was: float = rad_to_deg(sim.deck_pitch(sim.pod))
	# (places as doubles: a Vector2 keeps a height of 48 km to 4 mm, a third of a step's fall at 20 mph)
	var plan_was: float = (sim.pod.x - R.px[level]) * R.tx[level] + (sim.pod.y - R.py[level]) * R.ty[level]
	var z_was: float = sim.pod.z
	var seat_was := NAN
	var eyes := []      # the eye's last places: [m along the road's line, m up, s]
	var clock := 0.0
	var engine_was := Vector3.INF
	var guard := 0
	while guard < 40000 and _pod_f(sim, R) < float(to):
		guard += 1
		acc += 1.0 / HZ
		var steps := 0
		while acc >= DT:
			sim.step(hands_off, DT)
			_hold(sim, R, from, mph)
			sim.events.clear()
			acc -= DT
			steps += 1
		var f := _pod_f(sim, R)
		var pitch: float = rad_to_deg(sim.deck_pitch(sim.pod))
		var plan: float = (sim.pod.x - R.px[level]) * R.tx[level] + (sim.pod.y - R.py[level]) * R.ty[level]
		var z: float = sim.pod.z
		clock += steps * DT
		var inside: bool = f_was > float(first) and f < float(last)
		out.on = out.on and not sim.pod.off_road and int(sim.pod.path) == r
		out.frame = maxf(out.frame, absf(pitch - pitch_was))
		# (the designer's own surface, as the views draw the mountain: square to it)
		out.surface = maxf(out.surface, absf(float(sim.pod.z) - ride - Hyperion.height_xy(sim.pod.x, sim.pod.y)) * cos(deg_to_rad(pitch)))
		if inside:
			var rate := absf(pitch - pitch_was) / (steps * DT)
			out.rate_lo = minf(out.rate_lo, rate)
			out.rate_hi = maxf(out.rate_hi, rate)
			var speed := sqrt((plan - plan_was) * (plan - plan_was) + (z - z_was) * (z - z_was)) / (steps * DT)
			out.speed_lo = minf(out.speed_lo, speed)
			out.speed_hi = maxf(out.speed_hi, speed)
			var over_centre: float = z - ride - (top - below * radius)
			out.circle = maxf(out.circle, absf(sqrt(plan * plan + over_centre * over_centre) - radius))
			out.frames += 1
		if seat != null:
			seat._follow_origin()
			seat.craft.sync(sim, seat.inp, 1.0 / HZ)
			seat._ride.clear()      # (no easing: what is read is where the cockpit is asked to be, this frame)
			seat._place_camera(1.0)
			var rig: Transform3D = seat.rig.transform
			var nose := _nose(rig.basis, R, level)
			var eye3: Vector3 = rig * VrScript.EYE
			eyes.append([(float(seat.org_x) + float(eye3.x) - R.px[level]) * R.tx[level] + (float(seat.org_y) - float(eye3.z) - R.py[level]) * R.ty[level], float(eye3.y), clock])
			var engine: Vector3 = rig.affine_inverse() * (seat.craft.engines[0] as Node3D).position
			if not is_nan(seat_was):
				out.seat_frame = maxf(out.seat_frame, absf(nose - seat_was))
				if inside and eyes.size() > 9:      # (over nine frames, a tenth of a second: see the header)
					var then: Array = eyes[eyes.size() - 10]
					var now: Array = eyes[eyes.size() - 1]
					var eye_speed: float = sqrt(pow(float(now[0]) - float(then[0]), 2.0) + pow(float(now[1]) - float(then[1]), 2.0)) / (float(now[2]) - float(then[2]))
					out.eye_lo = minf(out.eye_lo, eye_speed)
					out.eye_hi = maxf(out.eye_hi, eye_speed)
				out.engine_step = maxf(out.engine_step, (engine - engine_was).length())
				var over := rad_to_deg(atan2(engine.y - VrScript.EYE.y, -(engine.z - VrScript.EYE.z)))
				out.engine_lo = minf(out.engine_lo, over)
				out.engine_hi = maxf(out.engine_hi, over)
			seat_was = nose
			engine_was = engine
		f_was = f
		pitch_was = pitch
		plan_was = plan
		z_was = z
	out["ended"] = pitch_was
	return out


func _process(_d: float) -> bool:
	frames += 1
	if frames != 3:
		return false
	var sim = c.sim
	if not Hyperion.ready:
		_check("the road SHyperion is on the Network, with its mountain", false)
		_finish()
		return false
	var r: int = Hyperion.road
	var R = sim.roads[r]
	var step: float = sim.NET_STEP
	var lip: int = int(Hyperion.at.lip)
	var drop: int = int(Hyperion.at.drop)
	var crest: int = int(Hyperion.at.crest)
	var summit: int = int(Hyperion.at.summit)
	var lip_radius: float = float(drop - lip) * step / absf(asin(clampf(sim.net_slope(r, float(drop)) / step, -1.0, 1.0)))
	var crest_radius: float = float(summit - crest) * step / absf(asin(clampf(sim.net_slope(r, float(crest)) / step, -1.0, 1.0)))

	# pitch, path, seat
	for mph in [20.0, 80.0, 250.0]:
		var v: float = mph / MPH
		var steady := rad_to_deg(v / lip_radius)
		var S := _roll(sim, r, mph, lip - 3, drop + 3, lip, drop, lip_radius, lip, c)
		var allowed: float = A_FRAME[mph]
		_check("pitch: over the lip at %.0f mph (a steady roll round its %.1f m is %.3f degrees a second, %.4f in a frame of six steps) the pitch the views are given changes by %.4f degrees a frame at most (%.3f allowed), and from the lip's first sample to its last it turns %.3f to %.3f degrees a second (%d frames); it ends %.2f degrees down" % [
				mph, lip_radius, steady, steady * 6.0 * DT, S.frame, allowed, S.rate_lo, S.rate_hi, S.frames, -float(S.ended)],
			S.on and S.frame <= allowed and S.rate_lo > 0.99 * steady and S.rate_hi < 1.01 * steady and S.frames > 100 and float(S.ended) < -87.5)
		_check("path: at %.0f mph (%.3f m/s) the pod moves %.3f to %.3f m/s along its path; it is %.4f m from the lip's circle at most, %.4f m from the mountain's own surface" % [
				mph, v, S.speed_lo, S.speed_hi, S.circle, S.surface],
			S.speed_lo > 0.995 * v and S.speed_hi < 1.005 * v and S.circle < 0.01 and S.surface < 0.01)
		_check("seat: at %.0f mph the cockpit's pitch changes by %.4f degrees a frame at most (%.3f allowed); over any tenth of a second the pilot's eye moves %.2f to %.2f m/s along its path; the left engine is drawn %.3f m at most from where it was the frame before, from the cockpit, and stays %.2f to %.2f degrees under the nose" % [
				mph, S.seat_frame, allowed, S.eye_lo, S.eye_hi, S.engine_step, -float(S.engine_hi), -float(S.engine_lo)],
			S.seat_frame <= allowed and S.eye_lo > 0.97 * v and S.eye_hi < 1.03 * v and S.engine_step < 0.15 and float(S.engine_hi) < -2.0 and float(S.engine_lo) > -9.0)

	# crest
	var fast := 1000.0
	var C := _roll(sim, r, fast, crest - 3, summit + 3, crest, summit, crest_radius, summit, null)
	var crest_steady := rad_to_deg(fast / MPH / crest_radius)
	_check("crest: over the crest at %.0f mph (its %.0f m round: %.3f degrees a second) the pitch turns %.3f to %.3f degrees a second and the pod moves %.2f to %.2f m/s along its path (%.2f held), %.4f m from the crest's circle at most, %.4f from the mountain's surface" % [
			fast, crest_radius, crest_steady, C.rate_lo, C.rate_hi, C.speed_lo, C.speed_hi, fast / MPH, C.circle, C.surface],
		C.on and C.rate_lo > 0.99 * crest_steady and C.rate_hi < 1.01 * crest_steady and C.speed_lo > 0.995 * fast / MPH and C.speed_hi < 1.005 * fast / MPH and C.circle < 0.01 and C.surface < 0.01)

	# samples
	var moved := 0
	var heights := 0
	var pitches := 0
	for i in R.N:
		moved += int(_deck_f(sim, r, float(i)) != float(i))
		heights += int(sim.road_h(r, float(i)) != sim.net_height(r, float(i)))
		pitches += int(sim.deck_sine(r, float(i)) != clampf(sim.net_slope(r, float(i)) / step, -0.9999, 0.9999))
	# ... and between them, on the lip: the place along the deck runs on from sample to sample without a step or a turn back
	var turned_back := 0
	var f := float(lip - 1)
	var was := _deck_f(sim, r, f)
	while f < float(drop + 1):
		f += 0.001
		var now := _deck_f(sim, r, f)
		turned_back += int(now < was or now - was > 0.01)
		was = now
	var e3 := -1
	for k in sim.roads.size():
		if String(sim.roads[k].name) == "E3":
			e3 = k
	var half_way: float = _deck_f(sim, r, float(drop) - 0.5) - float(drop - 1)
	_check("samples: at its %d samples the road is where it was (%d places along the deck moved, %d heights, %d pitches); half way over the map across the lip's last sample is %.3f of the way along its deck; over the lip the deck's place runs on with the map's (%d steps back or jumps in %d places); on E3 nothing is asked (its place %.2f, its pitch %.1f)" % [
			R.N, moved, heights, pitches, half_way, turned_back, roundi(float(drop - lip + 2) / 0.001), _deck_f(sim, e3, 9000.37), sim.deck_sine(e3, 9000.37)],
		moved == 0 and heights == 0 and pitches == 0 and turned_back == 0 and half_way > 0.3 and half_way < 0.45 and _deck_f(sim, e3, 9000.37) == 9000.37 and sim.deck_sine(e3, 9000.37) == 0.0
			and sim.road_h(e3, 9000.37) == sim.net_height(e3, 9000.37))

	# twins
	var X: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/brink_expected.json"))
	var s = Sim.new({"track": "network", "handling": "speed"})
	var hands_off := {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "handling": "speed"}
	var told := []
	var twins_ok: bool = int(X.road) == r and int(X.lip) == lip and int(X.drop) == drop and int(X.crest) == crest and (X.runs as Array).size() == 4
	for run in X.runs:
		var from := int(run.from)
		s.respawn_on(r, from, 1)
		_hold(s, s.roads[r], from, float(run.mph))
		var worst := 0.0
		var worst_pitch := 0.0
		var k := 0
		var stopped := -1
		var samples: Array = run.samples
		for n in range(1, int(run.steps) + 1):
			s.step(hands_off, DT)
			_hold(s, s.roads[r], from, float(run.mph))
			s.events.clear()
			if stopped < 0 and s._road_f(s.pod) >= float(run.to):
				stopped = n
			if k < samples.size() and int(samples[k][0]) == n:
				var want: Array = samples[k]
				worst = maxf(worst, Vector3(s.pod.x - float(want[1]), s.pod.y - float(want[2]), s.pod.z - float(want[3])).length())
				worst_pitch = maxf(worst_pitch, absf(float(s.deck_pitch(s.pod)) - float(want[4])))
				k += 1
		var end: Array = run.end
		worst = maxf(worst, Vector3(s.pod.x - float(end[1]), s.pod.y - float(end[2]), s.pod.z - float(end[3])).length())
		told.append("%s (%.0f mph, %d steps, %d places): %.6f mm and %.9f degrees apart at most, past sample %d at step %d" % [run.tag, float(run.mph), int(run.steps), k, worst * 1000.0, rad_to_deg(worst_pitch), int(run.to), stopped])
		twins_ok = twins_ok and k == samples.size() and worst < 1e-6 and worst_pitch < 1e-9 and stopped == int(run.steps)
	_check("twins: sim-core.js's runs flown again here: %s" % ["; ".join(told)], twins_ok)
	_finish()
	return false


func _finish() -> void:
	c.queue_free()
	if _prefs_existed:
		var prefs := FileAccess.open(Settings.PREFS, FileAccess.WRITE)
		prefs.store_buffer(_prefs_bytes)
		prefs.close()
	else:
		DirAccess.remove_absolute(Settings.PREFS)
	if _vr_prefs_existed:
		var prefs := FileAccess.open(VrScript.PREFS, FileAccess.WRITE)
		prefs.store_buffer(_vr_prefs_bytes)
		prefs.close()
	else:
		DirAccess.remove_absolute(VrScript.PREFS)
	var restored := FileAccess.file_exists(VrScript.PREFS) == _vr_prefs_existed and (not _vr_prefs_existed or FileAccess.get_file_as_bytes(VrScript.PREFS) == _vr_prefs_bytes)
	_check("the VR preferences are as they were found", restored)
	DirAccess.remove_absolute(ViewScript.best_dir + "network.json")
	print("BRINK %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
