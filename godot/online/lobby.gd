extends Control
const View := preload("res://view/craft_view.gd")
var session
var pilot: LineEdit
var address: LineEdit
var port: SpinBox
var track: OptionButton
var vr: CheckBox
var status: Label
var actions: Array[Button] = []
const TRACK_IDS := ["network", "gp", "eridanus", "range", "gp_dunes", "gp_glacier", "gp_basalt", "gp_mesa", "circuit"]
const TRACK_LABELS := ["The Network · highways & cities", "Grand Prix", "Eridanus", "100-mile range", "Dunes GP", "Glacier GP", "Basalt GP", "Mesa GP", "Original circuit"]

func _ready() -> void:
	session = get_node("/root/RaceSession")
	get_viewport().use_xr = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("10151e")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 620
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	var title := Label.new()
	title.text = "PHAETHON"
	title.add_theme_font_size_override("font_size", 44)
	title.modulate = Color("ffb76c")
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Two engines. Two pilots. Far too much road."
	subtitle.add_theme_font_size_override("font_size", 18)
	box.add_child(subtitle)
	pilot = _field(box, "Pilot name", "Pilot")
	pilot.max_length = 20
	address = _field(box, "Host address (joining only)", "")
	address.placeholder_text = "Tailscale IP, local IP or public host address"
	address.max_length = 253
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var port_label := Label.new()
	port_label.text = "UDP port"
	row.add_child(port_label)
	port = SpinBox.new()
	port.min_value = 1024
	port.max_value = 65535
	port.value = 27840
	row.add_child(port)
	track = OptionButton.new()
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for text in TRACK_LABELS: track.add_item(text)
	row.add_child(track)
	vr = CheckBox.new()
	vr.text = "VR cockpit (start with Play-VR.cmd / launch_online.ps1 -VR)"
	vr.button_pressed = session.use_vr
	box.add_child(vr)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_button(buttons, "Host session", _host)
	_button(buttons, "Join friend", _join)
	_button(buttons, "Solo drive", _solo)
	_button(buttons, "Cancel / disconnect", func(): session.leave_game())
	status = Label.new()
	status.custom_minimum_size = Vector2(620, 52)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.modulate = Color("70d9eb")
	box.add_child(status)
	var hint := Label.new()
	hint.text = "ONLINE: share your gaming PC through Tailscale, or forward UDP 27840.\nBoth players need the same release. The host chooses the track.\nOnline has no AI traffic or player collisions. Escape opens the driving menu.\nKeyboard: E throttle both · D reduce · X cut · A / Right brakes · Backspace reset"
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color("b4becb")
	box.add_child(hint)
	session.status_changed.connect(_refresh)
	session.joined.connect(_launch)
	_load_settings()
	_refresh()
	pilot.grab_focus()
	# CLI uses the exact same host/join/launch path as the visible buttons.
	var auto := ""
	for arg in OS.get_cmdline_user_args():
		if arg == "--host": auto = "host"
		if arg.begins_with("--join="):
			address.text = arg.trim_prefix("--join=")
			auto = "join"
		if arg.begins_with("--name="): pilot.text = arg.trim_prefix("--name=")
		if arg.begins_with("--port="): port.value = int(arg.trim_prefix("--port="))
		if arg.begins_with("--track="):
			var i := TRACK_IDS.find(arg.trim_prefix("--track="))
			if i >= 0: track.select(i)
		if arg == "--vr": vr.button_pressed = true
	if auto == "host": call_deferred("_host")
	if auto == "join": call_deferred("_join")

func _field(box: VBoxContainer, title: String, value: String) -> LineEdit:
	var label := Label.new()
	label.text = title
	box.add_child(label)
	var field := LineEdit.new()
	field.text = value
	field.custom_minimum_size.y = 38
	box.add_child(field)
	return field

func _button(row: HBoxContainer, title: String, action: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 42
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	row.add_child(button)
	actions.append(button)

func _refresh() -> void:
	status.text = session.status
	for i in actions.size(): actions[i].disabled = session.connecting and i < 3

func _host() -> void:
	_save_settings()
	if session.host_game(pilot.text, TRACK_IDS[track.selected], int(port.value)) == OK:
		_launch()

func _join() -> void:
	_save_settings()
	session.join_game(address.text, pilot.text, int(port.value))

func _solo() -> void:
	_save_settings()
	session.leave_game()
	View.track_override = TRACK_IDS[track.selected]
	View.job_override = "none"
	_launch()

func _launch() -> void:
	session.use_vr = vr.button_pressed
	if vr.button_pressed:
		var xr := XRServer.find_interface("OpenXR")
		if xr == null or not xr.is_initialized():
			session.leave_game("VR needs a fresh launch: connect Quest Link / OpenXR, close the game, then run Play-VR.cmd (source: launch_online.ps1 -VR). Or uncheck VR for desktop.")
			return
	var scene := "res://vr.tscn" if vr.button_pressed else "res://main.tscn"
	get_tree().call_deferred("change_scene_to_file", scene)

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://online.cfg") != OK: return
	pilot.text = session.clean_name(str(config.get_value("lobby", "pilot", "Pilot")))
	address.text = str(config.get_value("lobby", "address", ""))
	port.value = clampi(int(config.get_value("lobby", "port", 27840)), 1024, 65535)

func _save_settings() -> void:
	# Automated CLI smoke runs never overwrite the human's lobby preferences.
	if "--online-test" in OS.get_cmdline_user_args(): return
	var config := ConfigFile.new()
	config.set_value("lobby", "pilot", session.clean_name(pilot.text))
	config.set_value("lobby", "address", address.text.strip_edges())
	config.set_value("lobby", "port", int(port.value))
	config.save("user://online.cfg")
