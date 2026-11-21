## The start panel (Luke: "a few switches above the windscreen by the projector - maybe a covered
## switch for engine power, and another for a parking brake ... And then of course a dope start
## button"): two pods hung from the roof's header rail, one either side of the projector, turned
## toward the seated eye. Read left to right they are the start-up itself (vr/startup_sequence.gd),
## and each control's legend carries its number, printed, so the order can be read with the battery
## dead:
##   left pod    1 BATT     a bat-handle toggle. A standby lamp beside it breathes while the craft
##                          is cold: the one thing alight in a dark cockpit.
##               2 ENGINE   the same toggle under a red guard, hinged along its top. Lift the guard
##                          (a flick up), then throw the switch. The guard falls shut by itself.
##   right pod   3 START    a broad red button in a ring of two dozen lights (vr/start_ring.gdshader):
##                          dark without power, breathing amber when a start is on offer, filling
##                          clockwise as the engines turn over and catch, green once both run.
##               4 PARK     a toggle with a broad yellow paddle: up is set, down is released.
## Worked like the console switches: a controller's tip flicked up or down through a toggle's zone
## throws it; pushed into the button's face it presses it. The panel only reports what was worked
## (poke); the sequence decides what that does, and show_state() draws its answer, so a refused
## switch never moves. The next control to work breathes.
## Everything here faces down and aft, away from the sky and the suns, and lit as the rest of the
## cockpit is it would be black. It has a flood lamp of its own under the rail, as an overhead panel
## does, worked out in its finish (vr/panel_finish.gdshader): dim by daylight alone, up with the battery.
## Pod-local: x across (the pilot's right), y up the face as the pilot sees it, z out of the face.
##   var p := OverheadPanel.new(); canopy.add_child(p); p.build()
##   for hit in p.poke(controller, delta): ...      # [control, dir]: "batt" / "engine" / "park" with +1 or -1, "start" with 0
##   p.show_state(sequence, delta)                  # every frame
class_name OverheadPanel
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")
const Finish := preload("res://view/craft_materials.gd")
const Ring := preload("res://vr/start_ring.gdshader")
const FinishShader := preload("res://vr/panel_finish.gdshader")
const EYE := Vector3(0.0, 0.12, 0.6)            # the seated eye, canopy space (view/approach_projector.gd EYE)
const POD_W := 0.6                              # each pod's place along the header: this share of the way out from its middle
const DROP := 0.064                             # its controls' line below the rail's centre line ...
const AFT := 0.012                              # ... and this far aft of it
const TOE := 0.5                                # turned this far from lying along the rail toward square to the eye
const RAIL_R := 0.02                            # the rail's section (ApproachProjector.HEADER_R)
const BODY := Vector3(0.185, 0.026, 0.104)      # a pod: across, thick, tall
const BODY_Y := -0.012                          # its middle below the controls' line (the legends are under the controls)
const CONTROLS := {                             # where each stands on its pod: [pod (-1 left, 1 right), x]
	"batt": [-1.0, -0.046], "engine": [-1.0, 0.044], "start": [1.0, -0.043], "park": [1.0, 0.05]}
const LEGENDS := {"batt": "1  BATT", "engine": "2  ENGINE", "start": "3  START", "park": "4  PARK"}
const THROW_ANGLE := deg_to_rad(28.0)           # a toggle's swing either side of square
const GUARD_SWING := deg_to_rad(108.0)          # the guard lifted
const ZONE := Vector3(0.042, 0.07, 0.13)        # a toggle's zone in front of the face: half-width, half-height, depth
const THROW_V := 0.3                            # m/s: how fast a flick has to be (and under 4: faster is a tracking jump)
const COOLDOWN := 0.6                           # s between throws on one pod (one sweep of the hand is one throw)
const TIP := Vector3(0.0, -0.01, -0.07)         # a controller's tip, in its own frame (ModeSwitch.TIP)
const BUTTON_R := 0.0185                        # the start button's cap ...
const BUTTON_REACH := 0.032                     # ... and how near its axis a tip has to be to press it
const PRESS_Z := 0.02                           # pressed: a tip this near the face, having come from further out
const RELEASE_Z := 0.045                        # and let go again past this
const PRESS_TRAVEL := 0.005
const RING_SEGMENTS := 24
const FLOOD := Vector3(0.0, 0.78, 0.62)         # toward the flood lamp from a pod's face, pod-local: up its face and out from it
const GLOW := Vector2(0.42, 0.95)               # what a face gives back of its own colour: by daylight alone, and with the lamp on
const GREEN := Color(0.3, 1.0, 0.45)
const AMBER := Color(1.0, 0.62, 0.12)
const WHITE := Color(1.0, 0.95, 0.85)
const LEGEND := Color(0.86, 0.87, 0.8)

