## The minimap in the headset (Luke: "a minimap overlay of upcoming path", then "put the map in
## its own enclosure on the left side, pointed at the driver"): a screen in a hooded pod on an arm
## off the nose of the port console, left of the instruments and turned to face the eye, so a
## glance down-left shows the track ahead. (With `enclosure` off it is the translucent heads-up
## panel it was: no pod, drawn over everything.) Heading-up, the craft near the bottom, the next
## LOOK_S seconds of track above it (view/minimap.gd: it zooms out with speed, ~21 km at
## 4,000 mph), the loop in SPEEDCRAFT blue and the towns in STARFIGHTER magenta, a bar where the
## next mode change is and a readout of how far ("STARFIGHTER  12.4 km"). Circuits and the Network
## only; on the range the screen is dark (set_live).
## With the pod's HUD switch up the same drawing is shown in the windscreen too (view/minimap_glass.gd).
## Panel-local: x across, y up, the face looks down +z at the pilot.
##   var mp := MinimapPanel.new(); shell.add_child(mp); mp.transform = MinimapPanel.mount(eye); mp.build()
##   mp.show_frame(minimap.update(heading, delta))      every frame
extends Node3D

const MiniMap := preload("res://view/minimap.gd")
const MapGlass := preload("res://view/minimap_glass.gd")
const Interior := preload("res://vr/cockpit_interior.gd")
const Finish := preload("res://view/craft_materials.gd")
const Kit := preload("res://view/mesh_kit.gd")
const Traffic := preload("res://view/network_traffic.gd")
const POD := "res://art/cockpit/gauges_hd.glb"   # tools/art_gauges_hd.py: the MapPod mesh, in the screen's frame
const W := 0.22
const H := 0.22
const MARGIN := 0.007
const TOP := 0.026                  # the readout's band along the top
const LINE := 0.0024                # path half-width (m on the panel)
const DIST := 0.80                  # from the eye (0.85 until it was swung out to 39 degrees: there its pod's back corner met the rim)
const YAW := deg_to_rad(39.0)       # left of straight ahead, clear of the instruments (their end: 27 deg, now that they are 0.3 m nearer; it was 33 here, for an end at 21.5) ...
const PITCH := deg_to_rad(-11.0)    # ... and below the horizon, just over the port console's nose (see TILT)
const SCALE := 0.83                 # the screen and its pod, so it fills the eye as it did a metre away
# Luke, flight 34: "the left lever collides with the map at 90-100% throttle". At 14 degrees down the left grip came up
# through the foot of the screen from 85% on (5 to 6 cm into it at full throttle, in every craft). The pod has no room
# to go forward or down (the dash, the coaming), sideways (the coaming, the instruments) or simply up: the roof's port
# pillar stands 4 mm behind the controls strip on top, and leans back as it rises. So it is raised (11 degrees down)
# and its face tipped TILT toward the pilot about its middle, which swings its foot forward, away from the grip, and
# its strip aft, away from the pillar: the grip now passes 10 mm under it at the least (the Kiln's crown; the
# Phaethon's 27), the strip clears the pillar by 14 mm, and the screen is seen 33 degrees off square from the eye
# (6 before), 16% shorter than square on (tests/test_cockpit_reach.gd, test_cockpit_clash.gd).
const TILT := deg_to_rad(27.0)
const HUD := [1.0, deg_to_rad(30.0), deg_to_rad(-10.0), 1.0]   # the same four for the heads-up panel
const ARM_FOOT := Vector3(-0.6, 0.37, -0.028)   # where the arm stands on the port console (rig frame)
const SP_COL := Color(0.25, 0.65, 1.0)
const SF_COL := Color(1.0, 0.3, 0.75)
const PRIORITY := 40                # over the windscreen and the forcefield
# The screen's colours (Luke, flying the fourteenth: "There should also be a button to cycle through
# different color schemes on the map"): the two road colours (STARFIGHTER's stretches, SPEEDCRAFT's),
# the target, the craft and the towns, the frame's hairline, the glass and its backlight. The first is
# the map as it was. PAPER is dark ink on a pale screen, for a bright day.
const SCHEMES := [
	{"name": "NETWORK", "star": Color(1.0, 0.3, 0.75), "speed": Color(0.25, 0.65, 1.0), "target": Color(1.0, 0.86, 0.3), "craft": Color(1.0, 1.0, 1.0),
		"frame": Color(0.6, 0.75, 0.9), "glass": Color(0.012, 0.016, 0.022), "glow": Color(0.012, 0.018, 0.028)},
	{"name": "AMBER", "star": Color(1.0, 0.38, 0.1), "speed": Color(1.0, 0.72, 0.22), "target": Color(1.0, 0.96, 0.82), "craft": Color(1.0, 0.95, 0.85),
		"frame": Color(0.9, 0.6, 0.25), "glass": Color(0.02, 0.012, 0.006), "glow": Color(0.03, 0.016, 0.004)},
	{"name": "PHOSPHOR", "star": Color(0.8, 1.0, 0.3), "speed": Color(0.2, 1.0, 0.45), "target": Color(0.95, 1.0, 0.8), "craft": Color(0.9, 1.0, 0.9),
		"frame": Color(0.3, 0.85, 0.45), "glass": Color(0.004, 0.018, 0.008), "glow": Color(0.004, 0.028, 0.012)},
	{"name": "ICE", "star": Color(0.78, 0.62, 1.0), "speed": Color(0.75, 0.95, 1.0), "target": Color(1.0, 0.55, 0.2), "craft": Color(1.0, 1.0, 1.0),
		"frame": Color(0.7, 0.9, 1.0), "glass": Color(0.01, 0.02, 0.035), "glow": Color(0.01, 0.025, 0.045)},
	{"name": "PAPER", "star": Color(0.72, 0.08, 0.4), "speed": Color(0.06, 0.25, 0.62), "target": Color(0.8, 0.38, 0.0), "craft": Color(0.04, 0.05, 0.08),
		"frame": Color(0.15, 0.2, 0.28), "glass": Color(0.62, 0.62, 0.58), "glow": Color(0.42, 0.42, 0.38)},
]
# The map's own controls, on a strip along the top of its pod (Luke, flying the fourteenth: "The map
# could use a switch like the other 2, that switches from 'local' to 'global' map"): the same guarded
# toggle as the MODE and SLIDE switches at a little over half their size (up GLOBAL: the whole country,
# north up; down LOCAL: the roads round the craft, heading up), and beside it a push button that steps
# the screen's colours, its ring showing the one that is up. On top, in plain sight against the coaming
# from the seat: down the inboard edge the pod's own hood hid half of them and anything larger covered
# the left gauge, and under the outboard edge stands the SLIDE switch, which a hand going to one would throw.
# Between the two, a second toggle of the same kind (Luke, 2026-11-22: "Will you please add a switch to
# the map that projects it via the hud?"): up HUD, and the map is in the windscreen as well as here
# (view/minimap_glass.gd); down OFF. For it the strip grew outboard to the pod's own side (its inboard end,
# which has the roof's pillar 4 mm behind it, is where it was), the GLOBAL / LOCAL toggle went out to that
# end and the button 17 mm toward the other; each toggle's box is 80 mm wide (it was 90), so that a hand
# throwing one is in neither the other's nor the button's.
const CONTROLS_Y := 0.182           # the strip's middle, over the screen's (panel units; the screen's half-height is 0.11)
const STRIP_X := Vector2(-0.1335, 0.1065)   # the strip's ends: the pod's outboard side, and where its inboard end was
const SWITCH_X := -0.098            # the GLOBAL / LOCAL toggle, at the outboard end ...
const HUD_X := 0.0                  # ... the HUD toggle in the middle ...
const SWITCH_SCALE := 0.55
const BUTTON_AT := Vector3(0.08, CONTROLS_Y + 0.008, 0.004)   # ... and the button's face, inboard of both
const BUTTON_REACH := 0.03          # how near its axis a tip has to be to press it (panel units, as PRESS_Z)
const PRESS_Z := 0.024              # pressed: a tip this near the face, having come from further out
const SWITCH_ZONE := Vector3(0.04, 0.06, 0.13)   # m: half-size of the box in front of a toggle where a tip can throw it (short of its neighbours)
const SWITCH_COOL_MS := 800

