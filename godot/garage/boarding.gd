## One climb into or out of a parked craft, played live (garage.gd starts it from the board button): the pilot's key
## poses (garage/boarding_moves.gd) through a pose track (garage/pose_track.gd) on the rig (pilot_model.gd pose_free),
## the cab's canopy through its mechanism (garage/canopy_rig.gd), and the view:
##   headset   the view rides the pilot's head: the play space is moved by how far the helmet's eye moves, nothing is
##             turned, so the player's own head turns are his; what is left between where his eye is and where the
##             seat's (or the gate's) is gets spread over the climb, so the alignment at the end has little to do
##   desktop   a camera at the helmet's eye, eased in from the walker's view and out onto the seat's (or the
##             standing pilot's); with the pilot view (V) on when it starts, a camera outside watches instead
## The walker stays where it stood and is held (walker.begin_scripted); the pilot is moved and posed on his own.
## Signals: `arrived` when the pilot is seated (boarding) or on his feet outside (exit): garage.gd hands control back
## then; `finished` when the canopy is shut again after him.
extends Node

signal arrived
signal finished

const Moves := preload("res://garage/boarding_moves.gd")
const Track := preload("res://garage/pose_track.gd")
const CanopyRig := preload("res://garage/canopy_rig.gd")
const Suit := preload("res://garage/pilot_model.gd")
const Seat := preload("res://garage/garage_seat.gd")
const EASE_IN := 0.32       # seconds the desktop camera takes to leave the walker's view
const EASE_OUT := 0.38      # ... and to settle on the view the walker takes over with

var craft := ""
var boarding := true
var side := 1.0             # the gate's side of the bay: +1 its +X
var bay: Node3D
var walker
var pilot: Suit
var rig: CanopyRig
var track: Track
var t := 0.0
var pilot_done := false
var end_transform: Transform3D      # the walker's pose when the pilot arrives: the seat's eye, or his feet at the gate
var _canopy_from := 0.0
var _close_at := 0.0
var _camera: Camera3D
var _cinematic := false
var _from_view: Transform3D
var _xr := false
var _xr_eye := Vector3.ZERO         # where the climb last put the headset's eye (world)
var _xr_anchor := Vector3.ZERO      # the player's eye from the pilot's helmet eye when the climb began
var _xr_correction := Vector3.ZERO  # what is left to spread over the climb
var _done := false


## `cab`: the occupied cab (garage_cockpit.gd) standing in `bay_node`; `gate`: the bay's gate (world); `seat_eye`: the
## seat's eye (world); `grips`: the cab's throttle grips' points (world) for the seated hands; `rig_in`: the cab roof's
## mechanism, as far open as it already is.
func setup(id: String, climbing_in: bool, bay_node: Node3D, the_walker, the_pilot: Suit, rig_in: CanopyRig, gate: Transform3D,
		seat_eye: Transform3D, grips: Array) -> void:
	craft = id
	boarding = climbing_in
	bay = bay_node
	walker = the_walker
	pilot = the_pilot
	rig = rig_in
	_xr = walker.xr_live
	var gate_local := bay.global_transform.affine_inverse() * gate.origin
	side = 1.0 if gate_local.x >= 0.0 else -1.0
	_canopy_from = rig.amount
	var open_s := CanopyRig.open_seconds(craft) * (1.0 - _canopy_from)
	var seated_root := Transform3D(Basis(Vector3.UP, atan2(seat_eye.basis.z.x, seat_eye.basis.z.z)), Vector3.ZERO)
	seated_root.origin = seat_eye.origin - seated_root.basis * Suit.SEATED_EYE
	var seated := _canonical(_shot(seated_root, true, grips))
	var gate_canon := _mirror_point(gate_local)
	var moves := Moves.new(craft, gate_canon, seated, open_s * (0.72 if boarding else 1.0))
	var keys: Array[Dictionary]
	if boarding:
		pilot.scale = Vector3.ONE
		var start := _canonical(_live_shot())
		keys = moves.board(start)
		end_transform = seat_eye
	else:
		var out_heading := atan2(-gate.basis.z.x, -gate.basis.z.z)      # (facing away from the craft)
		var stand := Transform3D(Basis(Vector3.UP, out_heading), gate.origin)
		keys = moves.leave(_canonical(_shot(stand, false, [])))
		end_transform = stand
	track = Track.new(keys)
	_close_at = track.duration - 0.30 if boarding else track.duration
	walker.begin_scripted()
	_from_view = walker.eye_transform()
	if not _xr:
		_cinematic = boarding and walker.third_person
		_camera = Camera3D.new()
		_camera.name = "ClimbCamera"
		_camera.near = 0.045
		_camera.fov = walker.camera.fov
		add_child(_camera)
		_camera.global_transform = _from_view
		_camera.make_current()
	if _xr:
		# the climb's eye at its end and its start, against where the view is now and where the walker will align it
		_apply(track.duration, false)
		var last_eye := pilot.global_transform * pilot.eye_point()
		_apply(0.0, false)
		var first_eye := pilot.global_transform * pilot.eye_point()
		var now := walker.eye_transform().origin as Vector3
		_xr_anchor = now - first_eye
		var final_eye: Vector3 = end_transform.origin if boarding else end_transform * Suit.STANDING_EYE
		_xr_correction = final_eye - (last_eye + _xr_anchor)
		_xr_eye = now
	_apply(0.0)


