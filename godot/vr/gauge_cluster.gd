## The cockpit's instrument cluster (Luke: "illuminated physical analogue gauges and a digital
## Speedo readout ... cylindrical tubes with a convex glass cover, and racing inspired faces"):
## five tubes under a stitched cowl where the flat panel was. vr/dashboard.gd is still the
## fallback, and this keeps its mount, its show_state() and its labels. The mount is up under the
## cockpit's rim, and the binnacle stands on the dashboard's fascia (vr/cockpit_interior.gd HD_DASH).
##   centre    Mach on the dial; in its face the digital speed (mph) and the gear, ARMED,
##             RAMJET and TURBINES legends (TURBINES: green while the second stage runs), and
##             the battery as a lit arc round the foot; and right of the hub the g-meter, a
##             sub-dial with a needle of its own and a tell-tale (Luke: "a g-force meter ... a real
##             instrument, not just a number"): see G_FULL, below
##   inboard   a thrust dial per engine, orange past the burner gate; BURNER and FLAMEOUT
##             legends; that engine's health as a lit arc (amber when damaged, blinking red
##             when it is sputtering)
##   outboard  heat over air brake per engine, two needles on one hub; a HOT legend
##   below     two LCD strips: the run line and the repair hint on the left, the Mach / mile
##             line with the handling and controls on the right; and between them the points
##             counter, a row of drums that roll up as points are earned (Luke: "points on an
##             odometer roller, with a digital readout next to it of the feat"). The feat is
##             read on the right strip's lower line for a few seconds, in place of the handling.
##             The left strip's lower line, free in flight, carries the g-meter's figure, its slip
##             bar and the peak (they give way to the repair hint and to a run line of two lines)
## The binnacle is authored (tools/art_gauges_hd.py). The dials are one textured mesh
## (tools/art_gauge_faces.py), the glass another, and the needles share a third. Nothing is
## rebuilt, and a frame only touches what changed: a needle's transform, a lamp, the speed.
##   add_child(c); c.transform = GaugeCluster.mount(); c.build()     once
##   c.show_state(d)                    every frame: dashboard.gd's keys, plus mach, backlight, turbines, g, g_side
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")
const Finish := preload("res://view/craft_materials.gd")
const Layout := preload("res://vr/gauge_layout.gd")
const Classic := preload("res://vr/dashboard.gd")
const Interior := preload("res://vr/cockpit_interior.gd")
const BODY := "res://art/cockpit/gauges_hd.glb"
const FACES := "res://art/cockpit/gauge_faces.png"
const R := Layout.R
const PX := 0.00045                 # Label3D pixel size on the LCD strips
const AMBER := Classic.AMBER
const GREEN := Classic.GREEN
const ORANGE := Classic.ORANGE
const RED := Classic.RED
const CYAN := Classic.CYAN
const DIM := Classic.DIM
const YELLOW := Color(1.0, 0.9, 0.3)
const BACKLIGHT := Color(1.0, 0.96, 0.9)
const DAMAGED := Classic.DAMAGED
const BADLY := Classic.BADLY
const HOT := 0.95                   # engine heat at which HOT lights
const MACH_FULL := 8.0
const MPH_PER_MACH := 767.27        # 343 m/s (view/speed_cues.gd SOUND)
const NO_GAUGE := 7                 # for fittings no needle casts a shadow on
const DRUMS := "res://art/cockpit/odometer_digits.png"
const ROLL_TIME := 0.7              # s for the counter to roll an award in ...
const ROLL_SLOWEST := 20.0          # ... but never slower than this many points a second
const FEAT_BRIGHT := 2.2            # s a feat is read at full brightness on the strip
const FEAT_SHOWN := 6.0             # s before the strip goes back to the handling and controls
# The g-meter. It reads the whole load on the pilot, in g: 1 standing still (the seat holding you up,
# as an aircraft's reads on the ground), what a turn, the engines and the air brakes add to that, and
# 0 weightless over a jump. The craft pulls 35 g off the line, 20 to 35 in the turns it is flown
# through and past 100 on full air brakes at Mach 7, so its scale is in decades (g_scale): 1 g a
# seventh of the way up, 10 at the top of the dial, 20 where the last third and the amber begin.
const G_FULL: float = Layout.G_FULL # the top of the scale, g
const G_HARD: float = Layout.G_HARD # a hard turn: amber on the dial, and the slip bar's ball turns orange
const PEAK_HOLD := 5.0              # s the tell-tale stays at the highest load since ...
const PEAK_FALL := 0.5              # ... then it falls back to the needle, this much of the scale a second
const G_READ := 0.2                 # s between readings of the figures (a figure redrawn every frame cannot be read)
const SLIP := "res://vr/gauge_slip.gdshader"

static var enabled := true          # false before the cockpit is built: the flat panel instead


## A readout that is drawn by a shader or lit as a legend, kept with the flat panel's labels
## so callers and gates read it the same way.
class Readout extends RefCounted:
	var text := ""
	var modulate := Color.WHITE
	var visible := true


