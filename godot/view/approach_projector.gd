## Approach guidance, projected from the windscreen header. Coordinates are the canopy's (pod-local).
## Two mounts:
##   under the roof  (Canopy.roof_available()) a slim emitter housing bolted under the roof's own
##                   header rail (tools/art_roof_hd.py), and the image thrown onto the windscreen:
##                   the readout is drawn into a picture of its own (`port`) and that picture laid
##                   in the swept screen's inner face (view/guidance_image.gdshader), on a patch of
##                   the screen's own surface, so it wraps and lies back with the glass (Luke: "The
##                   projector looks great, but it should project onto the windscreen and bend
##                   with its curve"). From the seat it keeps the place it had: in the clear pane
##                   between the road and the shade band. (Before that it was a head-up display's
##                   virtual image, a flat pane 2 m out over the nose; and the first mount put a
##                   brow and a strut frame of its own up there, half a metre outside the swept
##                   screen: Luke: "it attached the new hud to a jerry rigged roof".)
##   open cockpit    a short brow of glazing from the oblong screen's top edge up to a header.
## While the craft is being started the same glass carries the start-up's checklist, and that one
## moves (Luke: "animation to the startup sequence display"): see set_checklist and
## view/startup_glass.gdshader. Outside the start-up none of that is drawn or run.
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")
const Finish := preload("res://view/craft_materials.gd")
const Glass := preload("res://view/guidance_glass.gdshader")
const Beam := preload("res://view/projector_beam.gdshader")
const Picture := preload("res://view/guidance_image.gdshader")
const Checklist := preload("res://view/startup_glass.gdshader")
const TICK_TIME := 0.45        # a step ticked off keeps its page on the glass this long, s, before the next is written
const SETTLE_TIME := 0.6       # ... and its segment of the rail is wiped full and flashed over this long
const TYPE_TIME := 0.36        # a new page arrives over this long, line by line
const SWEEP_TIME := 0.45       # the sweep across a line whose words changed
const BEAT_HZ := 1.25          # the pointer's beat while a control is waited for (a headset wants nothing blinking past 3 Hz)
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
const IMAGE_ELEVATION := deg_to_rad(19.5)     # the image's middle above eye level: over the road, under the shade band (from 24 degrees)
const IMAGE_WIDTH := deg_to_rad(38.0)         # across, at the eye: well inside the A-pillars (47 degrees out at that height)
const IMAGE_INSET := 0.004                    # it lies this far inside the glass, m
const PICTURE := Vector2i(1320, 320)          # the readout's own picture, pixels (the glass's 4.12 : 1): a third finer than a headset shows it
static var picture_every_frame := false       # (timings: true draws the readout's picture every frame, to weigh one)
static var _place := PackedFloat32Array()     # the image's place on the roof's screen: v at its foot and at its top ...
static var _reach := {}                       # ... and, at each height up it asked for (t), u at its right edge

var panel := MeshInstance3D.new()
var surface := ShaderMaterial.new()
var action: Label3D
var countdown: Label3D
var route: Label3D
var advice: Label3D
var status: Label3D
var message := ""
var deployment := 0.0
static var beams := true                             # (timings: false before build() leaves the beam out)
var port: SubViewport                                # (the roof's mount) where the readout is drawn: a picture of the glass and its type, and nothing else
var image: MeshInstance3D                            # (the roof's mount) that picture, lying in the windscreen
var image_mat: ShaderMaterial
var beam: MeshInstance3D                             # (the roof's mount) the fan of light from the lens to the image's top edge
var beam_mat: ShaderMaterial
var lens_mat: StandardMaterial3D                     # (the roof's mount) the emitter's lens: dark glass until it projects
var sheet := MeshInstance3D.new()                    # the start-up's drawing, between the glass and its type: hidden outside the start-up
var sheet_mat := ShaderMaterial.new()
var checklist := {}                                  # the start-up's state as last given (StartupSequence.display()); {} outside the start-up
var clock := 0.0                                     # s the checklist has been up
var ticking := 0.0                                   # s left of a step being ticked off (its page stays up meanwhile)
var typing := 1.0                                    # 0..1: a new page arriving
var sweeping := 1.0                                  # 0..1: the sweep across the middle line (1: none)
var ticked := 1.0                                    # 0..1: the last step's segment of the rail being wiped full (1: settled)
var _ticked_at := -10.0                              # the clock when that step was ticked off
var _written := ""                                   # the page the type shows: it trails `message` while a step is ticked off
var _stowing := false                                # the start-up is over: the sheet goes out with the glass, or at the next page
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
	surface.shader = Glass
	surface.render_priority = 3
	panel.material_override = surface
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if port:
		port.add_child(panel)                 # square to the picture's own lens
		panel.visibility_changed.connect(_follow_panel)
	else:
		panel.position.y = -SIZE.y*0.5        # hung from the header by its top edge
		pivot.add_child(panel)
	action = _label("Action", -0.323, 0.061, 0.00080)
	countdown = _label("DistanceAndTime", 0.435, 0.060, 0.00060, true)
	route = _label("Route", -0.323, -0.004, 0.00054)
	advice = _label("Advisory", -0.323, -0.069, 0.00050)
	status = _label("Status", 0.435, -0.069, 0.00050, true)
	sheet.name = "Checklist"
	sheet.mesh = quad
	sheet_mat.shader = Checklist
	sheet_mat.render_priority = 4         # over the glass, under the type
	sheet.material_override = sheet_mat
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sheet.visible = false
	panel.get_parent().add_child(sheet)       # (beside the panel, not under it: the panel's children are its lines of type)
	sheet.position = panel.position + Vector3(0.0, 0.0, 0.0008)
	if port:
		# The readout's picture is drawn in a room of its own, not in the cockpit: it is no fitting of the
		# hull's. (The projector is under the roof on every course now, for the start-up's checklist, and
		# the cockpit-clearance gate would measure the picture's panel as if it hung in the pod.)
		for node in port.find_children("*", "GeometryInstance3D", true, false):
			node.add_to_group("exterior")
	panel.hide()
	set_process(false)


