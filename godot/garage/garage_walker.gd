## A metre-scale standing rig. The capsule origin is the floor, and a seat pose is
## supplied at the actual cockpit eye rather than at the foot of the avatar.
extends CharacterBody3D

signal interact_requested
signal launch_requested
signal back_requested
signal cockpit_control_requested(control: String)
# On foot, the same two buttons work the bay in front of the pilot (garage.gd _work_bay): "paint" (key I, pad X, left
# X in the headset) and "body" (key P, pad L3, left stick click in the headset). The stick's click is that stick's
# own: "body" is refused only while it is pushed BODY_CLICK_MAX_STICK or more, so a brisk walk past the bay swaps
# nothing, and a deliberate click that tilts the stick a little (a real Touch thumbstick does) still counts.
signal bay_control_requested(control: String)
# Sprint and jump (Luke, 2026-11-26: "add sprint with left click, jump with A"). The same stick click, with the stick
# pushed BODY_CLICK_MAX_STICK or more, sprints (_stick_click): SPRINT_SPEED until the stick is let go. Jumping is
# jump(): the garage calls it for the board button (right A in the headset) where there is nothing to board
# (garage.gd _board_button); Space on the keyboard. Shift held while walking sprints too.
signal boot_planted(side: int, at: Vector3, speed: float)

const Pilot := preload("res://garage/pilot_model.gd")
const Levers := preload("res://input/lever_input.gd")
const CockpitControls := preload("res://garage/garage_controls.gd")
const STANDING_EYE_HEIGHT := Pilot.STANDING_EYE.y
const WALK_SPEED := 2.35
const SPRINT_SPEED := 4.6      # (under the stride's own limit of 5 m/s: step_locomotion)
const JUMP_SPEED := 3.0        # m/s off the floor: 0.46 m up, 0.6 s in the air
const TURN_SPEED := PI / 2.0  # radians per second at full right-stick travel
const DEADZONE := .19
const BODY_CLICK_MAX_STICK := .5   # an on-foot stick click at this deflection or more is walking, not the body control
const LOOK_LIMIT := deg_to_rad(82.0)

var allow_xr := false
var xr_live := false
var seated := false
var third_person := false
var using_gamepad := false
var sprinting := false      # on foot, from a stick click with the stick pushed until the stick is let go
var scripted := false       # a climb in or out is playing (garage/boarding.gd): no walking, looking or cockpit controls
var camera: Camera3D
var hands := {}

var _shape: CollisionShape3D
var _avatar: Pilot
var _distance := 0.0
var _jump := false          # asked for since the last step (jump())
var _head_sway := Vector3.ZERO
var _origin: Node3D
var _eye: Camera3D
var _boom: SpringArm3D
var _outside: Camera3D
var _gloves := {}
var _tracking_hands := false
var _xr: XRInterface
var _xr_focused := false
var _align_tracking := true
var _tracking_area := XRInterface.XR_PLAY_AREA_UNKNOWN
var _height_offset := 0.0
var _xr_down := Vector3i.ZERO
var _xr_cockpit_down := Vector2i.ZERO
var _controls := CockpitControls.new()
var _left_live := false
var _right_live := false
var _joy := -1
var _pad_axes := false
var _pitch := 0.0
var _focused := true
var _previous_mouse := Input.MOUSE_MODE_VISIBLE
var _owns_mouse := false
var _previous_xr := false


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = .18
	safe_margin = .004
	var capsule := CapsuleShape3D.new()
	capsule.radius = .29
	capsule.height = 1.76
	_shape = CollisionShape3D.new()
	_shape.name = "StandingCapsule"
	_shape.shape = capsule
	_shape.position.y = capsule.height * .5
	add_child(_shape)

	_xr = _garage_interface()
	xr_live = allow_xr and _xr != null and _xr.is_initialized()
	_previous_mouse = Input.mouse_mode
	_previous_xr = get_viewport().use_xr
	get_viewport().use_xr = xr_live
	if xr_live:
		get_viewport().msaa_3d = Viewport.MSAA_4X
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_origin = XROrigin3D.new()
		_eye = XRCamera3D.new()
		add_child(_origin)
		_origin.add_child(_eye)
		for side in ["left","right"]:
			var hand := XRController3D.new()
			hand.tracker = "%s_hand" % side
			hand.pose = &"grip"
			_origin.add_child(hand)
			hands[side] = hand
		if _xr.has_signal(&"pose_recentered"):
			_xr.connect(&"pose_recentered",_on_recenter)
		_xr.play_area_changed.connect(_on_recenter.unbind(1))
		XRServer.reference_frame_changed.connect(_on_recenter)
	else:
		_origin = Node3D.new()
		_origin.position = Pilot.STANDING_EYE
		_eye = Camera3D.new()
		add_child(_origin)
		_origin.add_child(_eye)
		_boom = SpringArm3D.new()
		_boom.position.y = 1.20
		_boom.rotation.x = -.14
		_boom.spring_length = 2.55
		_boom.margin = .04
		_boom.collision_mask = collision_mask
		var probe := SphereShape3D.new()
		probe.radius = .15
		_boom.shape = probe
		add_child(_boom)
		_boom.add_excluded_object(get_rid())
		_outside = Camera3D.new()
		_outside.near = .045
		_boom.add_child(_outside)
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_owns_mouse = true
	_eye.near = .045
	camera = _eye
	camera.make_current()


