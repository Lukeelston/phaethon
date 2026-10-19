## The cockpit's instrument panel: a real panel under the cowl line with the readouts on its
## face, not text floating in the air. Big speed in the middle (mph), Mach and
## seconds per mile, the run line across the top; per engine THR / BRK / HEAT / HP bar gauges
## (a tick on THR marks the burner gate; HP is wall damage, which costs thrust and makes the
## engine sputter), a battery bar, BURNER / ARMED / RAMJET lamps, FLAMEOUT and DAMAGED warnings
## with the repair hint; handling and control scheme along the bottom. The panel is curved: wrapped on an
## arc centred on the pilot's eye (every readout the same distance away), and sized so the
## whole thing sits inside the cockpit opening, clear of the hull skin and the lip
## (tests/test_dashboard.gd checks every corner against the hull). Panel-local: x along the
## arc, y up, the face looks down +z at the pilot.
##   add_child(dash); dash.transform = Dashboard.mount(); dash.build()    once
##   dash.show_state(d)                                     every frame (keys: see show_state)
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")

const R := 1.32                     # arc radius: about the eye's distance
const W := 0.84                     # face width, measured along the arc
const H := 0.28
const D := 0.05
const FACE := D / 2.0 + 0.006       # labels and gauges sit just proud of the face
const PX := 0.0009                  # Label3D pixel size on the panel
const BAR_H := 0.17
const BAR_Y0 := -0.085              # bar bottoms
const GATE := 0.88
const AMBER := Color(1.0, 0.72, 0.38)
const GREEN := Color(0.35, 0.92, 0.45)
const ORANGE := Color(1.0, 0.55, 0.15)
const RED := Color(1.0, 0.22, 0.15)
const CYAN := Color(0.45, 0.88, 1.0)
const DIM := Color(0.28, 0.26, 0.24)
const DAMAGED := 0.6     # engine health below this: warn and show the repair hint
const BADLY := 0.3       # ... below this it's sputtering hard: blink red

var labels := {}
var bars := {}      # name -> [fill MeshInstance3D, material]
var lamps := {}     # name -> [Label3D, on colour]


## Where the panel sits in the cockpit rig (floor origin, forward -Z): below the eye line,
## tilted to face the seat, inside the front of the cockpit opening.
static func mount() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, -0.29), Vector3(0, 0.27, -0.70))   # down with the lower seat


func build() -> void:
	_curved(Kit.rounded_box(Vector3(W + 0.06, H + 0.05, D + 0.01), 7.0, 48), Vector3(0, 0, -0.005), Color(0.10, 0.10, 0.11)).name = "housing"
	_curved(Kit.rounded_box(Vector3(W - 0.14, 0.03, 0.12), 5.0, 48), Vector3(0, H / 2.0 + 0.025, 0.04), Color(0.08, 0.08, 0.09)).name = "hood"   # shorter than the panel: its ends would reach the lip
	var face := BoxMesh.new()
	face.size = Vector3(W, H, 0.004)
	face.subdivide_width = 32
	_curved(face, Vector3(0, 0, D / 2.0 + 0.002), Color(0.04, 0.045, 0.05)).name = "face"
	# centre stack: wide labels stand a little proud so their flat ends clear the curve
	var proud := FACE + 0.03
	_label("progress", Vector2(0, 0.128), 20, AMBER, VERTICAL_ALIGNMENT_TOP, proud)
	_label("speed", Vector2(0, 0.03), 104, Color(0.95, 0.97, 1.0), VERTICAL_ALIGNMENT_CENTER, proud)
	_label("units", Vector2(0, -0.03), 22, Color(0.7, 0.74, 0.78), VERTICAL_ALIGNMENT_CENTER, proud)
	_label("mach", Vector2(0, -0.066), 26, CYAN, VERTICAL_ALIGNMENT_CENTER, proud)
	_label("footer", Vector2(0, -0.11), 17, Color(0.55, 0.55, 0.52), VERTICAL_ALIGNMENT_CENTER, proud)
	for side in ["L", "R"]:
		var s := -1.0 if side == "L" else 1.0
		_label("head" + side, Vector2(0.36 * s, 0.112), 19, Color(0.8, 0.8, 0.78))
		# outboard to inboard: THR, BRK, HEAT, HP (engine health)
		for i in 4:
			var name: String = ["thr", "brk", "heat", "hp"][i] + side
			var x: float = s * (0.41 - 0.035 * i)
			_bar(name, x)
			var tag := _label(name + "_lbl", Vector2(x, -0.11), 13, Color(0.6, 0.6, 0.58))
			tag.text = ["THR", "BRK", "HT", "HP"][i]
		# burner gate tick on THR
		_flat(Vector3(0.036, 0.003, 0.006), Vector2(s * 0.41, BAR_Y0 + BAR_H * GATE), FACE + 0.002, Color(0.9, 0.9, 0.9), true)
	_bar("bat", 0.245)
	var bat_tag := _label("bat_lbl", Vector2(0.245, -0.11), 13, Color(0.6, 0.6, 0.58))
	bat_tag.text = "BAT"
	_lamp("burner", "BURNER", Vector2(-0.24, 0.05), ORANGE)
	_lamp("armed", "ARMED", Vector2(-0.24, 0.0), Color(1.0, 0.9, 0.3))
	_lamp("ramjet", "RAMJET", Vector2(-0.24, -0.05), RED)
	_label("warn", Vector2(0, 0.088), 17, AMBER, VERTICAL_ALIGNMENT_CENTER, proud)   # the repair hint


