## Tracked garage rig using synthetic floor/seated head and grip poses. XR remains off.
## Run headless: --headless --xr-mode off -s res://tests/test_garage_xr_tracking.gd
extends SceneTree

const Pilot := preload("res://garage/pilot_model.gd")
const CONFIDENT := XRPose.XR_TRACKING_CONFIDENCE_HIGH

# An offline tracking driver. Like OpenXR, the camera center includes XRServer's
# reference frame and world scale. Controller nodes apply that same adjustment.
class Tracking extends XRInterfaceExtension:
	signal pose_recentered
	var head: XRPositionalTracker
	var area := XRInterface.XR_PLAY_AREA_STAGE
	var mode_changes := 0
	var hold_center := false
	var camera_sample := Transform3D.IDENTITY

	func _get_name() -> StringName: return &"GarageTest"
	func _get_capabilities() -> int: return XRInterface.XR_STEREO
	func _is_initialized() -> bool: return true
	func _get_camera_transform() -> Transform3D:
		if hold_center:
			var sample := camera_sample
			sample.origin *= XRServer.world_scale
			return XRServer.get_reference_frame() * sample
		return head.get_pose(&"default").get_adjusted_transform()
	func _get_play_area_mode() -> XRInterface.PlayAreaMode: return area
	func _supports_play_area_mode(_mode: XRInterface.PlayAreaMode) -> bool: return true
	func _set_play_area_mode(mode: XRInterface.PlayAreaMode) -> bool:
		mode_changes += 1
		area = mode
		return true
	func _process() -> void: pass


class Walker extends "res://garage/garage_walker.gd":
	var driver: Tracking
	var focused := true

	func _garage_interface() -> XRInterface: return driver
	func _xr_has_focus() -> bool: return focused


var driver := Tracking.new()
var pads := {}
var walker: Walker
var suit: Pilot
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func _poses(head: Transform3D, grip_pitch := PI / 2.0) -> void:
	driver.head.set_pose(&"default", head, Vector3.ZERO, Vector3.ZERO, CONFIDENT)
	for side: String in pads:
		var sign_side := -1.0 if side == "left" else 1.0
		var pose := head * Transform3D(Basis(Vector3.RIGHT, grip_pitch), Vector3(sign_side * .27, -.38, -.42))
		pads[side].set_pose(&"grip", pose, Vector3.ZERO, Vector3.ZERO, CONFIDENT)


func _tick_input() -> void:
	await process_frame
	await process_frame
	walker._xr_input()


func _eye() -> Vector3:
	# The origin of a ray through the image center comes from the live camera.
	# A camera used for XR projection is updated by XROrigin3D's internal process.
	return walker.camera.project_ray_origin(root.get_visible_rect().size * .5)


func _visor() -> Vector3:
	var head := suit.find_child("Head", true, false) as Node3D
	return head.to_global(Pilot.HELMET_EYE)


func _gloves() -> void:
	for side: String in pads:
		var hand: XRController3D = walker.hands[side]
		var mount := hand.get_child(0) as Node3D
		var mesh_node := mount.get_child(0) as MeshInstance3D
		var vertices: PackedVector3Array = mesh_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var wrist := Vector3.ZERO
		var tips := Vector3.ZERO
		var index := Vector3.ZERO
		var little := Vector3.ZERO
		var counts := Vector4i.ZERO
		for v in vertices:
			if v.y > .008:
				wrist += v
				counts.x += 1
			elif v.y < -.119:
				tips += v
				counts.y += 1
				if v.z < -.030:
					index += v
					counts.z += 1
				elif v.z > .010:
					little += v
					counts.w += 1
		if counts.x * counts.y * counts.z * counts.w == 0:
			check(false, side + " glove is missing cuff or fingertip geometry")
			continue
		var finger_axis := mesh_node.global_basis * (tips / counts.y - wrist / counts.x).normalized()
		var index_side := mesh_node.global_basis * (index / counts.z - little / counts.w).normalized()
		check(hand.get_has_tracking_data() and mount.is_visible_in_tree(), side + " tracked glove is shown")
		check(finger_axis.normalized().dot(-hand.global_basis.y) > .98, side + " fingertips follow the grip's finger axis")
		check(index_side.normalized().dot(-hand.global_basis.z) > .93, side + " index finger lies on the thumb side")
		check(mesh_node.to_global(Vector3(0,-.081,-.006)).distance_to(hand.global_position) < .002,
			side + " glove palm sits on the tracked grip")
		var head_to_grip: Vector3 = walker.camera.global_basis * Vector3((-.27 if side == "left" else .27), -.38, -.42)
		check((_eye() + head_to_grip).distance_to(hand.global_position) < .005,
			side + " tracked hand and projected eye share the same reference frame")


