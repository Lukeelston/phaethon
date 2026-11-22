## A starting pad (Luke, 2026-11-21: "personal starting pads for each insertion point - something that
## lets the pilot run through a preflight"). Where a Network flight begins, and where a crash puts the
## craft back, it stands in a bay at the right-hand roadside (CraftSim.net_pad_right, on the flat inside
## the edge ramp; the lane it takes is the outermost, which traffic leaves for a parked craft) instead
## of on the centre line among the lanes. On the pad:
##   the apron      a sealed slab with a yellow border, a stop bar under the pod's nose, blue edge lamps,
##                  chevrons from its front corner out to the lanes
##   the mast       ahead and to the right, turned to the seat: a lamp for each step of the start-up
##                  (BATT, ENGINE, START, RUN-UP) and a big one over them, red while the craft is held
##                  and green once it may go; under them a board with the place's name, its height, and
##                  whose pad it is (the machine, its paint, its role)
##   the gate       a striped boom across the way out, down while the craft is held, up when it may go
##   ground power   a cart with a lead to the pod's flank, which drops away when both engines run
##   local station  the equipment on the port side belongs to this particular shop; its crew
##                  gives the pilot a parting word when the gate clears
##   the closure    cones tapering in behind the pad and an arrow board telling traffic to move over
## It follows the cold start (vr/startup_sequence.gd) through show_startup(); a flight with no sequence (the
## flat game, a restart) is shown as released: green, the gate up, the lead away.
## One pad is built and stands wherever the sim's next respawn would be (CraftSim.net_home): the start
## point, then each city reached.
##   var pad := StartPad.new(); view.add_child(pad); pad.build(view)
##   pad.show_startup(startup)   every frame, in a cockpit with the sequence
##   pad.sync(delta)          every frame
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")
const Livery := preload("res://view/livery.gd")
const Stations := preload("res://view/pad_stations.gd")
const PadAudio := preload("res://audio/pad_audio.gd")
const Release := preload("res://release/release_config.gd")
const WIDE := 24.0               # the apron across (m): 11 to the pod's left, 13 to its right
const LEFT := -11.0
const BACK := 10.0               # ... behind the pod's middle
const PAST := 22.0               # ... beyond the engines' middle
const STEPS := ["BATT", "ENGINE", "START", "RUN-UP"]
const SLAB := Color(0.085, 0.09, 0.10)
const YELLOW := Color(0.92, 0.72, 0.10)
const WHITE := Color(0.90, 0.90, 0.86)
const STEEL := Color(0.30, 0.32, 0.34)
const AMBER := Color(2.8, 1.55, 0.22)
const RED := Color(3.2, 0.16, 0.10)
const GREEN := Color(0.22, 3.0, 0.62)
const BLUE := Color(0.25, 0.75, 3.0)
const UNLIT := Color(0.035, 0.035, 0.04)
const GATE_UP := 1.40            # rad the boom lifts through
const GATE_RATE := 0.9           # of its travel a second
const PLUG := Vector3(1.28, 1.25, 0.45)
const SEEN_TO := 12000.0         # m from the craft beyond which it is not drawn

var view
var sim
var home: Array = []             # [road, sample, way, m right of the centre line]: where it stands
var ahead := 21.75               # m from the pod's middle to the engines' (the craft's own)
var step_lamps: Array[MeshInstance3D] = []
var big_lamp: MeshInstance3D
var gate: Node3D                 # the boom's hinge
var lead: Node3D                 # ground power's cable
var cart_lamp: MeshInstance3D
var arrow: MeshInstance3D
var lines: Array[Label3D] = []   # the board's three
var station: MeshInstance3D
var station_sign: Label3D
var station_id := ""
var audio: PadAudio
var lit := [true, true, true, true]   # each step's lamp
var flashing := -1               # the step being done now (its lamp flashes), -1 none
var released := true             # the craft may go
var plugged := false             # ground power is on the pod
var gate_open := 1.0
var _startup_seen := false
var _at := Vector3.ZERO          # the pad's place in the sim's metres (x, y, height)
var _th := 0.0
var _pitch := 0.0
var _clock := 0.0


