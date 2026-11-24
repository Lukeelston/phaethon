## The Basilisk's gun as a WeaponMount (view/weapons/weapon_mount.gd): its turret (view/turret.gd), slaved to the
## pilot's gaze. The fire control (view/gunnery.gd) hands it the aim and the gaze in the render frame; this turns
## them into the cab's frame the turret lays itself in, and keeps what is the turret's own: the trunnion and the
## bore (is the bore on the aim?), and the interlock (would the line cross the cab, the sight ball, or either of
## the craft's engines?). Its aim ray is the gaze: the sight is where the pilot looks, and the gun follows.
##   weapon = TurretMount.new(turret, craft)     craft: the CraftModel, whose engines the interlock keeps clear of
class_name TurretMount
extends "res://view/weapons/weapon_mount.gd"

const TurretScript := preload("res://view/turret.gd")
const ENGINE_R := 1.55            # each engine, for the interlock: three balls along it of this radius
const ENGINE_BALLS := [-3.4, 0.0, 3.2]

var turret: TurretScript
var craft                         # the CraftModel (view/craft_model.gd): its engines


func _init(gun: TurretScript, model) -> void:
	turret = gun
	craft = model


func step(delta: float, want_out: bool, aim_render: Variant, gaze_dir_render: Vector3) -> void:
	var cab_xf: Transform3D = turret.global_transform
	var aim_cab: Variant = null
	if aim_render != null:
		aim_cab = cab_xf.affine_inverse() * (aim_render as Vector3)
	turret.power = power
	turret.step(delta, want_out, aim_cab, cab_xf.basis.inverse() * gaze_dir_render)


func is_out() -> bool:
	return turret.is_out()


func ready_to_fire() -> bool:
	return turret.ready_to_fire()


func deploy_t() -> float:
	return clampf(turret.t / TurretScript.T_FREE, 0.0, 1.0)


## The gaze: down the middle of the pilot's view.
func aim_ray(cam: Camera3D) -> Array:
	return [cam.global_position, -cam.global_transform.basis.z.normalized()]


## The bore within ON_TARGET of the line from the trunnion to the target.
func on_aim(target_render: Vector3) -> bool:
	if not turret.is_out():
		return false
	var cab_xf: Transform3D = turret.global_transform
	var line_cab := cab_xf.affine_inverse() * target_render - turret.trunnion()
	var bore_cab := cab_xf.basis.inverse() * turret.bore()
	return bore_cab.angle_to(line_cab) < TurretScript.ON_TARGET


## The line from the trunnion to the target through the cab, the sight ball, or either engine.
func fouled(target_render: Vector3) -> bool:
	if not turret.is_out():
		return false
	var line_cab := turret.global_transform.affine_inverse() * target_render - turret.trunnion()
	return not turret.clear_of_cab(line_cab) or _crosses_engines(turret.global_transform * turret.trunnion(), target_render)


func muzzles() -> Array:
	return turret.muzzles()


## The trunnion (global).
func origin() -> Vector3:
	return turret.global_transform * turret.trunnion()


## The coils' glow.
func add_heat(amount: float) -> void:
	turret.heat = minf(1.0, turret.heat + amount)


func node() -> Node3D:
	return turret


# --- the turret's own, for the gaze sight (view/gunnery.gd _draw): not every mount has these ---------------

## The aim lies outside its stops (it holds at its stop).
func limited() -> bool:
	return turret.limited


## The coils' glow, 0..1.
func heat() -> float:
	return turret.heat


## The bore's line (global): out of the barrels.
func bore() -> Vector3:
	return turret.bore()


## Does the line from the gun to `to` (render frame) pass through either of the craft's engines?
func _crosses_engines(from: Vector3, to: Vector3) -> bool:
	var d := to - from
	var length := d.length()
	if length < 0.01:
		return false
	d /= length
	for eng: Node3D in craft.engines:
		for z: float in ENGINE_BALLS:
			var c: Vector3 = eng.global_transform * Vector3(0, 0, z)
			var along := (c - from).dot(d)
			if along < 0.0 or along > length:
				continue
			if (c - from - d * along).length() < ENGINE_R:
				return true
	return false
