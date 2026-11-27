## The Kiln's plasma lance as a WeaponMount (view/weapons/weapon_mount.gd), on Codex's arms (view/arms/kiln_arms.gd: an
## induction lance on a parallel lift that rises out of the starboard foredeck's well, its barrel kept pointing ahead). It
## fires for itself (own_fire): the fire control (view/gunnery.gd) looks along the beam for what is on it (aim_ray: the
## beam is the aim, so the gaze sight stands where the beam goes) and hands this the trigger each frame (fire); this
## keeps the beam, its hits and its heat. Its figures are the craft's weapon row (sim/pilot_craft.gd TRAITS[..].weapon:
## reach, coneDeg, dps, fireS, coolS).
##   the beam   from the emitter's mouth along the gaze, held inside coneDeg of the craft's forward (the barrel's own line,
##              which Codex's lift keeps along the hull's); a gaze further off leaves it at the cone's edge, and the gaze
##              sight is told it is held there (limited). It runs `reach` m, or to the ground (the fire control's own
##              search along it: g.aim_ground), or to the first hostile on it: a raider's capsule or a flyer's sphere, as
##              the fire control's aim sees each (view/network_traffic.gd ray_car, view/raid_flyers.gd ray_flyer), among the
##              raid's threats() alone. Commuters are not looked for at all: no hit, no spark, no strike, no charge.
##   fire       while the trigger is held (the lance out and asked out) and it is not cooling, the beam is on: the hostile
##              it ends on takes dps hits a second through g.damage, whole hits (the fraction of one left over each frame
##              carried into the next, so 30 a second holds at any frame rate, and dropped when the beam goes off), bare:
##              no spark or impact sound of a hit's own (Ruling T: the glow at the beam's end is the hit's picture, the
##              hum its sound; a kill's burst and its sound stay). fire_s counts the burn up; at fireS it overheats and
##              cools coolS ("GUN HOT", then "GUN READY": status(), which the fire control says on the strip). Off, fire_s
##              drains back at the cooling's pace (fireS over coolS), so letting go a moment does not start the count
##              again. The cooling's clock runs whatever the switch does: thrown to SAFE and back it is not refilled.
##   drawn      one ribbon from the mouth to the beam's end (view/weapons/lance_beam.gdshader: as wide as BEAM_WIDTH of the
##              view wherever it is, a thin line from the mouth to 600 m out) and a glow at the end (the fire control's
##              glow, GLOW_DEG wide): nothing nearer the eye than the mouth, nothing fills the view, nothing moves the
##              camera or the cockpit. The emitter's heat follows fire_s / fireS.
##   felt       buzz(): a light steady buzz in the left hand while it burns (vr/vr_cockpit.gd _gun_buzz)
##   sounds     its hum (audio/raid_sounds.gd lance_hum), a loop at the mount the frames the beam burns, stopped in the
##              frame it goes off for whatever reason (g.own_loop, called every frame of fire), unheard. With none made
##              (Raids off, --mute, a shot, a source missing): its stand-in, the turret's servo higher, again every HUM_EVERY s
## Its arms are fitted on the hull the pilot sees (view/fleet_airframe.gd ensure_arms: the hull last dressed, the VR
## seat's own, else the craft's pod) the first time the GUN asks them out: a flight with Raids off that never arms them
## builds none of them, nor this one's drawing. With Raids on they are fitted at load, stowed (prepare).
##   weapon = LanceMount.new(craft)      craft: the CraftModel (view/craft_model.gd): its view, sim and fleet airframe
class_name LanceMount
extends "res://view/weapons/weapon_mount.gd"