var labels := {}       # name -> Label3D (the LCD strips) or Readout
var needles := {}      # name -> MeshInstance3D
var values := {}       # name -> what that needle shows, 0..1 of its scale
var lamps := {}        # name -> Color: its colour, and how lit it is in alpha
var _face_mat: ShaderMaterial
var ivory_thrust_dials := false
var _digit_mat: ShaderMaterial
var _needle_mat: StandardMaterial3D
var _lamp_index := {}
var _lamp_values := PackedVector4Array()
var _needle_info := {}     # name -> [base transform, length, angle at zero, angle at full, shader slot]
var _needle_angles := PackedFloat32Array()
var _backlight := -1.0
var _arcs := {}            # key -> [lamp names, how many are lit, colour, level]
var _lamps_changed := true
var _needles_changed := true
var _speed := -1
var _gear := -1
var _gear_ink := Color(0, 0, 0, 0)
var points := 0            # what the counter is rolling toward
var rolled := 0.0          # what its drums show now
var _drum_mat: ShaderMaterial
var _roll_rate := 0.0      # points a second, set when an award lands (so it rolls evenly and arrives)
var _rolled_sent := -1.0
var _rolled_at := 0
var _power := 1.0          # the battery bus (the start-up): every lamp's level is times this
var _testing := false      # the self-test: every lamp lit ...
var _sweep := -1.0         # ... and every needle here, 0..1 of its scale (-1: where it belongs)
var g_now := 1.0           # the load on the pilot, g (the needle)
var g_side := 0.0          # its part across the craft, g: + a left turn (the slip bar)
var g_peak := 1.0          # the highest load of the last few seconds (the tell-tale)
var _peak_age := 0.0       # s since the tell-tale was last pushed up
var _g_read := G_READ      # s since the figures were read
var _g_room := true        # the strip's lower line is free for them
var _tell_mat: StandardMaterial3D
var _g_mat: StandardMaterial3D
var _slip_mat: ShaderMaterial
var _slip: MeshInstance3D
var _slip_sent := Vector2(-9.0, -9.0)
var _run_line := ""        # the run line as last weighed, and whether it fits on one line
var _run_fits := true


static func available() -> bool:
	return enabled and Finish.hd and ResourceLoader.exists(BODY) and ResourceLoader.exists(FACES)


static func mount() -> Transform3D:
	return Classic.mount()


func build() -> void:
	var body := MeshInstance3D.new()
	body.name = "binnacle"
	body.mesh = Interior._hd_mesh(BODY, "Binnacle")
	Interior.Accent.dress(body)      # its cowl's stitching takes the livery's accent
	add_child(body)   # it casts shadows: the cowl and the tubes shade the dials
	for i in Layout.LAMPS.size():
		_lamp_index[Layout.LAMPS[i]] = i
		lamps[Layout.LAMPS[i]] = Color(0, 0, 0, 0)
	_lamp_values.resize(40)
	for arc in Layout.ARCS:
		var names := []
		for i in int(arc[6]):
			names.append("%s%d" % [arc[0], i])
		_arcs[arc[0]] = [names, -1, Color(0, 0, 0, 0), -1.0]
	_build_faces()
	_build_digits()
	_build_needles()
	_build_g_meter()
	_build_glass()
	_build_text()
	_build_odometer()
	for name in ["speed", "units", "gear", "gear_lbl", "headL", "headR"]:
		labels[name] = Readout.new()
	show_state({"mph": 0.0, "kmh": 0.0, "mach_line": "", "progress": "", "footer": "", "thr": [0.0, 0.0], "brk": [0.0, 0.0],
		"heat": [0.0, 0.0], "health": [1.0, 1.0], "flameout": [false, false], "battery": 1.0, "burner": false, "armed": false,
		"ramjet": false, "blink": true})


# ---- the dials: one mesh in the binnacle's frame, textured from the atlas ----