func build(v) -> void:
	view = v
	sim = v.sim
	name = "start_pad"
	var gap: float = float(sim.P.engineGap) / 2.0 - float(sim.P.podAnchorW) * float(sim.P.podWidth) / 2.0
	ahead = sqrt(float(sim.P.cableLen) * float(sim.P.cableLen) - gap * gap) + float(sim.P.podLen) / 2.0 + float(sim.P.engineLen) / 2.0
	var front := -(ahead + PAST)                 # the apron's front edge (ahead is -z)
	var long := BACK - front
	var mid_x := LEFT + WIDE / 2.0
	var mid_z := (BACK + front) / 2.0
	var right := LEFT + WIDE
	# what does not move: the slab and its paint, the mast, the gate's post, the cart, the cones
	var parts := [
		[Kit.box(Vector3(WIDE, 0.08, long)), Kit.at(Vector3(mid_x, 0.04, mid_z)), SLAB],
		[Kit.box(Vector3(WIDE, 0.02, 0.4)), Kit.at(Vector3(mid_x, 0.09, BACK - 0.2)), YELLOW],
		[Kit.box(Vector3(WIDE, 0.02, 0.4)), Kit.at(Vector3(mid_x, 0.09, front + 0.2)), YELLOW],
		[Kit.box(Vector3(0.4, 0.02, long)), Kit.at(Vector3(right - 0.2, 0.09, mid_z)), YELLOW],
		# the road side: a double line to hold short of
		[Kit.box(Vector3(0.3, 0.02, long)), Kit.at(Vector3(LEFT + 0.15, 0.09, mid_z)), YELLOW],
		[Kit.box(Vector3(0.3, 0.02, long)), Kit.at(Vector3(LEFT + 0.75, 0.09, mid_z)), YELLOW],
		# the stop bar under the pod's nose, and a box for each engine to stand in
		[Kit.box(Vector3(7.0, 0.02, 0.5)), Kit.at(Vector3(0.0, 0.09, -3.4)), WHITE],
		[Kit.box(Vector3(0.25, 0.02, 9.0)), Kit.at(Vector3(-5.2, 0.09, -ahead)), WHITE],
		[Kit.box(Vector3(0.25, 0.02, 9.0)), Kit.at(Vector3(5.2, 0.09, -ahead)), WHITE],
		[Kit.box(Vector3(0.25, 0.02, 9.0)), Kit.at(Vector3(0.0, 0.09, -ahead)), WHITE],
		# the mast and the gate's post
		[Kit.box(Vector3(0.5, 9.6, 0.5)), Kit.at(_mast() + Vector3(0.0, 4.8, 0.0)), STEEL],
		[Kit.box(Vector3(1.4, 0.3, 1.4)), Kit.at(_mast() + Vector3(0.0, 0.15, 0.0)), STEEL.darkened(0.3)],
		[Kit.box(Vector3(0.7, 2.3, 0.7)), Kit.at(Vector3(right - 0.6, 1.15, front + 1.0)), STEEL],
		# ground power
		[Kit.rounded_box(Vector3(1.5, 1.0, 2.3), 5.0), Kit.at(_cart() + Vector3(0.0, 0.62, 0.0)), Color(0.16, 0.17, 0.18)],
		[Kit.box(Vector3(1.2, 0.12, 2.0)), Kit.at(_cart() + Vector3(0.0, 0.06, 0.0)), STEEL.darkened(0.4)],
		[Kit.box(Vector3(1.52, 0.16, 2.32)), Kit.at(_cart() + Vector3(0.0, 0.86, 0.0)), YELLOW],
		# the arrow board's frame
		[Kit.box(Vector3(0.2, 2.2, 0.2)), Kit.at(_board_at() + Vector3(-1.3, 1.1, 0.0)), STEEL],
		[Kit.box(Vector3(0.2, 2.2, 0.2)), Kit.at(_board_at() + Vector3(1.3, 1.1, 0.0)), STEEL],
		[Kit.box(Vector3(3.4, 1.9, 0.18)), Kit.at(_board_at() + Vector3(0.0, 2.9, 0.0)), Color(0.04, 0.04, 0.045)],
	]
	# chevrons from the front corner out toward the lanes: the way off the pad
	for k in 3:
		var at := Vector3(LEFT - 4.0 - 5.0 * k, 0.05, front - 6.0 - 9.0 * k)
		parts.append([Kit.box(Vector3(0.6, 0.02, 6.0)), Kit.at(at + Vector3(1.6, 0.0, 0.0), Vector3(0.0, -0.62, 0.0)), YELLOW])
		parts.append([Kit.box(Vector3(0.6, 0.02, 6.0)), Kit.at(at + Vector3(-1.6, 0.0, 2.2), Vector3(0.0, 0.62, 0.0)), YELLOW])
	# cones tapering in from the wall's side, well behind, to the pad's road-side corner
	for k in 8:
		var u := float(k) / 7.0
		var at := Vector3(lerpf(right, LEFT, u), 0.0, lerpf(BACK + 52.0, BACK + 4.0, u))
		parts.append([Kit.cyl(0.06, 0.34, 0.95, 10), Kit.at(at + Vector3(0.0, 0.5, 0.0)), Color(0.95, 0.35, 0.06)])
		parts.append([Kit.cyl(0.17, 0.21, 0.16, 10), Kit.at(at + Vector3(0.0, 0.62, 0.0)), WHITE])
		parts.append([Kit.box(Vector3(0.8, 0.06, 0.8)), Kit.at(at + Vector3(0.0, 0.03, 0.0)), Color(0.10, 0.10, 0.10)])
	var fixed := MeshInstance3D.new()
	fixed.mesh = Kit.compound(parts)
	fixed.material_override = Kit.vertex_colors()
	fixed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fixed)
	# the apron's edge lamps: blue, every 8 m down both long sides (unshaded and over white: they bloom, and light nothing)
	var glow := []
	var z := BACK - 1.0
	while z > front:
		for x in [LEFT + 0.45, right - 0.2]:
			glow.append([Kit.box(Vector3(0.22, 0.16, 0.22)), Kit.at(Vector3(x, 0.17, z)), BLUE])
		z -= 8.0
	var lamps := MeshInstance3D.new()
	lamps.mesh = Kit.compound(glow)
	lamps.material_override = Kit.vertex_colors(true)
	lamps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lamps)
	_build_head()
	_build_gate(right, front)
	_build_lead()
	station = MeshInstance3D.new()
	station.name = "LocalStation"
	station.position = Vector3(-8.05, 0.0, -ahead + 2.5)
	station.rotation.y = atan2(-station.position.x, -station.position.z)
	station.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(station)
	station_sign = _label("", 0.66, Color("#fff1cb"))
	station_sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	station_sign.position = Vector3(0, 2.55, 1.10)
	station.add_child(station_sign)
	if view.engine_audio != null:
		audio = PadAudio.new()
		audio.setup(self, _cart() + Vector3.UP * 0.62, PLUG, gate, station_sign)
	# the arrow board's arrow: move over, to the lanes (an approaching driver's left)
	arrow = MeshInstance3D.new()
	arrow.mesh = Kit.compound([
		[Kit.box(Vector3(1.9, 0.26, 0.05)), Kit.at(Vector3(0.25, 0.0, 0.0)), Color.WHITE],
		[Kit.box(Vector3(1.0, 0.26, 0.05)), Kit.at(Vector3(-0.42, 0.3, 0.0), Vector3(0.0, 0.0, 0.72)), Color.WHITE],
		[Kit.box(Vector3(1.0, 0.26, 0.05)), Kit.at(Vector3(-0.42, -0.3, 0.0), Vector3(0.0, 0.0, -0.72)), Color.WHITE]])
	arrow.material_override = _lamp_material(AMBER)
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arrow.position = _board_at() + Vector3(0.0, 2.9, 0.12)
	add_child(arrow)
	_move(sim.net_home())


