## One flight owns its material and holds only the selected airframe's meshes.
extends RefCounted

const Pilot := preload("res://sim/pilot_craft.gd")
const Livery := preload("res://view/livery.gd")
const Kit := preload("res://view/mesh_kit.gd")
const FINISH := preload("res://view/fleet_finish.gdshader")
const ASSET_DIR := "res://art/pilot_fleet/"
const MASK := "_livery.png"     # <id>_livery.png: where each of its own colours is on its atlas (tools/art_livery_masks.py)
# Each craft's own colours as tools/art_pilot_fleet_finish.py paints its atlas (FLEET: paint, accent, trim;
# and the ink its number is printed in on its plates), as the mask's channels mark them: R its enamel, G its
# accent (its bands, accent panels and number plates), B its trim lines, A its number. (tests/test_paint.gd
# reads them back off the atlases.)
const INK := Color("#25343b")
const DARK_BAND := 0.12          # linear luminance under which a band is too dark for dark lettering on it
const OWN := {
	"orrery": [Color("#eee2bd"), Color("#166363"), Color("#c69956")],
	"kiln": [Color("#bf4636"), Color("#f5af44"), Color("#ad734e")],
	"vesper": [Color("#6b5894"), Color("#d5e2e8"), Color("#d69f97")],
	"basilisk": [Color("#474e49"), Color("#e59a2c"), Color("#8c7353")],
}
const STROBES := {"orrery": Vector3(1.315, 0.24, 1.04), "kiln": Vector3(1.02, 0.54, 2.34), "vesper": Vector3(2.22, 0.58, 1.83), "basilisk": Vector3(1.42, 0.17, -2.30)}
const CAB_HINGES := {"orrery": Vector3(1.295, -0.24, 0.77), "kiln": Vector3(1.396, -0.17, 0.70), "vesper": Vector3(1.241, -0.12, 0.69), "basilisk": Vector3(1.36, -0.17, 0.70)}

var id: String
var parts := {}
var drawn_hull: MeshInstance3D


static func supports(vehicle: String) -> bool:
	return STROBES.has(vehicle)


func _init(vehicle: String) -> void:
	id = vehicle
	var source := (load(ASSET_DIR + id + ".glb") as PackedScene).instantiate()
	var paint := finish_for(load(ASSET_DIR + id + ".tres") as StandardMaterial3D)
	if not Livery.is_factory():      # (Factory: the atlas as it was painted)
		repaint(paint, load(ASSET_DIR + id + MASK), colours(id))
	for node: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		# The import is shared between flights. Only this flight owns the surface assignment.
		var own := node.mesh.duplicate() as ArrayMesh
		own.surface_set_material(0, paint)
		parts[node.name] = own
	source.free()


## The baked bodywork's finish (view/fleet_finish.gdshader) from the atlas material the tools write:
## the same maps, with the occlusion the tools bake into the vertex colours, and specular
## anti-aliasing on the radiused edges. The Shrike's bodywork uses it too (view/shrike_airframe.gd).
static func finish_for(atlas: StandardMaterial3D) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = FINISH
	mat.set_shader_parameter("albedo_map", atlas.albedo_texture)
	mat.set_shader_parameter("normal_map", atlas.normal_texture)
	mat.set_shader_parameter("orm_map", atlas.roughness_texture)
	mat.set_shader_parameter("normal_depth", atlas.normal_scale)
	return mat


## A craft's colours in the current livery, as [its own, the livery's] for each of the mask's channels:
## its enamel takes the livery's paint; its bands and accent panels the livery's pin, the colour a livery
## sets against its paint (white on cobalt or crimson, gold on racing green, black on sunflower, red on
## bone, orange on obsidian); its thin trim lines the livery's stripe. (Not the livery's accent: each is a
## shade of its own paint, made for the Phaethon's fittings, and on these the bands vanished into the
## body: evidence/realism-spike/push45/paint/sheet-variants.png.) The number printed on its plates stays
## as printed, unless the plates go dark (Sunflower's black): then it is printed in the paint, to read.
## The Shrike's are the same four (view/shrike_airframe.gd colours()).
static func colours(vehicle: String) -> Array:
	var own: Array = OWN[vehicle]
	return [[own[0], Livery.coat("paint")], [own[1], Livery.coat("pin")], [own[2], Livery.coat("stripe")], [INK, lettering(INK)]]


