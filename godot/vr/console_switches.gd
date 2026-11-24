## The side consoles' spare switches, made to do real things (push 44; Luke, 2026-11-23, of the tactical display:
## "I also would like it to be a button. Matter of fact - if there are any menu items that could replace the
## vanity switches/buttons in the cockpit even better. I like the idea of physical controls to manipulate
## in-world."). Each console's three guarded toggles each work an on-and-off line of the quick menu's OPTIONS page
## (the same setting either way, saved the same way: vr_cockpit.gd flip_option), and one knob on each is a
## setting of the tactical display's:
##   left, ASSISTS / 01         TAC HUD     the tactical display (his name     OPTIONS: TACTICAL DISPLAY
##                                          for it: "the tac hud is awesome")
##     (front to aft)           FIELD       the avoidance field                AVOIDANCE FIELD
##                              AUTOPILOT   the autopilot                      AUTOPILOT (refused off the Network, or cold)
##                              TAC DIM     knob, aft: the display's brightness, 0.3 .. 1, clockwise brighter
##   right, PROPULSION / 02     GATES       the power-ups' lit gates           POWER-UPS
##                              HEAT        heat and energy                    HEAT AND ENERGY
##                              RUSH        the speed rush                     SPEED RUSH
##                              TAC WARN    knob, forward: how soon the rails warn of a bend, 0.35 .. 1.5 of the
##                                          display's own (lower sooner), clockwise sooner
## CABIN and BALANCE stay as they were: no setting is theirs.
##   shown        a bat forward is ON, aft OFF; ON lights its lens and its legend in the lens's colour (at the
##                battery's level). The bats and the two knobs are the authored console's own (tools/
##                art_console_hd.py), cut out of its mesh by their places in its atlas and turned here.
##   by hand      a controller's tip at rest on a bat, between its guards, has it (a light tick in that hand); then a
##                push along the console throws it, forward ON and aft OFF (a click), and the hand has to leave the
##                bat before it can have it again (so the hand drawn back after a push does not throw it back). A
##                knob is taken as the drift slider's knob is, a tip rested on its cap; then it turns with the
##                wrist, the controller rolled about its own pointing line, clockwise for clockwise, GAIN times as
##                far; a tick each TICK of a turn, a firmer one in its detent at 1 and at either stop. Lifted
##                away it is let go, and what it was left at is saved. Neither a trigger nor a grip is used:
##                both are the craft's own.
##   not by accident   a hand going by at any speed is never at rest on a bat, and throws nothing; a hand
##                at the throttle levers is 13 cm inboard of the bats at the nearest; a tracking jump is not a
##                push. The tips of the SLIDE and MODE switches' bats and the drift slider's knob are theirs
##                (keep_out, slider): a tip there is at none of these bats. The air over the bats is the
##                console's (AIR): the SLIDE and MODE switches throw for a tip moving along their throw anywhere
##                in a box 16 cm out of their panels, which covers the first bat on each side, so a hand going
##                to it or from it threw them. A tip in that air, a hand that has a bat or a knob, and one that had
##                one and has not settled since (CLAIM_S .. CLAIM_MAX) are the console's: the cockpit asks the
##                other controls to let them pass (claims). A hand that has just worked one of those is not
##                given a bat (poke's `busy`). (tests/test_console_switches.gd)
## The cockpit owns the settings: this says what a hand did and shows what it is told.
##   var c = ConsoleSwitches.new(); interior.add_child(c); c.build(interior)
##   var did: String = c.poke(controller, delta, busy)   per hand per frame: "", "rest", "on:<key>", "off:<key>"
##                                                       (a toggle thrown), or a knob's "held", "moved", "tick",
##                                                       "notch", "end", "let_go"
##   c.show_state({key: bool}, power, delta)            each frame
##   c.knob_value("dim" | "pace"), c.set_knob(key, value)
extends Node3D

