## Common fittings for the two retractile fleet bays. The visible closed mesh is the
## original painted cab. Its movable panels carry the very same UVs, AO and material.
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")
const BayFinish := preload("res://view/arms/fleet_bay_finish.gdshader")
const STEEL := Color("#7d8b91")
const DARK := Color("#253039")
const BRASS := Color("#b58950")
var heat := 0.0:
	set(value):
		var next := clampf(value, 0.0, 1.0)
		if heat == next:
			return
		heat = next
		if finish:
			finish.set_shader_parameter("heat", heat)
var finish: ShaderMaterial
var doors: Dictionary = {}
var shell: MeshInstance3D
var closed_skin: Mesh
var open_skin: Mesh
var _open := false
var _last_deploy := -1.0

func fit_shell(hull: MeshInstance3D, key: String, hot: Color) -> void:
	name = &"Arms"
	shell = hull
	hull.add_child(self)
	closed_skin = hull.mesh
	var paint := closed_skin.surface_get_material(0)
	var asset := load("res://art/pilot_fleet/" + key + "_bay.glb") as PackedScene
	var source := asset.instantiate()
	for piece: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		if piece.name == &"OpenCab":
			open_skin = piece.mesh.duplicate() as ArrayMesh
			open_skin.surface_set_material(0, paint)
		else:
			var leaf := MeshInstance3D.new()
			leaf.name = piece.name
			leaf.mesh = piece.mesh
			leaf.material_override = paint
			leaf.add_to_group(&"exterior")
			add_child(leaf)
			doors[leaf.name] = leaf
	source.free()
	finish = ShaderMaterial.new()
	finish.shader = BayFinish
	finish.set_shader_parameter("hot", hot)
	finish.set_shader_parameter("heat", heat)
	visible = false

func show_bay(t: float) -> bool:
	if t == _last_deploy:
		return false
	_last_deploy = t
	var opening := t > 0.0
	if opening != _open:
		shell.mesh = open_skin if opening else closed_skin
		visible = opening
		_open = opening
	return true

func _exit_tree() -> void:
	if _open and is_instance_valid(shell):
		shell.mesh = closed_skin

func mesh_node(parent: Node3D, label: String, mesh: Mesh) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.name = label
	piece.mesh = mesh
	piece.material_override = finish
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	piece.add_to_group(&"exterior")
	parent.add_child(piece)
	return piece

## A closed, bevelled annulus in the XZ plane. Authored profile is (radius, Y);
## include the inner return in the profile to keep the centre hollow.
static func turn(profile: Array, segments: int, closed := true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(profile.size() if closed else profile.size() - 1):
		var a: Vector2 = profile[row]
		var b: Vector2 = profile[(row + 1) % profile.size()]
		var outward := Vector2(b.y - a.y, a.x - b.x).normalized()
		for i in segments:
			var angle := TAU * i / segments
			var next := TAU * (i + 1) / segments
			for v in [[a, angle], [b, next], [b, angle], [a, angle], [a, next], [b, next]]:
				var p: Vector2 = v[0]
				var c := cos(float(v[1]))
				var s := sin(float(v[1]))
				st.set_normal(Vector3(outward.x * c, outward.y, outward.x * s))
				st.add_vertex(Vector3(p.x * c, p.y, p.x * s))
	st.index()
	return st.commit()
