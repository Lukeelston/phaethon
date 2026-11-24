## The drift slider (Luke, 2026-11-23, from the seat: "add a physical slider or knob in the cockpit to adjust
## the amount of drift in real time"): how far the cockpit steps out in a turn (vr_cockpit.gd's slide), from
## none to half as much again as it did before there was a slider. A fader in a low rail on the left
## console's inboard shoulder, behind the SLIDE / GRIP switch and beside the pilot's left thigh, its face
## turned up toward the seated eye. The switch is still the quick on and off; this is how much.
##   which way    forward is more, as a throttle is. Read from the seat the slot runs left to right: OFF at
##                the aft end, MAX at the forward one, and over it a ramp that grows toward MAX and is lit as
##                far as the knob stands (dark while the switch is at GRIP).
##   the notch    at STANDARD, the amount the cockpit had before the slider: the knob falls into it from
##                NOTCH either side and the amount there is exactly 1, so "as it was" can be found by feel.
##   by hand      a controller's tip rested on the knob takes hold of it (a tick in that hand), and then the
##                knob goes fore and aft with the hand, with a tick for every DETENT it is moved (counted
##                from the last tick, so a knob held on a line does not chatter), a firmer one into the
##                notch and at either end. Lifting the hand off the rail lets it go. Neither a trigger nor
##                a grip is used: both are the craft's own.
##   not by accident    it is taken only by a tip that has all but stopped within HOLD_R of the knob for HOLD_S
##                (a hand going by, or reaching slowly past, does neither), it is out of the box where a hand
##                throws the SLIDE switch, and the levers' grips pass it by more than 5 cm
##                (tests/test_drift_slider.gd, tests/test_cockpit_clash.gd).
## Why a slider and not a knob: a knob is turned by rolling the wrist while the hand stays on it, and in the
## trigger scheme that hand is holding a throttle; a fader is pushed with the hand as it is, and where its
## knob stands is the amount, read at a glance or found by the notch.
## Panel-local: x along the slot (+ is more: the cockpit's forward), y up the face as the pilot reads it, z
## out of the face.
##   const DriftSlider := preload("res://vr/drift_slider.gd")
##   var s := DriftSlider.new(); shell.add_child(s); s.transform = DriftSlider.mount(); s.build()
##   var did := s.poke(controller, delta)        per hand per frame: "", "held", "moved", "tick", "notch", "end", "let_go"
##   s.amount                                    0 .. AMOUNT_MAX (STANDARD in the notch)
##   s.show_state(lit, power)                    each frame
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")
const Finish := preload("res://view/craft_materials.gd")
const AMOUNT_MAX := 2.5        # the most: two and a half times what the cockpit stepped out before the slider (1.5 as it first
                               # flew; Luke, 2026-11-23, with it at the stop: "the slider's max should be more I think")
const STANDARD := 1.0          # ... which is this
const TRAVEL := 0.12           # m of slot from none to AMOUNT_MAX
const NOTCH := AMOUNT_MAX * 0.004 / TRAVEL      # the knob falls into the notch from this near it (of the amount: 4 mm of the slot)
const DETENT := AMOUNT_MAX * 0.01 / TRAVEL      # a tick in the hand for every this much it is moved (a centimetre of the slot)
const STILL := 0.0005          # less of a change than this is the hand's own tremor, not a move (0.04 mm of the slot)
const HOLD_R := 0.045          # m: a tip this near the knob's cap ...
const HOLD_S := 0.15           # ... for this long ...
const HOLD_V := 0.2            # ... and moving no faster than this (m/s) has taken hold of it: it has stopped there
const KEEP_R := 0.075          # held, it is let go when the tip is this far off the slot's line ...
const KEEP_END := 0.05         # ... or this far past either end of it
const JUMP_V := 4.0            # m/s: faster is a tracking jump, not a hand (ModeSwitch's own figure)
const TIP := Vector3(0.0, -0.01, -0.07)      # the controller's tip, in its own frame (ModeSwitch.TIP)
const FACE := Vector2(0.176, 0.04)           # the rail's face: along the slot, across it
const TILT := deg_to_rad(32.0)               # the face turned this far inboard of lying flat: toward the seated eye
const AT := Vector3(-0.56105, 0.3898, 0.48)  # the face's middle, cockpit metres: on the port console's inboard shoulder (aft of
                                             # the SLIDE switch's box, where the lever's grip at idle does not stand before its MAX
                                             # end, and 2.5 mm over the inboard edge of the console's own faceplate, which it covers)