static var enclosure := true   # false before the cockpit is built: the heads-up panel instead
var live := true         # is the screen showing a map? (set_live)
var lines: ArrayMesh     # rebuilt every frame from _v, _c (on the Network: ~5,000 vertices at a crossing;
var label: Label3D       # an ImmediateMesh's two calls a vertex cost ~0.7 ms of the headset's 8.3)
var _mat: StandardMaterial3D
var _housed := false
var _v := PackedVector3Array()
var _roads: MeshInstance3D   # the whole country's roads, drawn once (the Network's whole map)
var _c := PackedColorArray()
var scheme := 0              # which of SCHEMES the screen is drawn in (set_scheme)
var map_switch: ModeSwitch   # GLOBAL / LOCAL, on the pod (null on the heads-up panel)
var hud_switch: ModeSwitch   # HUD / OFF, beside it: the map in the windscreen too
var glass: Node3D            # view/minimap_glass.gd: made when the HUD switch is first thrown up (null until then)
var _canopy: Node3D          # where it goes: the roofed canopy (null without the roof: then the HUD switch does nothing)
var button: MeshInstance3D   # the colour button's cap
var _glass: StandardMaterial3D
var _ring: StandardMaterial3D
var _tips := {}              # controller -> [its tip in the switch's frame (m), from the button's face (panel units)], last frame
var _thrown_at := -100000    # ms: when the switch was last thrown, the button last pressed
var _hud_thrown_at := -100000
var _pressed_at := -100000
var _named_until := 0        # ms: until then the readout names the scheme just chosen