func _exit_tree() -> void:
	get_viewport().use_xr = _previous_xr
	if _owns_mouse:
		Input.mouse_mode = _previous_mouse


func _garage_interface() -> XRInterface:
	return XRServer.find_interface("OpenXR")


func _xr_has_focus() -> bool:
	var openxr := _xr as OpenXRInterface
	return openxr != null and openxr.get_session_state() == OpenXRInterface.SESSION_STATE_FOCUSED


func set_pilot(pilot: Pilot) -> void:
	_avatar = pilot
	add_child(pilot)
	pilot.set_seated(seated)
	pilot.set_first_person(not third_person)
	if xr_live:
		for side in hands:
			var glove: Node3D = pilot.make_glove(side)
			glove.hide()
			hands[side].add_child(glove)
			_gloves[side] = glove
	elif not xr_live:
		_origin.position = Pilot.STANDING_EYE


func set_seated(value: bool, pose: Transform3D) -> void:
	seated = value
	sprinting = false
	_jump = false
	_head_sway = Vector3.ZERO
	_controls.reset()
	_pad_axes = false
	if not seated:
		_controls.handles.clear()
	velocity = Vector3.ZERO
	_pitch = 0.0
	if third_person:
		_inspect(false)
	# Keep the visual horizon level, even when a parked airframe is pitched.
	var heading := atan2(pose.basis.z.x,pose.basis.z.z)
	var basis_yaw := Basis(Vector3.UP,heading)
	global_transform = Transform3D(basis_yaw,pose.origin - basis_yaw * Pilot.SEATED_EYE if seated else pose.origin)
	_shape.disabled = seated
	if _avatar:
		_avatar.rotation = Vector3.ZERO
		_avatar.scale = Vector3.ONE
		_avatar.position = Vector3.ZERO
		_avatar.set_seated(seated)
		_avatar.set_stride(_distance,false)
	if xr_live:
		_align_tracking = true
		if _xr_has_focus():
			_align_head()
	else:
		_origin.rotation = Vector3.ZERO
		_origin.position = Pilot.SEATED_EYE if seated else Pilot.STANDING_EYE
		_eye.rotation = Vector3.ZERO


func eye_transform() -> Transform3D:
	return camera.get_camera_transform()


## Hold the walker while a climb plays (garage/boarding.gd): it walks, looks and works no controls; the headset's
## gloves go and the pilot's own arms show (the climb puts his hands on the craft); its capsule stands aside.
func begin_scripted() -> void:
	scripted = true
	sprinting = false
	_jump = false
	velocity = Vector3.ZERO
	_controls.reset()
	_shape.disabled = true
	for glove: Node3D in _gloves.values():
		glove.hide()
	if _avatar:
		_tracking_hands = false
		_avatar.set_tracked_hands(false)


## Let go again (set_seated has already put the walker where the climb ended).
func end_scripted() -> void:
	scripted = false
	_shape.disabled = seated
	_controls.reset()
	if not xr_live:
		camera.make_current()


## Move the headset's view by `by` (world): the climb carries the player's eye along the pilot's.
func nudge_view(by: Vector3) -> void:
	_origin.global_position += by


func cockpit_input() -> Dictionary:
	return _controls.axes.duplicate()


