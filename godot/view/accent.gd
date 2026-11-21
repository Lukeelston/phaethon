## The livery's accent on the authored fittings (view/livery.gd): their orange enamel, thread and
## anodised bands are painted into their maps, so a livery other than Ember draws each with
## view/accent_recolour.gdshader over the fitting's own maps instead of its own material. Ember
## draws them exactly as they were made: nothing here touches them.
##   Accent.dress(mesh_instance)            after its mesh is set: an override, or none for Ember
##   Accent.of(material, glow)              the material to draw `material` with
extends RefCounted

const Livery := preload("res://view/livery.gd")
const SHADER := preload("res://view/accent_recolour.gdshader")

static var _made := {}    # [source material id, livery, glow] -> ShaderMaterial


static func of(source: Material, glow := Color(0, 0, 0)) -> Material:
	var accent = Livery.accent()
	var plain := source as BaseMaterial3D
	if accent == null or plain == null or plain.albedo_texture == null:
		return source
	var key := [plain.get_instance_id(), Livery.current, glow]
	if _made.has(key):
		return _made[key]
	var c: Color = accent
	# (the shader reads the maps as they are displayed: the accent's hue, saturation and value there)
	var turned := ShaderMaterial.new()
	turned.shader = SHADER
	turned.set_shader_parameter("albedo_map", plain.albedo_texture)
	turned.set_shader_parameter("normal_map", plain.normal_texture)
	turned.set_shader_parameter("orm_map", plain.roughness_texture if plain.roughness_texture else plain.metallic_texture)
	turned.set_shader_parameter("accent_hsv", Vector3(c.h, c.s, c.v))
	turned.set_shader_parameter("normal_depth", plain.normal_scale if plain.normal_enabled else 0.0)
	turned.set_shader_parameter("occlusion", plain.ao_light_affect if plain.ao_enabled else 0.0)
	turned.set_shader_parameter("glow", Vector3(glow.r, glow.g, glow.b))
	_made[key] = turned
	return turned


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
