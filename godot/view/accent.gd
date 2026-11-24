## The livery's accent on the authored fittings (view/livery.gd): their orange enamel, thread and
## anodised bands are painted into their maps, so a livery other than Ember draws each with
## view/accent_recolour.gdshader over the fitting's own maps instead of its own material. Ember
## draws them exactly as they were made: nothing here touches them.
##   Accent.dress(mesh_instance)            after its mesh is set: an override, or none for Ember
##   Accent.of(material, glow)              the material to draw `material` with
##   Accent.turned(material, colour)        ... with its orange turned to `colour`, whatever the livery
extends RefCounted

const Livery := preload("res://view/livery.gd")
const SHADER := preload("res://view/accent_recolour.gdshader")

static var _made := {}    # [source material id, livery, glow] -> ShaderMaterial


static func of(source: Material, glow := Color(0, 0, 0)) -> Material:
	var accent = Livery.accent()
	var plain := source as BaseMaterial3D
	if accent == null or plain == null or plain.albedo_texture == null:
		return source
	return _recolour(plain, accent, [plain.get_instance_id(), Livery.current, glow], glow)


## A fitting's material with its orange turned to `colour` (the Shrike's coaming takes its livery's paint,
## view/shrike_airframe.gd), made once and kept.
static func turned(source: Material, colour: Color, glow := Color(0, 0, 0)) -> Material:
	var plain := source as BaseMaterial3D
	if plain == null or plain.albedo_texture == null:
		return source
	return _recolour(plain, colour, [plain.get_instance_id(), colour, glow], glow)


static func _recolour(plain: BaseMaterial3D, c: Color, key: Array, glow: Color) -> Material:
	if _made.has(key):
		return _made[key]
	# (the shader reads the maps as they are displayed: the accent's hue, saturation and value there)
	var made := ShaderMaterial.new()
	made.shader = SHADER
	made.set_shader_parameter("albedo_map", plain.albedo_texture)
	made.set_shader_parameter("normal_map", plain.normal_texture)
	made.set_shader_parameter("orm_map", plain.roughness_texture if plain.roughness_texture else plain.metallic_texture)
	made.set_shader_parameter("accent_hsv", Vector3(c.h, c.s, c.v))
	made.set_shader_parameter("normal_depth", plain.normal_scale if plain.normal_enabled else 0.0)
	made.set_shader_parameter("occlusion", plain.ao_light_affect if plain.ao_enabled else 0.0)
	made.set_shader_parameter("glow", Vector3(glow.r, glow.g, glow.b))
	_made[key] = made
	return made


## Give a fitting the accent: an override on the instance (its mesh, and its mesh's material, are
## shared and stay as they were made). A fitting of several surfaces gets one each.
static func dress(fitting: MeshInstance3D) -> void:
	if fitting == null or fitting.mesh == null or Livery.accent() == null:
		return
	for s in fitting.mesh.get_surface_count():
		var own := fitting.mesh.surface_get_material(s)
		var turned := of(own)
		if turned != own:
			fitting.set_surface_override_material(s, turned)


## ... and every mesh under a node (an engine's shell, as it comes from its scene).
static func dress_all(under: Node) -> void:
	for part: MeshInstance3D in under.find_children("*", "MeshInstance3D", true, false):
		dress(part)
