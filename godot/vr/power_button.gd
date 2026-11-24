## The craft's power's button (Luke, 2026-11-24: "build the attributes and powers into the game"; sim/pilot_craft.gd
## TRAITS): a fingertip push-button on the left console's inboard face up front, over the POWER switch (ARM / SAFE: a
## guarded toggle, vr_cockpit.gd power_switch_mount) and turned up at the seat as it is. Pressed with a
## controller's tip as the map's colour button is (a tip coming in to its face, near its axis), it fires the power
## (CraftView.fire_power). Its lamp
## ring says where the power is: dark while it charges, steady when it is ready, pulsing while it runs; dark at SAFE,
## and dark for a craft whose power is not the button's (automatic, or the Basilisk's gun).
## Its legend is the power's own name (the LCD's: SLIPSTREAM, GYRO LOCK, ...).
## Panel-local: x across the button's face (the cockpit's forward), y up it, z out of it toward the pilot.
##   var b := PowerButton.new(); shell.add_child(b); b.transform = PowerButton.mount(); b.build("GYRO LOCK")
##   var pressed: bool = b.poke(controller, delta, blocked)       per hand per frame
##   b.show_state(state, power, delta)                            each frame: "dark", "steady", "pulse"
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")
const Finish := preload("res://view/craft_materials.gd")
const TIP := Vector3(0.0, -0.01, -0.07)      # the controller's tip, in its own frame (ModeSwitch.TIP)
const CAP_R := 0.0105                        # the cap's radius ...
const CAP_H := 0.008                         # ... and how far it stands proud of its bezel
const RING := Vector2(0.0122, 0.0152)        # the lamp ring round it: inner and outer radius
const BEZEL := Vector2(0.046, 0.06)          # the bezel plate: across, up the face
const CAP_Y := 0.008                         # the cap's middle, up the bezel from its middle (its legend under it)
const REACH := 0.016                         # m: how near the cap's axis a tip has to be to press it ...
const PRESS_Z := 0.016                       # ... coming in from further out than this over the face to nearer than it
const PRESS_FLOOR := -0.02                   # (deeper than this into the face is a hand gone through the console, not a press)
const JUMP_V := 4.0                          # m/s: faster is a tracking jump, not a finger
const REPEAT_S := 0.4                        # s between presses (on the cockpit's clock: show_state's frames)
const TRAVEL := 0.0035                       # the cap goes in this far as it is pressed, for ...
const SHOWN_S := 0.18                        # ... this long
const COLOUR := Color(1.0, 0.42, 0.12)       # the ring's lamp: the gates' and the burner's hot orange
# Where it sits (cockpit metres, floor origin, forward -Z): the port console's inboard face up front, over the POWER
# switch, under the SLIDE switch's nose and outboard of the left lever, level with the grip's foot at full throttle:
# a short drop of the hand from the grip (Luke, flight 34: "I think they should go somewhere more reachable up front":
# it was beside his thigh, 0.40 m from the grip at full throttle and 0.26 at half; now 0.13 and 0.18,
# tests/test_cockpit_reach.gd), its face turned TILT up at the seat.
const AT := Vector3(-0.5385, 0.325, 0.09)
const TILT := deg_to_rad(20.0)

var cap: MeshInstance3D
var ring: StandardMaterial3D
var legend: Label3D
var _tips := {}                # controller -> its tip a frame ago (panel metres)
var _clock := 0.0             # s: the frames show_state has been given
var _pressed_at := -100.0      # ... at the last press
var _glow := 0.0


## Where it sits in the cockpit rig: its face inboard, turned TILT up from the console's side toward the seat, its x
## along the console (forward), its y up the face.
static func mount() -> Transform3D:
	var x := Vector3(0.0, 0.0, -1.0)
	var z := Vector3(cos(TILT), sin(TILT), 0.0)
	return Transform3D(Basis(x, z.cross(x), z), AT)


