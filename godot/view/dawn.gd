## The dawn on the emergency run (docs/superpowers/specs/2026-10-19-emergency-run-design.md): a
## straight front sweeping the valley at the sim's dawnSpeed (1,000 mph), drawn so it's always
## visible and fair. The sim decides when it catches you (CraftSim.t_lit); this only shows it.
##   the wall      an additive curtain of light along the front, 300 km long and 3 mi tall, fogless
##                 (view/dawn.gdshader), standing where the front passes nearest you; brighter as
##                 it nears
##   the glow      the twin suns, just under the horizon on the dawn's side, lighting the sky there
##                 (sky-only lights; the twilight sky spreads their glow), growing as the front nears
##   the lit land  behind the front the ground warms (view/ground.gdshader: dawn_u, dawn_f)
##   the burn      caught in the open, the view burns to white (burn, 0..1: the views draw it)
##   var d := Dawn.new(); add_child(d); d.build(view)   once, on a job
##   d.sync(sim, delta)                                 every frame
extends Node3D

const WALL_LEN := 300000.0
const WALL_H := 4828.0             # 3 mi
const NEAR := 60000.0              # m: the wall and the glow build up as the front closes from here
const SUN_DIP := 3.0               # degrees under the horizon
const SUNS := [[Color(1.0, 0.86, 0.62), 0.0, 2.2], [Color(1.0, 0.58, 0.32), 7.0, 1.4]]   # colour, degrees off the dawn's bearing, energy

var view
var wall: MeshInstance3D
var suns: Array[DirectionalLight3D] = []
var burn := 0.0                    # 0..1: caught, the view burns to white
var dist := INF                    # m from the pod to the front (positive: not yet reached)
var eta := INF                     # s until it reaches the pod
var _mat: ShaderMaterial


func build(v) -> void:
	view = v
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://view/dawn.gdshader")
	wall = MeshInstance3D.new()
	wall.name = "dawn_wall"
	var q := QuadMesh.new()
	q.size = Vector2(WALL_LEN, WALL_H)
	wall.mesh = q
	wall.material_override = _mat
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wall)
	var dir: float = view.sim.P.dawnDir
	for s in SUNS:
		var l := DirectionalLight3D.new()
		l.sky_mode = DirectionalLight3D.SKY_MODE_SKY_ONLY
		l.light_color = s[0]
		l.light_angular_distance = 1.2
		l.light_energy = 0.0
		var a: float = dir + deg_to_rad(s[1])   # the light travels the front's way, from under the horizon behind it
		var t := Vector3(cos(a), tan(deg_to_rad(SUN_DIP)), -sin(a))
		add_child(l)
		l.look_at_from_position(Vector3.ZERO, t, Vector3.UP)
		suns.append(l)
	view.ground_mat.set_shader_parameter("dawn_on", 1.0)


func sync(sim, delta: float) -> void:
	var J: Dictionary = sim.job
	var t: float = 0.0 if J.t0 == null else sim.time - float(J.t0)
	var u := Vector2(cos(sim.P.dawnDir), sin(sim.P.dawnDir))
	var d: float = sim.P.dawnSpeed * (t - sim.P.dawnT0)   # the front: points with p.u < d are lit
	var pu: float = sim.pod.x * u.x + sim.pod.y * u.y
	dist = pu - d
	eta = dist / sim.P.dawnSpeed
	# the wall, where the front passes nearest the pod
	var fx: float = sim.pod.x - u.x * dist
	var fy: float = sim.pod.y - u.y * dist
	var ur := Vector3(u.x, 0.0, -u.y)
	var vr := Vector3(-u.y, 0.0, -u.x)
	wall.transform = Transform3D(Basis(vr, Vector3.UP, ur), Vector3(fx - view.org_x, WALL_H / 2.0 - 30.0, -(fy - view.org_y)))
	var near := clampf(1.0 - absf(dist) / NEAR, 0.0, 1.0)
	_mat.set_shader_parameter("intensity", 0.35 + 0.65 * near * near)
	wall.visible = absf(dist) < 250000.0
	for k in suns.size():
		suns[k].light_energy = float(SUNS[k][2]) * (0.25 + 0.75 * near)
	# the lit land behind it (render axes: x, -y; against the floating origin)
	var gm: ShaderMaterial = view.ground_mat
	gm.set_shader_parameter("dawn_u", Vector2(u.x, -u.y))
	gm.set_shader_parameter("dawn_f", d - (view.org_x * u.x + view.org_y * u.y))
	# caught: burn to white, then let the result show
	var caught: bool = J.stage == "failed" and J.reason == "dawn"
	var target := 1.0 if caught and sim.crash_t > 0.0 else 0.0
	burn = move_toward(burn, target, delta * (3.0 if target > burn else 0.7))