## A scheme's colour: "star", "speed", "target", "craft", "frame", "glass" or "glow".
func tone(key: String) -> Color:
	return SCHEMES[scheme][key]


## A vehicle's dot on the map, in scheme k: [half size (panel m), colour]. A raider or a raid's flyer (Raids:
## Traffic.HOSTILE_MARK) the biggest, in the hostile red whatever the scheme (hostile_tone); the racer (kind 4) a
## bigger one in the scheme's STARFIGHTER colour; every other kind a small one in its craft colour.
static func dot_style(kind: int, k := 0) -> Array:
	var sc: Dictionary = SCHEMES[k]
	if kind == Traffic.HOSTILE_MARK:
		return [0.0068, hostile_tone()]
	if kind == 4:
		return [0.006, sc.star]
	return [0.0028, Color(sc.craft, 0.8)]


## A raider's colour on this screen. Traffic.HOSTILE_COL is authored as it is to be seen (the flat map and the tactical
## display show it so); this screen's vertex colours are taken as linear (its material, and the windscreen's copy), so
## as it was it showed an orange-red: it is put into linear here, and the screen shows the red itself. The same in every
## scheme: on AMBER's orange roads it stands off by hue, its size and its dark edge (tests/test_raid_display.gd).
static func hostile_tone() -> Color:
	return Traffic.HOSTILE_COL.srgb_to_linear()


## Which of SCHEMES has this name, -1 none (the cockpit's saved choice).
static func scheme_named(name: String) -> int:
	for k in SCHEMES.size():
		if String(SCHEMES[k].name) == name:
			return k
	return -1


## The screen's colours: scheme k of SCHEMES (it wraps). The whole map's roads are drawn again in
## them, and for a moment the readout says which it is.
func set_scheme(k: int, announce := true) -> void:
	scheme = posmod(k, SCHEMES.size())
	if _glass:
		_glass.albedo_color = tone("glass")
		_glass.emission = tone("glow")
	if label:
		label.outline_modulate = Color(tone("glass"), 0.7)
	if _roads:
		_roads.free()
		_roads = null
	if announce:
		_named_until = Time.get_ticks_msec() + 1500


func _name_flash() -> void:
	if Time.get_ticks_msec() < _named_until:
		label.text = "MAP  " + String(SCHEMES[scheme].name)
		label.modulate = tone("craft")


func _build_controls(fleet_cockpit: bool) -> void:
	var turn := Vector3(PI / 2.0, 0, 0)
	var back := MeshInstance3D.new()   # the strip they stand on, its bracket to the pod's side, the button's bezel
	back.name = "controls"
	back.mesh = Kit.compound([
		# (its top edge 6 mm lower than its foot is deep: at full height its back corner stood 3 mm into the roof's port pillar, which passes behind it)
		[Finish.beveled_plate(Vector3(STRIP_X.y - STRIP_X.x, 0.012, 0.092), 0.003), Kit.at(Vector3((STRIP_X.x + STRIP_X.y) / 2.0, CONTROLS_Y - 0.003, -0.016), turn), Color(0.105, 0.12, 0.14)],
		[Kit.box(Vector3(0.09, 0.034, 0.012)), Kit.at(Vector3(0.0, CONTROLS_Y - 0.058, -0.02)), Color(0.09, 0.09, 0.1)],
		[Kit.cyl(0.021, 0.021, 0.007, 28), Kit.at(BUTTON_AT + Vector3(0, 0, -0.0045), turn), Color(0.04, 0.052, 0.065)]])
	back.material_override = Finish.powder_coat()
	add_child(back)
	map_switch = ModeSwitch.new()
	map_switch.name = "MapSwitch"
	map_switch.legends = ["GLOBAL", "LOCAL"]
	map_switch.colours = [Color(0.45, 0.85, 1.0), Color(1.0, 0.72, 0.25)]
	map_switch.throws = ["global", "local"]
	map_switch.transform = Transform3D(Basis.from_scale(Vector3.ONE * SWITCH_SCALE), Vector3(SWITCH_X, CONTROLS_Y, -0.002))
	add_child(map_switch)
	map_switch.build(fleet_cockpit)
	hud_switch = ModeSwitch.new()
	hud_switch.name = "HudSwitch"
	hud_switch.legends = ["HUD", "OFF"]
	hud_switch.colours = [Color(0.55, 0.95, 1.0), Color(0.16, 0.17, 0.19)]      # the projector's own light; OFF is a lamp barely lit
	hud_switch.throws = ["hud_on", "hud_off"]
	hud_switch.transform = Transform3D(Basis.from_scale(Vector3.ONE * SWITCH_SCALE), Vector3(HUD_X, CONTROLS_Y, -0.002))
	add_child(hud_switch)
	hud_switch.build(fleet_cockpit)
	button = MeshInstance3D.new()
	button.name = "SchemeButton"
	button.mesh = Kit.compound([[Kit.cyl(0.014, 0.0155, 0.01, 28), Kit.at(Vector3(0, 0, 0.001), turn), Color(0.82, 0.84, 0.88)]])
	button.material_override = Finish.machined()
	button.position = BUTTON_AT
	add_child(button)
	_ring = StandardMaterial3D.new()
	_ring.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var ring := MeshInstance3D.new()
	ring.name = "SchemeRing"
	ring.mesh = Kit.compound([[Finish.washer(0.0165, 0.0198, 0.002, 28), Kit.at(BUTTON_AT + Vector3(0, 0, -0.0005), turn), Color.WHITE]])
	ring.material_override = _ring
	add_child(ring)
	var legend := Label3D.new()
	legend.name = "SchemeLegend"
	legend.text = "COLOR"
	legend.font_size = 36
	legend.pixel_size = 0.00035 * SWITCH_SCALE
	legend.modulate = Color(0.82, 0.83, 0.76)
	legend.outline_size = 0
	legend.shaded = true
	legend.position = BUTTON_AT + Vector3(0, -0.03, 0.0)
	add_child(legend)
	show_controls(false, 1.0)