## Where the mast stands: ahead of the engines and toward the wall.
## The mast's post: at the apron's far right corner. (It stood 1.3 m further in until the seat was
## raised three and a half inches: from there the glass's image lies some five degrees lower against
## the world, and its right corner came down over the mast's lamps. The post went out to the edge and
## the head hangs to the right of it: _build_head.)
func _mast() -> Vector3:
	return Vector3(LEFT + WIDE - 0.3, 0.0, -(ahead + 13.0))


func _cart() -> Vector3:
	return Vector3(5.4, 0.0, 2.2)


func _board_at() -> Vector3:
	return Vector3(3.0, 0.0, BACK + 30.0)


static func _lamp_material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = colour
	return m


static func _label(text: String, high: float, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = high / 96.0
	l.modulate = colour
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


## The mast's head, turned to the seat: the four steps' lamps with their names, the big lamp over
## them, and the board under them.
func _build_head() -> void:
	var head := Node3D.new()
	head.name = "head"
	head.position = _mast()
	head.rotation.y = atan2(-head.position.x, -head.position.z)      # its face (+z) to the pod
	head.position += head.basis.z * 0.43  # fastened in front of the square post; keep it out of the lettering
	head.position += head.basis.x * 1.5   # ... and hung to the right of it, as the pilot sees it: clear of the glass's image (_mast)
	add_child(head)
	var panel := MeshInstance3D.new()
	panel.mesh = Kit.compound([
		[Kit.box(Vector3(4.0, 4.3, 0.24)), Kit.at(Vector3(0.0, 7.55, 0.0)), Color(0.05, 0.05, 0.055)],
		[Kit.box(Vector3(6.0, 2.5, 0.2)), Kit.at(Vector3(0.0, 3.9, 0.0)), Color(0.05, 0.05, 0.055)],
		[Kit.box(Vector3(6.0, 0.12, 0.22)), Kit.at(Vector3(0.0, 2.72, 0.0)), Livery.coat("paint")]])      # the pilot's own colour along its foot
	panel.material_override = Kit.vertex_colors()
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(panel)
	for k in STEPS.size():
		var y := 8.79 - 0.91 * k
		var lamp := MeshInstance3D.new()
		lamp.mesh = Kit.cyl(0.24, 0.24, 0.1, 20)
		lamp.rotation.x = PI / 2.0
		lamp.position = Vector3(-1.50, y, 0.18)
		lamp.material_override = _lamp_material(UNLIT)
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		head.add_child(lamp)
		step_lamps.append(lamp)
		var word := _label(STEPS[k], 0.65, Color(0.90, 0.92, 0.89))
		word.position = Vector3(-1.0, y, 0.17)
		head.add_child(word)
	big_lamp = MeshInstance3D.new()
	big_lamp.mesh = Kit.cyl(0.62, 0.62, 0.12, 28)
	big_lamp.rotation.x = PI / 2.0
	big_lamp.position = Vector3(0.0, 10.25, 0.1)
	big_lamp.material_override = _lamp_material(GREEN)
	big_lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(big_lamp)
	var hood := MeshInstance3D.new()
	hood.mesh = Kit.compound([[Kit.box(Vector3(1.7, 1.7, 0.2)), Kit.at(Vector3(0.0, 10.25, -0.06)), Color(0.05, 0.05, 0.055)]])
	hood.material_override = Kit.vertex_colors()
	hood.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(hood)
	for k in 3:
		var line := _label("", [0.76, 0.48, 0.43][k], [Color(0.96, 0.95, 0.9), Color(0.75, 0.78, 0.80), Color(0.95, 0.74, 0.25)][k])
		line.position = Vector3(-2.72, [4.63, 3.86, 3.24][k], 0.16)
		head.add_child(line)
		lines.append(line)


## The boom across the way out, hinged at the wall's side.
func _build_gate(right: float, front: float) -> void:
	gate = Node3D.new()
	gate.name = "gate"
	gate.position = Vector3(right - 0.6, 1.9, front + 1.0)
	add_child(gate)
	var parts := []
	var across := WIDE - 1.4
	var n := 11
	for k in n:
		parts.append([Kit.box(Vector3(across / n, 0.3, 0.3)), Kit.at(Vector3(-(k + 0.5) * across / n, 0.0, 0.0)), RED.lerp(Color(0.7, 0.05, 0.04), 0.9) if k % 2 == 0 else WHITE])
	var boom := MeshInstance3D.new()
	boom.mesh = Kit.compound(parts)
	boom.material_override = Kit.vertex_colors()
	boom.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gate.add_child(boom)


## Ground power's lead: from the cart, sagging to the ground, up to the pod's flank.
func _build_lead() -> void:
	lead = Node3D.new()
	lead.name = "lead"
	add_child(lead)
	var pts := [_cart() + Vector3(-0.75, 0.75, -0.4), Vector3(3.6, 0.22, 1.3), Vector3(2.3, 0.3, 0.8), PLUG]
	var parts := []
	for k in pts.size() - 1:
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[k + 1]
		var xf := Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP if absf((b - a).normalized().y) < 0.95 else Vector3.RIGHT), (a + b) * 0.5)
		parts.append([Kit.box(Vector3(0.09, 0.09, a.distance_to(b) + 0.06)), xf, Color(0.95, 0.55, 0.08)])
	parts.append([Kit.box(Vector3(0.2, 0.2, 0.3)), Kit.at(pts[pts.size() - 1]), Color(0.75, 0.76, 0.78)])
	var cable := MeshInstance3D.new()
	cable.mesh = Kit.compound(parts)
	cable.material_override = Kit.vertex_colors()
	cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lead.add_child(cable)
	cart_lamp = MeshInstance3D.new()
	cart_lamp.mesh = Kit.box(Vector3(0.22, 0.14, 0.22))
	cart_lamp.position = _cart() + Vector3(0.45, 1.19, -0.8)
	cart_lamp.material_override = _lamp_material(UNLIT)
	cart_lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cart_lamp)