## The roof's mount: the housing hangs under the header rail on two saddles, its lens looking down
## the glass; the image is the readout's picture lying in the screen itself, below the housing.
func _mount_under_header(_pivot: Node3D) -> void:
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
	# The readout's own picture: the glass and its type, square to a lens of their own, on nothing.
	port = SubViewport.new()
	port.name = "Picture"
	port.size = PICTURE
	port.transparent_bg = true
	port.world_3d = World3D.new()              # a room of its own: nothing of the world's is in the picture
	port.positional_shadow_atlas_size = 0
	port.render_target_update_mode = SubViewport.UPDATE_DISABLED    # drawn when the readout changes, not every frame
	add_child(port)
	var looks := Camera3D.new()
	looks.projection = Camera3D.PROJECTION_ORTHOGONAL
	looks.size = SIZE.y
	looks.position = Vector3(0.0, 0.0, 1.0)
	looks.near = 0.1
	looks.far = 3.0
	var room := Environment.new()              # (the readout is unlit: no sky, no glow, no grading of its own)
	room.background_mode = Environment.BG_COLOR
	room.background_color = Color(0, 0, 0, 0)
	looks.environment = room
	port.add_child(looks)
	looks.current = true
	# The image: that picture on a patch of the screen's own surface, a hair inside the glass.
	var sheet := SurfaceTool.new()
	sheet.begin(Mesh.PRIMITIVE_TRIANGLES)
	var across := 32
	var up := 10
	var eye_here := EYE - position
	for j in up:
		for i in across:
			var uv: Array[Vector2] = []
			var at: Array[Vector3] = []
			for c: Vector2i in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]:
				var st := Vector2(float(c.x) / across, float(c.y) / up)
				uv.append(st)
				at.append(image_point(st.x, st.y) - position)
			# (Godot's fronts wind clockwise: this one is toward the seat)
			var clockwise := (at[1] - at[0]).cross(at[2] - at[0]).dot(eye_here - at[0]) < 0.0
			for k: int in ([0, 1, 2, 0, 2, 3] if clockwise else [0, 2, 1, 0, 3, 2]):
				sheet.set_uv(Vector2(uv[k].x, 1.0 - uv[k].y))
				sheet.add_vertex(at[k])
	image_mat = ShaderMaterial.new()
	image_mat.shader = Picture
	image_mat.render_priority = 3      # over the roof's glass and the beam
	image_mat.set_shader_parameter("picture", port.get_texture())
	image = _part("Image", sheet.commit(), image_mat)
	image.visible = false
	# The beam (Luke: "add a light projector beam from the roof mounted hud projector to the actual
	# hud"): a fan from the lens down the screen to the image's top edge. From the seat it lies
	# between the housing and the readout, in the shade band, and never over the words.
	var slit: Vector3 = housing.transform * lens.position
	var fan := SurfaceTool.new()
	fan.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 16
	var rows := 10
	for j in rows:
		for i in cols:
			for corner: Vector2i in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]:
				var u := float(corner.x) / cols
				var v := float(corner.y) / rows
				var near := slit + Vector3((u - 0.5) * 0.15, 0.0, 0.0)
				var far := image_point(u, 1.0) - position
				fan.set_uv(Vector2(u, v))
				fan.add_vertex(near.lerp(far, v))
	beam_mat = ShaderMaterial.new()
	beam_mat.shader = Beam
	beam_mat.render_priority = 2      # over the roof's glass, under the image
	if beams:
		beam = _part("Beam", fan.commit(), beam_mat)
		beam.visible = false


