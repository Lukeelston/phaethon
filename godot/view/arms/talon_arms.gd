## The Talon's wing guns (sim/pilot_craft.gd WEAPONS "wing_guns"): one in each wing root, where Codex's swept wing
## leaves the chine beside the cockpit (view/talon_airframe.gd), fixed forward: the starfighter's, faster and lighter
## than the Phaethon's cannons (Raids, 2026-11-24; Luke: "Modelled and hidden - have codex work on the art"). These
## are stand-ins, plain boxes, until Codex's models fill the same contract, which every craft's arms keep
## (docs/superpowers/specs/2026-11-24-raids-art-brief-codex.md):
##   func build(craft) -> void           into the craft's hull/engines, stowed; craft is the CraftModel
##   func set_deploy(t: float) -> void   0 stowed .. 1 out
##   func muzzles() -> Array             global Transform3Ds, -Z out of each mouth
##   var heat: float                     0..1: the barrels' glow follows it
## build() puts this node where it rides. What rides on the pod goes under this node, on craft.pod: the VR cockpit
## moves the node onto its own hull with the pod's other fittings (vr/vr_cockpit.gd), so in VR the guns are on the
## hull the seat sees.
## Each gun, pod-local (forward -Z; x mirrored to port): a dark housing inside the wing root, its port where the root's
## leading edge meets the chine; a port cover over it, in the leading edge's titanium; a barrel in the housing.
## Deploying: the cover slides inboard into the chine (t 0 .. 0.35), then the barrel runs 0.6 m out of the port
## (0.3 .. 1). Stowed, nothing of it is drawn: it costs nothing until the GUN switch brings it out.
##   arms = TalonArms.new(); arms.build(craft); arms.set_deploy(t); arms.muzzles(); arms.heat = h
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")
const Finishes := preload("res://view/craft_materials.gd")
const TurretScript := preload("res://view/turret.gd")
const Talon := preload("res://view/talon_airframe.gd")
const STAND_IN := true      # (tests/test_arms.gd checks the stand-ins' own parts only where this is: Codex's art drops it)

const GUN := Vector3(1.18, -0.14, 0.0)         # each gun's line, pod-local (the starboard one's; x mirrored to port)
const GUNMETAL := Color(0.20, 0.21, 0.23)
const HOUSING := Vector3(0.064, 0.064, 0.86)
const HOUSING_Z := -0.52                       # its middle: from its port at -0.95 (the leading edge's middle across it) to -0.09
const BARREL := Vector3(0.05, 0.05, 0.84)
const BARREL_Z := -0.525                       # stowed: its mouth 5 mm inside the port
const PANEL := Vector3(0.072, 0.072, 0.008)
const PANEL_Z := -0.955                        # shut: over the port, on its face
const PANEL_SLIDE := 0.15                      # the cover slides this far inboard, into the chine ...
const RUN := 0.6                               # ... and then the barrel runs this far out
const T_PANEL := Vector2(0.0, 0.35)            # the deploy's share for the cover ...
const T_RUN := Vector2(0.3, 1.0)               # ... and for the barrel

var heat := 0.0:
	set(value):
		heat = clampf(value, 0.0, 1.0)
		_glow()
var guns: Array[Node3D] = []       # port, starboard: each gun (housing, cover, barrel)
var _panels: Array[Node3D] = []
var _barrels: Array[Node3D] = []
var _glow_mat: StandardMaterial3D  # the barrels': it glows with the heat
static var _meshes := {}           # the parts' meshes, made once for every Talon (in every paint: titanium and dark)


func build(craft) -> void:
	name = "Arms"
	(craft.pod as Node3D).add_child(self)
	_glow_mat = _barrel_material()
	for s: float in [-1.0, 1.0]:
		var gun := Node3D.new()
		gun.name = "WingGunL" if s < 0.0 else "WingGunR"
		gun.position = GUN * Vector3(s, 1.0, 1.0)
		add_child(gun)
		guns.append(gun)
		_part(gun, "Housing", _mesh("housing"), Finishes.painted_metal()).position = Vector3(0.0, 0.0, HOUSING_Z)
		_panels.append(_part(gun, "Panel", _mesh("panel"), Finishes.painted_metal()))
		_barrels.append(_part(gun, "Barrel", _mesh("barrel"), _glow_mat))
	set_deploy(0.0)
	_glow()


func set_deploy(t: float) -> void:
	var at := clampf(t, 0.0, 1.0)
	var slide := smoothstep(T_PANEL.x, T_PANEL.y, at)
	var run := smoothstep(T_RUN.x, T_RUN.y, at)
	for k in guns.size():
		var inboard := -signf(guns[k].position.x)
		guns[k].visible = at > 0.0
		_panels[k].position = Vector3(inboard * PANEL_SLIDE * slide, 0.0, PANEL_Z)
		_barrels[k].position = Vector3(0.0, 0.0, BARREL_Z - RUN * run)


func muzzles() -> Array:
	var out := []
	for barrel: Node3D in _barrels:
		out.append(barrel.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -BARREL.z / 2.0)))
	return out


func _glow() -> void:
	if _glow_mat:
		_glow_mat.emission = TurretScript.COIL_COOL.lerp(TurretScript.COIL_HOT, heat)
		_glow_mat.emission_energy_multiplier = 6.0 * heat


static func _barrel_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.metallic = 0.6
	mat.roughness = 0.35
	mat.emission_enabled = true
	mat.emission = TurretScript.COIL_COOL
	mat.emission_energy_multiplier = 0.0
	return mat


static func _mesh(key: String) -> ArrayMesh:
	if not _meshes.has(key):
		var spec: Array = {"housing": [HOUSING, Talon.CAVITY], "panel": [PANEL, Talon.TITANIUM], "barrel": [BARREL, GUNMETAL]}[key]
		_meshes[key] = Kit.compound([[Kit.box(spec[0]), Transform3D.IDENTITY, spec[1]]])
	return _meshes[key]


static func _part(parent: Node3D, part_name: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_to_group("exterior")      # (outside the cabin: the cockpit's fitting checks leave it be)
	parent.add_child(mi)
	return mi