func _unlit(shader: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(shader)
	return mat


func _add(mesh: Mesh, mat: Material, name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## A quad from four corners given anticlockwise as the pilot sees them (Godot fronts are clockwise).
func _quad(st: SurfaceTool, xf: Transform3D, p: Array, n: Array, uv: Array, colour: Color) -> void:
	for k in [0, 2, 1, 0, 3, 2]:
		var local: Vector3 = p[k]
		st.set_normal(xf.basis * (n[k] as Vector3))
		st.set_uv(uv[k])
		st.set_uv2(Vector2(local.x, local.y))
		st.set_color(colour)
		st.add_vertex(xf * local)


## A flat tile on a dial or a strip: centre and half size in metres, textured from an atlas rectangle.
func _tile(st: SurfaceTool, xf: Transform3D, centre: Vector2, half: Vector2, z: float, uv: Array, gauge: int, lamp: int, gloss: float) -> void:
	var p := [Vector3(centre.x - half.x, centre.y - half.y, z), Vector3(centre.x + half.x, centre.y - half.y, z),
		Vector3(centre.x + half.x, centre.y + half.y, z), Vector3(centre.x - half.x, centre.y + half.y, z)]
	var t := [Vector2(uv[0], uv[3]), Vector2(uv[2], uv[3]), Vector2(uv[2], uv[1]), Vector2(uv[0], uv[1])]
	var up := Vector3(0, 0, 1)
	_quad(st, xf, p, [up, up, up, up], t, Color(0.9 if gloss < 0.5 else 1.0, gloss, gauge / 8.0, lamp / 64.0))


func _build_faces() -> void:
	const SEG := 72
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for gi in Layout.GAUGES.size():
		var g: Dictionary = Layout.GAUGES[gi]
		var xf := Kit.on_arc(g.x, g.y, 0.0, R)
		var rf: float = g.rf
		# the dial: flat, with the scale on a raised ring round its edge
		var radii := [0.0, 0.3, 0.55, Layout.CHAPTER_R - 0.03, Layout.CHAPTER_R, 1.0]
		var lifts := [0.0, 0.0, 0.0, 0.0, Layout.CHAPTER, Layout.CHAPTER]
		for k in radii.size() - 1:
			for s in SEG:
				var p := []
				var n := []
				var uv := []
				var shade := 0.0
				for corner in [[k, s], [k + 1, s], [k + 1, s + 1], [k, s + 1]]:
					var r: float = radii[corner[0]]
					var a: float = TAU * corner[1] / SEG
					p.append(Vector3(r * rf * cos(a), r * rf * sin(a), g.face + lifts[corner[0]]))
					n.append(Vector3(-cos(a) * Layout.CHAPTER, -sin(a) * Layout.CHAPTER, 0.03 * rf).normalized() if k == 3 else Vector3(0, 0, 1))
					uv.append(Vector2(g.uv[0] + r * cos(a) * g.uv[2], g.uv[1] - r * sin(a) * g.uv[2]))
					shade += 0.25 * (0.92 - 0.42 * pow(r, 3.0))   # the tube's wall shades the dial's edge
				_quad(st, xf, p, n, uv, Color(shade, 0.0, gi / 8.0, 0.0))
	for t in Layout.TELLTALES:
		var g: Dictionary = Layout.GAUGES[t[1]]
		_tile(st, Kit.on_arc(g.x, g.y, 0.0, R), Vector2(t[2], t[3]) * g.rf, Vector2(t[4], t[5]) * g.rf * 0.5, g.face + 0.0003, t[6], t[1], _lamp_index[t[0]], 0.0)
	for arc in Layout.ARCS:
		var g: Dictionary = Layout.GAUGES[arc[1]]
		var xf := Kit.on_arc(g.x, g.y, 0.0, R)
		var step: float = deg_to_rad(float(arc[5] - arc[4])) / arc[6]
		var z: float = g.face + Layout.CHAPTER + 0.0003
		var b: Array = Layout.BLOCK_UV
		var up := Vector3(0, 0, 1)
		for i in int(arc[6]):
			var a0: float = deg_to_rad(float(arc[4])) + step * (i + 0.12)
			var a1: float = deg_to_rad(float(arc[4])) + step * (i + 0.88)
			var r0: float = arc[2] * g.rf
			var r1: float = arc[3] * g.rf
			var p := [Vector3(r0 * cos(a0), r0 * sin(a0), z), Vector3(r1 * cos(a0), r1 * sin(a0), z),
				Vector3(r1 * cos(a1), r1 * sin(a1), z), Vector3(r0 * cos(a1), r0 * sin(a1), z)]
			_quad(st, xf, p, [up, up, up, up], [Vector2(b[0], b[3]), Vector2(b[0], b[1]), Vector2(b[2], b[1]), Vector2(b[2], b[3])],
				Color(0.9, 0.0, arc[1] / 8.0, _lamp_index["%s%d" % [arc[0], i]] / 64.0))
	for w in Layout.WINDOWS:   # the LCD strips' dark glass
		_tile(st, Kit.on_arc(w[1], w[2], 0.0, R), Vector2.ZERO, Vector2(w[3], w[4]), w[5] + 0.0006, Layout.LCD_UV, NO_GAUGE, _lamp_index.lcd, 1.0)
	_face_mat = _unlit("res://vr/gauge_face.gdshader")
	_face_mat.set_shader_parameter("atlas", load(FACES))
	_face_mat.set_shader_parameter("ivory_thrust_dials", ivory_thrust_dials)
	var shadows := PackedVector4Array()
	shadows.resize(8)
	_needle_angles.resize(8)
	for i in Layout.NEEDLES.size():
		var nd: Array = Layout.NEEDLES[i]
		shadows[i] = Vector4(nd[1], 0.0, 0.0, nd[4] * Layout.GAUGES[nd[1]].rf)
	_face_mat.set_shader_parameter("needle", shadows)
	_add(st.commit(), _face_mat, "dials")


func _build_digits() -> void:
	var g: Dictionary = Layout.GAUGES[0]
	var xf := Kit.on_arc(g.x, g.y, 0.0, R)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var up := Vector3(0, 0, 1)
	for which in 2:
		var w: Array = Layout.SPEED_WINDOW if which == 0 else Layout.GEAR_WINDOW   # left, bottom, right, top
		var z: float = g.face + 0.0004
		var p := [Vector3(w[0], w[1], 0) * g.rf + Vector3(0, 0, z), Vector3(w[2], w[1], 0) * g.rf + Vector3(0, 0, z),
			Vector3(w[2], w[3], 0) * g.rf + Vector3(0, 0, z), Vector3(w[0], w[3], 0) * g.rf + Vector3(0, 0, z)]
		var aspect: float = (w[2] - w[0]) / (w[3] - w[1])
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_normal(xf.basis * up)
			st.set_uv([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)][k])
			st.set_uv2(Vector2(which, aspect))
			st.add_vertex(xf * (p[k] as Vector3))
	_digit_mat = _unlit("res://vr/gauge_digits.gdshader")
	_add(st.commit(), _digit_mat, "digits")


## One needle, a unit long from its pivot along +x: a tapered blade with a ridge down its back.
func _needle_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var root_l := Vector3(-0.06, 0.024, 0.0)
	var root_r := Vector3(-0.06, -0.024, 0.0)
	var root_top := Vector3(-0.06, 0.0, 0.026)
	var tip_l := Vector3(1.0, 0.007, 0.0)
	var tip_r := Vector3(1.0, -0.007, 0.0)
	var tip_top := Vector3(1.0, 0.0, 0.012)
	Finish._quad(st, root_l, tip_l, tip_top, root_top, Vector3(0, 1, 1))
	Finish._quad(st, root_r, tip_r, tip_top, root_top, Vector3(0, -1, 1))
	Finish._triangle(st, tip_l, tip_r, tip_top, Vector3(1, 0, 0))
	return st.commit()


func _build_needles() -> void:
	_needle_mat = StandardMaterial3D.new()
	_needle_mat.albedo_color = Color(0.95, 0.2, 0.05)
	_needle_mat.roughness = 0.4
	_needle_mat.emission_enabled = true
	_needle_mat.emission = Color(1.0, 0.16, 0.03)
	var mesh := _needle_mesh()
	for i in Layout.NEEDLES.size():
		var nd: Array = Layout.NEEDLES[i]
		var g: Dictionary = Layout.GAUGES[nd[1]]
		var base := Kit.on_arc(g.x, g.y, 0.0, R) * Transform3D(Basis(), Vector3(0, 0, g.face + Layout.NEEDLE_UP))
		needles[nd[0]] = _add(mesh, _needle_mat, "needle_" + str(nd[0]))
		_needle_info[nd[0]] = [base, nd[4] * g.rf, float(nd[2]), float(nd[3]), i, Vector3.ONE]
		values[nd[0]] = -1.0


## The g-meter's tell-tale, a unit long from the pivot along +x: a hairline out to an arrowhead that
## rides the scale's rim, where it can be told from the needle.
func _tell_tale_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var out := Vector3(0, 0, 1)
	Finish._quad(st, Vector3(0.0, 0.03, 0.0), Vector3(0.8, 0.03, 0.0), Vector3(0.8, -0.03, 0.0), Vector3(0.0, -0.03, 0.0), out)
	Finish._triangle(st, Vector3(0.74, 0.0, 0.0), Vector3(1.2, 0.2, 0.0), Vector3(1.2, -0.2, 0.0), out)
	return st.commit()


## The g-meter's own needles, on the centre face's sub-dial (Layout.G_DIAL): the needle, a stubby
## white blade (a blade as slim as the big dials' would be a hair at this size, and one their colour
## is lost over the scale's amber and red); under it the tell-tale, which the needle pushes up the
## scale and leaves behind; and a hub over the two. All of it rides under the Mach needle, which
## sweeps across it. (No shadow under these: the big needles' falls 3 mm low, and under a 16 mm
## needle that reads as a second one.)
func _build_g_meter() -> void:
	var dial: Array = Layout.G_DIAL
	var face: Dictionary = Layout.GAUGES[0]
	var pivot := Kit.on_arc(face.x, face.y, 0.0, R) * Transform3D(Basis(), Vector3(dial[0] * face.rf, dial[1] * face.rf, face.face))
	var reach: float = dial[5] * face.rf
	var up: float = dial[6]
	_tell_mat = StandardMaterial3D.new()
	_tell_mat.albedo_color = Color(0.25, 0.8, 0.9)
	_tell_mat.roughness = 0.5
	_tell_mat.emission_enabled = true
	_tell_mat.emission = CYAN
	_g_mat = StandardMaterial3D.new()
	_g_mat.albedo_color = Color(0.95, 0.95, 0.9)
	_g_mat.roughness = 0.4
	_g_mat.emission_enabled = true
	_g_mat.emission = BACKLIGHT
	for part in [["g_peak", _tell_tale_mesh(), _tell_mat, up * 0.5, Vector3.ONE], ["g", _needle_mesh(), _g_mat, up, Vector3(1.0, 5.0, 2.2)]]:
		needles[part[0]] = _add(part[1], part[2], "needle_" + str(part[0]))
		_needle_info[part[0]] = [pivot * Transform3D(Basis(), Vector3(0, 0, part[3])), reach, float(dial[3]), float(dial[4]), -1, part[4]]
		values[part[0]] = -1.0
	var hub_mat := StandardMaterial3D.new()
	hub_mat.albedo_color = Color(0.035, 0.037, 0.04)
	hub_mat.roughness = 0.34
	hub_mat.metallic = 0.5
	var tall: float = dial[7]
	var hub := _add(Kit.cyl(reach * 0.15, reach * 0.2, tall, 20), hub_mat, "g_hub")
	hub.transform = pivot * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0, tall * 0.5))


