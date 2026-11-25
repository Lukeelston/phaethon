## Phaethon pressure suit. Local -Z faces forward; the standing boot soles define Y=0.
extends Node3D

const SUIT := preload("res://garage/pilot_suit.glb")
const HIP_HEIGHT := .941
const SEATED_HIP := .541
const STANDING_EYE := Vector3(0, 1.673, -.067)
const SEATED_EYE := Vector3(0, 1.027, -.340)
const HELMET_EYE := Vector3(0, .126, -.067)
const SEATED_CUSHION := Vector3(0, .421, .010)
const THIGH := .432
const SHIN := .414
const STRIDE := 1.24
# Center of the authored index finger's pad relative to the OpenXR grip, mirrored at the wrist.
const RIGHT_INDEX_PAD := Vector3(.00377, -.06591, -.03734)

var _pelvis: Node3D
var _torso: Node3D
var _head: Node3D
var _thighs: Array[Node3D] = []
var _shins: Array[Node3D] = []
var _boots: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _shoulders: Array[Vector3] = []
var _forearms: Array[Node3D] = []
var _gloves: Array[MeshInstance3D] = []
var _seated := false
var _pan_rise := 0.0
var _first_person := false
var _tracked := false
var _moving := false
var _distance := 0.0
var _grip_targets := PackedVector3Array()


func _init() -> void:
	var shell := SUIT.instantiate()
	add_child(shell)
	_pelvis = shell.find_child("Pelvis",true,false)
	_torso = _pelvis.get_node("Torso")
	_head = _torso.get_node("Head")
	for side in ["L","R"]:
		var thigh: Node3D = _pelvis.get_node("Thigh"+side)
		var shin: Node3D = thigh.get_node("Shin"+side)
		var arm: Node3D = _torso.get_node("Arm"+side)
		var forearm: Node3D = arm.get_node("Forearm"+side)
		_thighs.append(thigh)
		_shins.append(shin)
		_boots.append(shin.get_node("Boot"+side))
		_arms.append(arm)
		_shoulders.append(arm.position)
		_forearms.append(forearm)
		_gloves.append(forearm.get_node("Glove"+side))
	# Godot imports the first GLTF material with vertex-colour albedo disabled.
	# Every fabric surface, including separately mounted XR gloves, uses this resource.
	var cloth := _gloves[0].mesh.surface_get_material(0) as StandardMaterial3D
	cloth.vertex_color_use_as_albedo = true
	_pose()


func set_seated(value: bool) -> void:
	if _seated != value:
		_seated = value
		_grip_targets.clear()
		_pose()


## Fleet buckets have a deeper bolster and a pan 52 mm higher than the two original seats.
func set_seat_vehicle(vehicle: String) -> void:
	var rise := .052 if vehicle in ["basilisk","orrery","kiln","vesper"] else 0.0
	if rise != _pan_rise:
		_pan_rise = rise
		if _seated:
			_pose()


func seated_cushion() -> Vector3:
	return SEATED_CUSHION + Vector3.UP*_pan_rise


## Pass cumulative ground distance in metres. Gait phase follows movement speed.
func set_stride(distance: float, moving: bool) -> void:
	if _distance == distance and _moving == moving:
		return
	_distance = distance
	_moving = moving
	if not _seated:
		_pose()


func planted_sole(side: int) -> Vector3:
	# The boot origin is the ankle, 95 mm above the sole. Bias slightly toward
	# the heel, where the first contact takes place.
	return _boots[side].to_global(Vector3(0,-.095,.045))


func set_first_person(value: bool) -> void:
	_first_person = value
	_head.visible = not value
	_update_arms()


func set_tracked_hands(active: bool) -> void:
	if _tracked == active:
		return
	_tracked = active
	_grip_targets.clear()
	if _seated:
		_seat_pose()
	_update_arms()


func _update_arms() -> void:
	for arm in _arms:
		arm.visible = not (_first_person and _tracked)


## Desktop gloves follow the moving grips. XR gloves remain on the two tracked controllers.
func set_grip_targets(left_world: Vector3, right_world: Vector3) -> void:
	if not _seated or _tracked:
		return
	var left := to_local(left_world)
	var right := to_local(right_world)
	if _grip_targets.size() == 2 and _grip_targets[0].is_equal_approx(left) and _grip_targets[1].is_equal_approx(right):
		return
	_grip_targets = PackedVector3Array([left, right])
	_seat_spine()
	_reach_grip(0, left)
	_reach_grip(1, right)


## Both glove meshes are authored in OpenXR grip space: little finger to index is -Z,
## wrist to fingertips is -Y, and the left and right palms face +X and -X respectively.
static func index_tip(controller: Node3D) -> Vector3:
	var hand := String(controller.tracker) if controller is XRController3D else String(controller.name)
	var left := hand.to_lower().contains("left")
	return Vector3(-RIGHT_INDEX_PAD.x if left else RIGHT_INDEX_PAD.x, RIGHT_INDEX_PAD.y, RIGHT_INDEX_PAD.z)


func make_glove(side: String) -> Node3D:
	var left := side.to_lower() in ["left","l","left_hand"]
	var mount := Node3D.new()
	mount.name = &"LeftGlove" if left else &"RightGlove"
	var glove := MeshInstance3D.new()
	glove.mesh = _gloves[0 if left else 1].mesh
	glove.position = -Vector3(0,-.081,-.006)
	mount.add_child(glove)
	return mount