const CM := preload("res://view/craft_model.gd")
const Kit := preload("res://view/mesh_kit.gd")
const Finish := preload("res://view/craft_materials.gd")
const FACE_Y := CM.POD_FRAME_UP - 0.214     # the faceplates' top, cockpit metres (tools/art_console_hd.py FACE_Y)
const CX := 0.615                           # each console's middle line, out from the cockpit's
const TOGGLE_Z := [0.28, 0.42, 0.56]        # the toggles, front to aft (tools/art_console_hd.py TOGGLES) ...
const KNOB_Z := [0.70, 0.835]               # ... and the knobs (KNOBS)
# The toggles by place: [the OPTIONS line's key, the legend, the side (-1 left), which (0 the front)].
const TOGGLES := [["tactical", "TAC HUD", -1.0, 0], ["field", "FIELD", -1.0, 1], ["autopilot", "AUTOPILOT", -1.0, 2],
	["powerups", "GATES", 1.0, 0], ["consumables", "HEAT", 1.0, 1], ["rush", "RUSH", 1.0, 2]]
const KEYS := ["tactical", "field", "autopilot", "powerups", "consumables", "rush"]
# The live knobs: [key, legend, side, which]. TAC DIM is the left console's aft knob (DIMMER that was), TAC WARN the
# right's forward one (SENS that was).
const KNOBS := [["dim", "TAC DIM", -1.0, 1], ["pace", "TAC WARN", 1.0, 0]]
const SPARE_KNOBS := {"-1/0": "CABIN", "1/1": "BALANCE"}      # decoration, as they were
const PLACARDS := {-1: "ASSISTS  /  01", 1: "PROPULSION  /  02"}   # (AUXILIARY that was; FLIGHT AIDS ran into the seat tub's edge from the seat)
const LENS := [Color(0.25, 0.58, 0.34), Color(0.25, 0.58, 0.34), Color(0.68, 0.4, 0.15)]   # by which: the console's own lenses' colours
const LEGEND_OFF := Color(0.72, 0.75, 0.72)
# Each toggle's legend lies aft of its bat (they lay 45 mm ahead of them: from the seat, which is aft of all three, a
# bat's own guards stood in front of its legend's outboard end, and the SLIDE switch's panel in front of the first's,
# AUX PWR's A).
const LEGEND_AFT := 0.045
# a bat, had and thrown
const ZONE := Vector3(0.026, 0.05, 0.04)    # m: a tip within this of a bat's middle line (across: between its guards, 24 mm
                                            # out, and a little), over the face (up to here: a bat's ball is 43 mm up), and
                                            # along the console has the bat, once it has rested there
