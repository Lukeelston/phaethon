## The Vesper's shock pulse as a WeaponMount (view/weapons/weapon_mount.gd), on Codex's arms (view/arms/vesper_arms.gd: a
## pulse wheel on a lift that rises out of the forward starboard sill, its four quarter rings fanning into one transducer).
## It fires for itself (own_fire): the fire control (view/gunnery.gd) hands this the trigger each frame (fire); this keeps
## the ring, its hits and the charge. It is not aimed: the gaze lays only the fire control's own sight. Its figures are
## the craft's weapon row (sim/pilot_craft.gd TRAITS[..].weapon: radius, rechargeS, gunshipFrac, spreadS).
##   release   on the trigger's press (not while it is held), the wheel out and asked out, and charged: a ring leaves the
##             wheel's centre (its muzzle) and widens to `radius` m in spreadS s (0 on the release's frame, radius x t /
##             spreadS after). The charge, rechargeS s, then counts down whatever the switch does (thrown to SAFE and
##             back it is not refilled); "PULSE READY" (status, which the fire control says on the strip) once it ends.
##   hits      the threats the raid has at the release (g.threats(): its raiders and its flyers; a commuter is never
##             looked at), each once, the first frame the ring's radius has reached its distance from the release point:
##             in the round for a flyer, over the ground for a raider. A drone or a raider is destroyed (g.damage with
##             its full HP, g.hp_of), bare: its burst and the burst's sound are the hit's picture and sound (up to 16
##             die inside half a second, and a spark and an impact sound each would take the fire control's six world
##             players from the bursts). The gunship takes gunshipFrac of its full HP (the flyers module's hp_max, read
##             through g.hp_of), not bare: seen and heard as a hit; it never kills a fresh one. One gone meanwhile (shot,
##             fled, the raid ended or reset: a restart, a respawn) is passed over, so once the raid is gone the ring hits
##             nothing; one that comes after the release is not hit by it, ahead of the ring or behind it. A ring under
##             way finishes its spread whatever the switch does: SAFE stops a new release, not one under way.
##   drawn     the ring (view/weapons/pulse_ring.gdshader): one flat band on the road's plane under the release point,
##             RING_LIFT over it, added, unshaded, no depth write; its outer edge at the ring's radius, BAND of it wide (a
##             bright leading edge, a faint wash behind), dimming from RING_ENERGY to RING_END x that over the spread and
##             out over LINGER_S at its radius after. It is kept in the sims' frame where it was released (drawn about
##             the floating origin, as the fire control's own are) and drawn only on a frame its band is CLEAR m or more
##             off the pod and each engine, over the ground: so it first shows clear of the craft's hull and engines
##             (at rest at 52.5 m, its 7th frame; at 1,500 mph, the craft chasing its front, at 225 m, its 30th: measured
##             by tests/test_pulse.gd) and never passes under them drawn. Nothing fills the view and nothing touches the camera or the HUD: no flash. The wheel's heat
##             follows the charge (charge / rechargeS: full at the release, out when it is ready again).
##   felt      one strong tick in both hands on the release, below a jolt's (kicks: vr/vr_cockpit.gd _gun_kick)
##   sounds    stand-ins for Task 9's, which owns them: turret sounds re-pitched (g.play), unheard: the boom on the release
##             (pulse_boom) and a cue when it is charged again (pulse_ready)
## Its arms are fitted on the hull the pilot sees (view/fleet_airframe.gd ensure_arms: the hull last dressed, the VR
## seat's own, else the craft's pod) the first time the GUN asks them out: a flight with Raids off that never arms them
## builds none of them, nor this one's drawing. With Raids on they are fitted at load, stowed (prepare).
##   weapon = PulseMount.new(craft)      craft: the CraftModel (view/craft_model.gd): its view, sim and fleet airframe
class_name PulseMount
extends "res://view/weapons/weapon_mount.gd"

