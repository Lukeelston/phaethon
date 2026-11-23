## Starter's bridge downtrack of the front row. Three banks fill red, then go green together.
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")
const DISTANCE := 175.0
var lamps: Array[MeshInstance3D] = []
var dark := StandardMaterial3D.new()
var red := StandardMaterial3D.new()
var green := StandardMaterial3D.new()
var _state := -1
var anchor := Vector2.ZERO

func build(race) -> void:
	var sim = race.sim
	var i: int = race._sample(DISTANCE, 0)
	var forward := Vector2(sim.ttx[i], sim.tty[i])
	anchor = Vector2(sim.tpx[i], sim.tpy[i]) + forward * (DISTANCE - race.cum[i])
	basis = Basis.looking_at(Vector3(forward.x, 0.0, -forward.y))
	var span: float = sim.tw[i] + 8.0
	var steel := Color(0.17, 0.19, 0.22)
	var parts := []
	for side in [-1.0, 1.0]:
		parts.append([Kit.box(Vector3(1.2, 14.0, 1.2)), Kit.at(Vector3(side * span * 0.5, 7, 0)), steel])
	parts.append([Kit.box(Vector3(span + 1.2, 1.0, 1.0)), Kit.at(Vector3(0, 13.5, 0)), steel])
	parts.append([Kit.box(Vector3(13.0, 3.4, 1.4)), Kit.at(Vector3(0, 12, 0)), Color(0.045, 0.05, 0.06)])
	var bridge := MeshInstance3D.new()
	bridge.mesh = Kit.compound(parts)
	bridge.material_override = Kit.vertex_colors()
	bridge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bridge)
	dark.albedo_color = Color(0.12, 0.075, 0.06)
	red.albedo_color = Color(2.2, 0.035, 0.016)
	green.albedo_color = Color(0.015, 2.0, 0.45)
	var lens := SphereMesh.new()
	lens.radius = 1.22
	lens.height = 2.44
	lens.radial_segments = 16
	lens.rings = 6
	for material in [dark, red, green]:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for k in 3:
		var lamp := MeshInstance3D.new()
		lamp.mesh = lens
		lamp.position = Vector3(4.0 * (k - 1), 12.0, 0.76)
		lamp.scale.z = 0.24
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lamp)
		lamps.append(lamp)

func sync(race) -> void:
	position = race._w(anchor.x, anchor.y, 0.0)
	visible = absf(position.x) < 1600.0 and absf(position.z) < 1600.0
	if not visible:
		return
	var state := 0
	if race.false_start:
		state = 3
	elif not race.started:
		state = 4 - ceili(race.lights)
	elif race.clock < 2.0:
		state = 4
	if state != _state:
		_state = state
		for k in lamps.size():
			lamps[k].material_override = green if state == 4 else (red if k < state else dark)