## How far up the g-meter's scale a pull of so many g reads, 0..1: in decades, so that 1 g and 100 are both on it.
static func g_scale(pull: float) -> float:
	return log(1.0 + maxf(pull, 0.0)) / log(1.0 + G_FULL)


## ... and the pull at a place on the scale.
static func g_at(place: float) -> float:
	return exp(place * log(1.0 + G_FULL)) - 1.0


## What the g-meter is to show: the whole load, and its part across the craft (+ a left turn). The
## needle pushes the tell-tale up with it.
func set_g(total: float, side: float) -> void:
	g_now = maxf(total, 0.0)
	g_side = side
	if g_now >= g_peak:
		g_peak = g_now
		_peak_age = 0.0


## The g-meter's clockwork over `dt` seconds (a long frame counts as a tenth of a second): the
## tell-tale stays where the needle left it for PEAK_HOLD, then falls back to the needle; and the
## figures on the strip are read again every G_READ.
func settle(dt: float) -> void:
	dt = clampf(dt, 0.0, 0.1)
	_peak_age += dt
	if _peak_age > PEAK_HOLD and g_peak > g_now:
		g_peak = maxf(g_now, g_at(g_scale(g_peak) - PEAK_FALL * dt))
	_g_read += dt
	if _g_read >= G_READ:
		_g_read = 0.0
		labels.g.text = g_text(g_now) + " G"
		labels.g_peak.text = "PEAK " + g_text(g_peak)