## A controller at the map's controls: "global" or "local" when this push throws the map's switch,
## "hud_on" or "hud_off" when it throws the HUD's, "scheme" when it presses the button, else "". The
## switches are thrown as the MODE and SLIDE switches are (a tip moving up or down through the box in
## front of one; in metres, whatever the pod's scale); the button as the START button is (a tip coming
## in to its face).
func poke(ctrl: Node3D, delta: float) -> String:
	if map_switch == null or not live:
		return ""
	var now := Time.get_ticks_msec()
	var at: Vector3 = ctrl.global_transform * ModeSwitch.TIP
	var tip: Vector3 = map_switch.global_transform.orthonormalized().affine_inverse() * at
	var hud_tip: Vector3 = hud_switch.global_transform.orthonormalized().affine_inverse() * at
	var press: Vector3 = global_transform.affine_inverse() * at - BUTTON_AT
	var was: Variant = _tips.get(ctrl)
	_tips[ctrl] = [tip, press, hud_tip]
	if was == null or delta <= 0.0:
		return ""
	if now - _thrown_at >= SWITCH_COOL_MS:
		var way := _thrown(map_switch, tip, (was as Array)[0], delta)
		if way != 0:
			map_switch.down = way < 0
			_thrown_at = now
			return "local" if way < 0 else "global"
	if now - _hud_thrown_at >= SWITCH_COOL_MS and _canopy != null:
		var way := _thrown(hud_switch, hud_tip, (was as Array)[2], delta)
		if way != 0:
			hud_switch.down = way < 0
			_hud_thrown_at = now
			return "hud_off" if way < 0 else "hud_on"
	var before: Vector3 = (was as Array)[1]
	if now - _pressed_at >= 500 and Vector2(press.x, press.y).length() < BUTTON_REACH and press.z < PRESS_Z and press.z > -0.03 \
			and before.z >= PRESS_Z and absf(press.z - before.z) / delta < 4.0:
		_pressed_at = now
		return "scheme"
	return ""


## Which way a tip throws one of the strip's toggles, if it does: -1 down, 1 up, 0 not at all. `tip`
## and `was` are the tip in that toggle's frame (m), now and a frame ago.
func _thrown(toggle: ModeSwitch, tip: Vector3, was: Vector3, delta: float) -> int:
	if absf(tip.x) < SWITCH_ZONE.x and absf(tip.y) < SWITCH_ZONE.y and tip.z > -0.01 and tip.z < SWITCH_ZONE.z:
		var vy: float = (tip.y - was.y) / delta
		if absf(vy) <= 4.0:   # (faster is a tracking jump, not a push)
			if vy < -ModeSwitch.THROW_V and not toggle.down:
				return -1
			if vy > ModeSwitch.THROW_V and toggle.down:
				return 1
	return 0


