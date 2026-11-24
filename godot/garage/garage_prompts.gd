extends Node3D

const UI := preload("res://release/release_config.gd")

var _title: Label
var _hint: Label
var _status: Label
var _placard: Node3D
var _vr_title: Label3D
var _vr_hint: Label3D
var _vr_status: Label3D
var _face: QuadMesh
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
	_face = QuadMesh.new()
	_face.size = Vector2(0.99, 0.19)
	var enamel := StandardMaterial3D.new()
	enamel.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	enamel.albedo_color = Color("#14222c")
	_face.material = enamel
	backing.mesh = _face
	backing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_placard.add_child(backing)
	_vr_title = _sign_line(42, 0.037, UI.AMBER)
	_vr_hint = _sign_line(28, -0.038, UI.INK)
	_vr_status = _sign_line(26, 0.063, UI.AMBER)
	_vr_status.hide()


func _sign_line(size: int, height: float, color: Color) -> Label3D:
	var line := Label3D.new()
	line.position = Vector3(-0.46, height, 0.003)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	line.font_size = size
	line.pixel_size = 0.00089
	line.modulate = color
	line.outline_size = 0
	_placard.add_child(line)
	return line


func boarding(craft: String) -> void:
	_vr_title.text = "Boarding " + craft
	_vr_hint.text = ""


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


func show_controls(craft: String, seated: bool, destination: String, pad: bool, anchor: Transform3D) -> void:
	_seated = seated
	_show_status()
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
	if _placard:
		# Walking anchors are floor poses. A seated anchor is already at the pilot's eyes.
		var offset := Vector3(-0.24, 1.55, -1.65)
		_placard.global_transform = anchor.orthonormalized().translated_local(offset)
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
	else:
		_title.text = action
		_hint.text = hint