func _process(delta: float) -> void:
	advance(delta)


## Run the climb on by `delta` seconds (tests step it by hand).
func advance(delta: float) -> void:
	if _done:
		return
	t += delta
	if not pilot_done:
		_apply(minf(t, track.duration))
		if t >= track.duration:
			_arrive()
	_canopy(t)
	if pilot_done and _canopy_settled(t):
		_done = true
		finished.emit()


## Straight to the end: the pilot where he was going, the canopy shut.
func finish_now() -> void:
	if _done:
		return
	if not pilot_done:
		t = track.duration
		_apply(t)
		_arrive()
	t = maxf(t, _close_at + CanopyRig.close_seconds(craft) + 0.01)
	_canopy(t)
	_done = true
	finished.emit()


## Leave the canopy where it is and stop (another climb takes it over).
func release() -> void:
	_done = true
	if not pilot_done:
		pilot_done = true
		_hand_back()


func _arrive() -> void:
	pilot_done = true
	arrived.emit()      # (garage.gd seats him or stands him at the gate first ...)
	_hand_back()        # (... then the walker's own view takes over)


func _hand_back() -> void:
	if _camera:
		_camera.queue_free()
		_camera = null
	walker.end_scripted()


func _canopy(at: float) -> void:
	var open_s := CanopyRig.open_seconds(craft) * (1.0 - _canopy_from)
	var opened := 1.0 if open_s <= 0.0 else lerpf(_canopy_from, 1.0, clampf(at / open_s, 0.0, 1.0))
	var shut := clampf((at - _close_at) / CanopyRig.close_seconds(craft), 0.0, 1.0)
	rig.apply(opened * (1.0 - shut) if at >= _close_at else opened)


func _canopy_settled(at: float) -> bool:
	return at >= _close_at + CanopyRig.close_seconds(craft)


func _apply(at: float, view := true) -> void:
	var pose := track.sample(at)
	var placed := _place(pose)
	pilot.global_transform = placed[0]
	pilot.pose_free(placed[1])
	if not view:
		return
	if _xr:
		var eye: Vector3 = pilot.global_transform * pilot.eye_point()
		var share := smoothstep(0.0, track.duration, at)
		var target := eye + _xr_anchor + _xr_correction * share
		walker.nudge_view(target - _xr_eye)
		_xr_eye = target
	elif _camera:
		_view(at, placed[0])


## The sampled pose as [the pilot's transform (world), pose_free's dictionary].
func _place(canon: Dictionary) -> Array:
	var p := _mirror_pose(canon)
	var heading := Basis(Vector3.UP, p.yaw)
	var root: Vector3 = p.pelvis - heading * p.hip
	var frame := bay.global_transform * Transform3D(heading, root)
	var to_local := Transform3D(heading, root).affine_inverse()
	var torso := Basis(p.torso_q) * Basis.from_scale(Vector3(1.0, p.stretch, 1.0))
	return [frame, {"pelvis": p.hip, "pelvis_basis": Basis(p.pelvis_q), "torso_at": p.torso_at, "torso_basis": torso,
			"head_basis": Basis(p.head_q), "ankles": [to_local * p.ankle_l, to_local * p.ankle_r],
			"feet": [heading.inverse() * Basis(p.foot_l), heading.inverse() * Basis(p.foot_r)],      # (the boots' turns are held in the bay's frame)
			"knees": [p.knee_l, p.knee_r], "grips": [to_local * p.grip_l, to_local * p.grip_r], "elbows": [p.elbow_l, p.elbow_r]}]