## Each frame: the switches' positions (local: the map's is down; hud: the HUD's is up), their lamps
## and the button's ring at the battery's level.
func show_controls(local: bool, power: float, hud := false) -> void:
	if map_switch == null:
		return
	map_switch.power = power
	map_switch.show_state(local, 1.0 if local else 0.0, false)
	hud_switch.power = power
	hud_switch.show_state(not hud, 0.0 if hud else 1.0, false)
	button.position = BUTTON_AT + Vector3(0, 0, -0.004 if Time.get_ticks_msec() - _pressed_at < 180 else 0.0)
	_ring.albedo_color = tone("speed").lerp(tone("target"), 0.15) * (0.3 + 1.5 * power) * power


## Where the panel sits in the cockpit rig (floor origin, forward -Z), facing `eye`.
static func mount(eye: Vector3) -> Transform3D:
	var pose: Array = [DIST, YAW, PITCH, SCALE] if housed() else HUD
	var dir := Vector3(-sin(pose[1]) * cos(pose[2]), sin(pose[2]), -cos(pose[1]) * cos(pose[2]))
	var face := Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.RIGHT, TILT if housed() else 0.0)
	return Transform3D(face.scaled(Vector3.ONE * float(pose[3])), eye + dir * float(pose[0]))


static func housed() -> bool:
	return enclosure and Finish.hd and ResourceLoader.exists(POD)


## Where the HUD switch's map is shown: the cockpit's canopy (after build()). Nothing is made yet.
func fit_glass(canopy: Node3D) -> void:
	_canopy = canopy if _housed and Canopy.roof_available() else null


## Each frame, after show_frame: with `on` (the HUD switch up) and the screen lit, the windscreen shows
## what the screen does; `dark` is 0 by day .. 1 at night. The glass's own parts are made the first time
## it is on; until then, and whenever it is off, there is nothing of it to draw or to run.
func show_glass(on: bool, dark: float, delta: float) -> void:
	on = on and live and _canopy != null
	if glass == null:
		if not on:
			return
		glass = MapGlass.new()
		glass.build(_canopy)
	glass.show_map(on, lines, _roads.mesh if _roads != null and _roads.visible else null, dark, delta)


## The screen shows a map, or (in its pod) sits dark; the heads-up panel just goes away.
func set_live(on: bool) -> void:
	live = on
	if _housed:
		for name in ["path", "readout", "roads"]:
			var n := get_node_or_null(name) as Node3D
			if n:
				n.visible = on
	else:
		visible = on


func build(fleet_cockpit := false) -> void:
	_housed = housed()
	var back := MeshInstance3D.new()
	back.name = "backing"
	var q := QuadMesh.new()
	q.size = Vector2(W, H)
	back.mesh = q
	if _housed:
		_glass = StandardMaterial3D.new()   # the screen itself: dark glass with a little backlight (the scheme's)
		_glass.albedo_color = tone("glass")
		_glass.roughness = 0.16
		_glass.emission_enabled = true
		_glass.emission = tone("glow")
		back.material_override = _glass
		var pod := MeshInstance3D.new()
		pod.name = "pod"
		pod.mesh = Interior._hd_mesh(POD, "MapPod")
		Interior.Accent.dress(pod)
		add_child(pod)
		_arm(fleet_cockpit)
	else:
		var bm := _hud_mat(PRIORITY)
		bm.vertex_color_use_as_albedo = false
		bm.albedo_color = Color(0.02, 0.03, 0.05, 0.5)
		back.material_override = bm
	add_child(back)
	_mat = _hud_mat(PRIORITY + 1)
	lines = ArrayMesh.new()
	var mi := MeshInstance3D.new()
	mi.name = "path"
	mi.mesh = lines
	mi.material_override = _mat
	mi.position = Vector3(0, 0, 0.001)
	add_child(mi)
	label = Label3D.new()
	label.name = "readout"
	label.pixel_size = 0.0005
	label.font_size = 26
	label.outline_size = 6
	label.outline_modulate = Color(0, 0, 0, 0.7)
	label.no_depth_test = not _housed
	label.render_priority = PRIORITY + 2
	label.outline_render_priority = PRIORITY + 1
	label.position = Vector3(0, H / 2.0 - MARGIN - TOP / 2.0, 0.002)
	add_child(label)
	if _housed:
		_build_controls(fleet_cockpit)
	show_frame({"pts": PackedVector2Array(), "modes": PackedByteArray(), "ahead": MiniMap.MIN_AHEAD, "next": {}})