func set_cockpit_grips(handles: Array[Node3D]) -> void:
	_controls.handles = handles.duplicate()


func cockpit_hands() -> Array[XRController3D]:
	return tracked_hands(true)


func tracked_hands(for_seat: bool) -> Array[XRController3D]:
	var active: Array[XRController3D] = []
	if seated == for_seat and xr_live and _xr_focused and not _align_tracking:
		for hand: XRController3D in hands.values():
			if hand.get_has_tracking_data():
				active.append(hand)
	return active


func _on_recenter() -> void:
	_align_tracking = true
	_head_sway = Vector3.ZERO
	if seated:
		_controls.reset()


func _align_head() -> void:
	var tracker := XRServer.get_tracker(&"head") as XRPositionalTracker
	var head := tracker.get_pose(&"default") if tracker else null
	if head == null or not head.has_tracking_data or head.tracking_confidence == XRPose.XR_TRACKING_CONFIDENCE_NONE:
		_align_tracking = true
		return
	# Raw OpenXR metres give us floor height and subsequent physical movement.
	# The camera supplies the eye actually projected after an inherited recenter.
	# Both hands ride this same origin. Keep the runtime's reference space intact.
	var raw_y := head.transform.origin.y * XRServer.world_scale
	var view := _origin.global_transform.affine_inverse() * eye_transform()
	var mode := _xr.get_play_area_mode()
	if _align_tracking or mode != _tracking_area:
		var floor_tracked := mode in [XRInterface.XR_PLAY_AREA_ROOMSCALE,XRInterface.XR_PLAY_AREA_STAGE]
		if not seated and floor_tracked and raw_y <= .20:
			return  # the runtime has not delivered a floor-space position yet
		var height := raw_y if floor_tracked else STANDING_EYE_HEIGHT
		var target := Pilot.SEATED_EYE if seated else Vector3(0,height,0)
		_height_offset = target.y - raw_y
		_origin.rotation.y = -atan2(view.basis.z.x,view.basis.z.z)
		_origin.position = target - _origin.basis * view.origin
		if not seated and _avatar:
			_avatar.scale = Vector3.ONE * (height/STANDING_EYE_HEIGHT)
			_avatar.position.z = -Pilot.STANDING_EYE.z * _avatar.scale.z
		_tracking_area = mode
		_align_tracking = false
	else:
		# An interface may publish its updated camera sample after the tracker.
		# Retain physical head-height deltas when that projected sample arrives.
		_origin.position.y = _height_offset + raw_y - (_origin.basis * view.origin).y


func _inspect(on: bool) -> void:
	if xr_live or (on and seated):
		return
	if third_person and not on and not seated and _avatar:
		rotate_y(_avatar.rotation.y)
	third_person = on
	_boom.rotation = Vector3(-.14,0,0)
	_pitch = 0.0
	_eye.rotation.x = 0.0
	camera = _outside if on else _eye
	camera.make_current()
	if _avatar:
		_avatar.rotation.y = 0
		_avatar.set_first_person(not on)


func _look(yaw: float, pitch: float) -> void:
	if scripted:
		return
	if third_person:
		_boom.rotation.y += yaw
		_boom.rotation.x = clampf(_boom.rotation.x + pitch,-1.08,.38)
	else:
		if seated:
			_origin.rotation.y = clampf(_origin.rotation.y + yaw,-2.35,2.35)
		else:
			rotate_y(yaw)
		_pitch = clampf(_pitch + pitch,-LOOK_LIMIT,LOOK_LIMIT)
		_eye.rotation.x = _pitch


