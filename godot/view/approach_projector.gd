## Approach guidance, projected from the windscreen header. Coordinates are the canopy's (pod-local).
## Two mounts:
##   under the roof  (Canopy.roof_available()) a slim emitter housing bolted under the roof's own
##                   header rail (tools/art_roof_hd.py), and the image where a head-up display's
##                   lies: a virtual image out beyond the glass, square to the seated eye, in the
##                   clear pane between the road and the shade band. (The first mount put a brow
##                   and a strut frame of its own up there, half a metre outside the swept screen:
##                   Luke: "it attached the new hud to a jerry rigged roof".)
##   open cockpit    a short brow of glazing from the oblong screen's top edge up to a header.
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")
const Finish := preload("res://view/craft_materials.gd")
const Glass := preload("res://view/guidance_glass.gdshader")
const SIZE := Vector2(0.94, 0.228)
const OPEN_TIME := 0.36
const CLOSE_TIME := 0.24
const ICE := Color("#bcf6fa")
const AMBER := Color("#ffcf79")
const READY := Color("#9cf3c0")
const ALERT := Color("#ff9c84")
const EYE := Vector3(0.0, 0.12, 0.6)          # the seated eye (the roof is drawn round it)
const HEADER := Vector3(0.0, 0.47, 0.30)      # the roof's header rail, its middle ...
const HEADER_R := 0.02                        # ... and its section
const IMAGE_RANGE := 2.0                      # the image this far from the eye, m: out over the nose, where a headset's eyes rest
const IMAGE_ELEVATION := deg_to_rad(19.5)     # its middle above eye level: over the road, under the shade band (from 24 degrees)
const IMAGE_WIDTH := deg_to_rad(38.0)         # across, at the eye: well inside the A-pillars (47 degrees out at that height)

var panel := MeshInstance3D.new()
var surface := ShaderMaterial.new()
var action: Label3D
var countdown: Label3D
var route: Label3D
var advice: Label3D
var status: Label3D
var message := ""
var deployment := 0.0
var lens_mat: StandardMaterial3D                     # (the roof's mount) the emitter's lens: dark glass until it projects
const LENS_IDLE := Color("#16343a")
const LENS_LIT := Color("#8fe9f0")

func build(canopy: Node3D) -> void:
	name = "ApproachProjector"
	canopy.add_child(self)
	var pivot := Node3D.new()
	pivot.name = "OpticalPlane"
	add_child(pivot)
	if Canopy.roof_available():
		_mount_under_header(pivot)
	else:
		_mount_on_brow(pivot)
	panel.name = "Projection"
	var quad := QuadMesh.new()
	quad.size = SIZE
	panel.mesh = quad
	panel.position.y = -SIZE.y*0.5
	surface.shader = Glass
	surface.render_priority = 3
	panel.material_override = surface
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(panel)
	action = _label("Action", -0.323, 0.061, 0.00080)
	countdown = _label("DistanceAndTime", 0.435, 0.060, 0.00060, true)
	route = _label("Route", -0.323, -0.004, 0.00054)
	advice = _label("Advisory", -0.323, -0.069, 0.00050)
	status = _label("Status", 0.435, -0.069, 0.00050, true)
	panel.hide()
	set_process(false)


## The roof's mount: the housing hangs under the header rail on two saddles, its lens looking down
## the glass; the image is not a pane in the cabin but the display's virtual image, beyond the
## screen, its top edge on the pivot and its face square to the seated eye.
func _mount_under_header(pivot: Node3D) -> void:
	position = HEADER + Vector3(0.0, -HEADER_R - 0.012, -0.004)
	var tilt := deg_to_rad(-24.0)        # nose down: the lens looks along the swept screen
	var fittings := []
	fittings.append([Finish.beveled_plate(Vector3(0.21, 0.017, 0.04), 0.005), Kit.at(Vector3.ZERO), Color("#22282b")])
	for side in [-1.0, 1.0]:
		fittings.append([Finish.beveled_plate(Vector3(0.026, 0.021, 0.044), 0.004), Kit.at(Vector3(side*0.112, 0.001, 0.0)), Color("#525c5e")])
		# a saddle up round the rail, and two screws in the cap's underside
		fittings.append([Finish.beveled_plate(Vector3(0.014, 0.02, 0.034), 0.003), Kit.at(Vector3(side*0.078, 0.014, 0.003)), Color("#3a4346")])
		for fore in [-1.0, 1.0]:
			fittings.append([Finish.slotted_screw(0.0026), Kit.at(Vector3(side*0.112, -0.0108, fore*0.013), Vector3(PI, 0.0, 0.0)), Color("#8b9596")])
	var housing := _part("Header", Kit.compound(fittings), Finish.painted_metal())
	housing.rotation.x = tilt
	lens_mat = StandardMaterial3D.new()
	lens_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lens_mat.albedo_color = LENS_IDLE
	var lens := MeshInstance3D.new()
	lens.name = "EmitterSlit"
	lens.mesh = Kit.box(Vector3(0.15, 0.002, 0.006))
	lens.material_override = lens_mat
	lens.position = Vector3(0.0, -0.0088, -0.008)
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	housing.add_child(lens)
	var size := 2.0 * IMAGE_RANGE * tan(IMAGE_WIDTH * 0.5) / SIZE.x
	var middle := EYE + Vector3(0.0, sin(IMAGE_ELEVATION), -cos(IMAGE_ELEVATION)) * IMAGE_RANGE
	var up := Vector3(0.0, cos(IMAGE_ELEVATION), sin(IMAGE_ELEVATION))
	pivot.position = middle + up * (SIZE.y * 0.5 * size) - position
	pivot.rotation.x = IMAGE_ELEVATION
	pivot.scale = Vector3.ONE * size


