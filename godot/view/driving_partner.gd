## The driving partner (Luke: "a 'driving partner', that stays around your speed and just generally does
## what you do - i found it interesting to see a stable reference point at high speed - kind of trippy";
## the main menu's DRIVING PARTNER, or --partner). A second craft holds formation, then occasionally
## passes, crosses well ahead and rejoins on the other side. Road-relative stations follow bends;
## swept gap checks keep it clear of the player and traffic. Narrow roads, jumps and shaft carry
## retain quiet formation. It remains visual only: nothing to hit and no sim parity change.
##   var p := DrivingPartner.new(); add_child(p); p.build(view)
##   p.update(delta)   every frame, after the camera
extends Node3D

const CraftModelScript := preload("res://view/craft_model.gd")
const Kit := preload("res://view/mesh_kit.gd")
const WING := 48.0          # m off your centreline
const AHEAD := 14.0         # m ahead of the pod: out of the cockpit's left or right, level with the cables
const SNAP := 1500.0        # m: further off than this (a restart) it's just put there
const MARGIN := 62.0        # m kept from a road's walls (clear of the edges' ramps)
const MIN_WING := 22.0      # m: however narrow the road, this far off you
const TEAL := Color(0.25, 0.85, 0.8)

var view
var sim
var x := 0.0
var y := 0.0
var z := 0.0
var th := 0.0
var lag := Vector2.ZERO     # the velocity it's flying
var side := 1.0             # +1 your left, -1 your right
var t := 0.0
var placed := false
var bank := 0.0
var maneuver := "formation"
var maneuver_time := 0.0
var _ahead := AHEAD
var _offset := WING
var _last_path := -999
var _last_lateral := 0.0
var _last_direction := 1.0
var _engines: Array[Node3D] = []
var _pod: MeshInstance3D
var _cables: Array[MeshInstance3D] = []
var _flames: Array[MeshInstance3D] = []
var _flame_mat: StandardMaterial3D


func build(v) -> void:
	view = v
	sim = v.sim
	name = "driving_partner"
	var finish := Kit.polished(0.55, 0.38)
	finish.albedo_color = TEAL
	var lit := Kit.vertex_colors(true)
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.albedo_color = Color(1.0, 0.6, 0.25)
	var cable_mat := StandardMaterial3D.new()
	cable_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cable_mat.albedo_color = TEAL
	for k in 2:
		var out := -1.0 if k == 0 else 1.0
		var eng := Node3D.new()
		add_child(eng)
		_engines.append(eng)
		var body := MeshInstance3D.new()
		body.mesh = CraftModelScript._engine_body(out)
		body.material_override = finish
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eng.add_child(body)
		var lights := MeshInstance3D.new()
		lights.mesh = CraftModelScript._engine_lights(out)
		lights.material_override = lit
		lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eng.add_child(lights)
		var fl := MeshInstance3D.new()   # the plume: as long as you're pushing
		fl.mesh = Kit.box(Vector3(CraftModelScript.ENG_W - 0.6, 0.4, 1.0))
		fl.material_override = _flame_mat
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eng.add_child(fl)
		_flames.append(fl)
		var c := MeshInstance3D.new()
		c.mesh = Kit.box(Vector3(0.12, 0.12, 1.0))
		c.material_override = cable_mat
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(c)
		_cables.append(c)
	_pod = MeshInstance3D.new()
	_pod.mesh = CraftModelScript.pod_hull()
	_pod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pod)


## [room to your left, to your right] on your road (m, off your centreline, inside MARGIN of its walls).
func _room() -> Vector2:
	var P = sim.pod
	if P.off_road or sim.kind == "range":
		return Vector2(WING * 2.0, WING * 2.0)
	var w := 0.0
	var lat := 0.0
	var normal := Vector2.ZERO
	if sim.kind == "network":
		var R = sim.roads[P.path]
		var i: int = clampi(P.hint, 0, R.N - 1)
		w = R.w[i]
		normal = Vector2(R.nx[i], R.ny[i])
		lat = (P.x - R.px[i]) * R.nx[i] + (P.y - R.py[i]) * R.ny[i]
	else:
		if P.path > 0:
			var B = sim.branches[P.path - 1]
			var i: int = clampi(P.hint, 0, B.N - 1)
			w = B.w[i]
			normal = Vector2(B.nx[i], B.ny[i])
			lat = (P.x - B.px[i]) * B.nx[i] + (P.y - B.py[i]) * B.ny[i]
		else:
			var i: int = clampi(P.hint, 0, sim.N - 1)
			w = sim.tw[i]
			normal = Vector2(sim.tnx[i], sim.tny[i])
			lat = (P.x - sim.tpx[i]) * sim.tnx[i] + (P.y - sim.tpy[i]) * sim.tny[i]
	var margin := minf(MARGIN, w * 0.2)
	var room := Vector2(w / 2.0 - margin - lat, w / 2.0 - margin + lat)
	# Road normals have a fixed direction; the pilot's left reverses when driving back.
	var left := Vector2(-sin(sim.pair_th), cos(sim.pair_th))
	return room if left.dot(normal) >= 0.0 else Vector2(room.y, room.x)