const ZONE_FOOT := -0.005                   # ... and from this far into the face (a tip pressed on the plate)
const REST_V := 0.25                        # m/s: slower than this ...
const REST_S := 0.05                        # ... for this long, at a bat, is a tip at rest on it
const THROW_V := 0.3                        # m/s along the console: a push (ModeSwitch's figure)
const JUMP_V := 4.0                         # m/s: faster is a tracking jump, not a hand (ModeSwitch's)
const THROW := 0.3                          # rad: a bat's lean either side of upright (the authored bat leans forward this far: ON)
const CLAIM_S := 0.5                        # s: a hand that has had a bat or a knob is the console's until this long after ...
const SETTLE_S := 0.1                       # ... and until it has settled, still (slower than HOLD_V) this long ...
const CLAIM_MAX := 1.5                      # ... or this long after, whichever is sooner (its way back to the lever is the console's too)
const KEEP_OUT_R := 0.03                    # m: round the other controls' working points (keep_out), no bat is had
# The air over each console's bats is the console's (the SLIDE and MODE switches throw for a tip moving along their throw
# anywhere in a box 16 cm out of their panels, which covers the first bat and the air over it: a hand going to it or
# back from it threw them): within AIR.x of the console's middle line, up to AIR.y over its face, between AIR_Z's two
# stations (from just aft of those panels' feet to just aft of the last bat), but for the keep_out spots. A tip there
# is passed over by those switches, the drift slider and the map (claims).
const AIR := Vector2(0.05, 0.15)      # (15 cm up: a hand coming straight down onto the first bat from higher crossed the SLIDE switch's box going down)
const AIR_Z := Vector2(0.235, 0.62)
const TIP := Vector3(0.0, -0.01, -0.07)     # the controller's tip, in its own frame (ModeSwitch.TIP)
# a knob, taken and turned
const KNOB_TOP := 0.027                     # m: the cap's top over the face
const HOLD_R := 0.035                       # m: a tip this near the cap's top ...
const HOLD_S := 0.15                        # ... for this long ...
const HOLD_V := 0.2                         # ... and slower than this (m/s) has taken the knob (the drift slider's figures)
const KEEP_R := 0.07                        # held, it is let go when the tip is this far from the cap
const GAIN := 2.0                           # the knob turns this many degrees for each the wrist rolls (its 270 for 135)
const STOP := deg_to_rad(135.0)             # either stop, from straight ahead: the plate's end marks
const DETENT := deg_to_rad(6.0)             # it falls into the detent (the setting at 1) from this near it
const TICK := deg_to_rad(15.0)              # a tick in the hand for every this much it is turned
const STILL := deg_to_rad(0.05)             # less is the hand's own tremor
const TWIST_JUMP := 0.6                     # rad of roll in a frame: a tracking jump
const DIM_LEAST := 0.3                      # TAC DIM's range (TacticalScript.dim's, to come): 0.3 .. 1, 1 at the clockwise stop
const PACE_SOONEST := 0.35                  # TAC WARN's (TacticalScript.pace's, to come): 0.35 at the clockwise stop,
const PACE_LATEST := 1.5                    # 1.5 at the other, 1 straight ahead
# the authored console's atlas (tools/art_console_hd.py: kit.rect, in a 2048 atlas at any --res)
const LEVER_UV := Rect2(1490.0 / 2048.0, 140.0 / 2048.0, 64.0 / 2048.0, 128.0 / 2048.0)
const KNOB_UV := Rect2(1490.0 / 2048.0, 630.0 / 2048.0, 360.0 / 2048.0, 170.0 / 2048.0)

static var _cut := {}                       # the authored consoles as cut: "<mesh id>/<side>" -> {base, levers, knob}

var levers: Array[Node3D] = []              # by toggle: the bat's pivot (rotation.x: 0 ON, 2 THROW OFF)
var knobs: Array[Node3D] = []               # by knob: its pivot (rotation.y)
var lenses: Array[StandardMaterial3D] = []
var legends: Array[Label3D] = []
var cut_tris := []                          # by toggle, then by knob: the triangles of the authored mesh each is made of (0: built in code)
var shown: Array[bool] = [false, false, false, false, false, false]
var keep_out: Array = []                    # [point (this node's metres), radius]: the other controls' working points
var slider: Node3D = null                   # the drift slider (vr/drift_slider.gd): its knob's cap is kept out too
var knob_angle := [0.0, 0.0]                # by knob: where its pointer stands, rad clockwise from straight ahead
var knob_held: Array = [null, null]         # ... the controller that has it
var _raw := [0.0, 0.0]                      # held: the angle the hand has turned it to, before the detent and the stops
var _ticked := [0.0, 0.0]                   # ... and where it was at that hand's last tick
var _changed := [false, false]
var _swing: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _drawn := []                            # by toggle: [on, power] as last lit
var _first := true
var _h := {}                                # controller -> what it is doing here (poke)


## The legend over a toggle's place, by side (-1 left) and which (0 the front).
static func toggle_legend(side: float, k: int) -> String:
	for t in TOGGLES:
		if float(t[2]) == side and int(t[3]) == k:
			return String(t[1])
	return ""


## ... and over a knob's.
static func knob_legend(side: float, k: int) -> String:
	for n in KNOBS:
		if float(n[2]) == side and int(n[3]) == k:
			return String(n[1])
	return String(SPARE_KNOBS.get("%d/%d" % [int(side), k], ""))


static func live_knob(side: float, k: int) -> bool:
	for n in KNOBS:
		if float(n[2]) == side and int(n[3]) == k:
			return true
	return false


## A toggle's place: the middle of its nut on the face.
static func toggle_at(i: int) -> Vector3:
	return Vector3(CX * float(TOGGLES[i][2]), FACE_Y, TOGGLE_Z[int(TOGGLES[i][3])])