## The open cockpit's mount: a short brow of glazing joins the oblong screen's top edge to a fixed
## overhead header. Both windscreen and projector share the shell's bank and shudder.
func _mount_on_brow(pivot: Node3D) -> void:
	var crown := Canopy.screen_point(0.5, 1.0)
	position = crown + Vector3(0, 0.37, 0.165)
	var fittings := []
	var glass := SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var previous_sill := Vector3.ZERO
	var previous_header := Vector3.ZERO
	for i in range(17):
		var t := i / 16.0
		var side := 2.0*t - 1.0
		var sill := Canopy.screen_point(lerpf(0.06, 0.94, t), 1.0) - position
		var header := Vector3(side*0.53, -0.055*side*side, 0.10*side*side)
		if i > 0:
			_strut(fittings, previous_header, header, 0.012)
			for p in [previous_sill, header, sill, previous_sill, previous_header, header]:
				glass.add_vertex(p)
		if i == 0 or i == 16:
			_strut(fittings, sill, header, 0.009)
		previous_header = header
		previous_sill = sill
	glass.generate_normals()
	var tint := StandardMaterial3D.new()
	tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tint.cull_mode = BaseMaterial3D.CULL_DISABLED
	tint.albedo_color = Color(0.13, 0.25, 0.29, 0.075)
	tint.render_priority = -2
	_part("BrowGlazing", glass.commit(), tint)
	fittings.append([Finish.beveled_plate(Vector3(0.44,0.038,0.076),0.008),
		Kit.at(Vector3(0,-0.004,0.010)), Color("#303b40")])
	for side in [-1.0,1.0]:
		fittings.append([Finish.beveled_plate(Vector3(0.057,0.038,0.074),0.006),
			Kit.at(Vector3(side*0.228,-0.002,0.010)), Color("#6b7778")])
	_part("Header", Kit.compound(fittings), Finish.painted_metal())
	var lens_mat := StandardMaterial3D.new()
	lens_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lens_mat.albedo_color = Color("#71d7df")
	var lens := _part("EmitterSlit", Kit.box(Vector3(0.34,0.004,0.014)), lens_mat)
	lens.position = Vector3(0,-0.024,0.036)
	pivot.position = Vector3(0,-0.029,0.041)
	pivot.rotation.x = deg_to_rad(23.0)


func _strut(parts: Array, a: Vector3, b: Vector3, radius: float) -> void:
	var direction := b-a
	parts.append([Kit.cyl(radius, radius, direction.length()+0.001, 8),
		Transform3D(Basis(Quaternion(Vector3.UP, direction.normalized())), (a+b)*0.5), Color("#36484d")])

func _part(tag: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = tag
	part.mesh = mesh
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	return part

func _label(tag: String, x: float, y: float, pixel: float, right := false) -> Label3D:
	var label := Label3D.new()
	label.name = tag
	label.font_size = 64
	label.pixel_size = pixel
	label.set_meta("design_pixel", pixel)
	label.position = Vector3(x,y,0.0015)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	label.outline_size = 3
	label.outline_modulate = Color("#082229")
	label.modulate = ICE
	label.double_sided = false
	label.render_priority = 5
	label.outline_render_priority = 4
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	panel.add_child(label)
	return label

func _fit(label: Label3D, value: String, width: float) -> void:
	if label.text == value:
		return
	label.text = value
	var pixels := ThemeDB.fallback_font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,label.font_size).x
	label.pixel_size = minf(float(label.get_meta("design_pixel")), width/maxf(pixels,1.0))

func set_message(value: String) -> void:
	if value == message:
		return
	var opening := message.is_empty()
	message = value
	if value.is_empty():
		set_process(true)
		return
	var lines := value.split("\n")
	var metrics := lines[0].split("  ",false,1)
	_fit(action, metrics[0], 0.37)
	_fit(countdown, metrics[1] if metrics.size()>1 else "", 0.366)
	_fit(route, lines[1].replace(" > ", "  ›  "), 0.757)
	var footer := lines[2].split(" | ",false,1)
	_fit(advice, footer[0], 0.55 if footer.size()>1 else 0.757)
	_fit(status, footer[1] if footer.size()>1 else "", 0.19)
	var tint := ICE
	if metrics[0] == "WRONG WAY":
		tint = ALERT
	elif status.text == "TOO SLOW":
		tint = AMBER
	elif status.text == "READY":
		tint = READY
	status.modulate = Color(tint, status.modulate.a)
	action.modulate = Color(tint if metrics[0]=="WRONG WAY" else ICE, action.modulate.a)
	surface.set_shader_parameter("signal", tint)
	var direction := -1 if metrics[0]=="LEFT EXIT" else (1 if metrics[0]=="RIGHT EXIT" else 0)
	surface.set_shader_parameter("direction", float(direction))
	surface.set_shader_parameter("wrong_way", metrics[0]=="WRONG WAY")
	if opening:
		panel.show()
		_reveal()
		set_process(true)

func _process(delta: float) -> void:
	var target := 0.0 if message.is_empty() else 1.0
	deployment = move_toward(deployment, target, delta / (CLOSE_TIME if message.is_empty() else OPEN_TIME))
	_reveal()
	if deployment == target:
		panel.visible = deployment > 0.0
		set_process(false)

func _reveal() -> void:
	var scan := smoothstep(0.0,1.0,deployment)
	surface.set_shader_parameter("scan", scan)
	if lens_mat:
		lens_mat.albedo_color = LENS_IDLE.lerp(LENS_LIT, scan)
	for label: Label3D in [action, countdown, route, advice, status]:
		var row := 0.5-label.position.y/SIZE.y
		var opacity := smoothstep(row, row+0.16, scan)
		label.modulate.a = opacity
		label.outline_modulate.a = opacity*0.8