## The arm: a satin tube from a flange on the port console's nose up to a boss on the pod's back.
## Built in the rig's frame (the node under it undoes this panel's own placement).
func _arm(fleet_cockpit: bool) -> void:
	var to_rig := transform
	var boss: Vector3 = to_rig * Vector3(-0.045, -0.085, -0.058)
	var away: Vector3 = -to_rig.basis.z.normalized()
	var p := [ARM_FOOT, ARM_FOOT + Vector3(0, 0.07, 0), boss + away * 0.06, boss]
	const STEPS := 14
	var sides := 16 if fleet_cockpit else 10
	const RADIUS := 0.011
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := []
	var side := Vector3.RIGHT
	for k in STEPS + 1:
		var t := float(k) / STEPS
		var u := 1.0 - t
		var at: Vector3 = u * u * u * p[0] + 3.0 * u * u * t * p[1] + 3.0 * u * t * t * p[2] + t * t * t * p[3]
		var along: Vector3 = (3.0 * u * u * (p[1] - p[0]) + 6.0 * u * t * (p[2] - p[1]) + 3.0 * t * t * (p[3] - p[2])).normalized()
		side = (side - along * side.dot(along)).normalized()   # carried along the tube, so it does not twist
		var other := side.cross(along) if fleet_cockpit else along.cross(side)
		var ring := []
		for s in sides:
			var a := TAU * s / sides
			ring.append([at, side * cos(a) + other * sin(a)])
		rings.append(ring)
	for k in STEPS:
		for s in sides:
			var s1 := (s + 1) % sides
			for corner in [[k, s], [k + 1, s1], [k + 1, s], [k, s], [k, s1], [k + 1, s1]]:
				var v: Array = rings[corner[0]][corner[1]]
				st.set_normal(v[1])
				st.add_vertex((v[0] as Vector3) + (v[1] as Vector3) * RADIUS)
	var holder := Node3D.new()
	holder.name = "arm"
	holder.transform = to_rig.affine_inverse()
	add_child(holder)
	var tube := MeshInstance3D.new()
	tube.name = "tube"
	tube.mesh = st.commit()
	tube.material_override = Finish.satin()
	holder.add_child(tube)
	var ends := MeshInstance3D.new()   # the flange on the console, the collar at the pod
	ends.name = "ends"
	var dark := Color(0.09, 0.09, 0.1)
	ends.mesh = Kit.compound([
		[Kit.cyl(0.026, 0.03, 0.009, 20), Kit.at(ARM_FOOT + Vector3(0, 0.0045, 0)), dark],
		[Kit.cyl(0.016, 0.018, 0.016, 16), Kit.at(ARM_FOOT + Vector3(0, 0.017, 0)), dark],
		[Kit.cyl(0.017, 0.017, 0.02, 16), Transform3D(Basis(Quaternion(Vector3.UP, away)), boss + away * 0.008), dark]])
	ends.material_override = Finish.powder_coat()
	holder.add_child(ends)