## Where a spot on the image lies on the roof's screen, (u, v): s across the image (0 at its left ..
## 1) and t up it (0 at its foot .. 1 at its top edge, nearest the header). Up the image is up the
## glass, so its lines bow with the screen's own, as the shade band's edge does; across it is across
## the seated eye's view, so its sides stand upright from the seat. (Laid square in the screen's own
## u as well, its top came out a fifth wider than its foot and the type leaned over at both ends.)
static func image_uv(s: float, t: float) -> Vector2:
	if _place.is_empty():
		var half := IMAGE_WIDTH * SIZE.y / SIZE.x * 0.5
		_place = PackedFloat32Array([_screen_v(IMAGE_ELEVATION - half), _screen_v(IMAGE_ELEVATION + half)])
	var v := lerpf(_place[0], _place[1], t)
	if not _reach.has(t):
		_reach[t] = _screen_u(IMAGE_WIDTH * 0.5, v)
	var right: float = _reach[t]         # (the screen is the same either side of its middle)
	return Vector2(lerpf(1.0 - right, right, s), v)


## Up the screen's middle, the v the seated eye meets at this elevation.
static func _screen_v(elevation: float) -> float:
	var lo := 0.03
	var hi := 0.99
	for i in 40:
		var mid := (lo + hi) * 0.5
		var d := ScreenReflection.screen(0.5, mid) - EYE
		if atan2(d.y, -d.z) < elevation:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


## Across the screen at height v, the u the seated eye meets this far to the right of dead ahead.
static func _screen_u(azimuth: float, v: float) -> float:
	var lo := 0.01
	var hi := 0.99
	for i in 40:
		var mid := (lo + hi) * 0.5
		var d := ScreenReflection.screen(mid, v) - EYE
		if atan2(d.x, -d.z) < azimuth:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


## That spot in the canopy's space, a hair inside the glass.
static func image_point(s: float, t: float) -> Vector3:
	var on := image_uv(s, t)
	return ScreenReflection.screen(on.x, on.y) + ScreenReflection.facing(on.x, on.y) * IMAGE_INSET


## A spot on the readout where the pilot sees it, in the world (s across, t up, as image_point).
func seen_at(s: float, t: float) -> Vector3:
	if image:
		return (get_parent() as Node3D).to_global(image_point(s, t))
	return panel.to_global(Vector3((s - 0.5) * SIZE.x, (t - 0.5) * SIZE.y, 0.0))


## Draw the readout's picture again (it is drawn only when it changes).
func _redraw() -> void:
	if port:
		port.render_target_update_mode = SubViewport.UPDATE_ALWAYS if picture_every_frame else SubViewport.UPDATE_ONCE


func _follow_panel() -> void:
	if image:
		image.visible = panel.visible
		if panel.visible:
			_redraw()


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
	if _stowing:
		_stow()            # (the start-up's sheet does not stay up under another page)
	if ticking > 0.0 and not opening:
		return             # a step is being ticked off: its page stays up until that is done (animate() writes this one)
	_write(value)
	if opening:
		panel.show()
		_reveal()
		set_process(true)


## Set the type to a page, and the glass's colours to what it says.
func _write(value: String) -> void:
	var lines := value.split("\n")
	var metrics := lines[0].split("  ",false,1)
	if not checklist.is_empty() and metrics[0] != action.text:
		typing = 0.0       # a new page of the checklist arrives line by line
	_written = value
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
	if beam_mat:
		beam_mat.set_shader_parameter("signal", tint)
	var direction := -1 if metrics[0]=="LEFT EXIT" else (1 if metrics[0]=="RIGHT EXIT" else 0)
	surface.set_shader_parameter("direction", float(direction))
	surface.set_shader_parameter("wrong_way", metrics[0]=="WRONG WAY")
	sheet_mat.set_shader_parameter("signal", tint)
	_redraw()


