extends Node3D

const UI := preload("res://release/release_config.gd")
const BayFont := preload("res://art/signs/RG2014D.ttf")

var _title: Label
var _hint: Label
var _status: Label
var _placard: Node3D
var _vr_title: Label3D
var _vr_hint: Label3D
var _vr_status: Label3D
var _vr_bay: Label3D       # on foot at a bay, under the sign's two lines: its paint control (or why it was refused)
var _backing: MeshInstance3D
var _face: QuadMesh
var _mount_clips: MultiMeshInstance3D
var _seated := false
var _state := ""


func setup(xr: bool) -> void:
	if xr:
		_make_placard()
		return
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	layer.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 24
	panel.offset_right = 24
	panel.offset_top = -24
	panel.offset_bottom = -24
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UI.box(Color(0.035, 0.057, 0.076, 0.91))
	style.border_color = UI.AMBER
	style.border_width_left = 3
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	panel.add_child(rows)
	_title = UI.label("", 22, UI.INK)
	_hint = UI.label("", 16, Color("#c0cacf"))
	_status = UI.label("", 17, UI.AMBER)
	_status.hide()
	rows.add_child(_title)
	rows.add_child(_status)
	rows.add_child(_hint)


func _make_placard() -> void:
	# Set down the sign in the garage so head movements never tow text across the pilot's view.
	_placard = Node3D.new()
	add_child(_placard)
	var backing := MeshInstance3D.new()
	_backing = backing
	_face = QuadMesh.new()
	_face.size = Vector2(0.99, 0.19)
	var enamel := StandardMaterial3D.new()
	enamel.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	enamel.albedo_color = Color("#14222c")
	_face.material = enamel
	backing.mesh = _face
	backing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_placard.add_child(backing)
	var clips := MultiMesh.new()
	clips.transform_format = MultiMesh.TRANSFORM_3D
	var metal := BoxMesh.new()
	metal.size = Vector3(.042,.086,.026)
	var finish := StandardMaterial3D.new()
	finish.albedo_color = Color("#78878b")
	finish.metallic = .64
	finish.roughness = .42
	metal.material = finish
	clips.mesh = metal
	clips.instance_count = 2
	for i in 2:
		clips.set_instance_transform(i,Transform3D(Basis.IDENTITY,Vector3((i-.5)*.57,.100,-.014)))
	_mount_clips = MultiMeshInstance3D.new()
	_mount_clips.multimesh = clips
	_placard.add_child(_mount_clips)
	_vr_title = _sign_line(42, 0.037, UI.AMBER)
	_vr_hint = _sign_line(28, -0.038, UI.INK)
	_vr_status = _sign_line(26, 0.063, UI.AMBER)
	_vr_status.hide()
	_vr_bay = _sign_line(40, -0.112, UI.INK)
	_vr_bay.font = BayFont
	_vr_bay.pixel_size = .00115
	_vr_bay.hide()


func _sign_line(size: int, height: float, color: Color) -> Label3D:
	var line := Label3D.new()
	line.position = Vector3(-0.46, height, 0.003)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	line.font_size = size
	line.pixel_size = 0.00089
	line.modulate = color
	line.outline_size = 0
	line.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	line.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	_placard.add_child(line)
	return line


func boarding(craft: String) -> void:
	_vr_title.text = "Boarding " + craft
	_vr_hint.text = ""
	# (the bay's controls are not taken while the cab builds: garage.gd _work_bay. The sign is its two lines again)
	_vr_bay.hide()
	_face.size = Vector2(.99, .19)
	_backing.position.y = 0.0


func set_runup_status(value: String) -> void:
	if _state == value: return
	_state = value
	_show_status()


func _show_status() -> void:
	if _vr_status:
		_vr_status.text = _state
		_vr_status.visible = _seated and not _state.is_empty()
	if _status:
		_status.text = _state
		_status.visible = _seated and not _state.is_empty()


func show_rotor(pad: bool, counter: Transform3D) -> void:
	_seated = false
	_show_status()
	if _placard:
		_sign_type(false)
		_mount_clips.hide()
		_vr_bay.hide()
		_backing.position.y = 0.0
		# Mount this instruction on the forward fascia, below the spindle.
		_placard.global_transform = counter.translated_local(Vector3(1.0, .847, .947)).scaled_local(Vector3.ONE * .60)
		_face.size = Vector2(.99, .19)
		_vr_title.position = Vector3(-.46, .037, .003)
		_vr_hint.position = Vector3(-.46, -.038, .003)
		_vr_title.text = "Rotor inspection"
		_vr_hint.text = "Grip and turn the rim     A  Spin"
	else:
		_title.text = "%s  Spin inspection rotor" % ("A" if pad else "E")
		_hint.text = "Watch the dial as the rotor turns."
		_status.hide()


