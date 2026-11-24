## Stateless artwork for the Network's flyer director. Distances are metres,
## +Y is up and -Z is forward for each flyer and its turret.
extends RefCounted

const DRONE := preload("res://art/traffic/raid_drone.glb")
const GUNSHIP := preload("res://art/traffic/raid_gunship.glb")
const FINISH := preload("res://art/traffic/fleet.tres")

## Build once per active raid. Write local poses, then set visible_instance_count.
static func drone_batch(capacity := 10) -> MultiMeshInstance3D:
	var imported := DRONE.instantiate()
	var body := imported as MeshInstance3D if imported is MeshInstance3D else imported.get_node("Drone") as MeshInstance3D
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = body.mesh
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	imported.free()
	var swarm := MultiMeshInstance3D.new()
	swarm.name = "RaidDrones"
	swarm.multimesh = mm
	swarm.material_override = FINISH
	swarm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return swarm

## TurretPivot rotates in yaw, TurretPivot/Cradle in pitch. The muzzle marker
## lies midway between the mouths. All three transforms follow their parent.
static func gunship() -> Node3D:
	var ship := GUNSHIP.instantiate() as Node3D
	ship.name = "RaidGunship"
	for part in ship.find_children("*", "MeshInstance3D", true, false):
		var mesh := part as MeshInstance3D
		mesh.material_override = FINISH
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ship
