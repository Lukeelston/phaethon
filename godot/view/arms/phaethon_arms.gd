## The Phaethon's cannons (sim/pilot_craft.gd WEAPONS "cannons"): one in the nose of each engine, in the splitter
## between its twin intakes, fixed along the engine's heading (Raids, 2026-11-24; Luke: "every vehicle should have
## their own weapon system like the basilisk's hidden cannon", and of their look, "Modelled and hidden - have codex
## work on the art"). These are stand-ins, plain boxes, until Codex's models fill the same contract, which every
## craft's arms keep (docs/superpowers/specs/2026-11-24-raids-art-brief-codex.md):
##   func build(craft) -> void           into the craft's hull/engines, stowed; craft is the CraftModel
##   func set_deploy(t: float) -> void   0 stowed .. 1 out
##   func muzzles() -> Array             global Transform3Ds, -Z out of each mouth
##   var heat: float                     0..1: the barrels' glow follows it
## build() puts this node where it rides. What rides on the pod goes under this node, on craft.pod: the VR cockpit
## moves the node onto its own hull with the pod's other fittings (vr/vr_cockpit.gd). The Phaethon's guns ride on its
## engines, which the cockpit leaves where they are, so this node stands on the model and holds none of them.
## Each engine's gun, engine-local (forward -Z): a dark housing behind the splitter, its port 4 mm proud of the
## splitter's face; a nose panel over the port, in the splitter's own colour; a barrel in the housing. Deploying: the
## panel slides up the splitter (t 0 .. 0.35), then the barrel runs 0.6 m out of the port (0.3 .. 1). Stowed, nothing
## of it is drawn: it costs nothing until the GUN switch brings it out.
##   arms = PhaethonArms.new(); arms.build(craft); arms.set_deploy(t); arms.muzzles(); arms.heat = h
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")
const Finishes := preload("res://view/craft_materials.gd")
const TurretScript := preload("res://view/turret.gd")

const SPLITTER := Color(0.391, 0.391, 0.405)   # the splitter's colour (craft_model._engine_body: DARK.lightened(0.3)); its face is at z -3.88
const CAVITY := Color(0.035, 0.04, 0.05)
const GUNMETAL := Color(0.20, 0.21, 0.23)
const HOUSING := Vector3(0.084, 0.084, 0.80)
const HOUSING_AT := Vector3(0.0, 0.0, -3.484)  # its port at -3.884, 4 mm proud of the splitter's face
const BARREL := Vector3(0.07, 0.07, 0.78)      # (a heavier bore than the Talon's wing guns; the fans' lips stand 10 cm off its line)
const BARREL_AT := Vector3(0.0, 0.0, -3.489)   # stowed: its mouth 5 mm inside the port
const PANEL := Vector3(0.09, 0.096, 0.006)
const PANEL_AT := Vector3(0.0, 0.0, -3.887)    # shut: over the port, on its face
const RUN := 0.6                               # the barrel runs this far out ...
const PANEL_LIFT := 0.10                       # ... once the panel has slid this far up the splitter, clear of the port
const T_PANEL := Vector2(0.0, 0.35)            # the deploy's share for the panel ...
const T_RUN := Vector2(0.3, 1.0)               # ... and for the barrel

var heat := 0.0:
	set(value):
		heat = clampf(value, 0.0, 1.0)
		_glow()
var guns: Array[Node3D] = []       # per engine: its gun (housing, panel, barrel)
var _panels: Array[Node3D] = []
var _barrels: Array[Node3D] = []
var _glow_mat: StandardMaterial3D  # the barrels': it glows with the heat
static var _meshes := {}           # the parts' meshes, made once for every Phaethon


func build(craft) -> void:
	name = "Arms"
	craft.add_child(self)
	_glow_mat = _barrel_material()
	for k in craft.engines.size():
		var gun := Node3D.new()
		gun.name = "CannonL" if k == 0 else "CannonR"
		(craft.engines[k] as Node3D).add_child(gun)
		guns.append(gun)
		_part(gun, "Housing", _mesh("housing"), Finishes.painted_metal()).position = HOUSING_AT
		_panels.append(_part(gun, "Panel", _mesh("panel"), Finishes.painted_metal()))
		_barrels.append(_part(gun, "Barrel", _mesh("barrel"), _glow_mat))
	set_deploy(0.0)
	_glow()


func set_deploy(t: float) -> void:
	var at := clampf(t, 0.0, 1.0)
	var slide := smoothstep(T_PANEL.x, T_PANEL.y, at)
	var run := smoothstep(T_RUN.x, T_RUN.y, at)
	for k in guns.size():
		guns[k].visible = at > 0.0
		_panels[k].position = PANEL_AT + Vector3(0.0, PANEL_LIFT * slide, 0.0)
		_barrels[k].position = BARREL_AT + Vector3(0.0, 0.0, -RUN * run)


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
		var spec: Array = {"housing": [HOUSING, CAVITY], "panel": [PANEL, SPLITTER], "barrel": [BARREL, GUNMETAL]}[key]
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