static var fitted := true  # (timings: false before the cockpit is built leaves the panel out)
var pods := {}             # -1.0 / 1.0 -> Node3D
var levers := {}           # control -> Node3D (the toggles' handles)
var swings := {}           # control -> its shown angle
var guard: Node3D
var guard_swing := 0.0
var button: Node3D
var button_in := 0.0       # how far the button is pushed in, 0..1 (eased)
var lamps := {}            # name -> StandardMaterial3D: "batt", "engine", "park", "standby"
var ring: ShaderMaterial   # the start button's ring of lights
var ring_progress := 1.0   # how much of it is lit, 0..1 (the tests read these two)
var ring_colour := Color.BLACK
var legends: Array[Label3D] = []
var cap_label: Label3D
var paint: ShaderMaterial  # the panel's two finishes: painted parts ...
var steel: ShaderMaterial  # ... and bare metal
var _flood := Vector3.UP   # toward the flood lamp, canopy space
var _prev := {}            # controller -> {pod side -> its tip's last place there}
var _cool := {-1.0: 0.0, 1.0: 0.0}
var _pressed := {}         # controller -> it has the button down
var _press_t := 0.0        # the button stays in this long after a press
var _clock := 0.0


## A point on the roof's header rail, canopy space: w -1 (left) .. 1 (right). (tools/art_roof_hd.py
## header(), less the rig's 0.6 m: bowed forward and up in the middle.)
static func header_at(w: float) -> Vector3:
	return Vector3(0.41 * w, 0.47 - 0.035 * w * w, 0.30 + 0.14 * w * w)


## A pod's frame in canopy space: hung under the rail, turned part of the way from lying along it
## to square with the seated eye, its face tipped down at that eye.
static func pod_frame(side: float) -> Transform3D:
	var w := POD_W * side
	var at := header_at(w) + Vector3(0.0, -DROP, AFT)
	var to_eye := (EYE - at).normalized()
	var along := (header_at(w + 0.01) - header_at(w - 0.01)).normalized()
	var across := along.slerp(Vector3.UP.cross(to_eye).normalized(), TOE).normalized()
	var out := (to_eye - across * to_eye.dot(across)).normalized()
	return Transform3D(Basis(across, out.cross(across).normalized(), out), at)


## Where a control stands, canopy space (the middle of its handle, a little proud of the face).
static func control_point(control: String) -> Vector3:
	var c: Array = CONTROLS[control]
	return pod_frame(c[0]) * Vector3(c[1], 0.0, 0.03)