## A knob's cap: the middle of its top.
static func knob_cap(k: int) -> Vector3:
	return Vector3(CX * float(KNOBS[k][2]), FACE_Y + KNOB_TOP, KNOB_Z[int(KNOBS[k][3])])


static func _knob_index(key: String) -> int:
	for k in KNOBS.size():
		if KNOBS[k][0] == key:
			return k
	return -1


## A knob's setting with its pointer at angle a (rad, clockwise from straight ahead).
static func value_at(key: String, a: float) -> float:
	var t := clampf(a / STOP, -1.0, 1.0)
	if key == "dim":
		return lerpf(DIM_LEAST, 1.0, (t + 1.0) * 0.5)
	return lerpf(1.0, PACE_SOONEST, t) if t >= 0.0 else lerpf(1.0, PACE_LATEST, -t)


## ... and where its pointer stands for a setting.
static func angle_for(key: String, value: float) -> float:
	if key == "dim":
		return (clampf((value - DIM_LEAST) / (1.0 - DIM_LEAST), 0.0, 1.0) * 2.0 - 1.0) * STOP
	if value <= 1.0:
		return clampf((1.0 - value) / (1.0 - PACE_SOONEST), 0.0, 1.0) * STOP
	return -clampf((value - 1.0) / (PACE_LATEST - 1.0), 0.0, 1.0) * STOP


func knob_value(key: String) -> float:
	var k := _knob_index(key)
	return 1.0 if k < 0 else (1.0 if is_equal_approx(knob_angle[k], angle_for(key, 1.0)) else value_at(key, knob_angle[k]))


## Stand a knob at a setting (the saved one, a test).
func set_knob(key: String, value: float) -> void:
	var k := _knob_index(key)
	if k >= 0:
		knob_angle[k] = angle_for(key, value)
		_raw[k] = knob_angle[k]


## Has a knob been turned since this was last asked?
func take_changed() -> bool:
	var was: bool = _changed[0] or _changed[1]
	_changed = [false, false]
	return was


## The authored console cut: its mesh without the bats and the live knob, and those as meshes of their own about
## their pivots (a bat's foot in its boot; a knob's middle on the face). {} if it has not got them.
static func cut(mesh: Mesh, side: float) -> Dictionary:
	var key := "%d/%d" % [mesh.get_instance_id(), int(side)]
	if _cut.has(key):
		return _cut[key]
	var out := {}
	if mesh.get_surface_count() != 1:
		return out
	var arr: Array = mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv = arr[Mesh.ARRAY_TEX_UV]
	var idx = arr[Mesh.ARRAY_INDEX]
	if uv == null or idx == null or (idx as PackedInt32Array).is_empty():
		return out
	var live := -1
	for n in KNOBS:
		if float(n[2]) == side:
			live = int(n[3])
	var keep := PackedInt32Array()
	var parts := {"lever0": [], "lever1": [], "lever2": [], "knob": []}      # (Arrays: a packed one taken out of a Dictionary may be a copy)
	for t in range(0, idx.size(), 3):
		var a: int = idx[t]
		var b: int = idx[t + 1]
		var c: int = idx[t + 2]
		var mid: Vector2 = ((uv[a] as Vector2) + (uv[b] as Vector2) + (uv[c] as Vector2)) / 3.0
		var z := (v[a].z + v[b].z + v[c].z) / 3.0
		var part := ""
		if LEVER_UV.has_point(mid):
			part = "lever%d" % clampi(roundi((z - TOGGLE_Z[0]) / (TOGGLE_Z[1] - TOGGLE_Z[0])), 0, 2)
		elif KNOB_UV.has_point(mid) and clampi(roundi((z - KNOB_Z[0]) / (KNOB_Z[1] - KNOB_Z[0])), 0, 1) == live:
			part = "knob"
		if part == "":
			keep.append(a)
			keep.append(b)
			keep.append(c)
		else:
			(parts[part] as Array).append_array([a, b, c])
	for p: String in parts:
		if (parts[p] as Array).is_empty():
			_cut[key] = out
			return out
	var material: Material = mesh.surface_get_material(0)
	var base_arr := arr.duplicate()
	base_arr[Mesh.ARRAY_INDEX] = keep
	var base := ArrayMesh.new()
	base.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, base_arr)
	base.surface_set_material(0, material)
	base.resource_name = mesh.resource_name
	out.base = base
	out.levers = []
	out.tris = []
	for k in 3:
		out.levers.append(_part(arr, PackedInt32Array(parts["lever%d" % k]), Vector3(CX * side, FACE_Y + 0.009, TOGGLE_Z[k]), material))
		out.tris.append((parts["lever%d" % k] as Array).size() / 3)
	out.knob = _part(arr, PackedInt32Array(parts.knob), Vector3(CX * side, FACE_Y, KNOB_Z[live]), material)
	out.tris.append((parts.knob as Array).size() / 3)
	out.all_tris = idx.size() / 3
	out.base_tris = keep.size() / 3
	_cut[key] = out
	return out


