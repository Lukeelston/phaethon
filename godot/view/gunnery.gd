## The fire control: it fires a craft's weapon through its mount (view/weapons/weapon_mount.gd; the Basilisk's is
## its gaze-slaved turret, view/weapons/turret_mount.gd on view/turret.gd). Each frame:
##   1. the aim's ray: the mount's (the turret's is the gaze: down the middle of the pilot's view, the headset's
##      or the flat view's camera)
##   2. what it is on: the first vehicle it meets (view/network_traffic.gd ray_pick), else the ground
##      (the Network's land and the craft's own road; elsewhere the course's surface), else the sky
##   3. the sight is drawn there, at that distance and a fixed size over everything (view/gun_sight.gdshader)
##   4. the mount is laid on it, leading a vehicle by the bolt's time of flight, and fires while the
##      trigger is held, the mount is on the aim, and its line is clear of the craft (the turret's: its cab and engines)
##   5. bolts fly; where they land, a flash and a puff of dust; a vehicle takes HP hits and is gone
## Bolts and bursts are kept in the sims' frame (x, y, height) and drawn about the floating origin.
## The switch (deploy) and the trigger are the cockpit's: vr/vr_cockpit.gd, or K and F in the flat view.
##   gunnery = Gunnery.frame(view, gunnery, delta)        # once per frame, after the camera and the world
class_name Gunnery
extends Node3D

const Sim := preload("res://sim/craft_sim.gd")
const WeaponMountScript := preload("res://view/weapons/weapon_mount.gd")
const TurretMountScript := preload("res://view/weapons/turret_mount.gd")
const SightShader := preload("res://view/gun_sight.gdshader")
const GlowShader := preload("res://view/gun_glow.gdshader")
const SmokeShader := preload("res://view/gun_smoke.gdshader")
const AUDIO_DIR := "res://audio/turret/"

const REACH := 2600.0             # m: the sight looks this far for something to be on
const SKY := 2000.0               # ... and with nothing there, it stands this far out
const SIGHT_DEG := 3.2            # the sight's width, degrees of view (a vehicle's brackets are its own size, at the least this)
const BRACKET := {0: 30.0, 1: 34.0, 2: 30.0, 3: 46.0, 4: 30.0}   # m across a vehicle's brackets, by kind (a transport's round its tractor)
const BOLT_V := 1100.0            # m/s: a bolt's speed over the ground (a tracer's: slow enough to be seen going) ...
const RATE := 12.0                # shots a second, the two emitters turn about
const SPREAD := deg_to_rad(0.12)  # each shot's scatter about the aim
const LOCK_S := 0.35              # s a vehicle holds under the sight to be locked (the brackets close)
const LOCK_EASE := 3.0            # ... and the lock lost a second with none under it
const HP := {0: 3, 1: 5, 2: 3, 3: 8, 4: 4}   # hits a vehicle takes, by traffic kind: car, slow, demon, transport, racer (a COMMUTER takes none: no weapon knocks one out)
const HOSTILE_HP := 6                         # hits a hostile raider (Raids) takes, whatever its kind

signal killed(car)                 # a hostile raider shot down (before traffic.knock_out takes it out of traffic): the raid counts it
signal struck_commuter(car)        # a bolt struck a commuter: sparks only
const MAX_BOLTS := 48
const BOLT_WIDTH := 0.0105        # a bolt's least width for its distance from the eye: about six tenths of a degree
const STREAK := 38.0              # m: a bolt's streak, once it is that far out of the muzzle
const MAX_FX := 40