const GunneryScript := preload("res://view/gunnery.gd")
const PilotCraft := preload("res://sim/pilot_craft.gd")
const RingShader := preload("res://view/weapons/pulse_ring.gdshader")
const DEPLOY_S := 1.0             # s from stowed to out: the leaves open, the wheel rises and fans (the fixed guns' figure)
const BAND := 0.06                # the ring's band, of its radius, inward of its edge (27 m at 450)
const CLEAR := 25.0               # m: drawn only on a frame its band is this far off the pod and each engine (over the ground)
const RING_LIFT := 0.3            # m: its plane over the road's (not to fight the road's surface)
const RING_ENERGY := 1.6          # its light at the release ...
const RING_END := 0.35            # ... this much of it at its radius ...
const LINGER_S := 0.25            # ... and out over this long after, at its radius
const RING_COL := Color(0.86, 0.62, 1.0)      # the wheel's lens's lilac (its front white-hot: the shader's)
const SEGMENTS := 128             # round the ring (a chord 0.14 m inside the circle at 450 m)
const BOOM_PITCH := 0.55          # (stand-ins, Task 9's to replace: the turret's burst, lower, for the release ...)
const READY_PITCH := 1.7          # (... and its servo, higher, for the charge full again)

var craft                         # the CraftModel (view/craft_model.gd)
var arms = null                   # Codex's arms (view/arms/vesper_arms.gd), fitted at the first arming
var t := 0.0                      # 0 stowed .. 1 out
var radius := 450.0               # the row's figures
var recharge_s := 12.0
var gunship_frac := 0.6
var spread_s := 0.5
var charge := 0.0                 # s of the recharge left (0: charged)
var released := 0                 # rings released this flight (kicks: one each)
var ring_t := -1.0                # s since the ring's release (-1: no ring)
var ring_r := 0.0                 # m: its radius now (its hits')
var centre := Vector3.ZERO        # where it was released (the sims' frame: the wheel's centre then)
var ring_h := 0.0                 # the road's height under it (the sims' frame): the plane it is drawn on
var ahead: Array = []             # the threats it has still to reach (those the raid had at its release)
var ring: MeshInstance3D = null   # its drawing (made with the arms' first frame: _build_drawing)
var drawn_r := -1.0               # the radius it was drawn at this frame, -1 for none (tests read it)
var ring_light := 0.0             # ... and how bright
var cost_ms := 0.0                # what the last frame's step and fire took (tests read it)
var _mat: ShaderMaterial
var _asked := false               # asked out this frame (the switch, with power)
var _shown := -1.0                # the deploy the arms were last set to
var _held := false                # the trigger held last frame
var _readied := false             # charged since its last release (status: PULSE READY)
var _cue := false                 # charged this frame (the ready cue's stand-in, played in fire)
var _step_us := 0


func _init(model) -> void:
	craft = model
	var row: Dictionary = model.view.sim.traits.get("weapon", {})
	radius = maxf(1.0, float(row.get("radius", radius)))
	recharge_s = maxf(0.01, float(row.get("rechargeS", recharge_s)))
	gunship_frac = float(row.get("gunshipFrac", gunship_frac))
	spread_s = maxf(0.01, float(row.get("spreadS", spread_s)))


func step(delta: float, want_out: bool, _aim_render: Variant, _gaze_dir_render: Vector3) -> void:
	var t0 := Time.get_ticks_usec()
	_asked = want_out
	if want_out and arms == null:
		_fit_arms()
	t = move_toward(t, 1.0 if want_out else 0.0, delta / DEPLOY_S)
	if arms != null and t != _shown:
		_shown = t
		arms.set_deploy(t)
	if charge > 0.0:      # (the recharge's clock: it runs whatever the switch does)
		charge -= delta
		if charge <= 1e-6:
			charge = 0.0
			_readied = true
			_cue = true
			_tell("ready (charged)")
	_step_us = Time.get_ticks_usec() - t0