func _unhandled_input(event: InputEvent) -> void:
	if not is_node_ready() or not _focused:
		return
	var key := KEY_NONE
	var click_stick := Vector2.ZERO      # (where L3's stick stood as it clicked: pushed is a sprint, not the body)
	if event is InputEventKey and event.pressed and not event.echo:
		key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		using_gamepad = false
	elif not xr_live and event is InputEventJoypadButton and event.pressed:
		if Input.get_connected_joypads().has(event.device) and not _is_gamepad(event.device):
			return
		_joy = event.device
		using_gamepad = true
		match event.button_index:
			JOY_BUTTON_A: key = KEY_E
			JOY_BUTTON_Y: key = KEY_F
			JOY_BUTTON_B: key = KEY_ESCAPE
			JOY_BUTTON_X: key = KEY_I
			JOY_BUTTON_LEFT_STICK:
				key = KEY_P
				click_stick = Vector2(Input.get_joy_axis(event.device, JOY_AXIS_LEFT_X), Input.get_joy_axis(event.device, JOY_AXIS_LEFT_Y))
			JOY_BUTTON_RIGHT_STICK: key = KEY_V
	elif not xr_live and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.relative.length_squared() > .01:
			using_gamepad = false
			_look(-event.relative.x*.0023,-event.relative.y*.0023)
		return
	elif not xr_live and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		using_gamepad = false
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_owns_mouse = true
		return
	match key:
		KEY_E: interact_requested.emit()
		KEY_F: launch_requested.emit()
		KEY_ESCAPE: back_requested.emit()
		KEY_V:
			if not scripted: _inspect(not third_person)
		KEY_I, KEY_P:
			if xr_live: return
			if seated:
				cockpit_control_requested.emit("power" if key == KEY_I else "park")
			elif key == KEY_I:
				bay_control_requested.emit("paint")
			else:
				_stick_click(click_stick)
		KEY_SPACE:
			if seated or scripted: return
			jump()
		_: return
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		velocity = Vector3.ZERO
		if seated: _controls.reset()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true


## Is a click on a stick deflected `v` the body control (not a brisk walk)? Under BODY_CLICK_MAX_STICK, which is well
## past DEADZONE: a pressed thumbstick tilts.
func _body_click(v: Vector2) -> bool:
	return v.length() < BODY_CLICK_MAX_STICK


## A stick click on foot, the stick standing at `stick`: near its centre it is the bay's body control, pushed it is
## the start of a sprint (which step_locomotion ends when the stick is let go).
func _stick_click(stick: Vector2) -> void:
	if seated or scripted:
		return
	if _body_click(stick):
		bay_control_requested.emit("body")
	else:
		sprinting = true


## Jump, if he is on his feet on the floor at the next step (a press in the air is dropped, none is saved up).
func jump() -> void:
	if not seated and not scripted:
		_jump = true


func _stick(v: Vector2) -> Vector2:
	var length := v.length()
	if length <= DEADZONE:
		return Vector2.ZERO
	return v / length * ((minf(length,1.0)-DEADZONE) / (1.0-DEADZONE))


func _is_gamepad(device: int) -> bool:
	return Levers.classify_pad(Input.get_joy_name(device),Input.is_joy_known(device)) == "gamepad"


func _desktop_input(delta: float) -> Vector2:
	var arrows := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
			- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
			float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
			- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if arrows != Vector2.ZERO:
		using_gamepad = false
	var pads := Input.get_connected_joypads()
	if not pads.has(_joy):
		if _joy >= 0 and seated and _pad_axes:
			_controls.reset()
			_pad_axes = false
			using_gamepad = false
		_joy = -1
		for device in pads:
			if _is_gamepad(device):
				_joy = device
				break
	if scripted:
		return Vector2.ZERO
	if seated:
		_seated_desktop_input(delta)
		return Vector2.ZERO
	var move := Vector2.ZERO
	if _joy >= 0:
		move = _stick(Vector2(Input.get_joy_axis(_joy,JOY_AXIS_LEFT_X),Input.get_joy_axis(_joy,JOY_AXIS_LEFT_Y)))
		var look := _stick(Vector2(Input.get_joy_axis(_joy,JOY_AXIS_RIGHT_X),Input.get_joy_axis(_joy,JOY_AXIS_RIGHT_Y)))
		if move != Vector2.ZERO or look != Vector2.ZERO:
			using_gamepad = true
			_look(-look.x*2.4*delta,-look.y*1.7*delta)
	if arrows != Vector2.ZERO and Input.is_physical_key_pressed(KEY_SHIFT):
		sprinting = true
	return (arrows+move).limit_length()


