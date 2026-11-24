## A metre-scale standing rig. The capsule origin is the floor, and a seat pose is
## supplied at the actual cockpit eye rather than at the foot of the avatar.
extends CharacterBody3D

signal interact_requested
signal launch_requested
signal back_requested

const Pilot := preload("res://garage/pilot_model.gd")
const Levers := preload("res://input/lever_input.gd")
const STANDING_EYE_HEIGHT := Pilot.STANDING_EYE.y
const WALK_SPEED := 2.35
const SNAP_ANGLE := PI / 6.0
const DEADZONE := .19
const LOOK_LIMIT := deg_to_rad(82.0)

var allow_xr := false
var xr_live := false
var seated := false
var third_person := false
var using_gamepad := false
var camera: Camera3D
var hands := {}

var _shape: CollisionShape3D
var _avatar: Pilot
var _distance := 0.0
var _origin: Node3D
var _eye: Camera3D
var _boom: SpringArm3D
var _outside: Camera3D
var _gloves := {}
var _tracking_hands := false
var _xr: OpenXRInterface
var _original_area := XRInterface.XR_PLAY_AREA_UNKNOWN
var _changed_area := false
var _xr_focused := false
var _align_tracking := true
var _xr_down := Vector3i.ZERO
var _left_live := false
var _right_live := false
var _snap_ready := false
var _snap := 0.0
var _joy := -1
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

	_xr = XRServer.find_interface("OpenXR") as OpenXRInterface
	xr_live = allow_xr and _xr != null and _xr.is_initialized()
	_previous_mouse = Input.mouse_mode
	_previous_xr = get_viewport().use_xr
	get_viewport().use_xr = xr_live
	if xr_live:
		get_viewport().msaa_3d = Viewport.MSAA_4X
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_original_area = _xr.get_play_area_mode()
		if _original_area not in [XRInterface.XR_PLAY_AREA_STAGE,XRInterface.XR_PLAY_AREA_ROOMSCALE]:
			for area in [XRInterface.XR_PLAY_AREA_STAGE,XRInterface.XR_PLAY_AREA_ROOMSCALE]:
				if _xr.supports_play_area_mode(area) and _xr.set_play_area_mode(area):
					_changed_area = true
					break
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
		_xr.pose_recentered.connect(_on_recenter)
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
	if _changed_area and _xr and _xr.is_initialized() and _xr.supports_play_area_mode(_original_area):
		_xr.set_play_area_mode(_original_area)


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
		_align_head()
	else:
		_origin.rotation = Vector3.ZERO
		_origin.position = Pilot.SEATED_EYE if seated else Pilot.STANDING_EYE
		_eye.rotation = Vector3.ZERO


func eye_transform() -> Transform3D:
	return camera.global_transform


func _on_recenter() -> void:
	_align_tracking = true


func _align_head() -> void:
	var tracker := XRServer.get_tracker(&"head") as XRPositionalTracker
	if tracker == null:
		return
	var head := tracker.get_pose(&"default")
	if head == null or not head.has_tracking_data:
		return
	# The cockpit can leave a seated calibration on XRServer. Place the rig from
	# the raw floor-space pose without changing the session's shared calibration.
	var height := STANDING_EYE_HEIGHT
	var mode := _xr.get_play_area_mode()
	if mode in [XRInterface.XR_PLAY_AREA_ROOMSCALE,XRInterface.XR_PLAY_AREA_STAGE] and head.transform.origin.y > .20:
		height = head.transform.origin.y * XRServer.world_scale
	if not seated and _avatar:
		_avatar.scale = Vector3.ONE * clampf(height/STANDING_EYE_HEIGHT,.65,1.22)
		_avatar.position.z = -Pilot.STANDING_EYE.z * _avatar.scale.z
	var target := Pilot.SEATED_EYE if seated else Vector3(0,height,0)
	var adjusted := head.get_adjusted_transform()
	_origin.rotation.y = -atan2(adjusted.basis.z.x,adjusted.basis.z.z)
	_origin.position = target - _origin.basis * adjusted.origin
	_align_tracking = false


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
		KEY_V: _inspect(not third_person)
		_: return
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		velocity = Vector3.ZERO
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true


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
		_joy = -1
		for device in pads:
			if _is_gamepad(device):
				_joy = device
				break
	var move := Vector2.ZERO
	if _joy >= 0:
		move = _stick(Vector2(Input.get_joy_axis(_joy,JOY_AXIS_LEFT_X),Input.get_joy_axis(_joy,JOY_AXIS_LEFT_Y)))
		var look := _stick(Vector2(Input.get_joy_axis(_joy,JOY_AXIS_RIGHT_X),Input.get_joy_axis(_joy,JOY_AXIS_RIGHT_Y)))
		if move != Vector2.ZERO or look != Vector2.ZERO:
			using_gamepad = true
			_look(-look.x*2.4*delta,-look.y*1.7*delta)
	return (arrows+move).limit_length()


