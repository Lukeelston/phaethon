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
## The same panel serves any two-way choice: set `legends`, `colours` and `throws` before build()
## (the slide's switch on the left console is one: vr_cockpit.gd).
class_name ModeSwitch
extends Node3D

const FleetThrottle := preload("res://vr/fleet_throttle.gd")
const Kit := preload("res://view/mesh_kit.gd")
const Finish := preload("res://view/craft_materials.gd")
const SPEED_COL := Color(0.25, 0.65, 1.0)     # SPEEDCRAFT: the cables' energized blue
const SF_COL := Color(1.0, 0.3, 0.75)         # STARFIGHTER: magenta (clear of the strain amber/red)
const HD_SWITCH := "res://art/cockpit/mode_switch_hd.glb"
const THROW_ANGLE := deg_to_rad(32.0)         # the lever's swing either side of centre
const ZONE := Vector3(0.075, 0.11, 0.16)      # half-size of the box in front of the face where a tip can throw it
const THROW_V := 0.3                          # m/s: how fast a push has to be (and under 4 m/s: faster is a tracking jump)
const TIP := Vector3(0.0, -0.01, -0.07)       # the controller's tip, in its own frame
const COOLDOWN := 1.0                         # s between throws (Luke: "a 1 second cool down between flips")

var down := false          # switch position: true = STARFIGHTER (the lower legend)
var legends: Array = ["SPEED", "STAR"]              # the lamps' legends: up, down
var colours: Array = [SPEED_COL, SF_COL]            # ... and their colours
var throws: Array = ["speed", "starfighter"]        # what poke() answers for a throw up, and down
var lever: Node3D
var lamp_sp: StandardMaterial3D
var lamp_sf: StandardMaterial3D
var swing := 0.0           # the lever's shown angle, eased toward its position
var power := 1.0           # the battery bus (the start-up): the lamps' level
var _prev := {}            # controller -> its tip's previous panel-local position
var _cool := 0.0


# The port console's switch stands this much further aft than the starboard one (Luke, after the flight
# of 22 November: "The map is good but is sticking through the drift switch mesh"). At the mirrored place
# the map's pod, hung over that console's nose, came down through the inboard half of the panel: its hood
# between the guards, the panel's corner out through the screen, and from the seat the upper legend and
# lamp behind it. Here the panel's back is 11 mm clear of the pod's lower corner and the whole face shows
# beside it; its face meets the console's top 24 mm short of that console's first legend (tests/test_cockpit_clash.gd).
const PORT_AFT := 0.09


## Where the panel sits in the cockpit rig (floor origin, forward -Z): on the front of the right
## console, beside the right lever, angled up at the pilot. (side -1: on the left console, PORT_AFT
## further aft.)
static func mount(side := 1.0) -> Transform3D:
	# (0.5825 out: at 0.585 the panel's upper outboard corner went through the coaming's outer skin, a 9 mm spur under the hull's lip where nothing saw it)
	return Transform3D(Basis(Vector3.RIGHT, -0.75), Vector3(0.5825 * side, 0.43, 0.08 + (PORT_AFT if side < 0.0 else 0.0)))