## The triangles `tris` of a surface's arrays as a mesh of their own, about `pivot`.
static func _part(arr: Array, tris: PackedInt32Array, pivot: Vector3, material: Material) -> ArrayMesh:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n = arr[Mesh.ARRAY_NORMAL]
	var tg = arr[Mesh.ARRAY_TANGENT]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var at := {}
	var nv := PackedVector3Array()
	var nn := PackedVector3Array()
	var nt := PackedFloat32Array()
	var nuv := PackedVector2Array()
	var ni := PackedInt32Array()
	for i in tris:
		if not at.has(i):
			at[i] = nv.size()
			nv.append(v[i] - pivot)
			nuv.append(uv[i])
			if n != null:
				nn.append((n as PackedVector3Array)[i])
			if tg != null:
				for j in 4:
					nt.append((tg as PackedFloat32Array)[i * 4 + j])
		ni.append(at[i])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = nv
	out[Mesh.ARRAY_TEX_UV] = nuv
	out[Mesh.ARRAY_INDEX] = ni
	if n != null:
		out[Mesh.ARRAY_NORMAL] = nn
	if tg != null:
		out[Mesh.ARRAY_TANGENT] = nt
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	m.surface_set_material(0, material)
	return m


## Build the switches on `interior` (vr/cockpit_interior.gd, after its build()): the bats and the live knobs cut out of
## the authored consoles (or, without them, built as the code-built consoles' were), the lenses and the legends.
func build(interior: Node3D) -> void:
	name = "ConsoleSwitches"
	var cuts := {}
	for side in [-1.0, 1.0]:
		var unit := interior.get_node_or_null("ConsoleL" if side < 0.0 else "ConsoleR") as MeshInstance3D
		var parts := {}
		if unit != null and unit.mesh != null:
			parts = cut(unit.mesh, side)
			if not parts.is_empty():
				unit.mesh = parts.base
			else:
				push_warning("ConsoleSwitches: the authored console has no bats to cut; they stay still")
		cuts[side] = parts
	var steel := Color(0.7, 0.73, 0.77)
	for i in TOGGLES.size():
		var side: float = TOGGLES[i][2]
		var k: int = TOGGLES[i][3]
		var at := toggle_at(i)
		var pivot := Node3D.new()
		pivot.name = "bat_" + String(TOGGLES[i][0])
		pivot.position = at + Vector3(0.0, 0.009, 0.0)
		add_child(pivot)
		var bat := MeshInstance3D.new()
		bat.name = "bat"
		var parts: Dictionary = cuts[side]
		if not parts.is_empty():
			bat.mesh = parts.levers[k]
			cut_tris.append(parts.tris[k])
		elif interior.get_node_or_null("ConsoleL" if side < 0.0 else "ConsoleR") == null:
			# the code-built console's bat (cockpit_interior.gd _toggle), about its foot
			bat.mesh = Kit.compound([[Kit.cyl(0.0035, 0.003, 0.027, 10), Kit.at(Vector3(0, 0.014, -0.003), Vector3(-THROW, 0, 0)), steel],
				[Kit.ball(0.0048, 8), Kit.at(Vector3(0, 0.027, -0.007)), steel]])
			bat.material_override = Finish.machined()
			cut_tris.append(0)
		else:
			cut_tris.append(-1)
		pivot.add_child(bat)
		levers.append(pivot)
		# its lens (the console's tiny inset status lens, beside it outboard) and its legend, both lit while it is ON
		var lens := MeshInstance3D.new()
		lens.name = "lens_" + String(TOGGLES[i][0])
		lens.mesh = Kit.cyl(0.0027, 0.0027, 0.0018, 10)
		lens.position = at + Vector3(0.042 * side, 0.0015, 0.0)
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lens.material_override = m
		add_child(lens)
		lenses.append(m)
		var l := Label3D.new()
		l.name = "legend_" + String(TOGGLES[i][0])
		l.text = String(TOGGLES[i][1])
		l.font_size = 40
		l.pixel_size = 0.00030
		l.modulate = LEGEND_OFF
		l.outline_size = 0
		l.shaded = true
		l.position = at + Vector3(0.0, 0.001, LEGEND_AFT)
		l.rotation.x = -PI / 2.0
		add_child(l)
		legends.append(l)
		_drawn.append([null, -1.0])
	for k in KNOBS.size():
		var side: float = KNOBS[k][2]
		var pivot := Node3D.new()
		pivot.name = "knob_" + String(KNOBS[k][0])
		pivot.position = Vector3(CX * side, FACE_Y, KNOB_Z[int(KNOBS[k][3])])
		add_child(pivot)
		var parts: Dictionary = cuts[side]
		if not parts.is_empty():
			var mi := MeshInstance3D.new()
			mi.name = "knob"
			mi.mesh = parts.knob
			pivot.add_child(mi)
			cut_tris.append(parts.tris[3])
		elif interior.get_node_or_null("ConsoleL" if side < 0.0 else "ConsoleR") == null:
			_code_knob(pivot)
			cut_tris.append(0)
		else:
			cut_tris.append(-1)
		knobs.append(pivot)
		set_knob(String(KNOBS[k][0]), 1.0)