func _hud_mat(priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = not _housed   # in its pod it is a screen, and things in front of it hide it
	m.disable_fog = true
	m.render_priority = priority
	return m


func show_frame(f: Dictionary) -> void:
	if f.has("whole"):
		_show_whole(f)
		return
	if _roads:
		_roads.visible = false
	var l := MiniMap.layout(f, W, H, MARGIN, TOP)
	_v.clear()
	_c.clear()
	_paths(l.segs)
	if l.zone != null:
		var z: Vector2 = l.zone
		var zc := tone("star") if int(f.next.mode) == 0 else tone("speed")
		_seg(z + Vector2(-0.014, 0), z + Vector2(0.014, 0), 0.0022, Color(zc.lightened(0.4), 1.0))
	if l.dawn != null:   # the dawn's front, across the map
		_seg(l.dawn[0], l.dawn[1], LINE * 3.2, Color(MiniMap.DAWN_COL, 0.25))
		_seg(l.dawn[0], l.dawn[1], LINE * 1.2, Color(MiniMap.DAWN_COL, 1.0))
	if l.pad != null:   # the medical pad: a red cross
		var pq: Vector2 = l.pad
		_seg(pq + Vector2(-0.009, 0), pq + Vector2(0.009, 0), 0.0028, Color(1, 1, 1, 0.9))
		_seg(pq + Vector2(0, -0.009), pq + Vector2(0, 0.009), 0.0028, Color(1, 1, 1, 0.9))
		_seg(pq + Vector2(-0.008, 0), pq + Vector2(0.008, 0), 0.0018, MiniMap.PAD_COL)
		_seg(pq + Vector2(0, -0.008), pq + Vector2(0, 0.008), 0.0018, MiniMap.PAD_COL)
	var plain := dot_style(Traffic.CAR, scheme)     # (read once a frame, not a dot at a time)
	var racer := dot_style(4, scheme)
	var raiders := []             # (drawn last: over the traffic round them)
	for d in l.get("dots", []):   # the Network's traffic: small dots; the racer, a bigger one in the towns' colour (dot_style)
		var kind := int(d[1])
		if kind == Traffic.HOSTILE_MARK:
			raiders.append(d[0])
			continue
		var st: Array = racer if kind == 4 else plain
		var r2: float = st[0]
		var dq: Vector2 = d[0]
		_tri(dq + Vector2(0, r2), dq + Vector2(-r2, -r2 * 0.7), dq + Vector2(r2, -r2 * 0.7), st[1])
	if not raiders.is_empty():    # a raider: bigger still, the hostile red on a dark edge (it reads on any scheme's roads)
		var hs := dot_style(Traffic.HOSTILE_MARK, scheme)
		var hr: float = hs[0]
		var rim := hr * 1.4
		for hq: Vector2 in raiders:
			_tri(hq + Vector2(0, rim), hq + Vector2(-rim, -rim * 0.7), hq + Vector2(rim, -rim * 0.7), Color(0.0, 0.0, 0.0, 0.8))
			_tri(hq + Vector2(0, hr), hq + Vector2(-hr, -hr * 0.7), hq + Vector2(hr, -hr * 0.7), hs[1])
	if l.get("target") != null:   # the Network's target city: a diamond on the map, smaller on its rim toward it
		_diamond(l.target[0], MiniMap.target_swell(0.011 if l.target[1] else 0.008, f))
	# the craft: a white arrowhead pointing up the map
	var cr: Vector2 = l.craft
	_tri(cr + Vector2(0, 0.011), cr + Vector2(-0.0075, -0.007), cr + Vector2(0.0075, -0.007), Color(tone("craft"), 0.95))
	# the frame: a hairline round the edge
	var e := Color(tone("frame"), 0.35)
	var hw := W / 2.0
	var hh := H / 2.0
	for k in 4:
		var a := [Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)][k] as Vector2
		var b := [Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh), Vector2(-hw, -hh)][k] as Vector2
		_seg(a, b, 0.0008, e)
	lines.clear_surfaces()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _v
	arr[Mesh.ARRAY_COLOR] = _c
	lines.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	label.text = MiniMap.readout(f)
	label.modulate = (tone("star") if int(f.next.mode) == 0 else tone("speed")).lightened(0.3) if not (f.next as Dictionary).is_empty() else tone("craft")
	_name_flash()


## The whole country (the Network): its roads drawn once into their own mesh; each frame the marks,
## the target and the craft, pointing its way.
func _show_whole(f: Dictionary) -> void:
	if _roads == null:
		var l0 := MiniMap.whole_layout(f, W, H, MARGIN, TOP, true)
		_v.clear()
		_c.clear()
		_paths(l0.segs, 0.45)
		var rm := ArrayMesh.new()
		var ra := []
		ra.resize(Mesh.ARRAY_MAX)
		ra[Mesh.ARRAY_VERTEX] = _v.duplicate()
		ra[Mesh.ARRAY_COLOR] = _c.duplicate()
		rm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ra)
		_roads = MeshInstance3D.new()
		_roads.name = "roads"
		_roads.mesh = rm
		_roads.material_override = _mat
		_roads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_roads)
	_roads.visible = true
	var l := MiniMap.whole_layout(f, W, H, MARGIN, TOP, false)
	_v.clear()
	_c.clear()
	for m in l.marks:   # the jumps (orange), the GPs (pink), the cities (white), their on-ramps (violet)
		var q: Vector2 = m[0]
		match m[1]:
			"jump":
				_tri(q + Vector2(0, 0.0065), q + Vector2(-0.005, -0.004), q + Vector2(0.005, -0.004), Color(MiniMap.JUMP_COL, 1.0))
			"leap":   # a jump's mark and a second over it: the long one
				for lift in [0.0, 0.007]:
					_tri(q + Vector2(0, 0.0075 + lift), q + Vector2(-0.006, -0.004 + lift), q + Vector2(0.006, -0.004 + lift), Color(MiniMap.JUMP_COL, 1.0))
			"gp":
				_seg(q + Vector2(-0.007, 0.007), q + Vector2(0.007, -0.007), 0.0018, Color(MiniMap.GP_COL, 1.0))
				_seg(q + Vector2(-0.007, -0.007), q + Vector2(0.007, 0.007), 0.0018, Color(MiniMap.GP_COL, 1.0))
			"city":
				_tri(q + Vector2(0, 0.004), q + Vector2(-0.004, -0.003), q + Vector2(0.004, -0.003), Color(tone("craft"), 0.9))
			"ramp":
				_seg(q + Vector2(-0.003, 0), q + Vector2(0.003, 0), 0.0016, Color(MiniMap.RAMP_COL, 1.0))
	if l.target != null:
		_diamond(l.target[0], MiniMap.target_swell(0.008, f))
	var cr: Vector2 = l.craft   # the craft: a white arrowhead pointing its way
	var dq: Vector2 = (l.craft_dir as Vector2).normalized() if (l.craft_dir as Vector2).length() > 0.0 else Vector2.UP
	var sd := dq.orthogonal()
	_tri(cr + dq * 0.011, cr - dq * 0.007 + sd * 0.0075, cr - dq * 0.007 - sd * 0.0075, Color(tone("craft"), 0.95))
	var e := Color(tone("frame"), 0.35)
	var hw := W / 2.0
	var hh := H / 2.0
	for k in 4:
		var a := [Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)][k] as Vector2
		var b := [Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh), Vector2(-hw, -hh)][k] as Vector2
		_seg(a, b, 0.0008, e)
	lines.clear_surfaces()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _v
	arr[Mesh.ARRAY_COLOR] = _c
	lines.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	label.text = "%s  %s" % [f.target.name, _mi(float(f.target.dist))] if f.has("target") else ""
	label.modulate = tone("target")
	_name_flash()


