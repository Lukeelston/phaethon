## The start panel (Luke: "a few switches above the windscreen by the projector - maybe a covered
## switch for engine power, and another for a parking brake ... And then of course a dope start
## button"): two pods hung from the roof's header rail, one either side of the projector, turned
## toward the seated eye. Read left to right they are the start-up itself (vr/startup_sequence.gd),
## and each control's legend carries its number, engraved, so the order can be read with the battery
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
## The pods, their fittings and the parts that move are authored (Luke, after flying the first,
## code-built panel: "polishing the startup switches so that they are on quality par with the rest
## of the cockpit"): tools/art_start_panel_hd.py writes art/cockpit/start_panel_hd.glb, each mesh in
## its pod's frame or about its own pivot, with the legends engraved in the faceplates.
## Everything here faces down and aft, away from the sky and the suns, and lit as the rest of the
## cockpit is it would be black. It has a flood lamp of its own under the rail, as an overhead panel
## does, worked out in its finish (vr/panel_finish.gdshader): dim by daylight alone, up with the
## battery, which also lights the legends from behind.
## Pod-local: x across (the pilot's right), y up the face as the pilot sees it, z out of the face.
##   var p := OverheadPanel.new(); canopy.add_child(p); p.build()
##   for hit in p.poke(controller, delta): ...      # [control, dir]: "batt" / "engine" / "park" with +1 or -1, "start" with 0
##   p.show_state(sequence, delta)                  # every frame
class_name OverheadPanel
extends Node3D

const Outlook := preload("res://view/outlook.gd")
const Ring := preload("res://vr/start_ring.gdshader")
const FinishShader := preload("res://vr/panel_finish.gdshader")
const HD := "res://art/cockpit/start_panel_hd.glb"
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
const LEGEND_Y := -0.0445                       # a legend's middle below its control, and its box (half its width, half its height)
const LEGEND_BOX := Vector2(0.021, 0.0052)
const LAMP_Y := -0.0535                         # a lamp's bar under its legend
const STANDBY_X := -0.028                       # the standby lamp, beside 1 BATT
const PLATE := Vector2(0.177, 0.096)            # a faceplate inside its housing's rim ...
const PLATE_AREA := Rect2(12.0 / 2048.0, 12.0 / 2048.0, 1040.0 / 2048.0, 564.0 / 2048.0)   # ... and the left one's place in the maps (the right one's is PLATE_STEP further down)
const PLATE_STEP := 584.0 / 2048.0
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
const FLOOD_AT := Vector3(0.0, 0.075, 0.07)     # ... and where it is: under the rail, over the pod's top edge
const GLOW := Vector2(0.5, 1.0)                 # what a face gives back of its own colour: by daylight alone, and with the lamp on
const NIGHT := 0.3                              # ... and what is left of the daylight's share at night (the standby lamp is then the one thing alight)
const BACKLIGHT := 0.85                         # the legends' own light with the battery on
const HALO := 0.3                               # a lamp's spill round its lens, of its lens's light
const GREEN := Color(0.3, 1.0, 0.45)
const AMBER := Color(1.0, 0.62, 0.12)
const WHITE := Color(1.0, 0.95, 0.85)

static var fitted := true  # (timings: false before the cockpit is built leaves the panel out)
static var _meshes := {}   # the authored meshes by name, loaded once
static var _maps := {}     # ... and their maps: base, normal, orm, glow
static var _halo: GradientTexture2D
var pods := {}             # -1.0 / 1.0 -> Node3D
var levers := {}           # control -> Node3D (the toggles' handles)
var swings := {}           # control -> its shown angle
var guard: Node3D
var guard_swing := 0.0
var button: Node3D
var button_in := 0.0       # how far the button is pushed in, 0..1 (eased)
var lamps := {}            # name -> StandardMaterial3D, a lamp's spill round its lens: "batt", "engine", "park", "standby"
var ring: ShaderMaterial   # the start button's ring of lights
var ring_progress := 1.0   # how much of it is lit, 0..1 (the tests read these two)
var ring_colour := Color.BLACK
var legends: Array[String] = []   # what is engraved under the controls (and START again on the button's cap)
var paint: ShaderMaterial  # the panel's finish: every authored part wears it
var steel: ShaderMaterial  # (the code-built panel kept bare metal apart: now the same finish)
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


## Where a place on a pod's faceplate (x across, y up, pod metres) is in the authored maps.
static func plate_uv(side: float, at: Vector2) -> Vector2:
	var u := PLATE_AREA.position.x + (at.x + PLATE.x * 0.5) / PLATE.x * PLATE_AREA.size.x
	var v := PLATE_AREA.position.y + (BODY_Y + PLATE.y * 0.5 - at.y) / PLATE.y * PLATE_AREA.size.y
	return Vector2(u, v + (PLATE_STEP if side > 0.0 else 0.0))


## The authored panel: its meshes by name and its four maps.
static func art() -> Dictionary:
	if _meshes.is_empty():
		var source := (load(HD) as PackedScene).instantiate()
		for child in source.find_children("*", "MeshInstance3D", true, false):
			_meshes[str(child.name)] = (child as MeshInstance3D).mesh
		source.free()
		var made := (_meshes["PodL"] as Mesh).surface_get_material(0) as BaseMaterial3D
		_maps = {"base": made.albedo_texture, "normal": made.normal_texture, "orm": made.roughness_texture, "glow": made.emission_texture}
	return {"meshes": _meshes, "maps": _maps}