## The start-up's checklist in motion. `state` is StartupSequence.display() while the craft is being
## started and {} at every other time: then the sheet is put away and none of this is run. Give it
## before the page that goes with it (set_message): a step that has just been ticked off keeps its
## page on the glass for TICK_TIME while its segment of the rail is wiped full, and only then is the
## next step's page written, line by line. (CLEARED waits for nothing.) What the sheet draws from
## the rest of the state is in view/startup_glass.gdshader.
func set_checklist(state: Dictionary) -> void:
	if state.is_empty():
		if not checklist.is_empty():
			checklist = {}
			ticking = 0.0
			typing = 1.0
			sweeping = 1.0
			_stowing = true    # (it goes out with the glass, or as the next page is written)
			set_process(true)
		return
	if checklist.is_empty():           # the bus has come up: a sweep across the glass, the rail lit behind it
		clock = 0.0
		_ticked_at = 0.3               # (the battery's own step, ticked as the rail lights)
		ticking = 0.0
		typing = 0.0
		sweeping = 1.0
		_stowing = false
		sheet.show()
		surface.set_shader_parameter("pointer", 0.0)
	elif int(state.done) > int(checklist.done):
		_ticked_at = clock
		if float(state.cleared) < 0.0:
			ticking = TICK_TIME
	elif int(state.mark) > int(checklist.mark):
		sweeping = 0.0
	checklist = state
	set_process(true)


## The checklist's clockwork, once a frame while it is up (a test steps it by hand).
func animate(delta: float) -> void:
	clock += delta
	if ticking > 0.0:
		ticking = maxf(0.0, ticking - delta)
		if ticking == 0.0 and _written != message and not message.is_empty():
			_write(message)
	typing = minf(1.0, typing + delta / TYPE_TIME)
	sweeping = minf(1.0, sweeping + delta / SWEEP_TIME)
	ticked = clampf((clock - _ticked_at) / SETTLE_TIME, 0.0, 1.0)
	var held := ticking > 0.0          # (the page still up is the finished step's: its bar stays full under it)
	var bars: Array = [1.0, 1.0] if held else checklist.bars
	var flare: Array = checklist.flare
	var landed: float = checklist.cleared
	sheet_mat.set_shader_parameter("age", clock)
	sheet_mat.set_shader_parameter("phase", fposmod(clock * BEAT_HZ, 1.0))
	sheet_mat.set_shader_parameter("done", float(checklist.done))
	sheet_mat.set_shader_parameter("tick", ticked)
	sheet_mat.set_shader_parameter("bars", Vector2(bars[0], bars[1]))
	sheet_mat.set_shader_parameter("pair", bool(checklist.pair) and not held)
	sheet_mat.set_shader_parameter("flare", Vector2(flare[0], flare[1]))
	sheet_mat.set_shader_parameter("aim", float(checklist.aim))
	sheet_mat.set_shader_parameter("ask", 1.0 if int(checklist.aim) != 0 and not held else 0.0)
	sheet_mat.set_shader_parameter("alert", 1.0 if checklist.alert else 0.0)
	sheet_mat.set_shader_parameter("sweep", sweeping)
	sheet_mat.set_shader_parameter("cleared", landed)
	action.scale = Vector3.ONE * arrival(landed)
	_ink()
	_redraw()


## CLEARED arrives larger than it stays: the top line's size, so long after the brake came off.
static func arrival(landed: float) -> float:
	return 1.0 if landed < 0.0 else 1.0 + 0.28 * (1.0 - smoothstep(0.0, 0.45, landed))


## Put the checklist's sheet away, and give the glass back its own arrow.
func _stow() -> void:
	if not _stowing and not sheet.visible:
		return
	_stowing = false
	sheet.hide()
	surface.set_shader_parameter("pointer", 1.0)
	action.scale = Vector3.ONE
	_ink()
	_redraw()


func _process(delta: float) -> void:
	var target := 0.0 if message.is_empty() else 1.0
	deployment = move_toward(deployment, target, delta / (CLOSE_TIME if message.is_empty() else OPEN_TIME))
	_reveal()
	if deployment == target:
		panel.visible = deployment > 0.0
		if _stowing or not panel.visible:
			_stow()
		if checklist.is_empty():
			set_process(false)
	if not checklist.is_empty():
		animate(delta)

func _reveal() -> void:
	var scan := smoothstep(0.0,1.0,deployment)
	surface.set_shader_parameter("scan", scan)
	sheet_mat.set_shader_parameter("scan", scan)
	_redraw()
	if lens_mat:
		lens_mat.albedo_color = LENS_IDLE.lerp(LENS_LIT, scan)
	if beam:
		beam.visible = deployment > 0.0
		beam_mat.set_shader_parameter("lit", scan)
	_ink()


## The type's ink: each line comes in as the glass is revealed down to it, and on a page of the
## checklist that has just been written, in its turn.
func _ink() -> void:
	var scan := smoothstep(0.0,1.0,deployment)
	for label: Label3D in [action, countdown, route, advice, status]:
		var row := 0.5-label.position.y/SIZE.y
		var opacity := smoothstep(row, row+0.16, scan)
		if typing < 1.0:
			var turn := 0.0 if label == action or label == countdown else (0.25 if label == route else 0.5)
			opacity *= smoothstep(turn, turn+0.5, typing)
		label.modulate.a = opacity
		label.outline_modulate.a = opacity*0.8
