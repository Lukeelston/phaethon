## The Network's shafts (the vertical turnarounds at the highways' ends) flown hands off (Luke: "Fix
## vertical turnarounds so the vehicle can enter and exit straight with no sideways or spin - right now,
## going slow makes the vehicle list, going fast makes it shift slightly"). The sims are flat: a shaft is
## a paperclip in plan whose bulb turns the craft with the road. The bulb used to turn each body by the
## road under itself, which bent the craft along the plan's arc: its cables steered it, it crept across
## to the wall and came out askew. It is carried whole now (sim/craft_sim.gd `carried`, sim-core.js).
## Both levers are always the same (a speed hold, nothing steering).
##   shape    the shaft's frame points the way its own centreline goes, at every sample of every shaft
##   fast     every shaft, both ways (up its way out, and up its way back), its whole length at 4,000 mph:
##            between the feet the pod stays within CREEP m of its place across the road and YAW degrees
##            of the road's own direction, touches no wall, is turned half a turn exactly, and 600 m past
##            the far foot it has not moved DRIFT m across. Two more from 60 m off the road's middle
##   slower   every shaft, both ways, at 900 and at 300 mph, through each place the plan changes (the
##            foot, the bulb's two changes of hand, its end) and out past the far foot: the same limits
##            (a whole shaft at 300 mph is 100,000 sim steps: the shortest is flown whole, below)
##   seen     through the view, on the shortest shaft: its whole length at 300 mph and, both ways, at
##            4,000. The craft model's lean (the "list") stays under LEAN degrees on every body, and the
##            pod as drawn stands within DRAWN degrees of the shaft's own frame under it
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_shaft_straight.gd -- --mute [--only=TE3-]
## Prints SHAFT STRAIGHT PASS. (tools/shaft_straight.js flies all of it whole in the JS sim, both handlings.)
extends SceneTree

const ViewScript := preload("res://view/craft_view.gd")
const SimScript := preload("res://sim/craft_sim.gd")
const Settings := preload("res://release/game_settings.gd")
const MPH := 2.236936
const DT := 1.0 / 480.0
const FAST := 4000.0
const SLOWER := [900.0, 300.0]
const LEAD := 40          # samples of flat leg flown before the foot (1 km)
const WINDOW := 4         # samples each side of a change of the plan, flown at the slower speeds (the craft is one sample long)
const CREEP := 1.0        # m across the road between the feet (tonight's sim: 88 to 96, the wall)
const OFF_CREEP := 1.5    # ... from 60 m off its middle (measured 0.6)
const YAW := 0.03         # degrees off the road's own direction, the pod and the pair (tonight's: 1.6 to 9)
const DRIFT := 0.15       # m across in the 600 m after the far foot (tonight's: up to 44)
const LEAN := 0.2         # degrees of bank on any body through the view (tonight's: 11 to 62)
const DRAWN := 0.05       # degrees between the pod as drawn and the shaft's frame under it (tonight's: 1.6 and more)
var fails := 0
var passed := 0
var v
var frames := 0
var only := ""
var shafts: Array = []
var steps := 0
var _prefs_existed := false
var _prefs_bytes := PackedByteArray()


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.get_slice("=", 1)
	ViewScript.track_override = "network"
	ViewScript.job_override = "none"
	ViewScript.best_dir = OS.get_user_data_dir().path_join("test_shaft_straight_%d_" % Time.get_ticks_usec())
	_prefs_existed = FileAccess.file_exists(Settings.PREFS)
	if _prefs_existed:
		_prefs_bytes = FileAccess.get_file_as_bytes(Settings.PREFS)
	Settings.set_driving_partner(false)
	v = ViewScript.new()
	root.add_child(v)


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1


func _process(_d: float) -> bool:
	frames += 1
	if frames != 3:
		return false
	v.set_process(false)
	for sh in v.sim.shafts:
		if only == "" or String(v.sim.roads[int(sh[0])].name) == only:
			shafts.append(sh)
	var began := Time.get_ticks_msec()
	_frames_follow()
	_seen()
	_fast()
	_slower()
	print("  (%d shafts, %d sim steps, %.0f s)" % [shafts.size(), steps, (Time.get_ticks_msec() - began) / 1000.0])
	v.queue_free()
	if _prefs_existed:
		var f := FileAccess.open(Settings.PREFS, FileAccess.WRITE)
		f.store_buffer(_prefs_bytes)
		f.close()
	elif FileAccess.file_exists(Settings.PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PREFS))
	var good := fails == 0 and passed > 0
	print("SHAFT STRAIGHT ", "PASS (%d checks)" % passed if good else "FAIL (%d failed, %d passed)" % [fails, passed])
	quit(0 if good else 1)
	return true