func _station() -> Vector2:
	var P = sim.pod
	var fw := Vector2(cos(sim.pair_th), sin(sim.pair_th))
	var lf := Vector2(-fw.y, fw.x)
	var room := _room()
	var mine: float = room.x if side > 0.0 else room.y
	var other: float = room.y if side > 0.0 else room.x
	if mine < WING * 0.6 and other > mine + 20.0:   # no room this side: over to the other
		side = -side
		var sw := mine
		mine = other
		other = sw
	var d := WING + 12.0 * sin(0.17 * t + 2.0) + 5.0 * sin(0.43 * t)
	var a := AHEAD + 14.0 * sin(0.11 * t) + 6.0 * sin(0.31 * t + 1.0)
	return Vector2(P.x, P.y) + fw * a + lf * side * clampf(d, MIN_WING, maxf(mine, MIN_WING))


## Road-relative target: follow the sampled bend rather than cutting a chord
## across it. The offsets are in the player's direction, in either road direction.
func _frame(a: float) -> Dictionary:
	var P = sim.pod
	var fw := Vector2(cos(sim.pair_th), sin(sim.pair_th))
	var out := {"point": Vector2(P.x, P.y) + fw * a, "fw": fw, "lat": 0.0, "width": 100000.0, "f": 0.0, "dir": 1.0}
	if sim.kind != "network" or P.off_road:
		return out
	var R = sim.roads[P.path]
	var i: int = clampi(P.hint, 0, R.N - 2)
	var direction := 1.0 if fw.dot(Vector2(R.tx[i], R.ty[i])) >= 0.0 else -1.0
	var along: float = (P.x - R.px[i]) * R.tx[i] + (P.y - R.py[i]) * R.ty[i]
	var f := clampf(float(i) + along / R.len[i] + a * direction / 24.0, 0.0, R.N - 1.001)
	var j := int(f)
	var u := f - j
	var tangent := Vector2(R.tx[j], R.ty[j]).lerp(Vector2(R.tx[j + 1], R.ty[j + 1]), u).normalized()
	var lateral: float = ((P.x - R.px[i]) * R.nx[i] + (P.y - R.py[i]) * R.ny[i]) * direction
	out = {"point": Vector2(R.px[j], R.py[j]) + Vector2(R.tx[j], R.ty[j]) * R.len[j] * u, "fw": tangent * direction, "lat": lateral, "width": R.w[j], "f": f, "dir": direction}
	return out


func _point(a: float, offset: float) -> Vector2:
	var frame := _frame(a)
	var normal := Vector2(-frame.fw.y, frame.fw.x)
	var margin := minf(MARGIN, frame.width * 0.2)
	var lateral := clampf(frame.lat + offset, -frame.width / 2.0 + margin, frame.width / 2.0 - margin)
	return frame.point + normal * lateral


func _can_pass() -> bool:
	if sim.pod.off_road or Vector2(sim.pod.vx, sim.pod.vy).length() < 400.0:
		return false
	if sim.kind != "network":
		return false # branch roll and narrow circuits retain quiet formation
	var R = sim.roads[sim.pod.path]
	return not R.shaft and R.role == "" and _frame(300.0).width >= 300.0