func _xr_input() -> Vector2:
	var focus := _xr.get_session_state() == OpenXRInterface.SESSION_STATE_FOCUSED
	var left: XRController3D = hands.left
	var right: XRController3D = hands.right
	var have_left := focus and left.get_has_tracking_data()
	var have_right := focus and right.get_has_tracking_data()
	if _gloves.has("left"):
		_gloves.left.visible = have_left
		_gloves.right.visible = have_right
	var show_tracked := have_left or have_right
	if show_tracked != _tracking_hands:
		_tracking_hands = show_tracked
		if _avatar:
			_avatar.set_tracked_hands(show_tracked)
	if not focus:
		if _xr_focused:
			_align_tracking = true
			velocity = Vector3.ZERO
		_xr_focused = false
		_left_live = false
		_right_live = false
		_snap_ready = false
		return Vector2.ZERO
	if _align_tracking:
		_align_head()
	var down := Vector3i(int(have_right and right.is_button_pressed("ax_button")),
			int(have_left and left.is_button_pressed("by_button")),
			int(have_right and right.is_button_pressed("by_button")))
	var actions := down - _xr_down if _xr_focused else Vector3i.ZERO
	if not _left_live:
		actions.y = 0
	if not _right_live:
		actions.x = 0
		actions.z = 0
	_xr_down = down
	_left_live = have_left
	_right_live = have_right
	_xr_focused = true
	if actions.x > 0: interact_requested.emit()
	elif actions.y > 0: launch_requested.emit()
	elif actions.z > 0: back_requested.emit()
	var turn := right.get_vector2("primary").x if have_right else 0.0
	if not have_right:
		_snap_ready = false
	elif absf(turn) < .35:
		_snap_ready = true
	elif _snap_ready and absf(turn) > .72 and not seated:
		_snap = -signf(turn)*SNAP_ANGLE
		_snap_ready = false
	var stick := left.get_vector2("primary") if have_left else Vector2.ZERO
	return _stick(Vector2(stick.x,-stick.y))


func _physics_process(delta: float) -> void:
	var intent := Vector2.ZERO
	if xr_live:
		intent = _xr_input()
	elif _focused:
		intent = _desktop_input(delta)
	if is_inside_tree():
		step_locomotion(intent,delta)


## Walking input is +X right, -Y forward. Only actual distance after wall
## contact drives the pilot's stride.
func step_locomotion(intent: Vector2, delta: float) -> void:
	if seated:
		velocity = Vector3.ZERO
		return
	var start := global_position
	if xr_live and _xr_focused and not _align_tracking:
		var room_step := _eye.global_position-global_position
		room_step.y = 0
		if room_step.length_squared() > .000001:
			move_and_collide(room_step)
			_origin.global_position -= room_step
		if _snap != 0.0:
			# The capsule is now directly below the headset. Its pivot preserves
			# the physical head position on a comfort turn, even against a wall.
			rotate_y(_snap)
			_snap = 0.0
	var forward := -camera.global_basis.z
	forward.y = 0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	var direction := (right*intent.x - forward*intent.y).limit_length()
	var horizontal := Vector2(velocity.x,velocity.z).move_toward(Vector2(direction.x,direction.z)*WALK_SPEED,11.0*delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	velocity.y = minf(velocity.y,0.0) - 9.8*delta
	move_and_slide()
	var travel := global_position-start
	travel.y = 0
	_distance += travel.length()
	if _avatar:
		if third_person and travel.length_squared() > .00001:
			var facing := atan2(-travel.x,-travel.z)-global_rotation.y
			_avatar.rotation.y = lerp_angle(_avatar.rotation.y,facing,minf(1.0,delta*12.0))
		_avatar.set_stride(_distance,travel.length_squared() > .000001)