func _seated_desktop_input(delta: float) -> void:
	var keys := Vector2(float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S)),
			float(Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_DOWN)))
	var brakes := Vector2(float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_RIGHT)))
	var idle := Input.is_physical_key_pressed(KEY_X)
	var sticks := Vector2.ZERO
	var triggers := Vector2.ZERO
	if _joy >= 0:
		sticks = Vector2(-Input.get_joy_axis(_joy, JOY_AXIS_LEFT_Y), -Input.get_joy_axis(_joy, JOY_AXIS_RIGHT_Y))
		triggers = Vector2(Input.get_joy_axis(_joy, JOY_AXIS_TRIGGER_LEFT), Input.get_joy_axis(_joy, JOY_AXIS_TRIGGER_RIGHT))
		for side in 2:
			sticks[side] = clampf(sticks[side], 0, 1) if sticks[side] > .08 else 0.0
			triggers[side] = clampf(triggers[side], 0, 1) if triggers[side] > .04 else 0.0
		var look := Vector2(float(Input.is_joy_button_pressed(_joy, JOY_BUTTON_DPAD_RIGHT))
				- float(Input.is_joy_button_pressed(_joy, JOY_BUTTON_DPAD_LEFT)),
				float(Input.is_joy_button_pressed(_joy, JOY_BUTTON_DPAD_DOWN))
				- float(Input.is_joy_button_pressed(_joy, JOY_BUTTON_DPAD_UP)))
		if sticks != Vector2.ZERO or triggers != Vector2.ZERO or look != Vector2.ZERO:
			using_gamepad = true
			_look(-look.x * 2.4 * delta, -look.y * 1.7 * delta)
		if sticks != Vector2.ZERO or triggers != Vector2.ZERO:
			_pad_axes = true
	if keys != Vector2.ZERO or brakes != Vector2.ZERO or idle:
		using_gamepad = false
		_pad_axes = false
	_controls.desktop(keys, brakes, idle, sticks, triggers, _pad_axes, delta)


func _xr_input(delta := 1.0 / 60.0) -> Vector2:
	var focus := _xr_has_focus()
	var left: XRController3D = hands.left
	var right: XRController3D = hands.right
	var have_left := focus and left.get_has_tracking_data()
	var have_right := focus and right.get_has_tracking_data()
	if _gloves.has("left"):
		_gloves.left.visible = have_left and not scripted
		_gloves.right.visible = have_right and not scripted
	var show_tracked := (have_left or have_right) and not scripted
	if show_tracked != _tracking_hands:
		_tracking_hands = show_tracked
		if _avatar:
			_avatar.set_tracked_hands(show_tracked)
	if not focus:
		if _xr_focused:
			_align_tracking = true
			velocity = Vector3.ZERO
			_controls.reset()
		_xr_focused = false
		_left_live = false
		_right_live = false
		return Vector2.ZERO
	var was_aligned := not _align_tracking
	if not scripted:
		_align_head()
	if seated and _align_tracking and was_aligned:
		_controls.reset()
	var down := Vector3i(int(have_right and right.is_button_pressed("ax_button")),
			int(have_left and left.is_button_pressed("by_button")),
			int(have_right and right.is_button_pressed("by_button")))
	var actions := down - _xr_down if _xr_focused else Vector3i.ZERO
	var switches := Vector2i(int(have_left and left.is_button_pressed("ax_button")),
			int(have_left and left.is_button_pressed("primary_click")))
	var pressed := switches - _xr_cockpit_down if not _align_tracking and _xr_focused and _left_live else Vector2i.ZERO
	_xr_cockpit_down = switches
	if not _left_live:
		actions.y = 0
	if not _right_live:
		actions.x = 0
		actions.z = 0
	_xr_down = down
	_left_live = have_left
	_right_live = have_right
	_xr_focused = true
	if seated and not _align_tracking and not scripted:
		var palms: Array[Node3D] = [left if have_left else null, right if have_right else null]
		var triggers := Vector2(left.get_float("trigger") if have_left else 0.0, right.get_float("trigger") if have_right else 0.0)
		var grips := Vector2(left.get_float("grip") if have_left else 0.0, right.get_float("grip") if have_right else 0.0)
		_controls.tracked(palms, triggers, grips, delta)
	var stick := left.get_vector2("primary") if have_left else Vector2.ZERO
	if actions.x > 0: interact_requested.emit()
	elif actions.y > 0: launch_requested.emit()
	elif actions.z > 0: back_requested.emit()
	elif pressed.x > 0:
		if seated: cockpit_control_requested.emit("power")
		else: bay_control_requested.emit("paint")
	elif pressed.y > 0:
		if seated: cockpit_control_requested.emit("park")
		else: _stick_click(stick)
	return _stick(Vector2(stick.x,-stick.y))


