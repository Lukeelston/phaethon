## Fixed guns as a WeaponMount (view/weapons/weapon_mount.gd): the Phaethon's engine-nose cannons and the Talon's wing
## guns (view/arms/<craft>_arms.gd), fixed forward, so they are aimed by pointing the craft (Raids, 2026-11-24).
## The bore is the craft's way: the pod's velocity in the sims' frame (its heading when slow), climbing as the craft is
## drawn climbing (view/craft_model.gd: its climb over its speed; a deck road's own pitch), level with the road. It is
## never the drawn barrels' -Z: in the VR seat those ride the hull's nose-down pitch (vr_cockpit.gd POD_PITCH) and
## would aim low. The muzzles give only where the bolts start; the aim is looked for from between them, along the bore.
## On the aim: within the craft's assistDeg (sim/pilot_craft.gd TRAITS[..].weapon) of the bore, where the fire
## control's assist lays the bolts on a raider (view/gunnery.gd _assist). Nothing of the craft fouls them. The GUN
## switch brings the arms out over DEPLOY_S; each shot warms the barrels' glow, which fades as the Basilisk's coils do.
##   weapon = FixedGunsMount.new(arms, craft)     craft: the CraftModel (its view's sim gives the craft's way)
class_name FixedGunsMount
extends "res://view/weapons/weapon_mount.gd"

const DEPLOY_S := 1.0             # s from stowed to out: the ports open, then the barrels run out
const HEAT_FADE := 2.2            # the barrels' glow fades this much a second (the Basilisk's coils: view/turret.gd)
const SLOW := 5.0                 # m/s: slower than this the bore is the pod's heading, level (the model's climb rule)

var arms                          # the craft's arms: build, set_deploy, muzzles, heat
var craft                         # the CraftModel (view/craft_model.gd)
var t := 0.0                      # 0 stowed .. 1 out
var _asked := false               # asked out this frame (the switch, with power)
var _assist := 0.0                # degrees: the craft's assistDeg
var _shown := 0.0                 # the deploy the arms were last set to


func _init(hardware, model) -> void:
	arms = hardware
	craft = model
	var row: Dictionary = model.view.sim.traits.get("weapon", {})
	_assist = float(row.get("assistDeg", 0.0))


func step(delta: float, want_out: bool, _aim_render: Variant, _gaze_dir_render: Vector3) -> void:
	_asked = want_out
	t = move_toward(t, 1.0 if want_out else 0.0, delta / DEPLOY_S)
	if t != _shown:
		_shown = t
		arms.set_deploy(t)
	if arms.heat > 0.0:
		arms.heat = maxf(0.0, arms.heat - delta * HEAT_FADE)


func is_out() -> bool:
	return t >= 1.0


func ready_to_fire() -> bool:
	return is_out() and _asked


func deploy_t() -> float:
	return t


## From between the muzzles, along the craft's way.
func aim_ray(_cam: Camera3D) -> Array:
	return [origin(), bore()]


## Within the assist cone about the bore, seen from between the muzzles.
func on_aim(target_render: Vector3) -> bool:
	var line := target_render - origin()
	if line.length_squared() < 1e-4:
		return false
	return rad_to_deg(bore().angle_to(line)) <= _assist + 1e-3


func fouled(_target_render: Vector3) -> bool:
	return false


func muzzles() -> Array:
	var out := []
	for m: Transform3D in arms.muzzles():
		out.append(m.origin)
	return out


## Between the muzzles (global): the lead is reckoned from here.
func origin() -> Vector3:
	var mouths: Array = arms.muzzles()
	var at := Vector3.ZERO
	for m: Transform3D in mouths:
		at += m.origin
	return at / maxf(1.0, mouths.size())


## The barrels' glow.
func add_heat(amount: float) -> void:
	arms.heat = minf(1.0, arms.heat + amount)


func assist_deg() -> float:
	return _assist


## The arms: the servo and the shots sound from the guns.
func node() -> Node3D:
	return arms


func boresight() -> bool:
	return true


func heat() -> float:
	return arms.heat


## The craft's way (global, a unit vector): the pod's velocity, or its heading when slower than SLOW; its climb as
## the model draws the pod's (its vertical speed over its speed; on a deck road, the deck's pitch under it).
func bore() -> Vector3:
	var sim = craft.view.sim
	var p = sim.pod
	var vh: float = sqrt(p.vx * p.vx + p.vy * p.vy)
	var ahead := Vector2(p.vx, p.vy) / vh if vh > SLOW else Vector2(cos(p.th), sin(p.th))
	var climb: float = atan2(p.vz, maxf(vh, 1.0)) if vh > SLOW else 0.0
	if sim.kind == "network" and not p.off_road and sim.roads[p.path].deck:
		climb = sim.deck_pitch(p)
	return Vector3(ahead.x * cos(climb), sin(climb), -ahead.y * cos(climb))      # (the sims' (x, y, up) to the render frame's (x, up, -y))
