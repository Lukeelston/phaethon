## A patrol craft's light bar (Luke: "a police variant of the vehicle"): a low dark housing with a red
## lamp to port and a blue to starboard that flash in turn, two quick flashes a side. The lamps are
## unshaded and brighter than white, so they bloom and light nothing: no real light is spent on them.
##   var bar := LightBar.new(); pod.add_child(bar); bar.build(LightBar.ON_ROOF)     pod-local
##   bar.flash(on, seconds)                 every frame
##   LightBar.showing(seconds)              which lamp is lit just now: 1 red, 2 blue, 0 neither
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")
const ON_ROOF := Vector3(0.0, 0.482, 1.02)      # on the closed canopy's hood, behind the pilot's head and down on its crown (tests/test_canopy.gd)
const ON_FIN := Vector3(0.0, 0.745, 1.72)       # across the top of the fin (a craft with no roof)
const RED := Color(3.2, 0.12, 0.08)
const BLUE := Color(0.12, 0.42, 3.4)
const PERIOD := 0.8                             # s: two flashes port, two starboard

var lamps: Array[MeshInstance3D] = []


## 1 while the red lamp is lit, 2 the blue, 0 between flashes.
static func showing(seconds: float) -> int:
	var ph := fposmod(seconds, PERIOD)
	if ph < 0.09 or (ph > 0.16 and ph < 0.25):
		return 1
	if (ph > 0.40 and ph < 0.49) or (ph > 0.56 and ph < 0.65):
		return 2
	return 0


func build(at: Vector3, wide := 0.72) -> void:
	name = "light_bar"
	position = at
	var housing := MeshInstance3D.new()
	housing.mesh = Kit.rounded_box(Vector3(wide, 0.045, 0.15), 5.0)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.03, 0.03, 0.035)
	dark.roughness = 0.4
	housing.material_override = dark
	housing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(housing)
	for side in 2:
		var s := -1.0 if side == 0 else 1.0
		var lens := MeshInstance3D.new()      # the lens, unlit: a dull red or blue
		lens.mesh = Kit.rounded_box(Vector3(wide * 0.44, 0.05, 0.12), 5.0)
		lens.position = Vector3(s * wide * 0.25, 0.04, 0.0)
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color(0.30, 0.02, 0.02) if side == 0 else Color(0.02, 0.05, 0.32)
		glass.roughness = 0.15
		lens.material_override = glass
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lens)
		var lamp := MeshInstance3D.new()      # ... and lit: a little larger, over it
		lamp.mesh = Kit.rounded_box(Vector3(wide * 0.46, 0.06, 0.13), 5.0)
		lamp.position = lens.position
		var lit := StandardMaterial3D.new()
		lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lit.albedo_color = RED if side == 0 else BLUE
		lamp.material_override = lit
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamp.visible = false
		add_child(lamp)
		lamps.append(lamp)


func flash(on: bool, seconds: float) -> void:
	var which := showing(seconds) if on else 0
	lamps[0].visible = which == 1
	lamps[1].visible = which == 2