const GunneryScript := preload("res://view/gunnery.gd")
const PilotCraft := preload("res://sim/pilot_craft.gd")
const BeamShader := preload("res://view/weapons/lance_beam.gdshader")
const DEPLOY_S := 1.0             # s from stowed to out: the leaves open and the lift raises the lance (the fixed guns' figure)
const BEAM_WIDTH := 0.0105        # rad of view across the beam, wherever it is (a bolt's streak's: view/gunnery.gd BOLT_WIDTH)
const BEAM_ENERGY := 2.2          # ... its light (a bolt's runs to 2.6)
const END_FADE := 0.15            # with nothing at its end (at reach, in the air) it fades out over this much of its length
const GLOW_DEG := 1.4             # the glow at the beam's end: this wide, degrees of view (the boresight ring's 1.6) ...
const GLOW_ON_HOSTILE := 1.6      # ... this much wider on a hostile ...
const GLOW_COL := Color(1.0, 0.6, 0.25)
const GLOW_LIGHT := {"hostile": 2.2, "ground": 1.2, "air": 0.4}      # ... and this bright, by what it ends on
const BUZZ_AMP := 0.15            # the hand's buzz while it burns (a gun tick is 0.22, the power's felt 0.35)
const HUM_EVERY := 0.9            # (with no hum made, its stand-in: the turret's servo, higher, again this often while it burns)

var craft                         # the CraftModel (view/craft_model.gd)
var arms = null                   # Codex's arms (view/arms/kiln_arms.gd), fitted at the first arming
var t := 0.0                      # 0 stowed .. 1 out
var reach := 600.0                # the row's figures
var cone := deg_to_rad(25.0)      # rad
var dps := 30.0
var fire_max := 2.5               # (fireS)
var cool_s := 3.0
var burning := false              # the beam on this frame
var fire_s := 0.0                 # s of burn heat, 0 .. fire_max
var hot := 0.0                    # s of cooling left (0: it burns)
var beam_from := Vector3.ZERO     # the beam (render frame): from the mouth, along a unit direction, beam_len m (0 while off)
var beam_dir := Vector3.FORWARD
var beam_len := 0.0
var on_beam = null                # the hostile the beam ends on this frame (a Car or a flyer), or null
var beam: MeshInstance3D = null   # the ribbon (made with the arms' first frame: _build_drawing) ...
var glow: MultiMesh = null        # ... and the glow at its end
var glow_at := Vector3.INF        # where the glow was drawn this frame, INF for nowhere (tests read it: headless, a batch keeps none)
var cost_ms := 0.0                # what the last frame's step and fire took (tests read it)
var _beam_mat: ShaderMaterial
var _asked := false               # asked out this frame (the switch, with power)
var _shown := -1.0                # the deploy the arms were last set to
var _limited := false             # the gaze outside the cone this frame
var _carry := 0.0                 # the fraction of a hit carried into the next frame
var _cooled := false              # cooled since it last overheated (status: GUN READY)
var _ends := "air"                # what the beam ends on: "hostile", "ground" or "air"
var _burn_s := 0.0                # s of this burn (the log)
var _hum := 0.0                   # s till the hum's stand-in again (with no hum made)
var _step_us := 0


func _init(model) -> void:
	craft = model
	var row: Dictionary = model.view.sim.traits.get("weapon", {})
	reach = float(row.get("reach", reach))
	cone = deg_to_rad(float(row.get("coneDeg", 25.0)))
	dps = float(row.get("dps", dps))
	fire_max = maxf(0.01, float(row.get("fireS", fire_max)))
	cool_s = maxf(0.01, float(row.get("coolS", cool_s)))


func step(delta: float, want_out: bool, _aim_render: Variant, _gaze_dir_render: Vector3) -> void:
	var t0 := Time.get_ticks_usec()
	_asked = want_out
	if want_out and arms == null:
		_fit_arms()
	t = move_toward(t, 1.0 if want_out else 0.0, delta / DEPLOY_S)
	if arms != null and t != _shown:
		_shown = t
		arms.set_deploy(t)
	if hot > 0.0:      # (the cooling's clock: it runs whatever the switch does)
		hot -= delta
		if hot <= 1e-6:
			hot = 0.0
			_cooled = true
			_tell("ready (cooled)")
	_step_us = Time.get_ticks_usec() - t0


## Raids on (its fire control made at load, dormant; Ruling D): the arms fitted now, stowed, so the first arming fits
## none in its frame. With Raids off they stay unbuilt until the GUN asks them out.
func prepare() -> void:
	if arms == null:
		_fit_arms()


## Raids on (weapon_mount.gd prepare_drawing): the beam's ribbon and glow made now, hidden, so the first arming's frame
## does not compile the beam's pipeline.
func prepare_drawing(g) -> void:
	if beam == null and arms != null:
		_build_drawing(g)


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