const FOOT := 0.036            # the rail's outboard wall, down from the face's upper edge into the console's top
const LIP := 0.011             # ... and its inboard edge, down from the face's lower edge
const CAP := Vector3(0.012, 0.026, 0.014)    # the knob's cap: along the slot, across it, tall
const CAP_Z := 0.016           # its middle, out from the face
const AMBER := Color(1.0, 0.62, 0.15)        # the SLIDE lamp's colour (vr_cockpit.gd)
const LEGENDS := ["OFF", "DRIFT", "MAX"]

const RAMP_SHADER := """
// The drift slider's ramp (vr/drift_slider.gd): lit as far along as the knob stands.
shader_type spatial;
render_mode unshaded, shadows_disabled;
uniform float level = 0.667;
uniform vec3 colour : source_color = vec3(1.0, 0.62, 0.15);
uniform float glow = 1.0;       // the lit part: the battery's level, none while the switch is at GRIP
uniform float rest = 0.2;       // the rest of it, and all of it unlit
void fragment() {
	ALBEDO = colour * mix(rest, 2.0, glow * (1.0 - step(level, UV.x)));
}
"""

var amount := STANDARD         # 0 .. AMOUNT_MAX
var held_by: Node3D = null     # the controller that has the knob
var knob: Node3D
var ramp: ShaderMaterial
var changed := false           # moved since it was last asked (take_changed)
var _tips := {}                # controller -> [its tip (panel metres), how long it has rested on the knob (s)]
var _grab := 0.0               # held: the tip's place along the slot less the knob's, as it took hold
var _ticked := STANDARD        # ... and the amount at that hand's last tick


## Where the rail sits in the cockpit (floor origin, forward -Z): along the port console's inboard
## shoulder, its slot fore and aft, its face tilted up at the pilot.
static func mount() -> Transform3D:
	var c := cos(TILT)
	var s := sin(TILT)
	return Transform3D(Basis(Vector3(0.0, 0.0, -1.0), Vector3(-c, s, 0.0), Vector3(s, c, 0.0)), AT)


## Where the knob stands along the slot for an amount, panel metres.
static func place(a: float) -> float:
	return TRAVEL * (clampf(a, 0.0, AMOUNT_MAX) / AMOUNT_MAX - 0.5)


## ... and the amount a place along the slot is: inside the travel, and exactly STANDARD in the notch.
static func amount_at(x: float) -> float:
	var a := clampf((x / TRAVEL + 0.5) * AMOUNT_MAX, 0.0, AMOUNT_MAX)
	return STANDARD if absf(a - STANDARD) < NOTCH else a


## The middle of the knob's cap now, panel metres: what a hand reaches for.
func cap_at() -> Vector3:
	return Vector3(place(amount), 0.0, CAP_Z)