func build() -> void:
	name = "OverheadPanel"
	art()
	paint = ShaderMaterial.new()
	paint.shader = FinishShader
	for map: String in _maps:
		paint.set_shader_parameter(map + "_map", _maps[map])
	steel = paint
	_flood = (pod_frame(-1.0).basis * FLOOD + pod_frame(1.0).basis * FLOOD).normalized()
	for side: float in [-1.0, 1.0]:
		var pod := Node3D.new()
		pod.name = "PodL" if side < 0.0 else "PodR"
		pod.transform = pod_frame(side)
		add_child(pod)
		pods[side] = pod
		_part(pod, "Housing", str(pod.name))
		_part(pod, "Clamps", "ClampsL" if side < 0.0 else "ClampsR")   # (up to the rail and round it)
	for control: String in CONTROLS:
		var c: Array = CONTROLS[control]
		var pod: Node3D = pods[c[0]]
		var x: float = c[1]
		legends.append(LEGENDS[control])
		if control != "start":
			lamps[control] = _lamp(pod, Vector3(x, LAMP_Y, 0.0034), Vector2(0.05, 0.02))
		match control:
			"batt":
				_toggle(pod, control, x, "Bat")
				lamps["standby"] = _lamp(pod, Vector3(x + STANDBY_X, 0.0, 0.0062), Vector2(0.024, 0.024))
			"engine":
				_toggle(pod, control, x, "Bat")
				guard = Node3D.new()
				guard.name = "guard"
				guard.position = Vector3(x, 0.026, 0.005)     # its hinge pin
				pod.add_child(guard)
				_part(guard, "cage", "Guard")
			"park":
				_toggle(pod, control, x, "Paddle")
			"start":
				_build_button(pod, x)
	for node in find_children("*", "GeometryInstance3D", true, false):
		# hung from the roof, outside the hull's opening by design, like the roof itself and the projector
		node.add_to_group("exterior")
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	show_state(null, 0.0)


func _part(parent: Node3D, tag: String, mesh: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = tag
	mi.mesh = _meshes[mesh]
	mi.material_override = paint
	parent.add_child(mi)
	return mi


## A toggle's handle (a bat, or the brake's paddle) on a pivot that swings about x. Its lock ring,
## nut and bushing are the pod's.
func _toggle(pod: Node3D, control: String, x: float, mesh: String) -> void:
	var lever := Node3D.new()
	lever.name = control + "_lever"
	lever.position = Vector3(x, 0, 0.006)
	pod.add_child(lever)
	_part(lever, "handle", mesh)
	levers[control] = lever
	swings[control] = THROW_ANGLE


## The start button: the ring of lights in the bezel's throat, and the cap that goes in.
func _build_button(pod: Node3D, x: float) -> void:
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
	_part(button, "cap", "Cap")
	legends.append("START")


## A lamp's spill: its light on the bezel and the plate round its lens (the lens itself is the
## finish's: lit through the fourth map). Added to what is there, so a dark lamp draws nothing.
func _lamp(pod: Node3D, at: Vector3, size: Vector2) -> StandardMaterial3D:
	if _halo == null:
		var fade := Gradient.new()
		fade.offsets = PackedFloat32Array([0.0, 0.3, 0.6, 1.0])
		fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.34), Color(1, 1, 1, 0.08), Color(1, 1, 1, 0)])
		_halo = GradientTexture2D.new()
		_halo.gradient = fade
		_halo.fill = GradientTexture2D.FILL_RADIAL
		_halo.fill_from = Vector2(0.5, 0.5)
		_halo.fill_to = Vector2(1.0, 0.5)
		_halo.width = 64
		_halo.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = _halo
	m.albedo_color = Color.BLACK
	var quad := QuadMesh.new()
	quad.size = size
	var mi := MeshInstance3D.new()
	mi.name = "lamp"
	mi.mesh = quad
	mi.material_override = m
	mi.position = at
	pod.add_child(mi)
	return m


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
	# the flood lamp: where it is now (the cockpit turns), and how bright (daylight alone until the battery is on);
	# the legends are lit from behind with it
	var turned := global_basis if is_inside_tree() else Basis.IDENTITY
	paint.set_shader_parameter("light", (turned * _flood).normalized())
	paint.set_shader_parameter("ahead", (turned * Vector3(0.0, 0.3, -0.95)).normalized())
	paint.set_shader_parameter("overhead", (turned * Vector3.UP).normalized())
	if is_inside_tree():
		paint.set_shader_parameter("lamp_left", (pods[-1.0] as Node3D).global_transform * FLOOD_AT)
		paint.set_shader_parameter("lamp_right", (pods[1.0] as Node3D).global_transform * FLOOD_AT)
	paint.set_shader_parameter("glow", lerpf(GLOW.x * lerpf(1.0, NIGHT, Outlook.darkness()), GLOW.y, power))
	paint.set_shader_parameter("backlight", BACKLIGHT * power)
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


## A lamp's light: its lens (the finish's), and its spill.
func _light(lamp: String, colour: Color) -> void:
	paint.set_shader_parameter("lamp_" + lamp, Vector3(colour.r, colour.g, colour.b))
	(lamps[lamp] as StandardMaterial3D).albedo_color = Color(colour.r * HALO, colour.g * HALO, colour.b * HALO, 1.0)