## The code-built console's knob (cockpit_interior.gd _knob), about its middle on the face: its pointer forward.
func _code_knob(pivot: Node3D) -> void:
	for piece in [[[Finish.washer(0.013, 0.022, 0.002, 24), Kit.at(Vector3(0, 0.001, 0)), Color(0.38, 0.41, 0.44)],
			[Kit.cyl(0.014, 0.015, 0.002, 24), Kit.at(Vector3(0, 0.0265, 0)), Color(0.45, 0.48, 0.51)], Finish.machined()],
			[[Finish.knurled_knob(0.018, 0.023), Kit.at(Vector3(0, 0.014, 0)), Color(0.08, 0.09, 0.10)], null, Finish.rubber()],
			[[Kit.box(Vector3(0.0022, 0.0005, 0.009)), Kit.at(Vector3(0, 0.0277, -0.006)), Color(0.88, 0.86, 0.72)], null, Finish.painted_metal()]]:
		var mi := MeshInstance3D.new()
		mi.mesh = Kit.compound([piece[0]] + ([piece[1]] if piece[1] != null else []))
		mi.material_override = piece[2]
		pivot.add_child(mi)
	pivot.set_meta(&"pointer_ahead", true)


## Is a tip (this node's metres) at another control's working spot: the SLIDE and MODE switches' bats (keep_out), the
## drift slider's knob?
func kept_out(tip: Vector3) -> bool:
	for spot: Array in keep_out:
		if tip.distance_to(spot[0]) < float(spot[1]):
			return true
	return slider != null and is_instance_valid(slider) and tip.distance_to(to_local(slider.global_transform * (slider.cap_at() as Vector3))) < KEEP_OUT_R


## Which bat a tip (this node's metres) is at: the toggle's index, -1 none (nor one where a tip is another control's).
func bat_at(tip: Vector3) -> int:
	for i in TOGGLES.size():
		var d := tip - toggle_at(i)
		if absf(d.x) < ZONE.x and d.y > ZONE_FOOT and d.y < ZONE.y and absf(d.z) < ZONE.z:
			return -1 if kept_out(tip) else i
	return -1