func _view(at: float, frame: Transform3D) -> void:
	var head := pilot.head_node().global_transform
	var eye := Transform3D(head.basis.orthonormalized(), head * Suit.HELMET_EYE)
	var view := eye
	if _cinematic:
		var watch := bay.global_transform * _mirror_point(Vector3(2.9, 1.05, 3.1))
		var look := bay.global_transform * _mirror_point(Vector3(0.45, 0.55, 0.62))
		view = Transform3D(Basis.looking_at(look - watch, Vector3.UP), watch)
		view = view.interpolate_with(eye, smoothstep(track.duration - 0.9, track.duration, at))
	var start := smoothstep(0.0, EASE_IN, at)
	view = _from_view.interpolate_with(view, start)
	var level := end_transform if boarding else Transform3D(end_transform.basis, end_transform * Suit.STANDING_EYE)
	view = view.interpolate_with(level, smoothstep(track.duration - EASE_OUT, track.duration, at))
	_camera.global_transform = view


# --- canonical (boarded from +X) against the bay's own side ------------------------------------------------------

func _mirror_point(p: Vector3) -> Vector3:
	return Vector3(p.x * side, p.y, p.z)


func _mirror_pose(pose: Dictionary) -> Dictionary:
	if side > 0.0:
		return pose
	var out := {}
	for name: String in pose:
		var value = pose[name]
		var other := name
		if name.ends_with("_l"):
			other = name.trim_suffix("_l") + "_r"
		elif name.ends_with("_r"):
			other = name.trim_suffix("_r") + "_l"
		if name == "yaw":
			value = -float(value)
		elif value is Vector3:
			value = Vector3(-value.x, value.y, value.z)
		elif value is Quaternion:
			value = Quaternion(value.x, -value.y, -value.z, value.w)
		out[other] = value
	return out


## A snapshot (pilot_model.gd snapshot(), the pilot standing at `frame` in the world) as canonical channels.
func _canonical(shot: Dictionary) -> Dictionary:
	var to_bay: Transform3D = bay.global_transform.affine_inverse() * shot.frame
	var forward := to_bay.basis * Vector3.FORWARD
	var channels := {"pelvis": to_bay * shot.pelvis, "hip": shot.pelvis, "yaw": atan2(-forward.x, -forward.z),
			"pelvis_q": Quaternion(shot.pelvis_basis.orthonormalized()), "torso_q": Quaternion(shot.torso_basis.orthonormalized()),
			"stretch": shot.torso_basis.y.length(), "torso_at": shot.torso_at, "head_q": Quaternion(shot.head_basis)}
	for i in 2:
		var s := "_l" if i == 0 else "_r"
		channels["ankle" + s] = to_bay * shot.ankles[i]
		channels["foot" + s] = Quaternion(Vector3.UP, channels.yaw) * Quaternion(shot.feet[i])      # (in the bay's frame: a planted boot holds still while he turns)
		channels["knee" + s] = shot.knees[i]
		channels["grip" + s] = to_bay * shot.grips[i]
		channels["elbow" + s] = shot.elbows[i]
	return _mirror_pose(channels)      # (mirroring is its own inverse: the bay's side into canonical)


## The rig's own pose at `frame`, seated or standing, from a pilot made for the purpose and thrown away.
func _shot(frame: Transform3D, seated: bool, grips: Array) -> Dictionary:
	var scratch := Suit.new()
	scratch.visible = false
	bay.add_child(scratch)
	scratch.global_transform = frame
	scratch.set_seat_vehicle(craft)
	scratch.set_seated(seated)
	if seated and grips.size() == 2:
		scratch.set_grip_targets(grips[0], grips[1])
	var shot := scratch.snapshot()
	shot.frame = frame
	scratch.free()
	return shot


## The pilot as he stands now, scale and offset dropped (the headset's sizes him to the player's height on foot).
func _live_shot() -> Dictionary:
	pilot.release_free()
	pilot.scale = Vector3.ONE
	var frame := Transform3D(pilot.global_transform.basis.orthonormalized(), pilot.global_transform.origin)
	var shot := pilot.snapshot()
	shot.frame = frame
	return shot