func _process(delta: float) -> void:
	if not xr_live or not _xr_focused or _align_tracking or seated or scripted:
		return
	var right: XRController3D = hands.right
	if right.get_has_tracking_data():
		_turn_xr(right.get_vector2("primary").x, delta)


func _turn_xr(axis: float, delta: float) -> void:
	if seated or absf(axis) <= DEADZONE:
		return
	var travel := clampf((absf(axis) - DEADZONE) / (1.0 - DEADZONE), 0.0, 1.0)
	# Render-rate yaw keeps slow turns smooth in the headset. Discard elapsed
	# loading time so a held stick cannot spin the pilot across a scene hitch.
	var angle := -signf(axis) * travel * TURN_SPEED * minf(delta, 0.05)
	var eye_offset := eye_transform().origin - global_position
	rotate_y(angle)
	# A pilot leaning out from the capsule turns in place around their head.
	_origin.global_position += eye_offset - eye_offset.rotated(Vector3.UP, angle)


func _physics_process(delta: float) -> void:
	var intent := Vector2.ZERO
	if xr_live:
		intent = _xr_input(delta)
	elif _focused:
		intent = _desktop_input(delta)
	if is_inside_tree():
		step_locomotion(intent,delta)


## Walking input is +X right, -Y forward. Only actual distance after wall
## contact drives the pilot's stride.
func step_locomotion(intent: Vector2, delta: float) -> void:
	if seated or scripted:
		velocity = Vector3.ZERO
		_jump = false
		return
	if intent == Vector2.ZERO:
		sprinting = false
	var start := global_position
	var stride_start := start
	var stride_limit := minf(.22, 5.0 * delta)
	if xr_live and _xr_focused and not _align_tracking:
		var room_step := eye_transform().origin-global_position
		room_step.y = 0
		if room_step.length_squared() > .000001:
			move_and_collide(room_step)
			_origin.global_position -= room_step
			stride_start = global_position - _tracked_stride(global_position - start, stride_limit)
	var forward := -eye_transform().basis.z
	forward.y = 0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	var direction := (right*intent.x - forward*intent.y).limit_length()
	var horizontal := Vector2(velocity.x,velocity.z).move_toward(Vector2(direction.x,direction.z)*(SPRINT_SPEED if sprinting else WALK_SPEED),11.0*delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	if _jump and is_on_floor():
		velocity.y = JUMP_SPEED
	elif is_on_floor():
		velocity.y = minf(velocity.y,0.0) - 9.8*delta
	else:
		velocity.y -= 9.8*delta
	_jump = false
	move_and_slide()
	var travel := global_position-start
	travel.y = 0
	var stride_motion := global_position - stride_start
	stride_motion.y = 0
	var distance := minf(travel.length(), stride_motion.length())
	var previous_step := floori(_distance / (Pilot.STRIDE * .5))
	# Tiny tracked-head jitter and tracking reacquisition are not strides.
	var walking := distance > .06 * delta and distance <= stride_limit
	if walking:
		_distance += distance
	if _avatar:
		if third_person and travel.length_squared() > .00001:
			var facing := atan2(-travel.x,-travel.z)-global_rotation.y
			_avatar.rotation.y = lerp_angle(_avatar.rotation.y,facing,minf(1.0,delta*12.0))
		_avatar.set_stride(_distance, walking)
		var step := floori(_distance / (Pilot.STRIDE * .5))
		# Room-scale tracking can jump on reacquisition. Only real grounded
		# walking across the next alternating plant produces a shoe contact.
		if step == previous_step + 1 and is_on_floor():
			var side := step % 2
			boot_planted.emit(side, _avatar.planted_sole(side), distance / delta)


func _tracked_stride(travel: Vector3, limit: float) -> Vector3:
	travel.y = 0
	if travel.length() > limit:
		_head_sway = Vector3.ZERO
		return Vector3.ZERO
	# Keep small, reversing tracking motions inside a 3 cm radius. A pilot
	# translating steadily carries that radius along, even at walking speed.
	# Only gait uses this tolerance. Camera and capsule follow the full pose.
	var offset := _head_sway + travel
	_head_sway = offset.limit_length(.03)
	return offset - _head_sway
