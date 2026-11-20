## A bounded, branching discharge. Channel shape restrikes at 22 Hz, while emitter
## attachment and its small continuous drift follow every rendered frame.
extends MeshInstance3D
const SEGMENTS := 32
const RESTRIKE := 1.0 / 22.0
const HALO_UV := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]
const RING := [Vector2(1,0), Vector2(0.5,0.8660254), Vector2(-0.5,0.8660254),
	Vector2(-1,0), Vector2(-0.5,-0.8660254), Vector2(0.5,-0.8660254)]
var channel := PackedVector3Array()
var branches: Array[PackedVector3Array] = []
var revision := 0
var _shape := PackedVector2Array()
var _branch_shapes: Array[PackedVector2Array] = []
var _age := 0.0
var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _core_material: StandardMaterial3D
var _glow_material: ShaderMaterial

func _init() -> void:
	mesh = ArrayMesh.new()   # rebuilt each frame from packed arrays (update_arc): a surface for the core, one for the glow
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rng.seed = 829371
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	_core_material = material
	_glow_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
varying vec4 arc_color;
void vertex() { arc_color = COLOR; }
void fragment() {
 float across = UV.y * 2.0 - 1.0;
 float halo = exp(-across * across * 5.5) * (1.0 - smoothstep(0.75, 1.0, abs(across)));
 ALBEDO = arc_color.rgb;
 ALPHA = arc_color.a * halo;
}
"""
	_glow_material.shader = shader

func _restrike() -> void:
	revision += 1
	_shape.resize(SEGMENTS + 1)
	_shape.fill(Vector2.ZERO)
	# Midpoint displacement has large bends with small branches on each bend,
	# rather than unrelated saw teeth at a uniform wavelength.
	var stride := SEGMENTS
	var amplitude := 0.52
	while stride > 1:
		for start in range(0, SEGMENTS, stride):
			var mid := start + stride / 2
			_shape[mid] = (_shape[start] + _shape[start + stride]) * 0.5 + Vector2(_rng.randf_range(-amplitude, amplitude), _rng.randf_range(-amplitude, amplitude))
		stride /= 2
		amplitude *= 0.64
	_branch_shapes.clear()
	for k in 3:
		var branch := PackedVector2Array([Vector2.ZERO])
		var direction := Vector2.from_angle(_rng.randf() * TAU)
		for j in range(1, 6):
			branch.append(direction * j * 0.11 + Vector2(_rng.randf_range(-0.055, 0.055), _rng.randf_range(-0.055, 0.055)))
		_branch_shapes.append(branch)

func update_arc(a: Vector3, b: Vector3, strain: float, broken: bool, delta: float) -> void:
	var built := mesh as ArrayMesh
	built.clear_surfaces()
	if broken or a.distance_squared_to(b) < 0.0001:
		channel.clear()
		branches.clear()
		return
	var dt := clampf(delta, 0.0, 0.1)
	_time += dt
	_age += dt
	if _shape.is_empty() or _age >= RESTRIKE:
		_age = fmod(_age, RESTRIKE)
		_restrike()
	var axis := (b - a).normalized()
	var u := axis.cross(Vector3.FORWARD).normalized()
	if u.length_squared() < 0.01:
		u = axis.cross(Vector3.UP).normalized()
	var w := axis.cross(u)
	var scale := clampf(a.distance_to(b) / 6.0, 0.35, 1.6)
	channel.resize(SEGMENTS + 1)
	for i in SEGMENTS + 1:
		var t := float(i) / SEGMENTS
		var drift := sin(t * PI) * sin(_time * 13.0 + t * 7.0) * 0.022
		channel[i] = a.lerp(b, t) + (u * (_shape[i].x + drift) + w * _shape[i].y) * scale
	branches.clear()
	for k in 3:
		var at := 7 + k * 8
		var path := PackedVector3Array()
		for j in 6:
			var p := _branch_shapes[k][j]
			path.append(channel[at] + (axis * j * 0.035 + u * p.x + w * p.y) * scale)
		branches.append(path)
	var hue := Color(0.18, 0.51, 1.0).lerp(Color(0.62, 0.24, 1.0), clampf(strain, 0.0, 1.0))
	var pulse := 0.88 + 0.12 * sin(_time * 37.0)
	var core := [PackedVector3Array(), PackedColorArray()]
	_tube(core, channel, 0.007, Color(1.3, 1.5, 1.7, pulse), false)
	for k in branches.size():
		var branch_color := Color(0.8, 0.9, 1.0, pulse * (0.48 + 0.3 * sin(_age / RESTRIKE * PI + k)))
		_tube(core, branches[k], 0.004, branch_color, true)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = core[0]
	arrays[Mesh.ARRAY_COLOR] = core[1]
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	built.surface_set_material(0, _core_material)
	var eye := (a + b) * 0.5 + Vector3(0, 0, 10)
	var viewport := get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport else null
	if camera:
		eye = to_local(camera.global_position)
	var glow := [PackedVector3Array(), PackedColorArray(), PackedVector2Array()]
	hue.a = 0.45 * pulse
	_halo(glow, channel, 0.10, hue, eye, false)
	for branch in branches:
		_halo(glow, branch, 0.06, Color(hue.r, hue.g, hue.b, hue.a * 0.55), eye, true)
	arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = glow[0]
	arrays[Mesh.ARRAY_COLOR] = glow[1]
	arrays[Mesh.ARRAY_TEX_UV] = glow[2]
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	built.surface_set_material(1, _glow_material)

## A camera-facing ribbon along `path` into [vertices, colours, uvs].
static func _halo(into: Array, path: PackedVector3Array, radius: float, col: Color, eye: Vector3, taper: bool) -> void:
	var offsets := PackedVector3Array()
	for i in path.size():
		var tangent := (path[mini(i+1,path.size()-1)] - path[maxi(i-1,0)]).normalized()
		var side := tangent.cross(eye - path[i]).normalized()
		if side.length_squared() < 0.01:
			side = tangent.cross(Vector3.UP).normalized()
		offsets.append(side * radius * (1.0-float(i)/(path.size()-1) if taper else 1.0))
	var verts: PackedVector3Array = into[0]
	var uvs: PackedVector2Array = into[2]
	var unit := PackedVector2Array(HALO_UV)
	for i in path.size()-1:
		verts.append_array(PackedVector3Array([path[i]-offsets[i], path[i+1]-offsets[i+1], path[i+1]+offsets[i+1],
			path[i]-offsets[i], path[i+1]+offsets[i+1], path[i]+offsets[i]]))
		uvs.append_array(unit)
	var tones: PackedColorArray = into[1]   # (one colour a tube: filled in for the vertices just added)
	var tone := PackedColorArray()
	tone.resize(verts.size() - tones.size())
	tone.fill(col)
	tones.append_array(tone)
	into[1] = tones
	into[0] = verts
	into[2] = uvs

## A six-sided tube along `path` into [vertices, colours].
static func _tube(into: Array, path: PackedVector3Array, radius: float, col: Color, taper: bool) -> void:
	var verts: PackedVector3Array = into[0]
	for i in path.size() - 1:
		var axis := (path[i + 1] - path[i]).normalized()
		var u := axis.cross(Vector3.UP).normalized()
		if u.length_squared() < 0.01:
			u = axis.cross(Vector3.RIGHT).normalized()
		var v := axis.cross(u)
		var r0 := radius * (1.0 - float(i) / (path.size() - 1) if taper else 1.0)
		var r1 := radius * (1.0 - float(i + 1) / (path.size() - 1) if taper else 1.0)
		for side in 6:
			var n0: Vector3 = u * RING[side].x + v * RING[side].y
			var n1: Vector3 = u * RING[(side + 1) % 6].x + v * RING[(side + 1) % 6].y
			var p0 := path[i] + n0 * r0
			var p2 := path[i + 1] + n1 * r1
			verts.append_array(PackedVector3Array([p0, path[i + 1] + n0 * r1, p2, p0, p2, path[i] + n1 * r0]))
	var tones: PackedColorArray = into[1]   # (one colour a tube: filled in for the vertices just added)
	var tone := PackedColorArray()
	tone.resize(verts.size() - tones.size())
	tone.fill(col)
	tones.append_array(tone)
	into[1] = tones
	into[0] = verts