## A bar of a constant section (y up the face, z out of it), from -half to half along the slot.
static func _bar(section: PackedVector2Array, half: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := section.size()
	var mid := Vector2.ZERO
	for p in section:
		mid += p / float(n)
	for i in n:
		var a := section[i]
		var b := section[(i + 1) % n]
		var out := (a + b) * 0.5 - mid
		Finish._quad(st, Vector3(-half, a.x, a.y), Vector3(half, a.x, a.y), Vector3(half, b.x, b.y), Vector3(-half, b.x, b.y), Vector3(0.0, out.x, out.y))
	for s in [-1.0, 1.0]:
		for i in range(1, n - 1):
			Finish._triangle(st, Vector3(s * half, section[0].x, section[0].y), Vector3(s * half, section[i].x, section[i].y),
				Vector3(s * half, section[i + 1].x, section[i + 1].y), Vector3(s, 0.0, 0.0))
	return st.commit()


## The ramp over the slot: a strip that grows from a line at OFF to RAMP_TALL at MAX, its UV.x the
## share of the travel.
static func _ramp_mesh(y0: float, low: float, tall: float, z: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(-TRAVEL * 0.5, y0, z)
	var b := Vector3(TRAVEL * 0.5, y0, z)
	var c := Vector3(TRAVEL * 0.5, y0 + tall, z)
	var d := Vector3(-TRAVEL * 0.5, y0 + low, z)
	for tri in [[a, b, c], [a, c, d]]:
		# (Godot's fronts wind clockwise: seen from +z, out of the face)
		var flip: bool = ((tri[1] as Vector3) - (tri[0] as Vector3)).cross((tri[2] as Vector3) - (tri[0] as Vector3)).z > 0.0
		for p: Vector3 in ([tri[0], tri[2], tri[1]] if flip else tri):
			st.set_normal(Vector3(0.0, 0.0, 1.0))
			st.set_uv(Vector2(p.x / TRAVEL + 0.5, 0.0))
			st.add_vertex(p)
	return st.commit()


func build() -> void:
	name = "DriftSlider"
	var turn := Vector3(PI / 2.0, 0.0, 0.0)      # (a plate's thickness out of the face)
	var half := FACE.y * 0.5
	# the rail: its face, an inboard lip under the face's lower edge, and an outboard wall straight down
	# into the console's top (the cockpit's down, as the face lies TILT over)
	var section := PackedVector2Array([Vector2(half, 0.0), Vector2(-half, 0.0), Vector2(-half, -LIP),
		Vector2(half - FOOT * sin(TILT), -FOOT * cos(TILT))])
	var body := MeshInstance3D.new()
	body.name = "rail"
	body.mesh = Kit.compound([
		[_bar(section, FACE.x * 0.5), Transform3D.IDENTITY, Color(0.105, 0.12, 0.14)],
		[Finish.beveled_plate(Vector3(FACE.x - 0.008, 0.003, FACE.y - 0.006), 0.001), Kit.at(Vector3(0.0, 0.0, 0.001), turn), Color(0.04, 0.052, 0.065)],
		[Kit.box(Vector3(TRAVEL + 0.01, 0.005, 0.0004)), Kit.at(Vector3(0.0, 0.0, 0.0027)), Color(0.008, 0.01, 0.012)]])      # the slot
	body.material_override = Finish.powder_coat()
	add_child(body)
	var marks := []
	for k in int(round(AMOUNT_MAX / 0.5)) + 1:      # a mark at each half: none, a half, STANDARD (the notch: longer, both sides of the slot), and on to the most
		var a := 0.5 * k
		var notch := is_equal_approx(a, STANDARD)
		marks.append([Kit.box(Vector3(0.0022 if notch else 0.0012, 0.011 if notch else 0.004, 0.0006)),
			Kit.at(Vector3(place(a), 0.0 if notch else -0.0052, 0.0029)), Color(0.9, 0.9, 0.84)])
	var hardware := [[Finish.slotted_screw(0.0028), Kit.at(Vector3(-FACE.x * 0.5 + 0.009, 0.0, 0.0028), turn), Color(0.55, 0.58, 0.62)],
		[Finish.slotted_screw(0.0028), Kit.at(Vector3(FACE.x * 0.5 - 0.009, 0.0, 0.0028), turn), Color(0.55, 0.58, 0.62)]]
	var paint := MeshInstance3D.new()
	paint.name = "marks"
	paint.mesh = Kit.compound(marks)
	paint.material_override = Finish.painted_metal()
	add_child(paint)
	var screws := MeshInstance3D.new()
	screws.name = "screws"
	screws.mesh = Kit.compound(hardware)
	screws.material_override = Finish.machined()
	add_child(screws)
	# the ramp: which way is more, and how much there is
	var sh := Shader.new()
	sh.code = RAMP_SHADER
	ramp = ShaderMaterial.new()
	ramp.shader = sh
	ramp.set_shader_parameter("colour", AMBER)
	var wedge := MeshInstance3D.new()
	wedge.name = "ramp"
	wedge.mesh = _ramp_mesh(0.0058, 0.0012, 0.0098, 0.0029)
	wedge.material_override = ramp
	wedge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wedge)
	# the knob: a stem up through the slot and a cap across it, a white line along its crown
	knob = Node3D.new()
	knob.name = "knob"
	add_child(knob)
	var cap := MeshInstance3D.new()
	cap.name = "cap"
	cap.mesh = Kit.compound([
		[Kit.box(Vector3(0.004, 0.0036, CAP_Z - CAP.z * 0.5)), Kit.at(Vector3(0.0, 0.0, 0.003 + (CAP_Z - CAP.z * 0.5) * 0.5)), Color(0.5, 0.53, 0.57)],
		[Kit.rounded_box(CAP, 5.0, 8), Kit.at(Vector3(0.0, 0.0, CAP_Z)), Color(0.82, 0.84, 0.88)]])
	cap.material_override = Finish.machined()
	knob.add_child(cap)
	var line := MeshInstance3D.new()
	line.name = "index"
	line.mesh = Kit.compound([[Kit.box(Vector3(0.0016, CAP.y * 0.8, 0.0008)), Kit.at(Vector3(0.0, 0.0, CAP_Z + CAP.z * 0.5)), Color(0.96, 0.95, 0.9)]])
	line.material_override = Finish.painted_metal()
	knob.add_child(line)
	# the legends, under the slot as the pilot reads it: OFF at the aft end, MAX at the forward one
	var places := [place(0.0), -0.014, place(AMOUNT_MAX)]
	for k in LEGENDS.size():
		var l := Label3D.new()
		l.name = "legend_%s" % String(LEGENDS[k]).to_lower()
		l.text = LEGENDS[k]
		l.font_size = 36
		l.pixel_size = 0.00027
		l.modulate = Color(0.82, 0.83, 0.76)
		l.outline_size = 0
		l.shaded = true
		l.position = Vector3(places[k], -0.0128, 0.0032)
		add_child(l)
	show_state(true, 1.0)


## A controller at the slider, a frame: "held" as its tip takes hold of the knob; while it has it,
## "moved" when the amount changed, or in place of that "tick" as it crosses a detent, "notch" as it falls
## into STANDARD and "end" as it reaches either end; "let_go" as the hand leaves the rail; else "".
## `blocked`: the hand is another control's this frame (vr/console_switches.gd has it): it takes nothing (a hand
## that already has the knob keeps it).
func poke(ctrl: Node3D, delta: float, blocked := false) -> String:
	var tip: Vector3 = global_transform.orthonormalized().affine_inverse() * (ctrl.global_transform * TIP)
	if blocked and held_by != ctrl:
		_tips[ctrl] = [tip, 0.0]
		return ""
	var was: Variant = _tips.get(ctrl)
	var rested: float = 0.0 if was == null else float((was as Array)[1])
	var speed: float = INF if was == null or delta <= 0.0 else tip.distance_to((was as Array)[0]) / delta
	var did := ""
	if held_by == ctrl:
		var off := Vector2(tip.y, tip.z - CAP_Z).length()
		if off > KEEP_R or absf(tip.x) > TRAVEL * 0.5 + KEEP_END:
			held_by = null
			rested = 0.0
			did = "let_go"
		elif speed > JUMP_V:
			_grab = tip.x - place(amount)      # (a tracking jump: the knob stays, and is held from where the tip is now)
		else:
			did = _move_to(tip.x - _grab)
	elif held_by == null:
		rested = rested + delta if tip.distance_to(cap_at()) < HOLD_R and speed < HOLD_V else 0.0
		if rested >= HOLD_S:
			held_by = ctrl
			_grab = tip.x - place(amount)
			_ticked = amount
			rested = 0.0
			did = "held"
	_tips[ctrl] = [tip, rested]
	return did


## The knob taken to a place along the slot: what that did ("" nothing).
func _move_to(x: float) -> String:
	var to := amount_at(x)
	var marked := to == STANDARD or to == 0.0 or to == AMOUNT_MAX      # (the notch and the ends are exact, and always taken)
	if to == amount or (not marked and absf(to - amount) < STILL):
		return ""
	var did := "moved"
	if to == STANDARD:
		did = "notch"
	elif to == 0.0 or to == AMOUNT_MAX:
		did = "end"
	elif absf(to - _ticked) >= DETENT:
		did = "tick"
	if did != "moved":
		_ticked = to
	amount = to
	changed = true
	return did


## Let go of it, whoever has it (the hands gone, the menu opened), and forget where they were.
func let_go() -> void:
	held_by = null
	_tips.clear()


## Has it been moved since this was last asked?
func take_changed() -> bool:
	var was := changed
	changed = false
	return was


## Each frame: the knob where the amount is, the ramp lit up to it (`lit`: the SLIDE switch is up) at the
## battery's level.
func show_state(lit: bool, power: float) -> void:
	if knob:
		knob.position.x = place(amount)
	if ramp:
		ramp.set_shader_parameter("level", amount / AMOUNT_MAX)
		ramp.set_shader_parameter("glow", power if lit else 0.0)
		ramp.set_shader_parameter("rest", 0.05 + 0.15 * power)
