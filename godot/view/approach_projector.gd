## Roof-header approach projector. Coordinates are relative to the real windscreen.
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

var panel := MeshInstance3D.new()
var surface := ShaderMaterial.new()
var action: Label3D
var countdown: Label3D
var route: Label3D
var advice: Label3D
var status: Label3D
var message := ""
var deployment := 0.0

func build(canopy: Node3D) -> void:
	name = "ApproachProjector"
	canopy.add_child(self)
	# A short canopy brow joins the existing windshield top to a fixed overhead
	# header. Both windshield and projector share the shell's bank and shudder.
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

	var pivot := Node3D.new()
	pivot.name = "OpticalPlane"
	pivot.position = Vector3(0,-0.029,0.041)
	pivot.rotation.x = deg_to_rad(23.0)
	add_child(pivot)
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
	for label: Label3D in [action, countdown, route, advice, status]:
		var row := 0.5-label.position.y/SIZE.y
		var opacity := smoothstep(row, row+0.16, scan)
		label.modulate.a = opacity
		label.outline_modulate.a = opacity*0.8