## The place's name for the board: a city's, a named road's, or the road's own.
func _place_name(road: int, sample: int) -> String:
	for c in sim.cities:
		if int(c.road) == road and absi(int(c.i) - sample) < 4:
			return String(c.name)
	var id := String(sim.roads[road].name)
	var world = view.get("network_world")
	if world != null and world.SCENIC_NAMES.has(id):
		return String(world.SCENIC_NAMES[id])
	return id


## Match the same insertion definitions the menu uses. A saved city and a newly reached city
## both resolve here. Two stops can share a road without sharing their station or its name.
func _set_station(road: int, sample: int) -> String:
	var id := ""
	var place := _place_name(road, sample)
	for entry in Release.INSERTIONS:
		var spot: Array = view.start_spot(entry[2])
		if spot.is_empty():
			continue
		var city_stop: bool = spot.size() == 1
		var r := int(sim.cities[spot[0]].road) if city_stop else int(spot[0])
		var i := int(sim.cities[spot[0]].i) if city_stop else int(spot[1])
		if r == road and i == sample:
			id = entry[0]
			place = String(entry[1]).to_upper()
			break
	if id != station_id:
		station_id = id
		if audio:
			audio.change_station(id)
		station.mesh = Stations.new().make(id, station.transform.affine_inverse(), _cart(), ahead) if Stations.LEGENDS.has(id) else null
	station.visible = station.mesh != null
	if station.visible:
		_station_legend()
	return place


