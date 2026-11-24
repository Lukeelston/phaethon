## What the fire control (view/gunnery.gd) fires through: a craft's weapon, whatever it is. The fire control finds
## what the aim is on, leads it, and fires while the trigger is held and the mount says it may; the mount is the
## weapon's own: how it comes out, where it looks from and along, whether it is on the aim and clear of the craft,
## where its bolts leave it, and its heat. Each craft's mount is built with its model (view/craft_model.gd `weapon`):
##   the Basilisk   view/weapons/turret_mount.gd: its gaze-slaved turret (view/turret.gd)
## The bodies here are the defaults: a mount that never comes out and never fires.
##   g.mount = craft.weapon; g.mount.power = power; g.mount.step(delta, want_out, aim_render, gaze_dir_render)
class_name WeaponMount
extends RefCounted

var power := 1.0           # the battery bus (the start-up): the fire control sets it before each step


## Each frame. want_out: the switch, with power. aim_render: the point to lay on (render frame), or null (hold, or
## go home). gaze_dir_render: where the pilot looks (a unit direction, render frame).
func step(_delta: float, _want_out: bool, _aim_render: Variant, _gaze_dir_render: Vector3) -> void:
	pass


## Out and free to fire?
func is_out() -> bool:
	return false


## Out, asked out, and its aim within what it can reach? (The fire control also wants it on the aim and clear.)
func ready_to_fire() -> bool:
	return false


## How far out it is: 0 stowed .. 1 out.
func deploy_t() -> float:
	return 0.0


## The ray the aim is looked for along: [origin, unit direction], render frame. A turret's is the gaze; fixed
## guns' their bore.
func aim_ray(cam: Camera3D) -> Array:
	return [cam.global_position, -cam.global_transform.basis.z.normalized()]


## Is it laid on `target_render` (render frame), near enough to fire?
func on_aim(_target_render: Vector3) -> bool:
	return false


## Would its line of fire to `target_render` (render frame) cross the craft itself?
func fouled(_target_render: Vector3) -> bool:
	return false


## Where the bolts leave it (global Vector3s), taken in turn.
func muzzles() -> Array:
	return []


## Where its fire comes from (global): the lead is reckoned from here.
func origin() -> Vector3:
	return Vector3.ZERO


## A shot's heat, 0..1 of its glow.
func add_heat(_amount: float) -> void:
	pass


## How far off its line (degrees) the fire control may take a target for it: 0 for a turret, which lays itself.
func assist_deg() -> float:
	return 0.0


## Where its sounds hang (the servo, the shots).
func node() -> Node3D:
	return null