var view
var mount: WeaponMountScript       # the craft's weapon (view/craft_model.gd `weapon`): what this fires through
var want_out := false              # the switch (the cockpit sets it; deploying waits on power)
var trigger := false               # the fire button held
var hold_fire := false             # (renders and tests: as if it were)
var power := 1.0                   # the battery bus
var aim_sim := Vector3.ZERO        # what the gaze is on (sims' frame), and how far
var aim_dist := SKY
var aim_kind := "sky"              # "sky", "ground", "vehicle"
var aim_car = null                 # the vehicle under the sight
var lock := 0.0                    # 0..1: how long it has held there
var fouled := false                # the line of fire would cross the craft
var on_aim := false                # the mount is on the (led) aim
var shots := 0                     # tests and the log read these
var hits := 0
var kills := 0
var commuter_strikes := 0          # bolts that struck a commuter (spared: sparks and the impact sound only)
var _struck_id := -1
var march_ms := 0.0                # the ground search's cost this frame
# Heat (the Basilisk's power's figures, sim/pilot_craft.gd TRAITS: fireS, coolS; Luke's sheet, 2026-11-24): fire held
# on for fireS s on end overheats the gun, and it will not fire again until it has cooled coolS s. A pause in the
# fire starts the count again. In the log as its power: "POWER: Basilisk Gaze Turret fired|active|ended|ready".
var firing := false                # firing this frame
var fire_s := 0.0                  # s of fire on end
var hot := 0.0                     # s of cooling left (0: it fires)
var _fire_shown := 0               # (whole seconds of fire told)
var _cool := 0.0
var _barrel := 0
var _damage := {}                  # vehicle id -> hits taken
var _lock_car = null               # the vehicle the lock is on
var _bolts: Array = []             # {a: Vector3, b: Vector3, t, dur, car, id}
var _fx: Array = []                # {p: Vector3, kind, t, dur, size}
var _rng := RandomNumberGenerator.new()
var sight: MeshInstance3D
var sight_mat: ShaderMaterial
var _bolt_mm: MultiMesh
var _flash_mm: MultiMesh
var _smoke_mm: MultiMesh
var _sounds := {}                  # name -> AudioStream
var _servo: AudioStreamPlayer3D
var _gun_audio: Array = []
var _world_audio: Array = []
var _was_out := false
var _was_moving := false


## Once per frame. Creates itself the first time the craft has a weapon.
static func frame(v, g, delta: float):
	if v == null or v.craft == null or v.craft.weapon == null:
		return g
	if g == null:
		g = load("res://view/gunnery.gd").new()
		v.add_child(g)
		g.build(v)
	g.step(delta)
	return g


func build(v) -> void:
	view = v
	name = "Gunnery"
	mount = v.craft.weapon
	_rng.seed = 7
	sight_mat = ShaderMaterial.new()
	sight_mat.shader = SightShader
	sight_mat.render_priority = 120
	sight = MeshInstance3D.new()
	sight.name = "GunSight"
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	sight.mesh = quad
	sight.material_override = sight_mat
	sight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sight.extra_cull_margin = 16384.0
	sight.visible = false
	add_child(sight)
	_bolt_mm = _batch("GunBolts", _bolt_mesh(), _glow_material(true), MAX_BOLTS)
	_flash_mm = _batch("GunFlashes", _disc(), _glow_material(false), MAX_FX)
	_smoke_mm = _batch("GunSmoke", _disc(), _smoke_material(), MAX_FX)
	for n in ["fire", "deploy", "stow", "impact", "burst"]:
		var path: String = AUDIO_DIR + n + ".wav"
		if ResourceLoader.exists(path):
			_sounds[n] = load(path)
	_servo = _player(mount.node(), -2.0)
	for i in 3:
		_gun_audio.append(_player(mount.node(), 1.0))
	for i in 6:
		var p := _player(self, 4.0)
		p.unit_size = 60.0
		p.max_distance = 6000.0
		_world_audio.append(p)