func _vertical_motion(posture: String) -> void:
	var original := driver.head.get_pose(&"default").transform
	var before := _eye()
	var lower := original
	lower.origin.y -= .23
	# The camera prediction may catch up one frame after the raw tracker.
	driver.camera_sample = original
	driver.hold_center = true
	_poses(lower)
	await _tick_input()
	var expected := before - Vector3.UP * .23
	check(_eye().distance_to(expected) < .008, posture + " physical crouch reaches the projected eye")
	driver.hold_center = false
	await _tick_input()
	check(_eye().distance_to(expected) < .008, posture + " late camera sample does not apply head movement twice")
	_poses(original)
	await _tick_input()
	check(_eye().distance_to(before) < .008, posture + " physically raising the head restores the original eye")


func _focus() -> void:
	var before := walker.rotation.y
	pads.right.set_input(&"primary", Vector2.RIGHT)
	walker.focused = false
	await _tick_input()
	walker._process(.03)
	check(is_equal_approx(before,walker.rotation.y) and not walker.hands.right.get_child(0).is_visible_in_tree(),
		"Focus loss stops turning and removes the inactive tracked glove")
	pads.right.set_input(&"primary", Vector2.ZERO)
	walker.focused = true
	await _tick_input()
	walker._process(.03)
	check(is_equal_approx(before,walker.rotation.y) and walker.hands.right.get_child(0).is_visible_in_tree()
		and _eye().distance_to(_visor()) < .012, "Focus returns with head aligned and hand tracking restored")


func _turns() -> void:
	# Simulate actual render polling at a few refresh rates. Each one starts with
	# a physically offset head, before a locomotion step puts the feet underneath.
	var yaw := []
	for hz in [45, 72, 120]:
		walker.set_seated(false, Transform3D(Basis.IDENTITY, Vector3(3,0,-2)))
		await _tick_input()
		var h := driver.head.get_pose(&"default").transform
		h.origin.x += .27
		_poses(h)
		await _tick_input()
		var initial_eye := _eye()
		var initial_up := walker.camera.global_basis.y
		pads.right.set_input(&"primary", Vector2(1,.85))
		var previous := walker.rotation.y
		var largest := 0.0
		var smallest := PI
		for frame in hz:
			walker._process(1.0 / hz)
			var step := absf(angle_difference(previous,walker.rotation.y))
			largest = maxf(step, largest)
			smallest = minf(step, smallest)
			previous = walker.rotation.y
		yaw.append(walker.rotation.y)
		check(smallest > .001 and largest < .045 and absf(angle_difference(walker.rotation.y,-PI/2.0)) < .004,
			"At %d Hz full right stick turns continuously through 90 degrees in one second" % hz)
		check(_eye().distance_to(initial_eye) < .008 and walker.camera.global_basis.y.dot(initial_up) > .999,
			"At %d Hz yaw pivots about the physical eye without introducing pitch" % hz)
		pads.right.set_input(&"primary", Vector2(.06, 1))
		walker._process(1.0 / hz)
		check(is_equal_approx(walker.rotation.y,previous), "A centered stick stops yaw despite vertical input")
		pads.right.set_input(&"primary", Vector2(-.595,0))
		for frame in hz:
			walker._process(1.0 / hz)
		check(absf(angle_difference(walker.rotation.y, -PI / 4.0)) < .004,
			"At %d Hz a half-strength reversal immediately turns back at half speed" % hz)
		var after_reverse := walker.rotation.y
		pads.right.set_input(&"primary", Vector2.ZERO)
		walker._process(1.0 / hz)
		check(is_equal_approx(walker.rotation.y, after_reverse), "Releasing the turn leaves the pilot at that heading")
	check(absf(angle_difference(yaw[0],yaw[2])) < .001, "Turn amount is independent of render frequency")