func _station_legend() -> void:
	station_sign.text = Stations.LEGENDS[station_id][1 if released else 0]
	_fit_line(station_sign, 0.66, 4.93)


## Keep the full place and livery names on the physical mast, including longer road names.
func _fit_line(line: Label3D, high: float, panel_width := 5.44) -> void:
	var width := ThemeDB.fallback_font.get_string_size(line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, line.font_size).x
	line.pixel_size = minf(high / line.font_size, panel_width / maxf(1, width))


## Stand at `h` ([road, sample, way, m right]): the sim's metres, the road's heading and its slope there.
func _move(h: Array) -> void:
	home = h.duplicate()
	var road := int(h[0])
	var i := int(h[1])
	var way := -1.0 if int(h[2]) < 0 else 1.0
	var R = sim.roads[road]
	var right := float(h[3])
	var x: float = R.px[i] - R.nx[i] * way * right
	var y: float = R.py[i] - R.ny[i] * way * right
	var rise: float = sim.net_height(road, float(mini(i + 2, R.N - 1))) - sim.net_height(road, float(maxi(i - 2, 0)))
	var run: float = maxf(1.0, float(mini(i + 2, R.N - 1) - maxi(i - 2, 0)) * float(R.len[i]))
	_at = Vector3(x, y, sim.net_height(road, float(i)) + sim.net_edge(float(R.w[i]), right).x)
	_th = atan2(R.ty[i] * way, R.tx[i] * way)
	_pitch = atan(way * rise / run)
	if lines.size() == 3:
		lines[0].text = _set_station(road, i)
		_fit_line(lines[0], 0.76)
		lines[1].text = "PAD   %s m" % _thousands(roundi(_at.z))
		var machine := "SHRIKE RS" if String(sim.P.get("vehicle", "")) == "shrike" else "PHAETHON"
		lines[2].text = "%s  %s" % [machine, Livery.current.to_upper()]
		_fit_line(lines[2], 0.43)


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## What the start-up has reached (vr/startup_sequence.gd), for the lamps, the gate and the lead.
func show_startup(seq) -> void:
	var running: bool = seq.all_running()
	lit = [seq.batt, seq.master, running, running and seq.checks_done()]
	flashing = -1
	if not seq.batt:
		flashing = 0
	elif not seq.master:
		flashing = 1
	elif not running:
		flashing = 2
	elif seq.park and not seq.checks_done():
		flashing = 3
	var was_released := released
	released = seq.is_hot()
	if not _startup_seen:
		_startup_seen = true
		gate_open = 1.0 if released else 0.0
	if released != was_released and station != null and station.visible:
		_station_legend()
	plugged = not running