func _player(parent: Node, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.volume_db = db
	p.unit_size = 6.0
	p.max_distance = 400.0
	p.bus = "Master"
	parent.add_child(p)
	return p


func _play(players: Array, sound: String, at := Vector3.INF, pitch := 1.0) -> void:
	if not _sounds.has(sound):
		return
	for p: AudioStreamPlayer3D in players:
		if not p.playing:
			if at != Vector3.INF:
				p.global_position = at
			p.stream = _sounds[sound]
			p.pitch_scale = pitch
			p.play()
			return


# --- the frames -------------------------------------------------------------------------------------

func to_render(p: Vector3) -> Vector3:
	return Vector3(p.x - view.org_x, p.z, -(p.y - view.org_y))


func to_sim(r: Vector3) -> Vector3:
	return Vector3(r.x + view.org_x, view.org_y - r.z, r.y)


static func dir_to_sim(d: Vector3) -> Vector3:
	return Vector3(d.x, -d.z, d.y)


# --- each frame ---------------------------------------------------------------------------------------

func step(delta: float) -> void:
	delta = minf(delta, 0.05)
	var cam: Camera3D = view.cam
	var out_ok := want_out and power > 0.5
	# The aim's ray (the turret's is the gaze), in the sims' frame for the search; and the gaze, for the mount
	# (the turret's sight ball follows it).
	var ray: Array = mount.aim_ray(cam)
	var aim_o: Vector3 = ray[0]
	var aim_d: Vector3 = ray[1]
	var gaze_d: Vector3 = -cam.global_transform.basis.z.normalized()
	var live := mount.deploy_t() > 0.0 or out_ok
	if live:
		_find(to_sim(aim_o), dir_to_sim(aim_d), delta)
	else:
		aim_kind = "sky"
		aim_car = null
		lock = 0.0
	# Lead a vehicle by the bolt's flight.
	var target := aim_sim
	if aim_car != null:
		target = _lead(aim_car)
	var target_r := to_render(target)
	mount.power = power
	mount.step(delta, out_ok, target_r if live else null, gaze_d)
	# Is it on, and the line clear?
	on_aim = mount.on_aim(target_r)
	fouled = mount.fouled(target_r)
	_cool = maxf(0.0, _cool - delta)
	var was_firing := firing
	firing = (trigger or hold_fire) and mount.ready_to_fire() and on_aim and not fouled and hot <= 0.0
	if firing:
		while _cool <= 0.0:
			_fire(target)
			_cool += 1.0 / RATE
	_heat_step(delta, was_firing)
	_sounds_step(out_ok)
	_fly(delta)
	_draw(cam)


## The gun's heat, a frame: fire on end counted (and told a second at a time), overheated at fireS, cooled coolS
## later. The figures are the craft's power's (the Basilisk's row); with none, the gun never overheats.
func _heat_step(delta: float, was_firing: bool) -> void:
	var pw: Dictionary = view.sim.traits.get("power", {})
	var fire_max := float(pw.get("fireS", INF))
	var title: String = view.power_title() if view.has_method("power_title") else "Gun"
	if hot > 0.0:
		hot = maxf(0.0, hot - delta)
		if hot == 0.0:
			print("POWER: %s ready (cooled)" % title)
			if view.has_method("_power_say"):
				view._power_say("GUN READY")
		return
	if firing:
		if not was_firing:
			fire_s = 0.0
			_fire_shown = 0
			print("POWER: %s fired" % title)
		fire_s += delta
		if floori(fire_s) > _fire_shown:
			_fire_shown = floori(fire_s)
			print("POWER: %s active %d s of fire" % [title, _fire_shown])
		if fire_s >= fire_max:
			hot = float(pw.get("coolS", 3.0))
			firing = false
			print("POWER: %s ended (overheated after %.1f s of fire: %.0f s to cool)" % [title, fire_s, hot])
			if view.has_method("_power_say"):
				view._power_say("GUN HOT")
			fire_s = 0.0
	elif was_firing:
		print("POWER: %s ended after %.1f s of fire" % [title, fire_s])
		fire_s = 0.0


## What the gaze is on: the first vehicle, else the ground, else the sky.
func _find(o: Vector3, d: Vector3, delta: float) -> void:
	var car_t := INF
	var picked := {}
	var traffic = view.traffic_net
	if traffic and traffic.has_method("ray_pick"):
		picked = traffic.ray_pick(o, d, REACH)
		if not picked.is_empty():
			car_t = float(picked.t)
		# A locked vehicle keeps the sight while the gaze stays inside the sight's ring of it, though
		# another crosses in front: the tracker holds its target in its gate.
		if _lock_car != null and (picked.is_empty() or picked.car != _lock_car) and traffic.cars.has(_lock_car):
			var gate := maxf(2.0, aim_dist * tan(deg_to_rad(SIGHT_DEG) * 0.3))
			var held: float = traffic.ray_car(_lock_car, o, d, gate)
			if held >= 0.0 and held < REACH:
				picked = {"car": _lock_car, "t": held}
				car_t = held
	var t0 := Time.get_ticks_usec()
	var ground_t := march(o, d, minf(REACH, car_t))
	march_ms = (Time.get_ticks_usec() - t0) / 1000.0
	if car_t < INF and (ground_t < 0.0 or car_t <= ground_t):
		aim_car = picked.car
		aim_kind = "vehicle"
		aim_dist = car_t
		aim_sim = o + d * car_t
	elif ground_t >= 0.0:
		aim_car = null
		aim_kind = "ground"
		aim_dist = ground_t
		aim_sim = o + d * ground_t
	else:
		aim_car = null
		aim_kind = "sky"
		aim_dist = SKY
		aim_sim = o + d * SKY
	# The lock holds through a glance off it (a head is never still, a vehicle never slow): it builds while
	# the same vehicle is under the sight, eases off while none is, and starts again on another.
	if aim_car != null and aim_car == _lock_car:
		lock = minf(1.0, lock + delta / LOCK_S)
	elif aim_car != null:
		_lock_car = aim_car
		lock = delta / LOCK_S
	else:
		lock = maxf(0.0, lock - delta * LOCK_EASE)
		if lock == 0.0:
			_lock_car = null


## The ground's height at (x, y), sims' frame: the craft's own road where it runs, and the land.
func ground_at(x: float, y: float) -> float:
	var sim = view.sim
	if sim.kind == "network":
		var h: float = view.landscape.height_at(Vector2(x, y)) if view.landscape else 0.0
		return maxf(h, _road_at(x, y))
	return view.surface(x, y).x


## The craft's own road under (x, y), or -INF off it (its deck may stand over the land).
func _road_at(x: float, y: float) -> float:
	var sim = view.sim
	if sim.pod.off_road:
		return -INF
	var path: int = sim.pod.path
	var R = sim.roads[path]
	var i := clampi(int(sim.pod.hint), 0, R.N - 2)
	var f := float(i)
	for k in 2:      # (twice: the road bends between here and there)
		var along: float = (x - R.px[i]) * R.tx[i] + (y - R.py[i]) * R.ty[i]
		f = clampf(float(i) + along / maxf(1.0, R.len[i]), 0.0, R.N - 1.001)
		i = clampi(int(f), 0, R.N - 2)
	var lat: float = (x - R.px[i]) * R.nx[i] + (y - R.py[i]) * R.ny[i]
	if absf(lat) > R.w[i] * 0.5 + 8.0:
		return -INF
	return sim.road_h(path, f)


## How far along the ray (sims' frame, d a unit vector) it meets the ground, or -1 by `reach`.
func march(o: Vector3, d: Vector3, reach: float) -> float:
	if d.z > 0.25:
		return -1.0         # (looking up: the land is behind and below)
	var t := 2.0
	var p := o + d * t
	if p.z <= ground_at(p.x, p.y):
		return t
	var steps := 0
	while t < reach and steps < 110:
		steps += 1
		var next := minf(reach, t + clampf(t * 0.07, 1.5, 90.0))
		p = o + d * next
		if p.z <= ground_at(p.x, p.y):
			var lo := t
			var hi := next
			for k in 7:
				var mid := (lo + hi) * 0.5
				var q := o + d * mid
				if q.z <= ground_at(q.x, q.y):
					hi = mid
				else:
					lo = mid
			return hi
		t = next
	return -1.0


## Where a vehicle will be when a bolt fired now reaches it (sims' frame).
func _lead(c) -> Vector3:
	var from := to_sim(mount.origin())
	var at := Vector3(c.x, c.y, aim_sim.z)
	var v := Vector3(c.hx * c.v, c.hy * c.v, 0.0)
	var speed := _bolt_speed((at - from).normalized())
	for k in 2:
		var tof := from.distance_to(at) / speed
		at = Vector3(c.x, c.y, aim_sim.z) + v * tof
	# (keep the gaze's height on it: the sight sits on its body, not its road)
	return at


## A bolt's speed over the ground along `dir` (sims' frame): BOLT_V, more by the craft's own way that way
## (fired ahead it still leaves the craft at BOLT_V).
func _bolt_speed(dir: Vector3) -> float:
	var sim = view.sim
	var ahead: float = sim.pod.vx * dir.x + sim.pod.vy * dir.y
	return BOLT_V + maxf(0.0, ahead)


func _fire(target: Vector3) -> void:
	var muzzles := mount.muzzles()
	var m: Vector3 = muzzles[_barrel % muzzles.size()]
	_barrel += 1
	var a := to_sim(m)
	var line := target - a
	var dist := line.length()
	var dir := line / maxf(dist, 0.01)
	# Scatter about the aim, a little.
	var side := dir.cross(Vector3(0, 0, 1)).normalized() if absf(dir.z) < 0.99 else Vector3(1, 0, 0)
	var up := side.cross(dir).normalized()
	var b := target + (side * _rng.randfn(0.0, 1.0) + up * _rng.randfn(0.0, 1.0)) * SPREAD * dist
	var dur := a.distance_to(b) / _bolt_speed(dir)
	if _bolts.size() >= MAX_BOLTS:
		_bolts.pop_front()
	_bolts.append({"a": a, "b": b, "t": 0.0, "dur": maxf(0.02, dur), "car": aim_car if aim_kind == "vehicle" else null,
		"kind": aim_kind})
	shots += 1
	mount.add_heat(0.35)
	_add_fx(a + dir * 0.4, "muzzle", 0.07, 0.35)
	_play(_gun_audio, "fire", Vector3.INF, 0.94 + 0.12 * _rng.randf())


func _fly(delta: float) -> void:
	for i in range(_bolts.size() - 1, -1, -1):
		var bolt: Dictionary = _bolts[i]
		bolt.t += delta
		if bolt.t < bolt.dur:
			continue
		_bolts.remove_at(i)
		_land(bolt)
	for i in range(_fx.size() - 1, -1, -1):
		_fx[i].t += delta
		if _fx[i].t >= _fx[i].dur:
			_fx.remove_at(i)


func _land(bolt: Dictionary) -> void:
	var at: Vector3 = bolt.b
	var c = bolt.car
	var traffic = view.traffic_net
	if c != null and traffic and traffic.cars.has(c):
		hits += 1
		var id: int = c.id
		var body := Vector3(c.x, c.y, at.z)
		_add_fx(body + Vector3(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3), _rng.randf_range(-1, 2)), "spark", 0.18, 9.0)
		_play(_world_audio, "impact", to_render(body), 1.25)
		if not c.hostile:
			# No shooting commuters: no weapon knocks one out. The bolt sparks and that is all (no damage entry).
			commuter_strikes += 1
			if _struck_id != id:
				_struck_id = id
				print("GUN: commuter struck")
			struck_commuter.emit(c)
			return
		_damage[id] = int(_damage.get(id, 0)) + 1
		if _damage[id] >= HOSTILE_HP:
			_damage.erase(id)
			kills += 1
			killed.emit(c)          # (the raid counts it first: knock_out takes the car out of traffic)
			traffic.knock_out(c)
			_add_fx(body, "fireball", 0.9, 34.0)
			_add_fx(body + Vector3(0, 0, 4), "smoke", 3.2, 46.0)
			_add_fx(body, "flash", 0.12, 90.0)
			_play(_world_audio, "burst", to_render(body))
			print("GUN: raider %d knocked out at %d m (%d shots, %d hits, %d out)" % [id, int(aim_dist), shots, hits, kills])
		return
	if bolt.kind == "sky":
		_add_fx(at, "spark", 0.25, 6.0)      # (spent: it fizzes out at the end of its reach)
		return
	_add_fx(at, "flash", 0.12, 12.0)
	_add_fx(at + Vector3(0, 0, 1.0), "spark", 0.22, 5.0)
	_add_fx(at, "dust", 1.6, 18.0)
	_play(_world_audio, "impact", to_render(at), 0.9 + 0.2 * _rng.randf())


