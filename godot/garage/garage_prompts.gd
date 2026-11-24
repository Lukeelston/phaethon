extends Node3D

const UI := preload("res://release/release_config.gd")

var _title: Label
var _hint: Label
var _placard: Node3D
var _vr_title: Label3D
var _vr_hint: Label3D


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
	rows.add_child(_title)
	rows.add_child(_hint)


func _make_placard() -> void:
	# Set down the sign in the garage so head movements never tow text across the pilot's view.
	_placard = Node3D.new()
	add_child(_placard)
	var backing := MeshInstance3D.new()
	var face := QuadMesh.new()
	face.size = Vector2(0.99, 0.19)
	var enamel := StandardMaterial3D.new()
	enamel.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	enamel.albedo_color = Color("#14222c")
	face.material = enamel
	backing.mesh = face
	backing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_placard.add_child(backing)
	_vr_title = _sign_line(42, 0.037, UI.AMBER)
	_vr_hint = _sign_line(28, -0.038, UI.INK)


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


func show_controls(craft: String, seated: bool, destination: String, pad: bool, anchor: Transform3D) -> void:
	var board := "A" if pad or _placard else "E"
	var fly := "Y" if pad or _placard else "F"
	var back := "B" if pad or _placard else "Esc"
	var action := "Walk to a cockpit"
	var hint := "WASD  Walk     Mouse  Look     V  Pilot view     Esc  Menu"
	if _placard:
		hint = "Left stick  Walk     Right stick  Snap turn     B  Menu"
	elif pad:
		hint = "Left stick  Walk     Right stick  Look     R3  Pilot view     B  Menu"
	if seated:
		action = craft + "  /  " + destination
		hint = "%s  Launch flight     %s  Step out     %s  Menu" % [fly, board, back]
	elif not craft.is_empty():
		action = "%s  Board %s" % [board, craft]
	if _placard:
		# Walking anchors are floor poses. A seated anchor is already at the pilot's eyes.
		var offset := Vector3(-0.24, 1.55, -1.65)
		if seated:
			offset = Vector3(-0.40, 0.23, -1.12)
		_placard.global_transform = anchor.orthonormalized().translated_local(offset)
		_vr_title.text = action
		_vr_hint.text = hint
	else:
		_title.text = action
		_hint.text = hint