## Fit a tucked racing posture to the measured pan and throttle heads. The helmet,
## arms and legs keep their standing dimensions as the waist folds into the bucket.
func _seat_pose() -> void:
	_seat_spine()
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		# The heels rest ahead of the pan, leaving room for the floor beneath the shins.
		var pitch := deg_to_rad(88.0)
		var shin_angle := deg_to_rad(64.5)-_pan_rise*2.5
		_thighs[i].rotation = Vector3(pitch,-side*.115,0)
		_shins[i].rotation.x = shin_angle-pitch
		_boots[i].rotation.x = .065-shin_angle
		var grip := _grip_targets[i] if _grip_targets.size() == 2 else SEATED_EYE + Vector3(side * .46, -.397, -.195)
		_reach_grip(i, grip)


func _seat_spine() -> void:
	_pelvis.position = Vector3.UP*(SEATED_HIP+_pan_rise)
	_torso.position = Vector3(0,-.052,-.003)
	var head_basis := Basis(Vector3.RIGHT,-.12)
	var neck := SEATED_EYE - head_basis*HELMET_EYE
	var spine := neck-_pelvis.position-_torso.position
	var lean := atan2(spine.z,spine.y)
	if _grip_targets.size() == 2:
		# Fold from the hip as either lever advances. Keep the pan and boots planted.
		var ahead := (SEATED_EYE.z - .195) - minf(_grip_targets[0].z, _grip_targets[1].z)
		lean -= deg_to_rad(14.0) * smoothstep(.055, .33, ahead)
	_torso.basis = Basis(Vector3.RIGHT,lean)*Basis.from_scale(Vector3(1,spine.length()/.57,1))
	_head.basis = _torso.basis.inverse()*head_basis


func _reach_grip(i: int, grip: Vector3) -> void:
	var shoulder := _pelvis.position + _torso.position + _torso.basis * _shoulders[i]
	var offset := grip - shoulder
	var axis := offset.normalized()
	var pole := Vector3(-.80 if i == 0 else .80, -1.0, .35)
	var bend := (pole - axis * axis.dot(pole)).normalized()
	var upper_length := .286
	var lower_length := .247 + .081
	# The shoulder rolls forward for the last few centimetres while both arm bones keep their length.
	var protraction := clampf(offset.length() - upper_length - lower_length + .006, 0.0, .075)
	_arms[i].position = _shoulders[i] + _torso.basis.inverse() * (axis * protraction)
	shoulder += axis * protraction
	offset = grip - shoulder
	var distance := clampf(offset.length(), absf(lower_length - upper_length) + .001, lower_length + upper_length - .001)
	var along := (distance * distance + upper_length ** 2 - lower_length ** 2) / (2.0 * distance)
	var elbow := shoulder + axis * along + bend * sqrt(maxf(0.0, upper_length ** 2 - along ** 2))
	var upper := Basis(Quaternion(Vector3.DOWN, (elbow - shoulder).normalized()))
	var lower := Basis(Quaternion(Vector3.DOWN, (shoulder + axis * distance - elbow).normalized()))
	_arms[i].basis = _torso.basis.inverse() * upper
	_forearms[i].basis = upper.inverse() * lower


func _pose() -> void:
	if _seated:
		_seat_pose()
		return
	var cycle := fposmod(_distance/STRIDE,1.0) if _moving else 0.0
	var swing := sin(TAU*cycle)
	_pelvis.position = Vector3.UP*HIP_HEIGHT
	_torso.transform = Transform3D(Basis.IDENTITY,Vector3.UP*.036)
	_head.basis = Basis.IDENTITY
	for i in 2:
		_arms[i].position = _shoulders[i]
	if _moving:
		_pelvis.position.y = .897-.029*cos(TAU*2.0*cycle)
		_pelvis.position.x = -.013*swing
		_torso.rotation = Vector3(-.042,.047*swing,.020*swing)
		_head.rotation = Vector3(.025,-.034*swing,-.019*swing)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var phase := fposmod(cycle+i*.5,1.0)
		var pitch := 0.0
		var knee := 0.0
		var boot := 0.0
		var shoulder := -.065
		var elbow := .176
		if _moving:
			var z := lerpf(-STRIDE*.25,STRIDE*.25,phase*2.0)
			var ankle_y := .095
			if phase > .5:
				var recovery := (phase-.5)*2.0
				z = STRIDE*.25*cos(PI*recovery)
				ankle_y += .104*sin(PI*recovery)
				boot = -.19*sin(TAU*recovery)
			var drop := _pelvis.position.y-ankle_y
			var length_squared := drop*drop + z*z
			knee = -acos(clampf((length_squared-THIGH*THIGH-SHIN*SHIN)/(2.0*THIGH*SHIN),-1.0,1.0))
			pitch = atan2(-z,drop) + atan2(-SHIN*sin(knee),THIGH+SHIN*cos(knee))
			shoulder = -.070-.41*cos(TAU*phase)
			elbow = .24+.14*(1.0-cos(TAU*phase))
		_thighs[i].rotation = Vector3(pitch,0,0)
		_shins[i].rotation.x = knee
		_boots[i].rotation.x = boot-pitch-knee
		_arms[i].basis = Basis.from_euler(Vector3(shoulder,0.0,side*.105))
		_forearms[i].basis = Basis(Vector3.RIGHT,elbow)
