## The driving partner (Luke: "a 'driving partner', that stays around your speed and just generally does
## what you do - i found it interesting to see a stable reference point at high speed - kind of trippy";
## the main menu's DRIVING PARTNER, or --partner). A second craft flying formation off your wing: it holds
## your speed (your velocity, a beat late, so it drifts back a little when you brake and comes up again
## when you accelerate), your heading and your road, wandering a few metres so it's alive. It keeps to
## the side with the room and inside the walls, comes off lips and up shafts with you, and it's not in
## the sims: nothing to hit, nothing in the parity. Teal engines, so it's not mistaken for traffic.
##   var p := DrivingPartner.new(); add_child(p); p.build(view)
##   p.update(delta)   every frame, after the camera
extends Node3D

const CraftModelScript := preload("res://view/craft_model.gd")
const Kit := preload("res://view/mesh_kit.gd")
const WING := 48.0          # m off your centreline
const AHEAD := 14.0         # m ahead of the pod: out of the cockpit's left or right, level with the cables
const LAG_V := 0.3          # s: how late it takes up your velocity
const LAG_P := 1.2          # s: how it settles back onto its station
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
	if sim.kind == "network":
		var R = sim.roads[P.path]
		var i: int = clampi(P.hint, 0, R.N - 1)
		w = R.w[i]
		lat = (P.x - R.px[i]) * R.nx[i] + (P.y - R.py[i]) * R.ny[i]
	else:
		if P.path > 0:
			return Vector2(MIN_WING, MIN_WING)
		var i: int = clampi(P.hint, 0, sim.N - 1)
		w = sim.tw[i]
		lat = (P.x - sim.tpx[i]) * sim.tnx[i] + (P.y - sim.tpy[i]) * sim.tny[i]
	var margin := minf(MARGIN, w * 0.2)
	return Vector2(w / 2.0 - margin - lat, w / 2.0 - margin + lat)


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


func update(delta: float) -> void:
	var dt := clampf(delta, 0.0, 0.1)
	t += dt
	var P = sim.pod
	var pv := Vector2(P.vx, P.vy)
	var st := _station()
	if not placed or Vector2(st.x - x, st.y - y).length() > SNAP or dt <= 0.0:
		placed = true
		x = st.x
		y = st.y
		th = sim.pair_th
		lag = pv
		z = P.z
	else:
		# (round a shaft's bulb the plan's velocity turns half a radian a second: that's the road, not
		# you, so it isn't late for it)
		var carried: bool = sim.kind == "network" and not P.off_road and sim.roads[P.path].shaft and sim.roads[P.path].kap[P.hint] != 0.0
		lag = pv if carried else lag + (pv - lag) * (1.0 - exp(-dt / LAG_V))
		x += lag.x * dt
		y += lag.y * dt
		var k := 1.0 - exp(-dt / LAG_P)
		x += (st.x - x) * k
		y += (st.y - y) * k
		var dth: float = CraftSim.wrap_angle(sim.pair_th - th)
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