## The emitter's mouth (global; its -Z the barrel's line), or null before the arms are fitted.
func _mouth() -> Variant:
	if arms == null:
		return null
	var mouths: Array = arms.muzzles()
	return mouths[0] if not mouths.is_empty() else null


func is_out() -> bool:
	return t >= 1.0


func ready_to_fire() -> bool:
	return is_out() and _asked


func deploy_t() -> float:
	return t


## The beam: from the mouth along the gaze (the camera's), held inside the cone about the barrel's line. Before the arms
## are fitted, the gaze from the eye. (Asked once a frame, before the mount's step: the beam's line is kept for fire.)
func aim_ray(cam: Camera3D) -> Array:
	var gaze := -cam.global_transform.basis.z.normalized()
	var m = _mouth()
	if m == null:
		_limited = false
		return [cam.global_position, gaze]
	var forward := (-(m as Transform3D).basis.z).normalized()
	beam_from = (m as Transform3D).origin
	_limited = forward.angle_to(gaze) > cone + 1e-6
	beam_dir = _within(forward, gaze, cone) if _limited else gaze
	return [beam_from, beam_dir]


## `want` (a unit vector) turned toward `forward` until it is within `most` rad of it.
static func _within(forward: Vector3, want: Vector3, most: float) -> Vector3:
	var axis := forward.cross(want)
	if axis.length_squared() < 1e-12:      # (straight behind: any way round)
		axis = forward.cross(Vector3.UP if absf(forward.y) < 0.9 else Vector3.RIGHT)
	return forward.rotated(axis.normalized(), most).normalized()


## The mouth (global).
func muzzles() -> Array:
	var m = _mouth()
	return [] if m == null else [(m as Transform3D).origin]


## The mouth, or the hull before the arms are fitted.
func origin() -> Vector3:
	var m = _mouth()
	return (m as Transform3D).origin if m != null else _hull().global_position


## The hull: the fire control's players (the hum's loop) hang there, where the arms are fitted.
func node() -> Node3D:
	return _hull()


func heat() -> float:
	return arms.heat if arms != null else 0.0


## The gaze outside the cone: the beam is held at its edge.
func limited() -> bool:
	return _limited


func own_fire() -> bool:
	return true


func own_sounds() -> Array:
	return ["lance_hum"]


## "GUN HOT" while it cools, "GUN READY" once it has cooled, else "".
func status() -> String:
	if hot > 0.0:
		return "GUN HOT"
	return "GUN READY" if _cooled else ""


## A light steady buzz while it burns.
func buzz() -> float:
	return BUZZ_AMP if burning else 0.0


# --- each frame, from the fire control -------------------------------------------------------------------------

func fire(g, delta: float, pulling: bool) -> void:
	var t0 := Time.get_ticks_usec()
	if beam == null and arms != null:
		_build_drawing(g)
	var on := pulling and hot <= 0.0 and arms != null
	if on and not burning:
		_burn_s = 0.0
		_hum = 0.0
		_tell("fired")
	elif burning and not on and hot <= 0.0:
		_tell("ended after %.1f s of burn" % _burn_s)
	on_beam = null
	if on:
		_burn(g, delta)
	else:
		_carry = 0.0      # (the remainder dropped: the beam is off)
		beam_len = 0.0
		fire_s = maxf(0.0, fire_s - delta * fire_max / cool_s)
	burning = on
	if not g.own_loop("lance_hum", on) and on:      # (no hum made: its stand-in, again every HUM_EVERY s of the burn)
		_hum -= delta
		if _hum <= 0.0:
			_hum = HUM_EVERY
			g.play_own("gun", "lance_hum")
	if arms != null:
		arms.heat = fire_s / fire_max
	if beam != null:
		_draw(g)
	cost_ms = (_step_us + Time.get_ticks_usec() - t0) / 1000.0


