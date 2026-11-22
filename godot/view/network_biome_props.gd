## Shared roadside meshes. The streamer chooses one shape for each tile/kind MultiMesh.
extends RefCounted
const Kit := preload("res://view/mesh_kit.gd")
const MODEL_DIR := "res://roadside/models/"
const KINDS := ["oak", "pine", "snowpine", "palm", "mangrove", "reeds", "scrub", "cactus", "rock", "farm", "outpost", "stilt", "urban", "industrial", "service", "solar", "wind", "basalt"]
const TREES := ["oak", "mangrove", "palm", "pine", "snowpine", "scrub"]
# One elaborate singleton is fine. An 8 km tile holding several hundred oaks uses its untextured mesh even up close.
const NEAR_TRIANGLES_PER_BATCH := 8192
static var far_shapes := true
var cache := {}
var proxy := {}
var far := {}
var distant := {}
var near_limit := {}
var material := ShaderMaterial.new()
var distance_material := ShaderMaterial.new()
var near_material := ShaderMaterial.new()

func _init() -> void:
	material.shader = preload("res://view/network_props.gdshader")
	distance_material.shader = material.shader
	distance_material.set_shader_parameter("linear_vertex_color", true)
	near_material.shader = preload("res://roadside/integration/roadside_near.gdshader")
	near_material.set_shader_parameter("color_atlas", preload("res://roadside/textures/roadside_color.jpg"))
	near_material.set_shader_parameter("orm_atlas", preload("res://roadside/textures/roadside_orm.png"))
	for kind: String in KINDS:
		cache[kind] = _model(kind, "near")
		proxy[kind] = _model(kind, "distance")
		near_limit[kind] = maxi(1, NEAR_TRIANGLES_PER_BATCH / triangles(cache[kind]))
		var bounds: AABB = proxy[kind].get_aabb()
		far[kind] = _fit(_make_far(kind), bounds) if kind in TREES else proxy[kind]
		distant[kind] = _fit(_make_distant(kind), bounds)

func _model(kind: String, tier: String) -> Mesh:
	var scene: PackedScene = load(MODEL_DIR + tier + "/" + kind + ".glb")
	var model := scene.instantiate()
	var node := model as MeshInstance3D
	if node == null:
		node = model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var mesh := node.mesh
	model.free()
	return mesh

# Keep the authored footprint and pivot as a tile changes detail. The far silhouettes carry
# the old procedural display-space colors; imported glTF vertex colors are already linear.
func _fit(mesh: Mesh, bounds: AABB) -> ArrayMesh:
	var old := mesh.get_aabb()
	var scale := bounds.size / old.size
	var builder := SurfaceTool.new()
	builder.append_from(mesh, 0, Transform3D(Basis.from_scale(scale), bounds.position - old.position * scale))
	return builder.commit()

## A growing thing's far shape: the same trunk, crown and colours in a few plain solids.
func _make_far(kind: String) -> ArrayMesh:
	var p := []
	var bark := Color(0.27,0.22,0.16)
	var green := Color(0.22,0.37,0.13)
	match kind:
		"oak", "mangrove":
			cyl(p,1.2,2.7,22,Vector3(0,11,0),bark,4)
			for k in [0, 3, 5]:   # three of its seven crowns, grown to fill the others' places
				var a: float = k*2.399
				var at := Vector3(cos(a)*(6+k)*0.7,24+(k%3)*4,sin(a)*(6+k)*0.7)
				p.append([Kit.ball(1.0,6),Kit.at(at,Vector3.ZERO,Vector3(10,8,11)*1.5),green*(0.72+0.055*k)])
		"palm":
			cyl(p,0.7,2,46,Vector3(0,23,0),bark,4)
			for k in 5:           # five fronds for seven
				var a := TAU*k/5
				p.append([Kit.ball(1,4),Kit.at(Vector3(cos(a)*11,44,sin(a)*11),Vector3(0,-a,0.2),Vector3(17,2.4,5.5)),green*(0.8+k*0.035)])
		"pine", "snowpine":
			cyl(p,0.5,1.6,33,Vector3(0,16.5,0),bark,4)
			cyl(p,0.2,12,20,Vector3(0,14,0),Color(0.12,0.25,0.18),5)
			cyl(p,0.2,7.5,18,Vector3(0,27,0),Color(0.12,0.25,0.18),5)
			if kind == "snowpine":
				cyl(p,0,9,13,Vector3(0,18,0),Color(0.85,0.89,0.91),5)
				cyl(p,0,5.5,12,Vector3(0,31,0),Color(0.85,0.89,0.91),5)
		"scrub":
			for z in [0.0, 4.0]:
				p.append([Kit.ball(1.0,6),Kit.at(Vector3(2.5,2,z),Vector3.ZERO,Vector3(5.5,2.6,3.6)),Color(0.43,0.43,0.28)])
	return Kit.compound(p)