func build(fleet := false) -> void:
	var turn := Vector3(PI / 2.0, 0, 0)
	var panels := [
		[Finish.beveled_plate(Vector3(0.12, 0.035, 0.15), 0.004), Kit.at(Vector3(0, 0, -0.0175), turn), Color(0.105, 0.12, 0.14)],
		[Finish.beveled_plate(Vector3(0.105, 0.003, 0.134), 0.001), Kit.at(Vector3(0, 0, 0.001), turn), Color(0.04, 0.052, 0.065)]]
	var metal := [
		[Finish.washer(0.008, 0.017, 0.002, 20), Kit.at(Vector3(0, 0, 0.004), turn), Color(0.5, 0.54, 0.58)],
		[Finish.washer(0.006, 0.012, 0.006, 6), Kit.at(Vector3(0, 0, 0.008), turn), Color(0.71, 0.74, 0.78)]]
	var guards := []
	# Tubular raised guards keep the original clearance around the moving bat handle.
	for side in [-1.0, 1.0]:
		for y in [-0.043, 0.043]:
			guards.append([Kit.cyl(0.0035, 0.0035, 0.039, 10), Kit.at(Vector3(side * 0.03, y, 0.023), turn), Color(0.68, 0.12, 0.06)])
		guards.append([Kit.cyl(0.0035, 0.0035, 0.086, 10), Kit.at(Vector3(side * 0.03, 0, 0.0425)), Color(0.8, 0.19, 0.08)])
		for y in [-0.057, 0.057]:
			metal.append([Finish.slotted_screw(0.0035), Kit.at(Vector3(side * 0.046, y, 0.003), turn), Color(0.55, 0.58, 0.62)])
	for y in [-0.05, 0.05]:
		metal.append([Finish.beveled_plate(Vector3(0.04, 0.002, 0.009), 0.0006), Kit.at(Vector3(0, y, 0.0045), turn), Color(0.27, 0.3, 0.34)])
	# Realism spike (tools/art_mode_switch_hd.py): one authored panel replaces the three batches.
	var authored := Finish.hd and ResourceLoader.exists(HD_SWITCH)
	var mi := MeshInstance3D.new()
	if authored:
		mi.mesh = CockpitInterior._hd_mesh(HD_SWITCH, "Panel")
		add_child(mi)
		if fleet:
			# The reference panel bakes its four screws into the face texture.
			# Set the three-dimensional crowns on exactly that face.
			var pieces := []
			var screw := Finish.socket_screw(.0032,Color("#a0a4a6"),true)
			for x in [-.046,.046]:
				for y in [-.057,.057]:
					pieces.append([screw, Kit.at(Vector3(x,y,.0015),turn),Color.WHITE,true])
			var heads := MeshInstance3D.new()
			heads.name = "PanelFasteners"
			heads.mesh = Kit.compound(pieces, null, true)
			heads.material_override = Finish.machined()
			add_child(heads)
	else:
		mi.mesh = Kit.compound(panels)
		mi.material_override = Finish.powder_coat()
		add_child(mi)
		var hardware := MeshInstance3D.new()
		hardware.mesh = Kit.compound(metal)
		hardware.material_override = Finish.machined()
		add_child(hardware)
		var guard := MeshInstance3D.new()
		guard.mesh = Kit.compound(guards)
		guard.material_override = Finish.painted_metal()
		add_child(guard)
	lever = Node3D.new()   # pivots about x; the bat handle sticks out of the face along +z
	lever.position = Vector3(0, 0, 0.006)
	add_child(lever)
	var bat := MeshInstance3D.new()
	bat.mesh = Kit.compound([[Kit.cyl(0.006, 0.008, 0.06, 10), Kit.at(Vector3(0, 0, 0.03), Vector3(PI / 2.0, 0, 0)), Color(0.82, 0.84, 0.88)],
		[Kit.cyl(0.011, 0.006, 0.03, 10), Kit.at(Vector3(0, 0, 0.07), Vector3(PI / 2.0, 0, 0)), Color(0.92, 0.93, 0.95)]])
	bat.material_override = Finish.machined()
	if authored:
		bat.mesh = CockpitInterior._hd_mesh(HD_SWITCH, "Bat")
		bat.material_override = null
	lever.add_child(bat)
	lamp_sp = _lamp(Vector3(0, 0.05, 0.004), str(legends[0]), fleet)
	lamp_sf = _lamp(Vector3(0, -0.05, 0.004), str(legends[1]), fleet)
	show_state(false, 0.0, false)


func _lamp(at: Vector3, text: String, fleet: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var bar := MeshInstance3D.new()
	if fleet:
		bar.mesh = FleetThrottle.lens(.034,.002,.005)
		bar.rotation.x = PI*.5
	else:
		bar.mesh = Kit.box(Vector3(0.034, 0.005, 0.002))
	bar.material_override = m
	bar.position = at + Vector3(0, 0, 0.003)
	add_child(bar)
	var l := Label3D.new()
	l.text = text
	l.font_size = 36
	l.pixel_size = 0.00035
	l.modulate = Color(0.82, 0.83, 0.76)
	l.outline_size = 0
	l.shaded = true
	# Both legends sit above their lamp; the console would hide a lower STAR legend.
	l.position = at + Vector3(0, 0.017, 0.003)
	add_child(l)
	return m


## A controller pushing the lever: returns "speed" or "starfighter" when this push throws it. `blocked`: the hand
## is another control's this frame (vr/console_switches.gd has it): it is followed, and throws nothing.
func poke(ctrl: Node3D, delta: float, blocked := false, tip_offset := TIP) -> String:
	_cool = maxf(0.0, _cool - delta)
	var tip: Vector3 = global_transform.affine_inverse() * (ctrl.global_transform * tip_offset)
	var was: Variant = _prev.get(ctrl)
	_prev[ctrl] = tip
	if was == null or delta <= 0.0 or _cool > 0.0 or blocked:
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
		return str(throws[1])
	if vy > THROW_V and down:
		down = false
		_cool = COOLDOWN
		return str(throws[0])
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
		lamp_sp.albedo_color = (colours[0] as Color) * (0.25 + 2.0 * (1.0 - blend)) * power
		lamp_sf.albedo_color = ((colours[1] as Color) * (0.25 + 2.0 * blend) if not pending else (colours[1] as Color) * (0.25 + 1.8 * blink)) * power
