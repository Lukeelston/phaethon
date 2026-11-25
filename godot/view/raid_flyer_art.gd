## Stateless artwork for the Network's flyer director. Distances are metres,
## +Y is up and -Z is forward for each flyer and its turret.
extends RefCounted

const DRONE_PATH := "res://art/traffic/raid_drone.glb"
const GUNSHIP_PATH := "res://art/traffic/raid_gunship.glb"
const FINISH_PATH := "res://art/traffic/fleet.tres"

# The director may preload this script on a flight with raids off. Keep each
# model cold until its first spawn, then share its mesh across future raids.
static var DRONE: PackedScene:
	get:
		if DRONE == null:
			DRONE = load(DRONE_PATH) as PackedScene
		return DRONE
static var GUNSHIP: PackedScene:
	get:
		if GUNSHIP == null:
			GUNSHIP = load(GUNSHIP_PATH) as PackedScene
		return GUNSHIP
static var FINISH: ShaderMaterial:
	get:
		if FINISH == null:
			FINISH = load(FINISH_PATH) as ShaderMaterial
		return FINISH

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