## Raids on (its fire control made at load, dormant; Ruling D): the arms fitted now, stowed, so the first arming fits
## none in its frame. With Raids off they stay unbuilt until the GUN asks them out.
func prepare() -> void:
	if arms == null:
		_fit_arms()


## Codex's arms on the hull the pilot sees (the hull last dressed: view/fleet_airframe.gd ensure_arms).
func _fit_arms() -> void:
	arms = craft.fleet.ensure_arms() if craft.fleet != null else null
	_shown = -1.0


## The hull the pilot sees, which the arms are fitted on: the VR seat's own, else the craft's pod.
func _hull() -> Node3D:
	var fleet = craft.fleet
	if fleet != null and is_instance_valid(fleet.drawn_hull):
		return fleet.drawn_hull
	return craft.pod


## The wheel's centre (global), or the hull before the arms are fitted.
func origin() -> Vector3:
	if arms != null:
		var mouths: Array = arms.muzzles()
		if not mouths.is_empty():
			return (mouths[0] as Transform3D).origin
	return _hull().global_position


func is_out() -> bool:
	return t >= 1.0


func ready_to_fire() -> bool:
	return is_out() and _asked


func deploy_t() -> float:
	return t


## The wheel's centre (global), where the ring leaves.
func muzzles() -> Array:
	return [origin()] if arms != null else []


## The hull: the fire control's players (the boom) hang there, where the arms are fitted.
func node() -> Node3D:
	return _hull()


func heat() -> float:
	return arms.heat if arms != null else 0.0


func own_fire() -> bool:
	return true


## "PULSE READY" once it has charged again after a release, else "".
func status() -> String:
	return "PULSE READY" if _readied else ""


## One for each release: a strong tick in both hands.
func kicks() -> int:
	return released


# --- each frame, from the fire control -------------------------------------------------------------------------

func fire(g, delta: float, pulling: bool) -> void:
	var t0 := Time.get_ticks_usec()
	if ring == null and arms != null:
		_build_drawing(g)
	if ring_t >= 0.0:
		_spread(g, delta)
	if pulling and not _held and charge <= 0.0 and arms != null:
		_release(g)
	_held = g.trigger or g.hold_fire
	if _cue:
		_cue = false
		g.play("gun", "deploy", Vector3.INF, READY_PITCH)      # (a stand-in for the charge's own cue: Task 9's pulse_ready)
	if arms != null:
		arms.heat = charge / recharge_s
	if ring != null:
		_draw(g)
	cost_ms = (_step_us + Time.get_ticks_usec() - t0) / 1000.0


## A ring leaves the wheel's centre: the threats there now are the ones it will reach.
func _release(g) -> void:
	centre = g.to_sim(origin())
	ring_h = g.ground_at(centre.x, centre.y)
	ring_t = 0.0
	ring_r = 0.0
	ahead = g.threats().duplicate()      # (the raid's raiders and flyers: never a commuter)
	charge = recharge_s
	_readied = false
	released += 1
	g.play("gun", "burst", Vector3.INF, BOOM_PITCH)      # (a stand-in for the release's own boom: Task 9's pulse_boom)
	_tell("released (%d threats about)" % ahead.size())


## A frame of the ring: it widens, and each threat it has reached is hit; past its spread it reaches no more, and once it
## has lingered it is gone.
func _spread(g, delta: float) -> void:
	ring_t += delta
	var done := ring_t >= spread_s - 1e-6
	ring_r = radius if done else radius * ring_t / spread_s
	var reach2 := (ring_r + 1e-4) * (ring_r + 1e-4)      # (one at the radius itself is reached)
	for k in range(ahead.size() - 1, -1, -1):
		var c = ahead[k]
		var flyer := GunneryScript._is_flyer(c)
		var dx: float = c.x - centre.x
		var dy: float = c.y - centre.y
		var dz: float = c.z - centre.z if flyer else 0.0
		if dx * dx + dy * dy + dz * dz > reach2:
			continue
		ahead.remove_at(k)
		if g.alive(c):      # (one gone meanwhile is passed over: shot, fled, the raid ended)
			_hit(g, c, flyer)
	if done:
		ahead.clear()      # (beyond the radius: never reached)
	if ring_t >= spread_s + LINGER_S - 1e-6:
		ring_t = -1.0