## A mesh wrapped onto the panel's arc (offset = its place on the flat layout).
func _curved(mesh: Mesh, offset: Vector3, c: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = Kit.bend(mesh, offset, R)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 0.5
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m


## A small flat box set onto the arc at (x, y), d toward the pilot, facing the eye.
func _flat(size: Vector3, at: Vector2, d: float, c: Color, unshaded := false) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	m.transform = Kit.on_arc(at.x, at.y, d, R)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m


func _label(name: String, at: Vector2, size: int, c: Color, valign := VERTICAL_ALIGNMENT_CENTER, d := FACE) -> Label3D:
	var l := Label3D.new()
	l.pixel_size = PX
	l.font_size = size
	l.outline_size = 0
	l.modulate = c
	l.vertical_alignment = valign
	l.double_sided = false
	l.transform = Kit.on_arc(at.x, at.y, d, R)
	add_child(l)
	labels[name] = l
	return l


func _bar(name: String, x: float) -> void:
	_flat(Vector3(0.03, BAR_H + 0.006, 0.004), Vector2(x, BAR_Y0 + BAR_H / 2.0), FACE - 0.003, Color(0.12, 0.12, 0.13))   # slot
	var fill := _flat(Vector3(0.022, BAR_H, 0.005), Vector2(x, BAR_Y0), FACE, GREEN, true)
	bars[name] = [fill, fill.material_override]


func _lamp(name: String, text: String, at: Vector2, on: Color) -> void:
	var l := _label(name, at, 19, DIM)
	l.text = text
	lamps[name] = [l, on]


func _set_bar(name: String, v: float, c: Color) -> void:
	var b: Array = bars[name]
	var f: MeshInstance3D = b[0]
	v = clampf(v, 0.0, 1.0)
	f.visible = v > 0.002
	f.scale.y = maxf(v, 0.002)
	f.position.y = BAR_Y0 + BAR_H * v / 2.0
	(b[1] as StandardMaterial3D).albedo_color = c


static func heat_col(h: float) -> Color:
	return GREEN.lerp(AMBER, clampf(h / 0.6, 0.0, 1.0)) if h < 0.6 else AMBER.lerp(RED, clampf((h - 0.6) / 0.35, 0.0, 1.0))


static func _grouped(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## d: mph, kmh (float); mach_line, progress, footer (String); thr, brk, heat, health, flameout
## ([left, right]); battery (0..1); burner, armed, ramjet (bool); blink (bool: warning phase).
func show_state(d: Dictionary) -> void:
	labels.speed.text = _grouped(int(round(d.mph)))
	labels.units.text = "MPH"   # imperial only (Luke: "make sure everything is in imperial")
	labels.mach.text = d.mach_line
	labels.progress.text = d.progress
	labels.footer.text = d.footer
	for k in 2:
		var side := "L" if k == 0 else "R"
		var thr: float = d.thr[k]
		_set_bar("thr" + side, thr, ORANGE if thr >= GATE else GREEN)
		_set_bar("brk" + side, d.brk[k], RED)
		_set_bar("heat" + side, minf(d.heat[k], 1.0), heat_col(d.heat[k]))
		var hp: float = d.health[k]
		_set_bar("hp" + side, hp, heat_col(1.0 - hp))
		var head: Label3D = labels["head" + side]
		if d.flameout[k]:
			head.text = "%s FLAMEOUT" % side
			head.modulate = RED if d.blink else DIM
		elif hp < DAMAGED:
			head.text = "%s DAMAGED" % side
			head.modulate = (RED if d.blink else DIM) if hp < BADLY else AMBER
		else:
			head.text = side
			head.modulate = Color(0.8, 0.8, 0.78)
	var hurt := []
	for k in 2:
		if d.health[k] < DAMAGED:
			hurt.append("L" if k == 0 else "R")
	labels.warn.text = "" if hurt.is_empty() else "HOLD X: REPAIR %s" % "+".join(hurt)
	labels.warn.modulate = RED if minf(d.health[0], d.health[1]) < BADLY else AMBER
	_set_bar("bat", d.battery, CYAN if d.battery > 0.2 else RED)
	for name in ["burner", "armed", "ramjet"]:
		var l: Label3D = lamps[name][0]
		l.modulate = lamps[name][1] if d[name] else DIM