## What dark lettering printed on a band or a plate is printed in: as it was, unless the livery's band
## colour (its pin) is too dark for it to read on (then the livery's paint).
static func lettering(ink: Color) -> Color:
	var band := Livery.coat("pin").srgb_to_linear()
	return Livery.coat("paint") if 0.2126 * band.r + 0.7152 * band.g + 0.0722 * band.b < DARK_BAND else ink


## Put a finish (finish_for) into a livery: the mask, and for each of its four channels [the colour the
## atlas was painted in, the colour it takes] (view/fleet_finish.gdshader). Set once, when the craft is
## built: nothing a frame.
static func repaint(finish: ShaderMaterial, mask: Texture2D, colours: Array) -> void:
	finish.set_shader_parameter("repaint", true)
	finish.set_shader_parameter("livery_mask", mask)
	for k in 4:
		finish.set_shader_parameter("from_" + "rgba"[k], colours[k][0])
		finish.set_shader_parameter("to_" + "rgba"[k], colours[k][1])


func part(key: StringName) -> ArrayMesh:
	return parts[key]


func mount(parent: Node3D, key: StringName, node_name: StringName) -> MeshInstance3D:
	var fitting := MeshInstance3D.new()
	fitting.name = node_name
	fitting.mesh = part(key)
	parent.add_child(fitting)
	return fitting


func dress_cab(hull: MeshInstance3D, closed: bool) -> void:
	drawn_hull = hull
	hull.mesh = part(&"Cab")
	mount(hull, &"Seat", &"FleetSeat")
	var bonnet := mount(hull, &"Bonnet", &"ServiceBonnet")
	bonnet.set_meta(&"service_bonnet", true)
	bonnet.visible = closed


## First GUN arm only. dress_cab receives the flat pod first and, in VR, the
## cockpit's visible hull last. An explicit hull is useful in a separate preview.
func ensure_arms(hull: MeshInstance3D = null):
	if hull == null:
		hull = drawn_hull
	if not is_instance_valid(hull) or id not in [Pilot.ORRERY, Pilot.KILN, Pilot.VESPER]:
		return null
	var existing := hull.get_node_or_null(^"Arms")
	if existing:
		return existing
	var rig = load("res://view/arms/" + id + "_arms.gd").new()
	rig.build(hull)
	return rig


func strobe_at(side: float) -> Vector3:
	return STROBES[id] * Vector3(side, 1, 1)


func lights(side: float) -> ArrayMesh:
	var nav := Color("#f04638") if side < 0 else Color("#3be8a1")
	return Kit.compound([
		[Kit.ball(0.065, 12), Kit.at(strobe_at(side) + Vector3(0, 0, 0.08)), nav],
		[Kit.box(Vector3(0.18, 0.032, 0.045)), Kit.at(Vector3(side * 0.78, 0.36, 3.78)), Color("#f0583b")],
	])


func rotor_centres() -> Array:
	match id:
		Pilot.ORRERY: return [Vector3(0, 0.19, -3.57)]
		Pilot.KILN: return [Vector3(-0.47, 0.0, -3.98), Vector3(0.47, 0.0, -3.98)]
		Pilot.BASILISK: return [Vector3(-0.47, 0.04, -4.12), Vector3(0.47, 0.04, -4.12)]
		_: return [Vector3(-0.80, 0.04, -4.29), Vector3(0.80, 0.04, -4.29)]


func fit_canopy(root: Node3D) -> void:
	var roof := mount(root, &"Roof", &"roof")
	var pane := mount(root, &"Glass", &"roof_glass")
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.42, 0.67, 0.72, 0.069) if id == Pilot.ORRERY else Color(0.64, 0.66, 0.74, 0.065)
	glass.roughness = 0.09
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	pane.material_override = glass
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	roof.add_to_group("exterior")
	pane.add_to_group("exterior")
