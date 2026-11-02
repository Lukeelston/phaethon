## The handling switch (Luke: "switch onto speedcraft mode, preferably by physically flipping a
## switch on the virtual dashboard"): a guarded bat-handle toggle on a small panel at the front of
## the right console, angled up at the pilot. Up is SPEEDCRAFT, down is STARFIGHTER. Throw it with
## either controller: a controller's tip moving up or down through the lever's zone fast enough
## flips it that way (the cockpit clicks that hand). The lamps glow the mode's colour; the
## STARFIGHTER lamp blinks while the switch is down but the craft is still too fast for it to take
## (it engages below 1,250 mph, then blends in over a second).
## Panel-local: x across, y up the panel, the face looks down +z at the pilot.
##   var sw := ModeSwitch.new(); shell.add_child(sw); sw.transform = ModeSwitch.mount(); sw.build()
##   var flip := sw.poke(controller, delta)       per hand per frame: "speed", "starfighter" or ""
##   sw.show_state(down, blend, pending)          each frame
class_name ModeSwitch
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")
const SPEED_COL := Color(0.25, 0.65, 1.0)     # SPEEDCRAFT: the cables' energized blue
const SF_COL := Color(1.0, 0.3, 0.75)         # STARFIGHTER: magenta (clear of the strain amber/red)
const THROW_ANGLE := deg_to_rad(32.0)         # the lever's swing either side of centre
const ZONE := Vector3(0.075, 0.11, 0.16)      # half-size of the box in front of the face where a tip can throw it
const THROW_V := 0.3                          # m/s: how fast a push has to be (and under 4 m/s: faster is a tracking jump)
const TIP := Vector3(0.0, -0.01, -0.07)       # the controller's tip, in its own frame
const COOLDOWN := 1.0                         # s between throws (Luke: "a 1 second cool down between flips")

var down := false          # switch position: true = STARFIGHTER
var lever: Node3D
var lamp_sp: StandardMaterial3D
var lamp_sf: StandardMaterial3D
var swing := 0.0           # the lever's shown angle, eased toward its position
var _prev := {}            # controller -> its tip's previous panel-local position
var _cool := 0.0


## Where the panel sits in the cockpit rig (floor origin, forward -Z): on the front of the right
## console, beside the right lever, angled up at the pilot.
static func mount() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, -0.75), Vector3(0.585, 0.43, 0.08))


func build() -> void:
	var parts := [
		[Kit.rounded_box(Vector3(0.12, 0.15, 0.035), 6.0), Kit.at(Vector3(0, 0, -0.0175)), Color(0.11, 0.11, 0.12)],   # panel
		[Kit.box(Vector3(0.1, 0.13, 0.004)), Kit.at(Vector3(0, 0, 0.001)), Color(0.04, 0.04, 0.045)],                   # face
		[Kit.box(Vector3(0.008, 0.11, 0.045)), Kit.at(Vector3(-0.03, 0, 0.022)), Color(0.85, 0.12, 0.1)],               # guard rails
		[Kit.box(Vector3(0.008, 0.11, 0.045)), Kit.at(Vector3(0.03, 0, 0.022)), Color(0.85, 0.12, 0.1)],
		[Kit.cyl(0.016, 0.018, 0.01, 14), Kit.at(Vector3(0, 0, 0.004), Vector3(PI / 2.0, 0, 0)), Color(0.55, 0.57, 0.6)],   # bezel
	]
	var mi := MeshInstance3D.new()
	mi.mesh = Kit.compound(parts)
	mi.material_override = Kit.vertex_colors()
	add_child(mi)
	lever = Node3D.new()   # pivots about x; the bat handle sticks out of the face along +z
	lever.position = Vector3(0, 0, 0.006)
	add_child(lever)
	var bat := MeshInstance3D.new()
	bat.mesh = Kit.compound([[Kit.cyl(0.006, 0.008, 0.06, 10), Kit.at(Vector3(0, 0, 0.03), Vector3(PI / 2.0, 0, 0)), Color(0.82, 0.84, 0.88)],
		[Kit.cyl(0.011, 0.006, 0.03, 10), Kit.at(Vector3(0, 0, 0.07), Vector3(PI / 2.0, 0, 0)), Color(0.92, 0.93, 0.95)]])
	bat.material_override = Kit.polished(1.0, 0.25)
	lever.add_child(bat)
	lamp_sp = _lamp(Vector3(0, 0.05, 0.004), "SPEED")
	lamp_sf = _lamp(Vector3(0, -0.05, 0.004), "STAR")
	show_state(false, 0.0, false)


func _lamp(at: Vector3, text: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var bar := MeshInstance3D.new()
	bar.mesh = Kit.box(Vector3(0.05, 0.012, 0.004))
	bar.material_override = m
	bar.position = at + Vector3(0, 0.0 if at.y > 0.0 else 0.0, 0.0)
	add_child(bar)
	var l := Label3D.new()
	l.text = text
	l.font_size = 36
	l.pixel_size = 0.0006
	l.modulate = Color(0.85, 0.85, 0.8)
	l.position = at + Vector3(0, 0.017 if at.y > 0.0 else -0.017, 0.003)
	add_child(l)
	return m


## A controller pushing the lever: returns "speed" or "starfighter" when this push throws it.
func poke(ctrl: Node3D, delta: float) -> String:
	_cool = maxf(0.0, _cool - delta)
	var tip: Vector3 = global_transform.affine_inverse() * (ctrl.global_transform * TIP)
	var was: Variant = _prev.get(ctrl)
	_prev[ctrl] = tip
	if was == null or delta <= 0.0 or _cool > 0.0:
		return ""
	var inside := absf(tip.x) < ZONE.x and absf(tip.y) < ZONE.y and tip.z > -0.01 and tip.z < ZONE.z
	if not inside:
		return ""
	var vy: float = (tip.y - (was as Vector3).y) / delta
	if absf(vy) > 4.0:   # a tracking glitch, not a push
		return ""
	if vy < -THROW_V and not down:
		down = true
		_cool = COOLDOWN
		return "starfighter"
	if vy > THROW_V and down:
		down = false
		_cool = COOLDOWN
		return "speed"
	return ""


## Show the switch: its position, the live blend (0 SPEEDCRAFT .. 1 STARFIGHTER) on the lamps, and
## a blinking STARFIGHTER lamp while it waits for the craft to slow down.
func show_state(is_down: bool, blend: float, pending: bool) -> void:
	down = is_down
	swing = lerpf(swing, THROW_ANGLE if is_down else -THROW_ANGLE, 0.35)
	if lever:
		lever.rotation.x = swing
	var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
	if lamp_sp:
		lamp_sp.albedo_color = SPEED_COL * (0.25 + 2.0 * (1.0 - blend))
		lamp_sf.albedo_color = SF_COL * (0.25 + 2.0 * blend) if not pending else SF_COL * (0.25 + 1.8 * blink)