func _add_fx(p: Vector3, kind: String, dur: float, size: float) -> void:
	if _fx.size() >= MAX_FX:
		_fx.pop_front()
	_fx.append({"p": p, "kind": kind, "t": 0.0, "dur": dur, "size": size})


## asked_out: what the mount was asked this frame (the switch, with power).
func _sounds_step(asked_out: bool) -> void:
	var out := mount.is_out()
	var moving := mount.deploy_t() > 0.0 and not out
	if moving and not _was_moving:
		_servo.stream = _sounds.get("deploy" if asked_out else "stow")
		if _servo.stream:
			_servo.play()
	_was_moving = moving
	if out != _was_out:
		print("GUN: ", "out" if out else "stowing")
	_was_out = out


# --- drawing -------------------------------------------------------------------------------------------

func _draw(cam: Camera3D) -> void:
	var eye := cam.global_position
	# (the gaze sight's stops, coils and pipper are the turret's own: a mount without them shows none of them)
	var gun := mount as TurretMountScript
	# The sight: at the aim, the size of SIGHT_DEG there.
	var showing := mount.deploy_t() > 0.0 and want_out
	sight.visible = showing
	if showing:
		var at := to_render(aim_sim)
		var dist := eye.distance_to(at)
		var size := 2.0 * dist * tan(deg_to_rad(SIGHT_DEG) * 0.5)
		var sight_at := at
		if aim_kind == "vehicle" and aim_car != null:
			# Brackets round the vehicle itself (its middle, on its road), not a ring over where the gaze struck it.
			sight_at = to_render(Vector3(aim_car.x, aim_car.y, aim_sim.z))
			size = maxf(size, float(BRACKET.get(aim_car.kind, 30.0)))
		sight.global_transform = Transform3D(Basis().scaled(Vector3.ONE * size), sight_at)
		var state := 0
		if not mount.is_out():
			state = 3
		elif (gun != null and gun.limited()) or fouled:
			state = 2
		elif aim_kind == "vehicle":
			state = 1
		sight_mat.set_shader_parameter("state", state)
		sight_mat.set_shader_parameter("power", power)
		sight_mat.set_shader_parameter("lock", lock)
		sight_mat.set_shader_parameter("heat", gun.heat() if gun != null else 0.0)
		sight_mat.set_shader_parameter("spin", Time.get_ticks_msec() * 0.004 if state == 3 else 0.0)
		# The pipper: where the bore meets the sight's distance, as seen from the eye.
		if gun != null:
			var bore_pt := mount.origin() + gun.bore() * dist
			var to_bore := (bore_pt - eye).normalized()
			var basis := cam.global_transform.basis
			var fwd := (sight_at - eye).normalized()
			var off := Vector2(to_bore.dot(basis.x) - fwd.dot(basis.x), to_bore.dot(basis.y) - fwd.dot(basis.y))
			var half := size * 0.5 / maxf(eye.distance_to(sight_at), 0.01)
			var pip := off / half
			sight_mat.set_shader_parameter("pipper", Vector2(pip.x, pip.y))
			sight_mat.set_shader_parameter("pipper_on", 1.0 if mount.is_out() and pip.length() < 3.0 else 0.0)
		else:
			sight_mat.set_shader_parameter("pipper_on", 0.0)
	# Bolts: streaks along their flight, thick enough to see from where the eye is.
	var n := 0
	for bolt: Dictionary in _bolts:
		var k: float = bolt.t / bolt.dur
		var a: Vector3 = bolt.a
		var b: Vector3 = bolt.b
		var head := to_render(a.lerp(b, k))
		var dir := to_render(b) - to_render(a)
		var length := dir.length()
		if length < 0.01:
			continue
		dir /= length
		var streak := minf(STREAK, length * k + 0.3)
		var mid := head - dir * streak * 0.5
		var width := maxf(0.22, eye.distance_to(mid) * BOLT_WIDTH)
		var z := -dir
		var x := z.cross(Vector3.UP if absf(z.y) < 0.98 else Vector3.RIGHT).normalized()
		var y := z.cross(x)
		# Turn the flat ribbon to face the eye about its own line.
		var to_eye := (eye - mid)
		var face := (to_eye - dir * to_eye.dot(dir)).normalized()
		if face.length_squared() > 0.5:
			y = face
			x = y.cross(z).normalized()
		_bolt_mm.set_instance_transform(n, Transform3D(Basis(x * width, y * width, z * streak), mid))
		_bolt_mm.set_instance_color(n, Color(2.6, 1.5, 0.55, 1.0))
		n += 1
	_bolt_mm.visible_instance_count = n
	# Flashes, sparks and fire (added), dust and smoke (blended).
	var nf := 0
	var ns := 0
	for f: Dictionary in _fx:
		var u: float = f.t / f.dur
		var p := to_render(f.p)
		var size: float = f.size
		match String(f.kind):
			"muzzle":
				p = mount.muzzles()[(_barrel + 1) % 2]
				_flash_mm.set_instance_transform(nf, Transform3D(Basis().scaled(Vector3.ONE * 0.35 * (1.0 - u)), p))
				_flash_mm.set_instance_color(nf, Color(1.0, 0.7, 0.35) * (1.0 - u))
				nf += 1
			"flash", "spark":
				var s := size * (0.4 + 0.6 * u) * (maxf(1.0, eye.distance_to(p) * 0.004))
				_flash_mm.set_instance_transform(nf, Transform3D(Basis().scaled(Vector3.ONE * s), p))
				var c := Color(1.0, 0.85, 0.6) if f.kind == "flash" else Color(1.0, 0.55, 0.2)
				_flash_mm.set_instance_color(nf, c * (1.0 - u) * 2.0)
				nf += 1
			"fireball":
				_flash_mm.set_instance_transform(nf, Transform3D(Basis().scaled(Vector3.ONE * size * (0.35 + 0.65 * sqrt(u))), p + Vector3.UP * 6.0 * u))
				_flash_mm.set_instance_color(nf, Color(1.0, 0.45 + 0.3 * (1.0 - u), 0.15) * (1.0 - u * u) * 2.2)
				nf += 1
			"dust", "smoke":
				var grow := size * (0.35 + 0.65 * sqrt(u))
				_smoke_mm.set_instance_transform(ns, Transform3D(Basis().scaled(Vector3.ONE * grow), p + Vector3.UP * (2.0 + 10.0 * u) * (1.0 if f.kind == "smoke" else 0.3)))
				var col := Color(0.36, 0.31, 0.26) if f.kind == "dust" else Color(0.12, 0.11, 0.1)
				col.a = (1.0 - u) * (0.75 if f.kind == "dust" else 0.85)
				_smoke_mm.set_instance_color(ns, col)
				ns += 1
	_flash_mm.visible_instance_count = nf
	_smoke_mm.visible_instance_count = ns


func _batch(n: String, mesh: Mesh, mat: Material, count: int) -> MultiMesh:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = n
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 16384.0
	mmi.custom_aabb = AABB(Vector3(-30000, -30000, -30000), Vector3(60000, 60000, 60000))
	add_child(mmi)
	return mm


## A bolt: a flat ribbon one unit long, across X and along Z, facing +Y (its streak texture's head
## is at the -Z end).
static func _bolt_mesh() -> Mesh:
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.orientation = PlaneMesh.FACE_Y
	return q


static func _disc() -> Mesh:
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	return q


static func _glow_material(streak: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GlowShader
	m.set_shader_parameter("streak", streak)
	m.render_priority = 1
	return m


static func _smoke_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SmokeShader
	return m