## A pull as the strip prints it: tenths, until there is no room for them.
static func g_text(pull: float) -> String:
	return ("%.1f" % pull) if pull < 99.95 else str(roundi(pull))


func _build_glass() -> void:
	const RINGS := 10
	const SEG := 64
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for g in Layout.GAUGES:
		var xf := Kit.on_arc(g.x, g.y, 0.0, R)
		var a: float = g.rg - 0.0006
		var rise: float = Layout.DOME * 2.0 * a
		var rc := (a * a + rise * rise) / (2.0 * rise)   # the dome's radius of curvature
		var edge := asin(a / rc)
		var rim: float = g.mouth - Layout.SEAT
		for i in RINGS:
			for s in SEG:
				for corner in [[i, s], [i + 1, s + 1], [i + 1, s], [i, s], [i, s + 1], [i + 1, s + 1]]:
					var th: float = edge * corner[0] / RINGS
					var ph: float = TAU * corner[1] / SEG
					var n := Vector3(sin(th) * cos(ph), sin(th) * sin(ph), cos(th))
					st.set_normal(xf.basis * n)
					st.add_vertex(xf * (n * rc + Vector3(0, 0, rim - rc * cos(edge))))
	var mat := _unlit("res://vr/gauge_glass.gdshader")
	mat.set_shader_parameter("up_local", mount().basis.inverse() * Vector3.UP)
	_add(st.commit(), mat, "glass")


func _text(name: String, window: Array, y: float, size: int, colour: Color, valign: int) -> void:
	var l := Label3D.new()
	l.name = name
	l.pixel_size = PX
	l.font_size = size
	l.outline_size = 0
	l.modulate = colour
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = valign
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.width = (window[3] * 2.0 - 0.014) / PX
	l.double_sided = false
	l.transform = Kit.on_arc(window[1], window[2], 0.0, R) * Transform3D(Basis(), Vector3(0, y, window[5] + 0.0014))
	add_child(l)
	labels[name] = l