func build() -> void:
	name = "OverheadPanel"
	paint = ShaderMaterial.new()
	paint.shader = FinishShader
	paint.set_shader_parameter("roughness", 0.62)
	paint.set_shader_parameter("sheen", 0.03)
	steel = ShaderMaterial.new()
	steel.shader = FinishShader
	steel.set_shader_parameter("roughness", 0.32)
	steel.set_shader_parameter("sheen", 0.55)
	steel.set_shader_parameter("fill", 0.22)
	_flood = (pod_frame(-1.0).basis * FLOOD + pod_frame(1.0).basis * FLOOD).normalized()
	for side: float in [-1.0, 1.0]:
		var pod := Node3D.new()
		pod.name = "PodL" if side < 0.0 else "PodR"
		pod.transform = pod_frame(side)
		add_child(pod)
		pods[side] = pod
		_build_pod(pod, side)
	for control: String in CONTROLS:
		var c: Array = CONTROLS[control]
		var pod: Node3D = pods[c[0]]
		var x: float = c[1]
		_legend(pod, Vector3(x, -0.0445, 0.0032), LEGENDS[control])
		if control != "start":
			lamps[control] = _lamp(pod, Kit.box(Vector3(0.03, 0.0034, 0.0016)), Vector3(x, -0.0535, 0.003))
		match control:
			"batt":
				_toggle(pod, control, x, false)
				lamps["standby"] = _lamp(pod, Kit.cyl(0.0031, 0.0031, 0.0016, 20), Vector3(x - 0.028, 0.0, 0.003), Vector3(PI / 2.0, 0, 0))
			"engine":
				_toggle(pod, control, x, false)
				_build_guard(pod, x)
			"park":
				_toggle(pod, control, x, true)
			"start":
				_build_button(pod, x)
	for node in find_children("*", "GeometryInstance3D", true, false):
		# hung from the roof, outside the hull's opening by design, like the roof itself and the projector
		node.add_to_group("exterior")
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	show_state(null, 0.0)