## Reserve the swept corridor, including a freight train's tail. This is visual
## avoidance only: the partner never becomes a physical obstacle to the player.
func _target_clear(a: float, offset: float) -> bool:
	var frame := _frame(0.0)
	var origin := Vector2(sim.pod.x, sim.pod.y)
	var fw: Vector2 = frame.fw
	var lf := Vector2(-fw.y, fw.x)
	# Reserve the actual clamped trajectory, including the engines and cables.
	var lo := INF
	var hi := -INF
	var back := INF
	var front := -INF
	for u in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var q := _point(lerpf(_ahead, a, u), lerpf(_offset, offset, u)) - origin
		lo = minf(lo, q.dot(lf) - 10.0)
		hi = maxf(hi, q.dot(lf) + 10.0)
		back = minf(back, q.dot(fw) - 12.0)
		front = maxf(front, q.dot(fw) + 40.0)
	var player_lo := INF
	var player_hi := -INF
	var player_back := INF
	var player_front := -INF
	for b in sim.bodies:
		var q := Vector2(b.x, b.y) - origin
		player_lo = minf(player_lo, q.dot(lf) - 10.0)
		player_hi = maxf(player_hi, q.dot(lf) + 10.0)
		player_back = minf(player_back, q.dot(fw) - 12.0)
		player_front = maxf(player_front, q.dot(fw) + 12.0)
	if lo < player_hi and hi > player_lo and back < player_front and front > player_back:
		return false
	var traffic = view.get("traffic_net")
	if traffic == null or sim.kind != "network" or sim.pod.off_road:
		return true
	var speed := Vector2(sim.pod.vx, sim.pod.vy).length()
	var duration := clampf(maxf(absf(a - _ahead) / 85.0, absf(offset - _offset) / 18.0), 0.6, 3.0)
	for c in traffic.cars:
		var same_road: bool = c.road == sim.pod.path
		var relative := Vector2(c.x - sim.pod.x, c.y - sim.pod.y)
		if not same_road and (relative.length_squared() > 36000000.0 or absf(sim.net_height(c.road, c.f) - sim.pod.z) > 20.0):
			continue
		var lateral: float = c.lat * frame.dir - frame.lat if same_road else relative.dot(lf)
		var gap: float = (c.f - frame.f) * frame.dir * 24.0 if same_road else relative.dot(fw)
		var heading := Vector2(c.dir * frame.dir, 0.0) if same_road else Vector2(Vector2(c.hx, c.hy).dot(fw), Vector2(c.hx, c.hy).dot(lf))
		var velocity: Vector2 = heading * c.v - Vector2(speed, 0.0)
		var nose := Vector2(gap, lateral) + heading * 9.0
		var tail := Vector2(gap, lateral) - heading * (275.0 if c.kind == 3 else 9.0)
		var xmin := minf(nose.x, tail.x) + minf(0.0, velocity.x * duration) - 16.0
		var xmax := maxf(nose.x, tail.x) + maxf(0.0, velocity.x * duration) + 16.0
		var ymin := minf(nose.y, tail.y) + minf(0.0, velocity.y * duration) - 16.0
		var ymax := maxf(nose.y, tail.y) + maxf(0.0, velocity.y * duration) + 16.0
		if xmin < front and xmax > back and ymin < hi and ymax > lo:
			return false
	return true


func _move_station(dt: float) -> void:
	var room := _room()
	var target_a := AHEAD
	var target_side := side
	maneuver_time += dt
	if not _can_pass():
		maneuver = "formation"
		maneuver_time = 0.0
	else:
		match maneuver:
			"formation":
				if maneuver_time > 7.0:
					maneuver = "lead"
					maneuver_time = 0.0
			"lead":
				target_a = 280.0
				if _ahead > 260.0 and maneuver_time > 6.0:
					maneuver = "cross"
					side = -side
					maneuver_time = 0.0
			"cross":
				target_a = 280.0
				if _offset * side > 65.0:
					maneuver = "rejoin"
					maneuver_time = 0.0
			"rejoin":
				if absf(_ahead - AHEAD) < 2.0:
					maneuver = "formation"
					maneuver_time = 0.0
	target_side = side
	var mine: float = room.x if side > 0.0 else room.y
	var other: float = room.y if side > 0.0 else room.x
	if mine < 32.0 and other > mine + 20.0:
		target_side = -side
	var width := 72.0 if maneuver != "formation" else WING + 5.0 * sin(t * 0.23)
	var target_offset := target_side * minf(width, maxf(MIN_WING, room.x if target_side > 0 else room.y))
	# Cross ahead or behind the entire craft, never through its cables.
	if target_offset * _offset < 0.0 and _ahead > -100.0 and _ahead < 100.0:
		target_a = -120.0
		target_offset = _offset
	elif (target_offset * _offset < 0.0 or absf(_offset) < 35.0) and (_ahead <= -100.0 or _ahead >= 100.0):
		# Finish crossing before pulling alongside again. Otherwise a blocked
		# pass can oscillate at the centreline between two individually safe goals.
		target_a = _ahead
	if not _target_clear(target_a, target_offset):
		var candidates := [Vector2(_ahead, -target_offset), Vector2(-120.0, _offset), Vector2(-120.0, -target_offset)]
		var found := false
		for candidate in candidates:
			if _target_clear(candidate.x, candidate.y):
				target_a = candidate.x
				target_offset = candidate.y
				found = true
				break
		if not found:
			target_a = _ahead
			target_offset = _offset
	if target_offset * side < 0.0:
		side = signf(target_offset)
	_ahead = move_toward(_ahead, target_a, 85.0 * dt)
	_offset = move_toward(_offset, target_offset, 18.0 * dt)