func _build_text() -> void:
	var status: Array = Layout.WINDOWS[0]
	var systems: Array = Layout.WINDOWS[1]
	_text("progress", status, status[4] - 0.006, 32, AMBER, VERTICAL_ALIGNMENT_TOP)
	_text("warn", status, -status[4] + 0.008, 32, AMBER, VERTICAL_ALIGNMENT_BOTTOM)
	_text("mach", systems, systems[4] - 0.006, 36, CYAN, VERTICAL_ALIGNMENT_TOP)
	_text("footer", systems, -systems[4] + 0.008, 23, Color(0.6, 0.6, 0.57), VERTICAL_ALIGNMENT_BOTTOM)
	_text("feat", systems, -systems[4] + 0.008, 27, GREEN, VERTICAL_ALIGNMENT_BOTTOM)   # (in the footer's place while a feat is fresh)
	(labels.feat as Label3D).visible = false
	# the g-meter on the status strip's lower line: the figure, the slip bar, the peak
	var line := -float(status[4]) + 0.008
	_readout_at("g", status, -0.090, line, 32, Color(0.95, 0.95, 0.9), HORIZONTAL_ALIGNMENT_RIGHT)
	_readout_at("g_peak", status, 0.090, line + 0.0012, 23, Color(0.62, 0.62, 0.58), HORIZONTAL_ALIGNMENT_LEFT)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := Vector2(0.078, 0.0058)
	var z: float = status[5] + 0.0012
	var mid := line + 0.0078                                  # (the figure's own middle: capitals 32 high, standing on the line)
	var p := [Vector3(-half.x, mid - half.y, z), Vector3(half.x, mid - half.y, z), Vector3(half.x, mid + half.y, z), Vector3(-half.x, mid + half.y, z)]
	var up := Vector3(0, 0, 1)
	_quad(st, Kit.on_arc(status[1], status[2], 0.0, R), p, [up, up, up, up], [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], Color.WHITE)
	_slip_mat = _unlit(SLIP)
	_slip_mat.set_shader_parameter("aspect", half.x / half.y)
	_slip = _add(st.commit(), _slip_mat, "g_slip")


## A figure on a strip that is not a centred line: its own place along the strip, and which way it is set.
func _readout_at(name: String, window: Array, x: float, y: float, size: int, colour: Color, align: int) -> void:
	var l := Label3D.new()
	l.name = name
	l.pixel_size = PX
	l.font_size = size
	l.outline_size = 0
	l.modulate = colour
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.double_sided = false
	l.transform = Kit.on_arc(window[1], window[2], 0.0, R) * Transform3D(Basis(), Vector3(x, y, window[5] + 0.0014))
	add_child(l)
	labels[name] = l


## The points counter: a small module standing just proud of the fascia between the two strips, its
## drums behind a window, a frame round it and its legend under it.
func _build_odometer() -> void:
	var o: Array = Layout.ODOMETER
	var xf := Kit.on_arc(o[0], o[1], 0.0, R)
	var half := Vector2(o[2], o[3])
	var out: float = o[4]
	var turn := Vector3(PI / 2.0, 0, 0)
	var plate := Vector3(half.x * 2.0 + 0.016, out, half.y * 2.0 + 0.026)       # (a plate lies flat: across, thick, tall)
	var parts := [[Finish.beveled_plate(plate, 0.0015), Kit.at(Vector3(0, -0.005, out * 0.5), turn), Color(0.06, 0.066, 0.075)]]
	var rail := 0.0022
	for side in [-1.0, 1.0]:      # the window's frame, a little proud of the plate
		parts.append([Kit.box(Vector3(half.x * 2.0 + rail * 2.0, rail, 0.0016)), Kit.at(Vector3(0, side * (half.y + rail * 0.5), out + 0.0008)), Color(0.5, 0.52, 0.55)])
		parts.append([Kit.box(Vector3(rail, half.y * 2.0, 0.0016)), Kit.at(Vector3(side * (half.x + rail * 0.5), 0, out + 0.0008)), Color(0.5, 0.52, 0.55)])
	var module := _add(Kit.compound(parts), Finish.powder_coat(), "odometer_module")
	module.transform = xf
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z := out + 0.0003                                                        # on the plate's face, back behind the frame (the plate has no hole: behind its face they were hidden)
	var p := [Vector3(-half.x, -half.y, z), Vector3(half.x, -half.y, z), Vector3(half.x, half.y, z), Vector3(-half.x, half.y, z)]
	var up := Vector3(0, 0, 1)
	_quad(st, xf, p, [up, up, up, up], [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], Color.WHITE)
	_drum_mat = _unlit("res://vr/odometer.gdshader")
	_drum_mat.set_shader_parameter("numerals", load(DRUMS))
	_drum_mat.set_shader_parameter("drums", int(o[5]))
	_add(st.commit(), _drum_mat, "odometer")
	var legend := Label3D.new()
	legend.name = "points_lbl"
	legend.text = "POINTS"
	legend.pixel_size = PX
	legend.font_size = 15
	legend.outline_size = 0
	legend.modulate = Color(0.72, 0.72, 0.68)
	legend.double_sided = false
	legend.transform = xf * Transform3D(Basis(), Vector3(0, -half.y - 0.0095, out + 0.0006))
	add_child(legend)
	labels["points_lbl"] = legend
	labels["points"] = Readout.new()


## What the counter is to show: an award rolls in over ROLL_TIME at an even rate, a small one no
## slower than ROLL_SLOWEST points a second, and a run's reset spins it back in half the time.
func set_points(total: int) -> void:
	if total == points:
		return
	points = total
	var gap := float(points) - rolled
	_roll_rate = maxf(absf(gap) / (ROLL_TIME if gap > 0.0 else ROLL_TIME * 0.5), ROLL_SLOWEST)