func place_on_marker(mount: Transform3D) -> void:
	if _placard and not _placard.global_transform.is_equal_approx(mount):
		_placard.global_transform = mount


func _sign_type(on_marker: bool) -> void:
	_vr_title.font = BayFont if on_marker else null
	_vr_hint.font = BayFont if on_marker else null
	_vr_title.font_size = 62 if on_marker else 42
	_vr_hint.font_size = 40 if on_marker else 28
	_vr_title.pixel_size = .00120 if on_marker else .00089
	_vr_hint.pixel_size = .00115 if on_marker else .00089


## `paint`: on foot at a bay, the name of the paint the craft there wears (its control is offered); `refused`: why the
## last change at that bay was refused ("" none); `body`: at the Phaethon's bay, the body standing there (its control,
## the other body, is offered).
func show_controls(craft: String, seated: bool, destination: String, pad: bool, anchor: Transform3D, paint := "",
		refused := "", body := "") -> void:
	_seated = seated
	_show_status()
	var at_bay := not seated and not craft.is_empty() and not paint.is_empty()
	var board := "A" if pad or _placard else "E"
	var fly := "Y" if pad or _placard else "F"
	var back := "B" if pad or _placard else "Esc"
	var action := "Walk to a cockpit"
	var hint := "WASD  Walk     Mouse  Look     V  Pilot view     Esc  Menu"
	if _placard:
		hint = "Left stick  Walk     Right stick  Turn     B  Menu"
	elif pad:
		hint = "Left stick  Walk     Right stick  Look     R3  Pilot view     B  Menu"
	if seated:
		action = craft + "  /  " + destination
		if _placard:
			hint = "X  Start or stop     Left stick click  Park\nTriggers  Throttle     Grips  Airbrakes\nGrip and move levers · Reach up for switches"
		elif pad:
			hint = "X  Start or stop     L3  Parking brake     D-pad  Look\nLeft / right stick forward  Throttles     LT / RT  Airbrakes"
		else:
			hint = "I  Start or stop     P  Parking brake\nW/S  Left throttle     ↑/↓  Right throttle     X  Idle\nA  Left airbrake     →  Right airbrake"
		hint += "\n%s  Launch flight     %s  Step out     %s  Menu" % [fly, board, back]
	elif not craft.is_empty():
		action = "%s  Board %s" % [board, craft]
		if at_bay:
			var swap := "     %s  Body: %s" % ["L3" if pad else "P", body] if not body.is_empty() else ""
			hint = "%s  Paint: %s%s\n%s" % ["X" if pad else "I", paint, swap, hint]
	if _placard:
		_sign_type(not seated)
		if not seated:
			action = "A   BOARD" if not craft.is_empty() else "WALK TO A COCKPIT"
			hint = "B   MENU" if not craft.is_empty() else "LEFT STICK  WALK     RIGHT STICK  TURN"
		_mount_clips.visible = not seated
		_placard.global_transform = anchor
		_face.size = Vector2(.74, .32) if seated else Vector2(.99, .19)
		for row: Label3D in [_vr_title, _vr_status, _vr_hint]:
			row.position.x = -.34 if seated else -.46
		_vr_title.position.y = .112 if seated else .037
		_vr_hint.position.y = -.050 if seated else -.038
		if seated:
			# Fixed along the port canopy rail, away from the windshield and lever arc.
			var rail := anchor.orthonormalized().translated_local(Vector3(-.46, -.02, -.13))
			_placard.global_transform = rail.rotated_local(Vector3.UP, deg_to_rad(75)).scaled_local(Vector3.ONE * .68)
		_vr_title.text = action
		_vr_hint.text = hint
		# on foot at a bay a third line, under the two (the card grows downward, from its clips): the paint control
		_vr_bay.visible = at_bay
		_vr_bay.modulate = UI.AMBER if not refused.is_empty() else UI.INK
		_vr_bay.text = refused.to_upper() if not refused.is_empty() else "X   PAINT  " + paint.to_upper()
		if refused.is_empty() and not body.is_empty():
			_vr_bay.text += "\nL STICK CLICK   BODY  " + body.to_upper()
		if at_bay:
			_face.size = Vector2(.99, .30)
		_backing.position.y = -.055 if at_bay else 0.0
	else:
		_title.text = action
		_hint.text = hint
		if not seated:
			_status.text = refused
			_status.visible = not refused.is_empty()