## Is a tip in the air over a console's bats (AIR), and not at another control's spot?
func over_bats(tip: Vector3) -> bool:
	var dy := tip.y - FACE_Y
	if absf(absf(tip.x) - CX) < AIR.x and dy > ZONE_FOOT and dy < AIR.y and tip.z > AIR_Z.x and tip.z < AIR_Z.y:
		return not kept_out(tip)
	return false


## Does the console have this hand: it has a bat or a knob, its tip is in the air over the bats, or it had a bat or a
## knob under CLAIM_S ago, or under CLAIM_MAX ago and has not settled since? (Then the cockpit's other controls let it
## pass.)
func claims(ctrl: Node3D) -> bool:
	var h: Dictionary = _h.get(ctrl, {})
	if h.is_empty():
		return false
	var away := float(h.away)
	return int(h.has) >= 0 or int(h.knob) >= 0 or bool(h.over) or away < CLAIM_S or (away < CLAIM_MAX and float(h.still) < SETTLE_S)


## A controller at the consoles, a frame: see the head of this file. `busy`: it has just worked another control (or
## holds one), and is given no bat or knob.
func poke(ctrl: Node3D, delta: float, busy := false) -> String:
	var g: Transform3D = global_transform.affine_inverse() * ctrl.global_transform
	var tip: Vector3 = g * TIP
	var h: Dictionary = _h.get(ctrl, {})
	if h.is_empty():
		_h[ctrl] = {"tip": tip, "basis": g.basis, "rest": 0.0, "has": -1, "spent": -1, "away": CLAIM_MAX, "still": SETTLE_S, "over": over_bats(tip),
			"knob": -1, "krest": 0.0}
		return ""
	var was: Vector3 = h.tip
	var was_basis: Basis = h.basis
	h.tip = tip
	h.basis = g.basis
	h.away = float(h.away) + delta
	h.over = over_bats(tip)
	if delta <= 0.0:
		return ""
	var vel := (tip - was) / delta
	var speed := vel.length()
	h.still = float(h.still) + delta if speed < HOLD_V else 0.0
	if int(h.knob) >= 0:
		return _turn(ctrl, h, tip, was_basis, g.basis, speed)
	if speed > JUMP_V:          # (a tracking jump: whatever it had, it has not now)
		h.has = -1
		h.rest = 0.0
		h.krest = 0.0
		return ""
	var at := bat_at(tip)
	if at != int(h.spent):
		h.spent = -1
	if at < 0:
		h.has = -1
		h.rest = 0.0
		return _take_knob(ctrl, h, tip, speed, delta, busy)
	h.krest = 0.0
	if busy or at == int(h.spent):
		h.has = -1
		h.rest = 0.0
		return ""
	if int(h.has) == at:
		h.away = 0.0
		var on: bool = shown[at]
		if (on and vel.z > THROW_V) or (not on and vel.z < -THROW_V):
			h.has = -1
			h.spent = at
			h.rest = 0.0
			return ("off:" if on else "on:") + String(TOGGLES[at][0])
		return ""
	h.has = -1
	h.rest = float(h.rest) + delta if speed < REST_V else 0.0
	if float(h.rest) >= REST_S:
		h.has = at
		h.rest = 0.0
		h.away = 0.0
		return "rest"
	return ""


## A tip not at a bat: at rest on a knob's cap long enough, it has it.
func _take_knob(ctrl: Node3D, h: Dictionary, tip: Vector3, speed: float, delta: float, busy: bool) -> String:
	for k in KNOBS.size():
		if tip.distance_to(knob_cap(k)) < HOLD_R:
			if knob_held[k] != null or busy or speed >= HOLD_V:
				h.krest = 0.0
				return ""
			h.krest = float(h.krest) + delta
			if float(h.krest) >= HOLD_S:
				h.krest = 0.0
				h.knob = k
				h.away = 0.0
				knob_held[k] = ctrl
				_raw[k] = knob_angle[k]
				_ticked[k] = knob_angle[k]
				return "held"
			return ""
	h.krest = 0.0
	return ""