## ... and its distant one: a trunk and one solid for the crown.
func _make_distant(kind: String) -> ArrayMesh:
	var p := []
	var bark := Color(0.27,0.22,0.16)
	var green := Color(0.22,0.37,0.13)
	match kind:
		"oak", "mangrove":
			cyl(p,1.5,2.7,22,Vector3(0,11,0),bark,3)
			p.append([Kit.ball(1.0,6),Kit.at(Vector3(0,27,0),Vector3.ZERO,Vector3(21,11,21)),green*0.86])
		"palm":
			cyl(p,0.9,2,46,Vector3(0,23,0),bark,3)
			p.append([Kit.ball(1.0,6),Kit.at(Vector3(0,44.5,0),Vector3.ZERO,Vector3(22,3.2,22)),green*0.88])
		"pine", "snowpine":
			cyl(p,0.2,11,34,Vector3(0,19,0),Color(0.12,0.25,0.18),5)
			if kind == "snowpine":
				cyl(p,0,7.5,20,Vector3(0,27,0),Color(0.85,0.89,0.91),5)
		"scrub":
			p.append([Kit.ball(1.0,4),Kit.at(Vector3(2.5,2,2),Vector3.ZERO,Vector3(5.5,2.6,5.5)),Color(0.43,0.43,0.28)])
		"service":
			box(p,Vector3(19,1,7),Vector3(0,5,2),Color(0.82,0.62,0.36))
			box(p,Vector3(9,4,5),Vector3(-5,2,-4),Color(0.57,0.53,0.43))
		"farm", "industrial", "outpost":
			box(p,Vector3(8,4,6),Vector3(-4,2,0),Color(0.59,0.47,0.36))
			cyl(p,2,2,7,Vector3(3,3.5,1),Color(0.56,0.58,0.57),5)
		"stilt":
			box(p,Vector3(8,4,7),Vector3(0,6,0),Color(0.48,0.39,0.29))
			box(p,Vector3(1,5,1),Vector3(0,2.5,0),bark)
		"urban":
			for i in 3:
				box(p,Vector3(3,4+i,4),Vector3(-4+i*4,2+i*0.5,i%2*4),Color(0.44,0.49,0.49))
		"solar":
			box(p,Vector3(8,0.8,6),Vector3.ZERO,Color(0.15,0.24,0.30))
			box(p,Vector3(8,0.8,6),Vector3(0,0.3,8),Color(0.16,0.23,0.29))
		"wind":
			cyl(p,0.12,0.45,8,Vector3(0,4,0),Color(0.72,0.73,0.69),4)
			for k in 3:
				var turn := TAU*k/3.0
				p.append([Kit.box(Vector3(0.27,3.5,0.16)),Kit.at(Vector3(-sin(turn)*1.75,8+cos(turn)*1.75,0.5),Vector3(0,0,turn)),Color(0.80,0.80,0.77)])
		"reeds", "cactus":
			for i in 3:
				cyl(p,0.2,0.6,4+i,Vector3(i*1.5,2+i*0.5,i%2),Color(0.36,0.42,0.21),3)
		"rock", "basalt":
			for i in 3:
				cyl(p,1.5,2.1,2+i,Vector3(i*2.0,1+i*0.5,i%2),Color(0.30+i*0.03,0.30+i*0.03,0.28+i*0.03),4)
	return Kit.compound(p)

## Retier in place so the tile keeps exactly one batch, transform buffer and reveal clock per kind.
func detail(batch: MultiMeshInstance3D, level: int) -> void:
	var kind := String(batch.name)
	var mesh: Mesh
	if far_shapes and level == 2:
		mesh = distant[kind]
	elif far_shapes and level == 1:
		mesh = far[kind]
	elif batch.multimesh.instance_count <= near_limit[kind]:
		mesh = cache[kind]
	else:
		mesh = proxy[kind]
	if batch.multimesh.mesh != mesh:
		batch.multimesh.mesh = mesh
	if mesh == cache[kind]:
		batch.material_override = near_material
	elif mesh == proxy[kind]:
		batch.material_override = distance_material
	else:
		batch.material_override = material

static func triangles(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var index = arrays[Mesh.ARRAY_INDEX]
		n += (index.size() if index != null and index.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n

func box(parts: Array, size: Vector3, p: Vector3, c: Color, angle := 0.0) -> void:
	parts.append([Kit.box(size), Kit.at(p,Vector3(0,angle,0)),c])
func cyl(parts: Array, top: float, bottom: float, h: float, p: Vector3, c: Color, sides := 8) -> void:
	parts.append([Kit.cyl(top,bottom,h,sides),Kit.at(p),c])
func batch(parent: Node3D, kind: String, transforms: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = distant[kind]
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i,transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = kind
	instance.multimesh = mm
	detail(instance, 2)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = 38000 # shader fades individual fragments before this bound
	instance.set_instance_shader_parameter("stream_reveal",0.0)
	parent.add_child(instance)