## The road's own direction (radians, the way it is flown) u of the way along sample i's chord: a chord's
## direction is the arc's at its middle.
static func road_heading(R, i: int, u: float, dir: int) -> float:
	return atan2(R.ty[i] * dir, R.tx[i] * dir) + (u - 0.5) * R.kap[i] * R.len[i]


static func _deg_off(a: float, b: float) -> float:
	return rad_to_deg(SimScript.wrap_angle(a - b))


## Where the plan changes along a shaft: its foot, the bulb's two changes of hand, the bulb's end.
static func changes(s, sh: Array) -> Array:
	var R = s.roads[int(sh[0])]
	var out := []
	for i in range(int(sh[1]), int(sh[2]) + 1):
		if signf(R.kap[i]) != signf(R.kap[i - 1]):
			out.append(i)
	return out


## One flight, hands off: sim `s` put on shaft `sh`'s road going `dir` (1 up its way out, -1 up its way
## back) at `mph` with both levers the same. From LEAD samples before the near foot, or from sample
## `from_i` (anywhere: it is set down along the road's own direction there); to 600 m past the far foot,
## or to sample `until_f`. `lat0`: set that many m left of the road's middle just before the foot (or
## just up it on the way back, where there is no flat before the foot). `each`, if given, is called
## after every 8 steps with the pod's fractional sample.
func fly(s, sh: Array, dir: int, mph: float, lat0 := 0.0, from_i := -1, until_f := -1.0, each := Callable()) -> Dictionary:
	var r := int(sh[0])
	var i_up := int(sh[1])
	var i_dn := int(sh[2])
	var R = s.roads[r]
	var near := i_up if dir > 0 else i_dn
	var far := i_dn if dir > 0 else i_up
	var i0: int = from_i if from_i >= 0 else (maxi(80, i_up - LEAD) if dir > 0 else mini(R.N - 9, i_dn + LEAD))
	s.respawn_on(r, i0, dir)
	# (set down along its sample's chord, which round the bulb is half the sample's turn off the road's
	# direction at the sample itself: turned to that, about the pod)
	var th0 := road_heading(R, i0, 0.0, dir)
	var turn0: float = SimScript.wrap_angle(th0 - s.pod.th)
	var v0 := mph / MPH
	for b in s.bodies:
		var rel := Vector2(b.x - s.pod.x, b.y - s.pod.y).rotated(turn0)
		b.x = s.pod.x + rel.x
		b.y = s.pod.y + rel.y
		b.th += turn0
		b.vx = v0 * cos(th0)
		b.vy = v0 * sin(th0)
	var turn_from = s.get("carry_turn")
	var out := {"done": false, "creep": 0.0, "yaw": 0.0, "yaw_out": 0.0, "drift_out": 0.0, "contacts": 0, "t": 0.0, "turned": NAN}
	var flat := far if dir > 0 else far - 1          # the leg it comes out along: the flat samples beyond the far foot
	var ax: float = R.px[far]
	var ay: float = R.py[far]
	var atx: float = R.tx[flat] * dir
	var aty: float = R.ty[flat] * dir
	var th_out := atan2(aty, atx)
	var lat_ref := INF
	var lat_foot := INF
	var integ := 0.0
	var hint := i0
	var shifted := lat0 == 0.0 or from_i >= 0
	var steps_max := int((60.0 + float(absi(i_dn - i_up) + 2 * LEAD) * 24.0 / maxf(40.0, 0.5 * v0)) * 480.0)
	var inp := {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
	for k in steps_max:
		var P = s.pod
		var spd: float = sqrt(P.vx * P.vx + P.vy * P.vy)
		var err := (v0 - spd) / maxf(20.0, v0)       # the speed hold: both levers the same, always
		integ = clampf(integ + err * DT * 0.8, -1.0, 1.0)
		var thr := clampf(0.25 + 4.0 * err + integ, 0.0, 0.87)
		inp.thrL = thr
		inp.thrR = thr
		s.step(inp, DT)
		steps += 1
		for e in s.events:
			if e.type == "scrape" or e.type == "hit":
				out.contacts += 1
		s.events.clear()
		out.t += DT
		s._nearest_on(r, P.x, P.y, hint, 14)
		hint = s._n_i
		var u: float = clampf(s._n_t, 0.0, 1.0)
		var f: float = float(hint) + u
		var lat: float = s._n_lat * dir
		if not shifted and (f >= float(near - 30) if dir > 0 else f <= float(near - 3)):
			for b in s.bodies:
				b.x += R.nx[hint] * dir * lat0
				b.y += R.ny[hint] * dir * lat0
			shifted = true
			continue
		var past: float = (P.x - ax) * atx + (P.y - ay) * aty      # m beyond the far foot, along the leg
		var between: bool = f < float(far) if dir > 0 else f > float(far)
		if from_i < 0:
			between = between and (f >= float(near - 20) if dir > 0 else f <= float(near - 4))
		if between and shifted:
			if lat_ref == INF:
				lat_ref = lat
			var th_road := road_heading(R, hint, u, dir)
			out.creep = maxf(out.creep, absf(lat - lat_ref))
			out.yaw = maxf(out.yaw, absf(_deg_off(P.th, th_road)))
			out.yaw = maxf(out.yaw, absf(_deg_off(atan2(s.eR.x - s.eL.x, -(s.eR.y - s.eL.y)), th_road)))   # the pair: forward is a quarter turn from L to R
		elif lat_ref != INF and past >= 0.0 and past < 5000.0:
			var across: float = -(P.x - ax) * aty + (P.y - ay) * atx
			if lat_foot == INF:
				lat_foot = across
				out.yaw_out = absf(_deg_off(P.th, th_out))
				var turn_to = s.get("carry_turn")
				if turn_to != null and turn_from != null:
					out.turned = float(turn_to) - float(turn_from)
			out.drift_out = absf(across - lat_foot)
			if past >= 600.0:
				out.done = true
				break
		if each.is_valid() and k % 8 == 7:
			each.call(f)
		if until_f >= 0.0 and (f >= until_f if dir > 0 else f <= until_f):
			out.done = true
			break
		if P.off_road:
			break
	return out


func _name(sh: Array) -> String:
	return v.sim.roads[int(sh[0])].name


## Every shaft both ways, its whole length at 4,000 mph; and two of them from 60 m off the road's middle, a side each.
func _fast() -> void:
	var s = v.sim
	var worst := {"creep": 0.0, "yaw": 0.0, "yaw_out": 0.0, "drift_out": 0.0, "turn": 0.0}
	var contacts := 0
	var through := 0
	var n := 0
	var bad := []
	for sh in shafts:
		for dir in [1, -1]:
			var o := fly(s, sh, dir, FAST)
			n += 1
			through += int(o.done)
			contacts += int(o.contacts)
			for key in ["creep", "yaw", "yaw_out", "drift_out"]:
				worst[key] = maxf(worst[key], o[key])
			var off_half: float = INF if is_nan(float(o.turned)) else absf(absf(float(o.turned)) - PI)
			worst.turn = maxf(worst.turn, off_half)
			if not o.done or o.creep > CREEP or o.yaw > YAW or o.yaw_out > YAW or o.drift_out > DRIFT or o.contacts > 0 or off_half > 1e-3:
				bad.append("%s %s (creep %.1f m, yaw %.2f, out %.2f deg and %.1f m, %d contacts)" % [_name(sh), "out" if dir > 0 else "back", o.creep, o.yaw, o.yaw_out, o.drift_out, o.contacts])
	_check("fast: every shaft both ways, its whole length at 4,000 mph, hands off (%d flights, %d through): across the road it moves %.2f m at most (limit %.1f); the pod and the pair stay within %.4f deg of the road's direction (limit %.2f); %d wall contacts; turned half a turn to within %.6f rad; out of it %.4f deg off the leg and %.3f m across in the next 600 m (limit %.2f)%s" % [
		n, through, worst.creep, CREEP, worst.yaw, YAW, contacts, worst.turn, worst.yaw_out, worst.drift_out, DRIFT, "" if bad.is_empty() else "; wrong: " + "; ".join(bad.slice(0, 5))],
		n == 2 * shafts.size() and bad.is_empty())
	var off := {"creep": 0.0, "yaw": 0.0, "yaw_out": 0.0, "drift_out": 0.0}
	var off_ok := true
	var off_n := 0
	for k in mini(2, shafts.size()):
		var dir := 1 if k % 2 == 0 else -1
		var side := 60.0 if k % 2 == 0 else -60.0
		var o := fly(s, shafts[(k * 7 + 3) % shafts.size()], dir, FAST, side)
		off_n += 1
		for key in off:
			off[key] = maxf(off[key], o[key])
		off_ok = off_ok and o.done and o.creep <= OFF_CREEP and o.yaw <= YAW and o.yaw_out <= YAW and o.drift_out <= DRIFT and o.contacts == 0
	_check("fast: from 60 m off the road's middle, either side (%d flights): it keeps its lane to %.2f m (limit %.1f) and %.4f deg, and comes out %.4f deg off the leg, %.3f m across in 600 m" % [
		off_n, off.creep, OFF_CREEP, off.yaw, off.yaw_out, off.drift_out], off_ok)


## Every shaft both ways at the slower speeds, through each place the plan changes and out past the far foot.
func _slower() -> void:
	var s = v.sim
	for mph in SLOWER:
		var worst := {"creep": 0.0, "yaw": 0.0, "yaw_out": 0.0, "drift_out": 0.0}
		var contacts := 0
		var n := 0
		var bad := []
		for sh in shafts:
			var at := changes(s, sh)
			for dir in [1, -1]:
				var legs := []      # [from sample, to sample (-1: 600 m past the far foot)]
				if dir > 0:
					for c in at:
						legs.append([int(c) - WINDOW, float(int(c) + WINDOW)])
					legs.append([int(sh[2]) - WINDOW, -1.0])
				else:
					legs.append([int(sh[2]) + WINDOW, float(int(sh[2]) - WINDOW)])
					for k in range(at.size() - 1, 0, -1):
						legs.append([int(at[k]) + WINDOW, float(int(at[k]) - WINDOW)])
					legs.append([int(at[0]) + WINDOW, -1.0])
				for leg in legs:
					var o := fly(s, sh, dir, mph, 0.0, int(leg[0]), float(leg[1]))
					n += 1
					contacts += int(o.contacts)
					for key in worst:
						worst[key] = maxf(worst[key], o[key])
					if not o.done or o.creep > 0.1 or o.yaw > YAW or o.yaw_out > YAW or o.drift_out > DRIFT or o.contacts > 0:
						bad.append("%s %s from %d (%.2f m, %.2f deg, out %.2f deg)" % [_name(sh), "out" if dir > 0 else "back", int(leg[0]), o.creep, o.yaw, o.yaw_out])
		_check("slower: every shaft both ways at %d mph through its foot, its bulb's changes of hand and end, and out past its far foot (%d passes): the pod and the pair stay within %.4f deg of the road's direction (limit %.2f) and %.3f m of their place across it (limit 0.1); %d wall contacts; out of it %.4f deg off the leg and %.3f m across in 600 m (limit %.2f)%s" % [
			int(mph), n, worst.yaw, YAW, worst.creep, contacts, worst.yaw_out, worst.drift_out, DRIFT, "" if bad.is_empty() else "; wrong: " + "; ".join(bad.slice(0, 5))],
			n == 10 * shafts.size() and bad.is_empty())


## The world's shape: at every sample of every shaft the frame's forward is the way the centreline
## itself goes (the road crosses the highway's line on its way over the top, 200 m in all: with the
## frame's forward the shape's alone, the lanes ran across the nose of a craft flying dead straight),
## and the frame is still a square, right-handed one. (Not at the four samples where the shape itself
## changes, a straight to an arc: the way between two chords' middles is not the direction there.)
func _frames_follow() -> void:
	var S = v.network_world.shaft
	var worst := 0.0
	var skew := 0.0
	var where := ""
	for sh in v.sim.shafts:
		var r := int(sh[0])
		var q := PI * float(sh[3]) / 2.0
		var joints := [q, q + float(sh[4]), 3.0 * q + float(sh[4]), 3.0 * q + 2.0 * float(sh[4])]
		var d := 0.0
		for i in range(int(sh[1]), int(sh[2]) - 1):
			var here := d
			d += v.sim.roads[r].len[i]
			var at_joint := false
			for j in joints:
				at_joint = at_joint or absf(here - float(j)) < 36.0
			if i == int(sh[1]) or at_joint:
				continue
			var a: Array = S.at(r, float(i) - 0.5)
			var b: Array = S.at(r, float(i) + 0.5)
			var way := Vector3(float(b[0]) - float(a[0]), float(b[2]) - float(a[2]), -(float(b[1]) - float(a[1]))).normalized()
			var A: Array = S.at(r, float(i))
			var t: Vector3 = A[3]
			var l: Vector3 = A[4]
			var n: Vector3 = A[5]
			var off := rad_to_deg(way.angle_to(t))
			if off > worst:
				worst = off
				where = "%s sample %d" % [v.sim.roads[r].name, i]
			skew = maxf(skew, maxf(absf(t.dot(l)), maxf(absf(t.dot(n)), (t.cross(l) - n).length())))
	_check("shape: every shaft's frame points the way its own centreline goes, to %.3f deg at worst (%s; limit 0.05; tonight's shape: 0.4 to 0.8 over the top), and is square and right-handed to %.5f" % [worst, where, skew],
		worst <= 0.05 and skew < 1e-3)


## Through the view: the lean the craft model gives each body, and the pod as drawn against the shaft's
## own frame under it.
func _seen() -> void:
	var sim = v.sim
	var sh: Array = []
	for q in shafts:      # the shortest
		if sh.is_empty() or int(q[2]) - int(q[1]) < int(sh[2]) - int(sh[1]):
			sh = q
	var r := int(sh[0])
	var flights := [
		["its whole length, out, at 300 mph", 1, 300.0],
		["its whole length, out, at 4,000 mph", 1, FAST],
		["its whole length, back, at 4,000 mph", -1, FAST],
	]
	for fl in flights:
		var st := {"lean": 0.0, "yaw": 0.0, "roll": 0.0, "pitch": 0.0, "n": 0}
		v.craft._prev_v.clear()      # (the lean's own memory: a new flight is not a turn)
		for k in 3:
			v.craft.bank[k] = 0.0
			v.craft._lat[k] = 0.0
		var o := fly(sim, sh, int(fl[1]), float(fl[2]), 0.0, -1, -1.0, func(f: float):
			v.inp = {"thrL": 0.5, "thrR": 0.5, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
			v._follow_origin()
			v.craft.sync(sim, v.inp, 8.0 * DT)
			if not v.network_world.shaft.on(r, f):
				return
			st.n += 1
			for k in 3:
				st.lean = maxf(st.lean, absf(rad_to_deg(v.craft.bank[k])))
			var rel: Basis = v.network_world.shaft.frame(r, f).inverse() * v.craft.pod.basis.orthonormalized()
			if int(fl[1]) < 0:       # flown down the samples: the frame's forward is behind
				rel = Basis(Vector3.UP, PI) * rel
			var fwd := rel * Vector3.FORWARD
			var up := rel * Vector3.UP
			st.yaw = maxf(st.yaw, absf(rad_to_deg(atan2(-fwd.x, -fwd.z))))
			st.pitch = maxf(st.pitch, absf(rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)))))
			st.roll = maxf(st.roll, absf(rad_to_deg(atan2(up.x, up.y)))))
		_check("seen, %s %s: over %d frames the craft leans %.3f deg at most (limit %.1f), and the pod is drawn %.4f deg in yaw, %.4f in roll and %.4f in pitch off the shaft's frame (limit %.2f); the sim's own %.2f m across and %.4f deg, %d wall contacts" % [
			_name(sh), fl[0], st.n, st.lean, LEAN, st.yaw, st.roll, st.pitch, DRAWN, o.creep, o.yaw, o.contacts],
			o.done and st.n > 200 and st.lean <= LEAN and st.yaw <= DRAWN and st.roll <= LEAN and st.pitch <= DRAWN and o.creep <= CREEP and o.yaw <= YAW and o.contacts == 0)