## Roll the counter toward its points for `dt` seconds (a long frame counts as a tenth of a second).
func roll(dt: float) -> void:
	if rolled != float(points):
		rolled = move_toward(rolled, float(points), _roll_rate * clampf(dt, 0.0, 0.1))
	if rolled != _rolled_sent:
		_rolled_sent = rolled
		_drum_mat.set_shader_parameter("value", rolled)


# ---- every frame ----

func _set_needle(name: String, v: float, over := 0.0) -> void:
	if _sweep >= 0.0:
		v = _sweep
	elif _power <= 0.0:
		v = 0.0            # a dead instrument's needle lies on its stop
	v = clampf(v, 0.0, 1.0 + over)
	if is_equal_approx(v, values[name]):
		return
	values[name] = v
	var info: Array = _needle_info[name]
	var angle := deg_to_rad(lerpf(info[2], info[3], v))
	if int(info[4]) >= 0:      # (the g-meter's needles cast no shadow for the dials' shader to move)
		_needle_angles[info[4]] = angle
		_needles_changed = true
	(needles[name] as MeshInstance3D).transform = (info[0] as Transform3D) * Transform3D(Basis(Vector3(0, 0, 1), angle) * Basis.from_scale((info[5] as Vector3) * float(info[1])), Vector3.ZERO)


## Where a needle points: degrees anticlockwise from three o'clock, as the pilot sees it.
func needle_angle(name: String) -> float:
	var info: Array = _needle_info[name]
	return lerpf(info[2], info[3], values[name])


func _lamp(name: String, colour: Color, level: float, as_given := false) -> void:
	if not as_given:
		if _testing and name != "backlight" and name != "lcd":
			level = 1.0
		level *= _power
	var now := Color(colour, level)
	if now == lamps[name]:
		return
	lamps[name] = now
	_lamps_changed = true
	var lin := colour.srgb_to_linear()
	_lamp_values[_lamp_index[name]] = Vector4(lin.r, lin.g, lin.b, level)


## A lit arc: `v` of its segments, from the first.
func _arc(key: String, v: float, colour: Color, level: float) -> void:
	var arc: Array = _arcs[key]
	var names: Array = arc[0]
	if _testing:
		v = 1.0
		level = 1.0
	level *= _power
	var lit := clampi(ceili(v * names.size() - 0.001), 0, names.size())
	if lit == arc[1] and colour == arc[2] and level == arc[3]:
		return
	arc[1] = lit
	arc[2] = colour
	arc[3] = level
	for i in names.size():
		_lamp(names[i], colour, level if i < lit else 0.0, true)


## How many of an arc's segments are lit (for the gates).
func arc_lit(key: String, count: int) -> int:
	var n := 0
	for i in count:
		n += 1 if (lamps["%s%d" % [key, i]] as Color).a > 0.0 else 0
	return n