func _run() -> void:
	if DisplayServer.get_name() != "headless" or XRServer.primary_interface != null:
		push_error("Run in an isolated headless process with XR off")
		quit(1)
		return
	driver.head = XRPositionalTracker.new()
	driver.head.name = &"head"
	driver.head.type = XRServer.TRACKER_HEAD
	XRServer.add_tracker(driver.head)
	for side in ["left", "right"]:
		var pad := XRControllerTracker.new()
		pad.name = StringName(side + "_hand")
		pad.type = XRServer.TRACKER_CONTROLLER
		XRServer.add_tracker(pad)
		pads[side] = pad
	XRServer.add_interface(driver)
	XRServer.primary_interface = driver
	# Simulate an existing cockpit recenter before entering a standing room.
	_poses(Transform3D(Basis(Vector3.UP,.28),Vector3(.25,1.24,-.17)))
	XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, false)
	var inherited := XRServer.get_reference_frame()
	check(absf(inherited.origin.y) > 1.0, "Fixture carries an actual seated XRServer recenter into the garage")
	# A sitting runtime supplies its last local pose until the frame after a
	# requested switch to stage. In stage the same head has a physical floor
	# offset. A premature calibration would add that offset to the avatar twice.
	driver.area = XRInterface.XR_PLAY_AREA_SITTING
	var local_head := Transform3D(Basis(Vector3.UP,.37), Vector3(.41,.08,-.17))
	_poses(local_head)
	walker = Walker.new()
	walker.allow_xr = true
	walker.driver = driver
	root.add_child(walker)
	walker.set_physics_process(false)
	walker.set_process(false)
	if walker.xr_live:
		suit = Pilot.new()
		walker.set_pilot(suit)
		await _tick_input()
		var start := Transform3D(Basis(Vector3.UP,.36), Vector3(5,0,-3))
		walker.set_seated(false, start)
		if driver.area == XRInterface.XR_PLAY_AREA_STAGE:
			local_head.origin.y += 1.22
			_poses(local_head)
		await _tick_input()
		var height_error := _eye().y - _visor().y
		print("Garage head-to-visor height after local-space entry: %.3f m" % height_error)
		check(absf(height_error) < .012, "A delayed floor pose cannot lift the camera four feet above the walking suit")
		driver.area = XRInterface.XR_PLAY_AREA_STAGE
		_poses(Transform3D(Basis(Vector3.UP,.37), Vector3(.41,1.78,-.17)))
		driver.pose_recentered.emit()
		await _tick_input()
		walker.set_seated(false, start)
		await _tick_input()
		check(walker.camera is XRCamera3D and absf(_eye().y-1.78) < .006 and _eye().distance_to(_visor()) < .012,
			"Stage tracking puts the projected standing eye at the model's visor, at the wearer's height")
		check(XRServer.get_reference_frame().is_equal_approx(inherited), "Entering the garage preserves the shared XRServer reference")
		_gloves()
		await _vertical_motion("Standing")
		await _focus()
		await _turns()
		var seat := Transform3D(Basis(Vector3.UP, -.51), Vector3(-4,1.42,6))
		walker.set_seated(true,seat)
		await _tick_input()
		check(_eye().distance_to(seat.origin) < .007 and _eye().distance_to(_visor()) < .012,
			"Boarding puts the projected eye at the cockpit and seated visor")
		await _vertical_motion("Seated")
		pads.right.set_input(&"primary", Vector2.RIGHT)
		var at := walker.transform
		walker._process(.02)
		check(at.is_equal_approx(walker.transform), "Right stick cannot spin the seated pilot or the cockpit")
		pads.right.set_input(&"primary", Vector2.ZERO)
		driver.area = XRInterface.XR_PLAY_AREA_SITTING
		XRServer.clear_reference_frame()
		_poses(Transform3D(Basis(Vector3.UP, .23), Vector3(.12,.08,-.28)), .63)
		driver.pose_recentered.emit()
		await _tick_input()
		check(_eye().distance_to(seat.origin) < .007, "A change to seated reference space recenters at the same cockpit eye")
		_gloves()
		walker.set_seated(false,start)
		await _tick_input()
		check(_eye().distance_to(_visor()) < .012 and absf(_eye().y-Pilot.STANDING_EYE.y) < .006,
			"Dismount in local reference space restores one standing eye height")
		check(driver.mode_changes == 0, "The garage leaves the runtime's incoming reference space in place")
	else:
		check(false, "Garage constructed its production XR cameras and controller rig")
	walker.free()
	XRServer.clear_reference_frame()
	XRServer.primary_interface = null
	XRServer.remove_interface(driver)
	for pad in pads.values(): XRServer.remove_tracker(pad)
	XRServer.remove_tracker(driver.head)
	print("GARAGE XR TRACKING %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))