## Threat c reached: a drone or a raider destroyed (bare), the gunship a share of its full HP (as a hit is seen and
## heard). `quiet`: a commuter is never touched, should one ever be among them.
func _hit(g, c, flyer: bool) -> void:
	var at := Vector3(c.x, c.y, c.z if flyer else g.view.traffic_net.body_height(c))
	if flyer and String(c.kind) == "gunship":
		g.damage(c, roundi(gunship_frac * g.hp_of(c)), at, true)
	else:
		g.damage(c, g.hp_of(c), at, true, true)


## The pulse's word in the log, as the fire control tells a gun's ("GUN: Vesper pulse released").
func _tell(what: String) -> void:
	var id: String = craft.view.sim.P.vehicle
	print("GUN: %s %s %s" % [PilotCraft.NAMES.get(id, id.capitalize()), PilotCraft.weapon_of(id), what])


# --- drawing ----------------------------------------------------------------------------------------------------

## The ring's band, under the fire control (drawn about the floating origin as its own are), hidden.
func _build_drawing(g) -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = RingShader
	_mat.render_priority = 1      # (as the fire control's glow)
	_mat.set_shader_parameter("colour", Vector3(RING_COL.r, RING_COL.g, RING_COL.b))
	ring = MeshInstance3D.new()
	ring.name = "PulseRing"
	ring.mesh = _band_mesh(1.0 - BAND)
	ring.material_override = _mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	g.add_child(ring)


## A flat band round the up axis (the render frame's XZ plane), from `inner` to 1 across; UV.y 0 at its inner edge, 1 at
## its outer.
static func _band_mesh(inner: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()
	for k in SEGMENTS + 1:
		var a := TAU * float(k) / SEGMENTS
		var out := Vector3(cos(a), 0.0, sin(a))
		verts.append(out * inner)
		uvs.append(Vector2(float(k) / SEGMENTS, 0.0))
		verts.append(out)
		uvs.append(Vector2(float(k) / SEGMENTS, 1.0))
	for k in SEGMENTS:
		var i := 2 * k
		index.append_array(PackedInt32Array([i, i + 1, i + 2, i + 1, i + 3, i + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The ring where it was released, as wide as it has spread and as bright as it has faded; not on a frame its band is
## within CLEAR of the craft.
func _draw(g) -> void:
	drawn_r = -1.0
	ring_light = 0.0
	var showing := ring_t >= 0.0 and ring_r > 0.0 and _clear_of_craft(g.view.sim)
	ring.visible = showing
	if not showing:
		return
	var u := clampf(ring_t / spread_s, 0.0, 1.0)
	var light := lerpf(RING_ENERGY, RING_ENERGY * RING_END, u)
	if ring_t > spread_s:
		light *= clampf(1.0 - (ring_t - spread_s) / LINGER_S, 0.0, 1.0)
	var at: Vector3 = g.to_render(Vector3(centre.x, centre.y, ring_h + RING_LIFT))      # (the sims' frame, about the floating origin)
	ring.global_transform = Transform3D(Basis().scaled(Vector3(ring_r, 1.0, ring_r)), at)
	_mat.set_shader_parameter("energy", light)
	drawn_r = ring_r
	ring_light = light


## Is the band (BAND of the radius inward of its edge) CLEAR m or more off the pod and each engine, over the ground?
func _clear_of_craft(sim) -> bool:
	var outer := ring_r + CLEAR
	var inner := ring_r * (1.0 - BAND) - CLEAR
	for b in [sim.pod, sim.eL, sim.eR]:
		var dx: float = b.x - centre.x
		var dy: float = b.y - centre.y
		var d := sqrt(dx * dx + dy * dy)
		if d > inner and d < outer:
			return false
	return true