## d: dashboard.gd's keys, and optionally mach (float; else from mph at sea level), backlight
## (0..1: the instrument lighting, turned down in the dark), turbines (bool: the second
## stage is running), g and g_side (the load on the pilot and its part across the craft, + a left
## turn: the g-meter; 1 and 0 when they are not given), and the start-up's two: power (0..1: the
## battery bus; at 0 nothing is lit and nothing reads) and sweep (0..1 through the self-test, -1
## when it is not running: every lamp lit, every needle up its scale and back, eights in the digits).
func show_state(d: Dictionary) -> void:
	_power = clampf(float(d.get("power", 1.0)), 0.0, 1.0)
	var sweep: float = d.get("sweep", -1.0)
	_testing = sweep >= 0.0 and _power > 0.0
	_sweep = (1.0 - absf(2.0 * clampf(sweep, 0.0, 1.0) - 1.0)) if _testing else -1.0
	var mph: float = d.mph
	var shown := 8888 if _testing else int(round(mph))
	if shown != _speed:
		_speed = shown
		labels.speed.text = Classic._grouped(shown)
		_digit_mat.set_shader_parameter("speed", shown)
	labels.units.text = "MPH"
	labels.mach.text = d.mach_line
	labels.progress.text = d.progress
	labels.footer.text = d.footer
	# the points counter, and the feat beside it while it is fresh
	set_points(int(d.get("points", 0)))
	(labels.points as Readout).text = str(points)
	var now := Time.get_ticks_usec()
	var since := float(now - _rolled_at) / 1e6 if _rolled_at > 0 else 0.0
	roll(since)
	_rolled_at = now
	set_g(float(d.get("g", 1.0)), float(d.get("g_side", 0.0)))
	settle(since)
	var feat: String = d.get("feat", "")
	var age: float = d.get("feat_age", 1e9)
	var fresh := feat != "" and age < FEAT_SHOWN
	var feat_label: Label3D = labels.feat
	feat_label.visible = fresh
	(labels.footer as Label3D).visible = not fresh
	if fresh:
		feat_label.text = feat
		feat_label.modulate = Color(GREEN, lerpf(1.0, 0.5, smoothstep(FEAT_BRIGHT, FEAT_BRIGHT + 0.8, age)))
	var blink: bool = d.blink
	var backlight: float = float(d.get("backlight", 1.0)) * _power
	for strip in ["progress", "warn", "mach", "footer"]:
		(labels[strip] as Label3D).visible = _power >= 0.5 and (strip != "footer" or not fresh)
	feat_label.visible = fresh and _power >= 0.5
	_set_needle("mach", float(d.get("mach", mph / MPH_PER_MACH)) / MACH_FULL, 0.02)
	_set_needle("g", g_scale(g_now), 0.035)
	_set_needle("g_peak", g_scale(g_peak), 0.035)
	var hurt := []
	for k in 2:
		var side := "L" if k == 0 else "R"
		_set_needle("thr" + side, d.thr[k])
		_set_needle("brk" + side, d.brk[k])
		_set_needle("heat" + side, d.heat[k])
		var hp: float = d.health[k]
		var head: Readout = labels["head" + side]
		if d.flameout[k]:
			head.text = "%s FLAMEOUT" % side
			head.modulate = RED if blink else DIM
		elif hp < DAMAGED:
			head.text = "%s DAMAGED" % side
			head.modulate = (RED if blink else DIM) if hp < BADLY else AMBER
			hurt.append(side)
		else:
			head.text = side
			head.modulate = Color(0.8, 0.8, 0.78)
		if d.flameout[k] and hp < DAMAGED:
			hurt.append(side)
		_lamp("flameout" + side, RED, 1.0 if d.flameout[k] and blink else 0.0)
		_lamp("hot" + side, RED, 1.0 if d.heat[k] >= HOT else 0.0)
		_arc("hp" + side, hp, GREEN if hp >= DAMAGED else (AMBER if hp >= BADLY else RED), 1.0 if hp >= BADLY or blink else 0.3)
	labels.warn.text = "" if hurt.is_empty() else "HOLD X: REPAIR %s" % "+".join(hurt)
	labels.warn.modulate = RED if minf(d.health[0], d.health[1]) < BADLY else AMBER
	# the g-meter's line on the strip, while the strip has the room: the repair hint has that line
	# first, and a run line that takes two (the start-up's checklist, a finished run) runs down into it
	if d.progress != _run_line:
		_run_line = d.progress
		_run_fits = not _run_line.contains("\n") and ThemeDB.fallback_font.get_string_size(_run_line, HORIZONTAL_ALIGNMENT_LEFT, -1,
			(labels.progress as Label3D).font_size).x < (labels.progress as Label3D).width
	_g_room = _power >= 0.5 and hurt.is_empty() and _run_fits
	(labels.g as Label3D).visible = _g_room
	(labels.g_peak as Label3D).visible = _g_room
	_slip.visible = _g_room
	if _g_room:      # the ball goes where the pilot is thrown: right in a left turn
		var slip := Vector2(signf(g_side) * g_scale(absf(g_side)), 1.0 if absf(g_side) >= G_HARD else 0.0)
		if absf(slip.x - _slip_sent.x) > 0.002 or slip.y != _slip_sent.y:
			_slip_sent = slip
			_slip_mat.set_shader_parameter("ball", slip.x)
			_slip_mat.set_shader_parameter("hard", slip.y)
	_arc("bat", d.battery, CYAN if d.battery > 0.2 else RED, 1.0)
	_lamp("burner", ORANGE, 1.0 if d.burner else 0.0)
	_lamp("armed", YELLOW, 1.0 if d.armed else 0.0)
	_lamp("ramjet", RED, 1.0 if d.ramjet else 0.0)
	_lamp("turbines", GREEN, 1.0 if d.get("turbines", false) else 0.0)
	_lamp("backlight", BACKLIGHT, backlight)
	_lamp("lcd", BACKLIGHT, backlight)
	var g: int = 8 if _testing else int(d.get("gear", 0))
	var gear: Readout = labels.gear
	gear.text = str(g) if g > 0 else ""
	gear.modulate = ORANGE if d.get("overdrive", false) else Color(0.95, 0.95, 0.9)
	(labels.gear_lbl as Readout).visible = g > 0
	if _lamps_changed:
		_lamps_changed = false
		_face_mat.set_shader_parameter("lamp", _lamp_values)
	if _needles_changed:
		_needles_changed = false
		_face_mat.set_shader_parameter("needle_angle", _needle_angles)
	if g != _gear or gear.modulate != _gear_ink:
		_gear = g
		_gear_ink = gear.modulate
		_digit_mat.set_shader_parameter("gear", g)
		_digit_mat.set_shader_parameter("gear_ink", gear.modulate)
	if not is_equal_approx(backlight, _backlight):
		_backlight = backlight
		_digit_mat.set_shader_parameter("level", backlight)
		_drum_mat.set_shader_parameter("level", backlight)
		_needle_mat.emission_energy_multiplier = 1.7 * backlight
		_tell_mat.emission_energy_multiplier = 1.6 * backlight
		_g_mat.emission_energy_multiplier = 1.1 * backlight