## A frame of the beam on: where it ends, the hits on what it ends on, and the heat.
func _burn(g, delta: float) -> void:
	var o: Vector3 = g.to_sim(beam_from)
	var d := GunneryScript.dir_to_sim(beam_dir)
	var end := reach
	_ends = "air"
	if g.aim_ground >= 0.0 and g.aim_ground < end:
		end = g.aim_ground
		_ends = "ground"
	var traffic = g.view.traffic_net
	var raid = g.view.get("raids")
	var flyers = raid.get("flyers") if raid != null else null
	for c in g.threats():      # (the raid's raiders and flyers: never a commuter)
		var at := -1.0
		if GunneryScript._is_flyer(c):
			if flyers != null:
				at = flyers.ray_flyer(c, o, d)
		elif traffic != null:
			at = traffic.ray_car(c, o, d)
		if at >= 0.0 and at < end and g.alive(c):
			end = at
			on_beam = c
			_ends = "hostile"
	beam_len = end
	_carry += dps * delta
	var n := floori(_carry + 1e-6)
	_carry -= n
	if on_beam != null and n > 0:
		g.damage(on_beam, n, o + d * end, false, true)      # (bare: Ruling T)
	_burn_s += delta
	fire_s += delta
	if fire_s >= fire_max - 1e-6:      # (overheated: this frame is its last)
		fire_s = fire_max
		hot = cool_s
		_cooled = false
		_tell("ended (overheated after %.1f s of burn: %.0f s to cool)" % [_burn_s, cool_s])


## The lance's word in the log, as the fire control tells a gun's ("GUN: Kiln Six lance fired").
func _tell(what: String) -> void:
	var id: String = craft.view.sim.P.vehicle
	print("GUN: %s %s %s" % [PilotCraft.NAMES.get(id, id.capitalize()), PilotCraft.weapon_of(id), what])


# --- drawing ----------------------------------------------------------------------------------------------------

## The ribbon and the glow, under the fire control (drawn about the floating origin as its own are).
func _build_drawing(g) -> void:
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = BeamShader
	_beam_mat.render_priority = 1      # (as the fire control's glow)
	_beam_mat.set_shader_parameter("width", BEAM_WIDTH)
	_beam_mat.set_shader_parameter("energy", BEAM_ENERGY)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.orientation = PlaneMesh.FACE_Y
	beam = MeshInstance3D.new()
	beam.name = "LanceBeam"
	beam.mesh = quad
	beam.material_override = _beam_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.extra_cull_margin = 16384.0      # (its width is made in its shader)
	beam.visible = false
	g.add_child(beam)
	var discs := MultiMeshInstance3D.new()      # (one disc of the fire control's glow, in a batch of one for its colour)
	discs.name = "LanceGlow"
	glow = MultiMesh.new()
	glow.transform_format = MultiMesh.TRANSFORM_3D
	glow.use_colors = true
	glow.mesh = GunneryScript._disc()
	glow.instance_count = 1
	glow.visible_instance_count = 0
	discs.multimesh = glow
	discs.material_override = GunneryScript._glow_material(false)
	discs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	discs.custom_aabb = AABB(Vector3(-30000, -30000, -30000), Vector3(60000, 60000, 60000))
	g.add_child(discs)


## The ribbon from the mouth to the beam's end, and the glow there; neither while the beam is off.
func _draw(g) -> void:
	var showing := burning and beam_len > 0.01
	beam.visible = showing
	glow.visible_instance_count = 1 if showing else 0
	glow_at = Vector3.INF
	if not showing:
		return
	var end := beam_from + beam_dir * beam_len
	var z := -beam_dir
	var x := z.cross(Vector3.UP if absf(z.y) < 0.98 else Vector3.RIGHT).normalized()
	beam.global_transform = Transform3D(Basis(x, z.cross(x), z * beam_len), (beam_from + end) * 0.5)
	_beam_mat.set_shader_parameter("span", beam_len)
	_beam_mat.set_shader_parameter("fade_out", beam_len * END_FADE if _ends == "air" else 1.0)
	var eye: Vector3 = g.view.cam.global_position
	var size := 2.0 * eye.distance_to(end) * tan(deg_to_rad(GLOW_DEG) * 0.5) * (GLOW_ON_HOSTILE if _ends == "hostile" else 1.0)
	glow.set_instance_transform(0, Transform3D(Basis().scaled(Vector3.ONE * size), end))
	glow.set_instance_color(0, GLOW_COL * float(GLOW_LIGHT[_ends]))
	glow_at = end