func build(name_on_it: String) -> void:
	name = "PowerButton"
	var turn := Vector3(PI / 2.0, 0.0, 0.0)      # (a cylinder's axis out of the face)
	var bezel := MeshInstance3D.new()
	bezel.name = "bezel"
	bezel.mesh = Kit.compound([
		[Finish.beveled_plate(Vector3(BEZEL.x, 0.004, BEZEL.y), 0.0012), Kit.at(Vector3(0.0, 0.0, -0.001), turn), Color(0.105, 0.12, 0.14)],
		[Kit.box(Vector3(BEZEL.x - 0.004, BEZEL.y - 0.004, 0.026)), Kit.at(Vector3(0.0, 0.0, -0.016)), Color(0.09, 0.1, 0.115)],      # (its block, back into the console's side)
		[Finish.washer(RING.y, RING.y + 0.0035, 0.003, 32), Kit.at(Vector3(0.0, CAP_Y, 0.0015), turn), Color(0.42, 0.45, 0.49)],
		[Finish.slotted_screw(0.0024), Kit.at(Vector3(-BEZEL.x * 0.5 + 0.0045, BEZEL.y * 0.5 - 0.0045, 0.001), turn), Color(0.55, 0.58, 0.62)],
		[Finish.slotted_screw(0.0024), Kit.at(Vector3(BEZEL.x * 0.5 - 0.0045, -BEZEL.y * 0.5 + 0.0045, 0.001), turn), Color(0.55, 0.58, 0.62)]])
	bezel.material_override = Finish.powder_coat()
	add_child(bezel)
	ring = StandardMaterial3D.new()
	ring.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var lamp := MeshInstance3D.new()
	lamp.name = "ring"
	lamp.mesh = Kit.compound([[Finish.washer(RING.x, RING.y, 0.0025, 32), Kit.at(Vector3(0.0, CAP_Y, 0.0018), turn), Color.WHITE]])
	lamp.material_override = ring
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lamp)
	cap = MeshInstance3D.new()
	cap.name = "cap"
	cap.mesh = Kit.compound([[Kit.cyl(CAP_R, CAP_R, CAP_H, 28), Kit.at(Vector3(0.0, CAP_Y, CAP_H * 0.5), turn), Color(0.14, 0.15, 0.16)],
		[Kit.cyl(CAP_R * 0.82, CAP_R, 0.0015, 28), Kit.at(Vector3(0.0, CAP_Y, CAP_H + 0.00075), turn), Color(0.2, 0.21, 0.22)]])
	cap.material_override = Finish.rubber()
	add_child(cap)
	legend = Label3D.new()      # the power's name under the cap, on two lines where it is two words
	legend.name = "legend"
	legend.text = name_on_it.replace(" ", "
") if name_on_it.length() > 9 else name_on_it
	legend.font_size = 36
	legend.pixel_size = 0.00021 if name_on_it.length() <= 9 or name_on_it.contains(" ") else 0.00017
	legend.line_spacing = -6.0
	legend.modulate = Color(0.82, 0.83, 0.76)
	legend.outline_size = 0
	legend.shaded = true
	legend.position = Vector3(0.0, CAP_Y - RING.y - 0.0035 - 0.0072, 0.0012)
	add_child(legend)
	show_state("dark", 1.0, 0.0)


## The cap's middle on its face, panel metres: what a finger reaches for.
func face_at() -> Vector3:
	return Vector3(0.0, CAP_Y, CAP_H)


## A controller at the button, a frame: true as its tip comes in to the cap's face near its axis (from further out
## than PRESS_Z to nearer). `blocked`: the hand is another control's this frame.
func poke(ctrl: Node3D, delta: float, blocked := false) -> bool:
	var tip: Vector3 = global_transform.orthonormalized().affine_inverse() * (ctrl.global_transform * TIP) - face_at()
	var was: Variant = _tips.get(ctrl)
	_tips[ctrl] = tip
	if was == null or delta <= 0.0 or blocked:
		return false
	if _clock - _pressed_at < REPEAT_S:
		return false
	var before: Vector3 = was
	if Vector2(tip.x, tip.y).length() < REACH and tip.z < PRESS_Z and tip.z > PRESS_FLOOR and before.z >= PRESS_Z \
			and tip.distance_to(before) / delta < JUMP_V:
		_pressed_at = _clock
		return true
	return false


## Each frame: the cap in as it was pressed, and the ring as the power stands: "dark", "steady" or "pulse" (at the
## battery's level `power`).
func show_state(state: String, power: float, delta: float) -> void:
	_clock += maxf(delta, 0.0)
	if cap:
		cap.position.z = -TRAVEL if _clock - _pressed_at < SHOWN_S else 0.0
	var want := 0.06
	if state == "steady":
		want = 1.6
	elif state == "pulse":
		want = 0.5 + 1.6 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0125))
	_glow = want if delta <= 0.0 or state == "pulse" else lerpf(_glow, want, 1.0 - exp(-delta * 12.0))
	if ring:
		ring.albedo_color = COLOUR * (0.08 + _glow * power) * maxf(power, 0.05)
		ring.albedo_color.a = 1.0