func _part(parent: Node3D, tag: String, parts: Array, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = tag
	mi.mesh = Kit.compound(parts)
	mi.material_override = material
	parent.add_child(mi)
	return mi


## A pod: a housing with a recessed faceplate, screwed at its corners, on two clamps round the rail.
func _build_pod(pod: Node3D, side: float) -> void:
	var turn := Vector3(PI / 2.0, 0, 0)
	var body := [
		[Finish.beveled_plate(BODY, 0.007), Kit.at(Vector3(0, BODY_Y, -BODY.y * 0.5), turn), Color(0.36, 0.38, 0.41)],
		[Finish.beveled_plate(Vector3(BODY.x - 0.014, 0.003, BODY.z - 0.014), 0.0012), Kit.at(Vector3(0, BODY_Y, 0.001), turn), Color(0.2, 0.215, 0.24)]]
	var metal := []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			metal.append([Finish.slotted_screw(0.003), Kit.at(Vector3(sx * (BODY.x * 0.5 - 0.0085), BODY_Y + sy * (BODY.z * 0.5 - 0.0085), 0.003), turn), Color(0.6, 0.63, 0.67)])
	# the clamps: a strut from the pod's back up to the rail, and a collar round the rail there
	var inv := pod.transform.affine_inverse()
	var clamps := []
	var none := Color(0.42, 0.45, 0.48)
	for sx: float in [-0.058, 0.058]:
		var w := POD_W * side + sx / 0.41
		var on_rail: Vector3 = inv * header_at(w)
		var foot := Vector3(sx, 0.014, -BODY.y + 0.002)
		var run := on_rail - foot
		clamps.append([Kit.cyl(0.0055, 0.0055, run.length(), 16), Transform3D(Basis(Quaternion(Vector3.UP, run.normalized())), foot + run * 0.5), none])
		var along: Vector3 = inv.basis * (header_at(w + 0.01) - header_at(w - 0.01)).normalized()
		clamps.append([Finish.washer(RAIL_R - 0.002, RAIL_R + 0.006, 0.016, 28), Transform3D(Basis(Quaternion(Vector3.UP, along)), on_rail), none])
	_part(pod, "Housing", body, paint)
	_part(pod, "Clamps", clamps, paint)
	# the controls' fixed metal goes in with the screws: one mesh for a pod's bare metal
	for control: String in CONTROLS:
		var c: Array = CONTROLS[control]
		if c[0] != side:
			continue
		var x: float = c[1]
		if control == "start":
			metal.append([Finish.washer(0.0245, 0.0312, 0.0085, 56), Kit.at(Vector3(x, 0, 0.00425), turn), Color(0.72, 0.75, 0.8)])
			metal.append([Finish.washer(0.0305, 0.0336, 0.003, 56), Kit.at(Vector3(x, 0, 0.0015), turn), Color(0.4, 0.42, 0.46)])
		else:
			metal.append([Finish.washer(0.0058, 0.0115, 0.003, 28), Kit.at(Vector3(x, 0, 0.003), turn), Color(0.55, 0.58, 0.63)])
			metal.append([Finish.washer(0.0047, 0.0088, 0.0045, 6), Kit.at(Vector3(x, 0, 0.0058), turn), Color(0.78, 0.81, 0.85)])
	_part(pod, "Hardware", metal, steel)


## A bat-handle toggle (a broad paddle for the brake): a collar and a nut on the face, the handle on
## a pivot that swings about x.
func _toggle(pod: Node3D, control: String, x: float, paddle: bool) -> void:
	var turn := Vector3(PI / 2.0, 0, 0)
	var lever := Node3D.new()
	lever.name = control + "_lever"
	lever.position = Vector3(x, 0, 0.006)
	pod.add_child(lever)
	var handle := [[Kit.cyl(0.0036, 0.0048, 0.026, 24), Kit.at(Vector3(0, 0, 0.013), turn), Color(0.74, 0.77, 0.82)]]
	if paddle:
		handle.append([Kit.rounded_box(Vector3(0.025, 0.0075, 0.017), 4.0, 12), Kit.at(Vector3(0, 0, 0.0345)), Color(1.0, 0.8, 0.1)])
	else:
		handle.append([Kit.cyl(0.0066, 0.004, 0.015, 24), Kit.at(Vector3(0, 0, 0.0335), turn), Color(0.93, 0.94, 0.96)])
	_part(lever, "handle", handle, steel)
	levers[control] = lever
	swings[control] = THROW_ANGLE


## The guard over the engine switch: a red cage hinged along its top edge, over the handle, with a
## window in its front (the switch is seen through it) and a lip at its foot to lift it by.
func _build_guard(pod: Node3D, x: float) -> void:
	guard = Node3D.new()
	guard.name = "guard"
	guard.position = Vector3(x, 0.026, 0.005)
	pod.add_child(guard)
	var none := Color(0.93, 0.1, 0.05)
	var deep := 0.046
	var tall := 0.054
	var wide := 0.0342
	var wall := 0.0026
	var cage := [
		[Kit.box(Vector3(wide, wall, deep)), Kit.at(Vector3(0, -tall + wall * 0.5, deep * 0.5)), none],                 # the foot
		[Kit.box(Vector3(wide, 0.009, wall)), Kit.at(Vector3(0, -0.0045, deep - wall * 0.5)), none],                    # the front: its top bar ...
		[Kit.box(Vector3(wide, 0.013, wall)), Kit.at(Vector3(0, -tall + 0.0065, deep - wall * 0.5)), none],             # ... its bottom bar
		[Kit.box(Vector3(0.017, wall, 0.005)), Kit.at(Vector3(0, -tall + wall * 0.5, deep + 0.0025)), none]]            # the lip
	for sx in [-1.0, 1.0]:
		cage.append([Kit.box(Vector3(wall, tall, deep)), Kit.at(Vector3(sx * (wide - wall) * 0.5, -tall * 0.5, deep * 0.5)), none])          # a cheek
		cage.append([Kit.box(Vector3(0.0075, tall, wall)), Kit.at(Vector3(sx * (wide - 0.0075) * 0.5, -tall * 0.5, deep - wall * 0.5)), none])   # a front rail
	cage.append([Kit.cyl(0.003, 0.003, wide + 0.006, 14), Kit.at(Vector3.ZERO, Vector3(0, 0, PI / 2.0)), Color(0.62, 0.65, 0.7)])   # the hinge pin
	_part(guard, "cage", cage, paint)


## The start button: a machined bezel, the ring of lights inside it, and a broad red cap that goes in.
func _build_button(pod: Node3D, x: float) -> void:
	var turn := Vector3(PI / 2.0, 0, 0)
	var none := Color(0.86, 0.06, 0.04)
	# the ring: a flat band between the cap and the bezel, u once round it clockwise from the top
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var around := 96
	var r0 := BUTTON_R + 0.0008
	var r1 := 0.0243
	for i in around:
		for corner: Vector2i in [Vector2i(i, 0), Vector2i(i, 1), Vector2i(i + 1, 1), Vector2i(i, 0), Vector2i(i + 1, 1), Vector2i(i + 1, 0)]:
			var u := float(corner.x) / around
			var a := TAU * u
			var r := r1 if corner.y == 1 else r0
			st.set_uv(Vector2(u, float(corner.y)))
			st.set_normal(Vector3(0, 0, 1))
			st.add_vertex(Vector3(x + r * sin(a), r * cos(a), 0.0058))
	ring = ShaderMaterial.new()
	ring.shader = Ring
	ring.set_shader_parameter("segments", float(RING_SEGMENTS))
	var band := MeshInstance3D.new()
	band.name = "start_ring"
	band.mesh = st.commit()
	band.material_override = ring
	pod.add_child(band)
	button = Node3D.new()
	button.name = "start_button"
	button.position = Vector3(x, 0, 0)
	pod.add_child(button)
	_part(button, "cap", [
		[Kit.cyl(BUTTON_R - 0.0016, BUTTON_R, 0.004, 56), Kit.at(Vector3(0, 0, 0.0105), turn), none],
		[Kit.cyl(BUTTON_R, BUTTON_R, 0.0085, 56), Kit.at(Vector3(0, 0, 0.00425), turn), none]], paint)
	cap_label = Label3D.new()
	cap_label.name = "cap_label"
	cap_label.text = "START"
	cap_label.font_size = 40
	cap_label.pixel_size = 0.000225
	cap_label.outline_size = 0
	cap_label.shaded = false
	cap_label.double_sided = false
	cap_label.position = Vector3(0, 0, 0.0128)
	button.add_child(cap_label)


func _lamp(pod: Node3D, mesh: Mesh, at: Vector3, rot := Vector3.ZERO) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color.BLACK
	var mi := MeshInstance3D.new()
	mi.name = "lamp"
	mi.mesh = mesh
	mi.material_override = m
	mi.position = at
	mi.rotation = rot
	pod.add_child(mi)
	return m


func _legend(pod: Node3D, at: Vector3, text: String) -> void:
	var l := Label3D.new()
	l.name = "legend_" + text.replace(" ", "")
	l.text = text
	l.font_size = 36
	l.pixel_size = 0.00027
	l.outline_size = 0
	l.shaded = false            # printed white, and lit from behind once the battery is on
	l.double_sided = false
	l.position = at
	pod.add_child(l)
	legends.append(l)


## A controller's tip, in a pod's frame.
func _tip_in(pod: Node3D, ctrl: Node3D) -> Vector3:
	return pod.global_transform.affine_inverse() * (ctrl.global_transform * TIP)


## What this controller worked this frame: an array of [control, dir] ("batt", "engine" or "park"
## flicked up (+1) or down (-1); "start" pressed (0)). Usually empty. (A frame of no length only
## notes where the tip is.)
func poke(ctrl: Node3D, delta: float) -> Array:
	var worked := []
	var prev: Dictionary = _prev.get(ctrl, {})
	for side: float in pods:
		var pod: Node3D = pods[side]
		var tip := _tip_in(pod, ctrl)
		var was: Variant = prev.get(side)
		prev[side] = tip
		if was == null or delta <= 0.0:
			continue
		var before: Vector3 = was
		for control: String in CONTROLS:
			var c: Array = CONTROLS[control]
			if c[0] != side:
				continue
			var x: float = c[1]
			if control == "start":
				var near := Vector2(tip.x - x, tip.y).length() < BUTTON_REACH
				if _pressed.get(ctrl, false):
					if tip.z > RELEASE_Z or not near:
						_pressed[ctrl] = false
				elif near and tip.z < PRESS_Z and tip.z > -0.03 and before.z >= PRESS_Z and absf(tip.z - before.z) / delta < 4.0:
					_pressed[ctrl] = true
					_press_t = 0.25
					worked.append(["start", 0])
				continue
			if _cool[side] > 0.0:
				continue
			if absf(tip.x - x) >= ZONE.x or absf(tip.y) >= ZONE.y or tip.z <= -0.01 or tip.z >= ZONE.z:
				continue
			var vy := (tip.y - before.y) / delta
			if absf(vy) > 4.0 or absf(vy) < THROW_V:    # a tracking jump, or no flick at all
				continue
			_cool[side] = COOLDOWN
			worked.append([control, 1 if vy > 0.0 else -1])
	_prev[ctrl] = prev
	return worked


## Draw the panel as the sequence has it (null: cold and dark). Call once a frame; it also runs the
## panel's own clocks (the rest between throws, the button's spring).
func show_state(seq, delta: float) -> void:
	_clock += delta
	for side in _cool:
		_cool[side] = maxf(0.0, _cool[side] - delta)
	_press_t = maxf(0.0, _press_t - delta)
	var power: float = seq.power if seq else 0.0
	var snap := delta <= 0.0
	# the flood lamp: where it is now (the cockpit turns), and how bright (daylight alone until the battery is on)
	var lamp: Vector3 = (global_basis * _flood).normalized() if is_inside_tree() else _flood
	for finish: ShaderMaterial in [paint, steel]:
		finish.set_shader_parameter("light", lamp)
		finish.set_shader_parameter("glow", lerpf(GLOW.x, GLOW.y, power))
	var on := {"batt": seq.batt if seq else false, "engine": seq.master if seq else false, "park": seq.park if seq else true}
	for control: String in levers:
		swings[control] = lerpf(swings[control], -THROW_ANGLE if on[control] else THROW_ANGLE, 1.0 if snap else 1.0 - exp(-delta * 22.0))
		(levers[control] as Node3D).rotation.x = swings[control]
	guard_swing = lerpf(guard_swing, GUARD_SWING if (seq and seq.guard_open) else 0.0, 1.0 if snap else 1.0 - exp(-delta * 14.0))
	guard.rotation.x = -guard_swing
	var held := _press_t > 0.0
	for c in _pressed:
		held = held or _pressed[c]
	button_in = lerpf(button_in, 1.0 if held else 0.0, 1.0 if snap else 1.0 - exp(-delta * 30.0))
	button.position.z = -PRESS_TRAVEL * button_in
	# the lamps: what is on, and the next control to work breathing
	var next: String = seq.next_control() if seq else "batt"
	var breath := 0.5 + 0.5 * sin(_clock * TAU * 1.3)
	_light("standby", GREEN * (0.3 + 1.9 * breath) if not on.batt else Color.BLACK)
	_light("batt", GREEN * 1.8 * power if on.batt else Color.BLACK)
	var engine := Color.BLACK
	if on.engine:
		engine = GREEN * 1.8
	elif next == "guard" or next == "engine":
		engine = AMBER * (0.25 + 1.7 * breath)
	_light("engine", engine * power)
	ring_progress = 1.0
	ring_colour = WHITE * 0.16
	if seq and seq.all_running():
		ring_colour = Color(0.1, 0.95, 0.34) * 1.45
	elif seq and seq.starting():       # it fills as the engines come up: the left one the first half, the right the second
		ring_colour = Color(1.0, 0.82, 0.55) * (1.5 + 0.5 * sin(_clock * 61.0) * sin(_clock * 23.0))
		ring_progress = 0.5 * (seq.engine_k(0) + seq.engine_k(1))
	elif next == "start":
		ring_colour = AMBER * (0.35 + 2.0 * breath)
	ring_colour = ring_colour * power
	ring.set_shader_parameter("lit", Vector3(ring_colour.r, ring_colour.g, ring_colour.b))
	ring.set_shader_parameter("level", 1.0)
	ring.set_shader_parameter("progress", ring_progress)
	var park := Color.BLACK
	if on.park:
		park = AMBER * ((0.3 + 1.9 * breath) if next == "park" else 1.5)
	_light("park", park * power)
	var ink := LEGEND * lerpf(0.55, 1.2, power)
	for l in legends:
		l.modulate = Color(ink.r, ink.g, ink.b, 1.0)
	var cap := Color(1.0, 0.97, 0.9) * lerpf(0.7, 1.25, power)
	cap_label.modulate = Color(cap.r, cap.g, cap.b, 1.0)


func _light(lamp: String, colour: Color) -> void:
	(lamps[lamp] as StandardMaterial3D).albedo_color = Color(colour.r, colour.g, colour.b, 1.0)