func update(delta: float) -> void:
	var dt := clampf(delta, 0.0, 0.1)
	t += dt
	var P = sim.pod
	var pv := Vector2(P.vx, P.vy)
	var frame := _frame(0.0)
	if placed and _last_path == P.path and _last_direction == frame.dir and sim.kind == "network" and not P.off_road:
		# Preserve the partner's lane when the player moves sideways. Otherwise
		# road-edge clamping can pull an existing formation straight into the pod.
		_offset += _last_lateral - frame.lat
	elif placed and _last_path != P.path:
		placed = false
	if not placed:
		_station() # select the roomy side on first placement
		_ahead = AHEAD
		_offset = side * minf(WING, maxf(MIN_WING, _room().x if side > 0.0 else _room().y))
		maneuver = "formation"
		maneuver_time = 0.0
	_last_path = P.path
	_last_lateral = frame.lat
	_last_direction = frame.dir
	_move_station(dt)
	var st := _point(_ahead, _offset)
	if not placed or Vector2(st.x - x, st.y - y).length() > SNAP or dt <= 0.0:
		placed = true
		x = st.x
		y = st.y
		th = sim.pair_th
		lag = pv
		z = P.z
	else:
		# Road-relative feed-forward keeps even fast bends attached to their lane.
		var carried: bool = sim.kind == "network" and not P.off_road and sim.roads[P.path].shaft and sim.roads[P.path].kap[P.hint] != 0.0
		lag = pv
		x = st.x
		y = st.y
		var forward: Vector2 = _frame(_ahead).fw
		var dth: float = CraftSim.wrap_angle(atan2(forward.y, forward.x) - th)
		th += dth * (1.0 if carried else 1.0 - exp(-dt / 0.25))
		bank += ((0.0 if carried else clampf(-dth * 2.5, -0.6, 0.6)) - bank) * (1.0 - exp(-dt / 0.3))
	# its height: the road under it, or yours in the air
	if P.off_road or sim.kind != "network":
		z = P.z
	else:
		z = float(sim.surface_at(x, y, P.hint, P.path).x) + float(sim.P.rideH)
	_draw_it()


func _draw_it() -> void:
	var P = sim.pod
	var fw := Vector2(cos(th), sin(th))
	var lf := Vector2(-fw.y, fw.x)
	var lat: float = sim.P.engineGap / 2.0 - sim.P.podAnchorW * sim.P.podWidth / 2.0
	var ahead: float = sqrt(sim.P.cableLen * sim.P.cableLen - lat * lat) + sim.P.podLen / 2.0 + sim.P.engineLen / 2.0
	var Q: Basis = view.shaft_carry_at(x, y)
	if sim.kind != "network" and P.path > 0:
		Q = CraftModelScript.road_attitude(sim, x, y, CraftModelScript.slope_pitch(view, x, y, th, 12.0))
	var pitch := 0.0
	if not Q.is_equal_approx(Basis.IDENTITY):
		pitch = 0.0
	elif P.off_road or sim.kind == "network":
		var sp := Vector2(P.vx, P.vy).length()
		pitch = atan2(P.vz, maxf(sp, 1.0)) if sp > 5.0 else 0.0
	var att: Basis = Q * Basis.from_euler(Vector3(pitch, th - PI / 2.0, bank))
	_pod.transform = Transform3D(att, view.wz(x, y, z - 0.2 + CraftModelScript.POD_LIFT))
	var bodies := [sim.eL, sim.eR]
	for k in 2:
		var sd := 1.0 if k == 0 else -1.0
		var e: Vector2 = Vector2(x, y) + fw * ahead + lf * sd * sim.P.engineGap / 2.0
		var eng: Node3D = _engines[k]
		eng.transform = Transform3D(att, view.wz(e.x, e.y, z + 0.1))
		var push: float = clampf(float(bodies[k].thrust), 0.0, 1.6)
		var fl: MeshInstance3D = _flames[k]
		fl.visible = push > 0.02
		if fl.visible:
			var ln := 1.5 + 2.0 * push + (10.0 * push if sim.mode != "normal" else 0.0)
			fl.scale = Vector3(1.0, 1.0, ln)
			fl.position = Vector3(0.0, 0.0, 4.0 + ln / 2.0)
		var a: Vector3 = eng.transform * CraftModelScript.ENGINE_EYE
		var b: Vector3 = _pod.transform * Vector3(-sd * sim.P.podAnchorW * sim.P.podWidth / 2.0, CraftModelScript.POD_EYE_H, -sim.P.podLen / 2.0 - 0.1)
		var c: MeshInstance3D = _cables[k]
		var span := a - b
		if span.length() > 0.1:
			c.transform = Transform3D(Basis.looking_at(span, att.y) * Basis.from_scale(Vector3(1.0, 1.0, span.length())), (a + b) / 2.0)