func sync(delta: float) -> void:
	var h: Array = sim.net_home()
	if h != home:
		_move(h)
	position = view.wz(_at.x, _at.y, _at.z)
	rotation = Vector3(_pitch, _th - PI / 2.0, 0.0)
	visible = Vector2(sim.pod.x - _at.x, sim.pod.y - _at.y).length() < SEEN_TO
	if not visible:
		if audio and audio.nearby:
			audio.leave()
		return
	_clock += delta
	var blink := fposmod(_clock, 0.9) < 0.5
	for k in step_lamps.size():
		var on: bool = lit[k] or (k == flashing and blink)
		(step_lamps[k].material_override as StandardMaterial3D).albedo_color = (GREEN if lit[k] else AMBER) if on else UNLIT
	(big_lamp.material_override as StandardMaterial3D).albedo_color = GREEN if released else RED
	gate_open = move_toward(gate_open, 1.0 if released else 0.0, GATE_RATE * delta)
	if audio and _startup_seen:
		var pilot := Vector3(sim.pod.x, sim.pod.y, sim.pod.z)
		audio.sync(pilot.distance_squared_to(_at) < PadAudio.EARSHOT * PadAudio.EARSHOT, plugged, released, gate_open)
	gate.rotation.z = -GATE_UP * smoothstep(0.0, 1.0, gate_open)
	lead.visible = plugged
	(cart_lamp.material_override as StandardMaterial3D).albedo_color = GREEN if plugged else UNLIT
	arrow.visible = fposmod(_clock, 1.4) < 0.9