## A held knob, a frame: let go if the tip has gone from it; else turned by the wrist's roll since the last frame.
func _turn(ctrl: Node3D, h: Dictionary, tip: Vector3, was_basis: Basis, basis: Basis, speed: float) -> String:
	var k: int = h.knob
	h.away = 0.0
	if tip.distance_to(knob_cap(k)) > KEEP_R:
		h.knob = -1
		knob_held[k] = null
		return "let_go"
	var dq := Quaternion((was_basis.inverse() * basis).orthonormalized())
	var roll := wrapf(2.0 * atan2(dq.z, dq.w), -PI, PI)      # about the controller's own pointing line (its z)
	if absf(roll) > TWIST_JUMP or speed > JUMP_V:          # (a tracking jump: the knob stays)
		return ""
	# clockwise as the hand sees it, looking along its pointing line, is a turn about its -z: a negative roll
	_raw[k] = clampf(float(_raw[k]) - roll * GAIN, -STOP - DETENT, STOP + DETENT)
	return _turn_to(k, _raw[k])


## A knob turned to angle a by hand: what that did ("" nothing).
func _turn_to(k: int, a: float) -> String:
	var key: String = KNOBS[k][0]
	var detent := angle_for(key, 1.0)
	var to := clampf(a, -STOP, STOP)
	if absf(to - detent) < DETENT:
		to = detent
	var marked := to == detent or absf(to) == STOP
	var now: float = knob_angle[k]
	if to == now or (not marked and absf(to - now) < STILL):
		return ""
	var did := "moved"
	if to == detent:
		did = "notch"
	elif absf(to) == STOP:
		did = "end"
	elif absf(to - float(_ticked[k])) >= TICK:
		did = "tick"
	if did != "moved":
		_ticked[k] = to
	knob_angle[k] = to
	_changed[k] = true
	return did


## Let go of everything (the hands gone, the menu opened), and forget where the hands were.
func let_go() -> void:
	knob_held = [null, null]
	_h.clear()


## Each frame: the bats lean as the settings stand (`states`, {key: on}), the lenses and the legends lit for the ON
## ones at the battery's level (`power`, 0 dead .. 1), the knobs' pointers where they are.
func show_state(states: Dictionary, power: float, delta: float) -> void:
	var follow := 1.0 if _first else 1.0 - exp(-maxf(delta, 0.0) * 25.0)
	_first = false
	for i in TOGGLES.size():
		var on := bool(states.get(TOGGLES[i][0], false))
		shown[i] = on
		_swing[i] = lerpf(_swing[i], 0.0 if on else 2.0 * THROW, follow)
		levers[i].rotation.x = _swing[i]
		var drawn: Array = _drawn[i]
		if drawn[0] == on and absf(float(drawn[1]) - power) < 0.02:
			continue
		_drawn[i] = [on, power]
		var colour: Color = LENS[int(TOGGLES[i][3])]
		lenses[i].albedo_color = colour * ((0.4 + 2.0 * power) if on else 0.12 + 0.1 * power)
		lenses[i].albedo_color.a = 1.0
		var lit := on and power > 0.05
		legends[i].shaded = not lit
		legends[i].modulate = colour.lightened(0.2) * (0.6 + 1.0 * power) if lit else LEGEND_OFF      # (more of the lens's colour: a paler green was hard to tell from the unlit grey by day)
		legends[i].modulate.a = 1.0
	for k in KNOBS.size():
		# the authored knob's pointer is painted inboard (tools/art_console_hd.py paint_small: down its girth's middle,
		# the vertices at -x round the right console's knobs): a quarter turn from straight ahead, anticlockwise on the
		# right console and clockwise on the left (it is the mirror)
		var painted: float = 0.0 if knobs[k].has_meta(&"pointer_ahead") else -PI / 2.0 * float(KNOBS[k][2])
		knobs[k].rotation.y = -(float(knob_angle[k]) - painted)