static func _mi(m: float) -> String:
	return "%.0f mi" % (m / 1609.344) if m >= 16093.44 else "%.1f mi" % (m / 1609.344)


## The path segments: a soft glow under every one, then the lines over them all (written in place:
## at a crossing there are hundreds).
func _paths(segs: Array, width := 1.0) -> void:
	var n := segs.size()
	var g0 := _v.size()
	var l0 := g0 + 6 * n
	_v.resize(g0 + 12 * n)
	_c.resize(g0 + 12 * n)
	var glow := [Color(tone("star"), 0.22), Color(tone("speed"), 0.22)]
	var line := [Color(tone("star").lightened(0.15), 0.95), Color(tone("speed").lightened(0.15), 0.95)]
	for k in n:
		var seg: Array = segs[k]
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var m := 1 if int(seg[2]) == 1 else 0
		var u := (b - a).orthogonal()
		u = u.normalized() if u.length_squared() >= 1e-12 else Vector2.ZERO   # a point: nothing drawn
		for pass_ in 2:
			var o := u * (LINE * 2.8 if pass_ == 0 else LINE) * width
			var j := (g0 if pass_ == 0 else l0) + 6 * k
			var p0 := Vector3(a.x + o.x, a.y + o.y, 0.0)
			var p2 := Vector3(b.x - o.x, b.y - o.y, 0.0)
			_v[j] = p0
			_v[j + 1] = Vector3(a.x - o.x, a.y - o.y, 0.0)
			_v[j + 2] = p2
			_v[j + 3] = p0
			_v[j + 4] = p2
			_v[j + 5] = Vector3(b.x + o.x, b.y + o.y, 0.0)
			var c: Color = glow[m] if pass_ == 0 else line[m]
			for q in 6:
				_c[j + q] = c


func _seg(a: Vector2, b: Vector2, w: float, c: Color) -> void:
	var d := b - a
	if d.length_squared() < 1e-12:
		return
	var n := d.orthogonal().normalized() * w
	var p0 := Vector3(a.x + n.x, a.y + n.y, 0.0)
	var p2 := Vector3(b.x - n.x, b.y - n.y, 0.0)
	_v.append(p0)
	_v.append(Vector3(a.x - n.x, a.y - n.y, 0.0))
	_v.append(p2)
	_v.append(p0)
	_v.append(p2)
	_v.append(Vector3(b.x + n.x, b.y + n.y, 0.0))
	for k in 6:
		_c.append(c)


## The target's diamond at q, its half size sw.x; a raid's city (sw.y > 0) swells, on a rim in the hostile red that
## strong (MiniMap.target_swell; drawn first, so the diamond lies over it).
func _diamond(q: Vector2, sw: Vector2) -> void:
	if sw.y > 0.0:
		var e := sw.x + 0.003
		var rim := Color(hostile_tone(), sw.y)
		_tri(q + Vector2(0, e), q + Vector2(-e, 0), q + Vector2(e, 0), rim)
		_tri(q + Vector2(-e, 0), q + Vector2(0, -e), q + Vector2(e, 0), rim)
	var r := sw.x
	_tri(q + Vector2(0, r), q + Vector2(-r, 0), q + Vector2(r, 0), Color(tone("target"), 1.0))
	_tri(q + Vector2(-r, 0), q + Vector2(0, -r), q + Vector2(r, 0), Color(tone("target"), 1.0))


func _tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	_v.append(Vector3(a.x, a.y, 0.0))
	_v.append(Vector3(b.x, b.y, 0.0))
	_v.append(Vector3(c.x, c.y, 0.0))
	_c.append(col)
	_c.append(col)
	_c.append(col)
