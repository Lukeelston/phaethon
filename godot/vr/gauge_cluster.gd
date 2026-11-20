## The cockpit's instrument cluster (Luke: "illuminated physical analogue gauges and a digital
## Speedo readout ... cylindrical tubes with a convex glass cover, and racing inspired faces"):
## five tubes under a stitched cowl where the flat panel was. vr/dashboard.gd is still the
## fallback, and this keeps its mount, its show_state() and its labels.
##   centre    Mach on the dial; in its face the digital speed (mph) and the gear, ARMED,
##             RAMJET and TURBINES legends (TURBINES: green while the second stage runs), and
##             the battery as a lit arc round the foot
##   inboard   a thrust dial per engine, orange past the burner gate; BURNER and FLAMEOUT
##             legends; that engine's health as a lit arc (amber when damaged, blinking red
##             when it is sputtering)
##   outboard  heat over air brake per engine, two needles on one hub; a HOT legend
##   below     two LCD strips: the run line and the repair hint on the left, the Mach / mile
##             line with the handling and controls on the right
## The binnacle is authored (tools/art_gauges_hd.py). The dials are one textured mesh
## (tools/art_gauge_faces.py), the glass another, and the needles share a third. Nothing is
## rebuilt, and a frame only touches what changed: a needle's transform, a lamp, the speed.
##   add_child(c); c.transform = GaugeCluster.mount(); c.build()     once
##   c.show_state(d)                    every frame: dashboard.gd's keys, plus mach, backlight, turbines
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


static func available() -> bool:
	return enabled and Finish.hd and ResourceLoader.exists(BODY) and ResourceLoader.exists(FACES)


static func mount() -> Transform3D:
	return Classic.mount()


func build() -> void:
	var body := MeshInstance3D.new()
	body.name = "binnacle"
	body.mesh = Interior._hd_mesh(BODY, "Binnacle")
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
	_build_glass()
	_build_text()
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
		_needle_info[nd[0]] = [base, nd[4] * g.rf, float(nd[2]), float(nd[3]), i]
		values[nd[0]] = -1.0


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


# ---- every frame ----

func _set_needle(name: String, v: float, over := 0.0) -> void:
	v = clampf(v, 0.0, 1.0 + over)
	if is_equal_approx(v, values[name]):
		return
	values[name] = v
	_needles_changed = true
	var info: Array = _needle_info[name]
	var angle := deg_to_rad(lerpf(info[2], info[3], v))
	_needle_angles[info[4]] = angle
	(needles[name] as MeshInstance3D).transform = (info[0] as Transform3D) * Transform3D(Basis(Vector3(0, 0, 1), angle).scaled(Vector3.ONE * float(info[1])), Vector3.ZERO)


## Where a needle points: degrees anticlockwise from three o'clock, as the pilot sees it.
func needle_angle(name: String) -> float:
	var info: Array = _needle_info[name]
	return lerpf(info[2], info[3], values[name])


func _lamp(name: String, colour: Color, level: float) -> void:
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
	var lit := clampi(ceili(v * names.size() - 0.001), 0, names.size())
	if lit == arc[1] and colour == arc[2] and level == arc[3]:
		return
	arc[1] = lit
	arc[2] = colour
	arc[3] = level
	for i in names.size():
		_lamp(names[i], colour, level if i < lit else 0.0)


## How many of an arc's segments are lit (for the gates).
func arc_lit(key: String, count: int) -> int:
	var n := 0
	for i in count:
		n += 1 if (lamps["%s%d" % [key, i]] as Color).a > 0.0 else 0
	return n


## d: dashboard.gd's keys, and optionally mach (float; else from mph at sea level), backlight
## (0..1: the instrument lighting, turned down in the dark) and turbines (bool: the second
## stage is running).
func show_state(d: Dictionary) -> void:
	var mph: float = d.mph
	var shown := int(round(mph))
	if shown != _speed:
		_speed = shown
		labels.speed.text = Classic._grouped(shown)
		_digit_mat.set_shader_parameter("speed", shown)
	labels.units.text = "MPH"
	labels.mach.text = d.mach_line
	labels.progress.text = d.progress
	labels.footer.text = d.footer
	var blink: bool = d.blink
	var backlight: float = d.get("backlight", 1.0)
	_set_needle("mach", float(d.get("mach", mph / MPH_PER_MACH)) / MACH_FULL, 0.02)
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
	_arc("bat", d.battery, CYAN if d.battery > 0.2 else RED, 1.0)
	_lamp("burner", ORANGE, 1.0 if d.burner else 0.0)
	_lamp("armed", YELLOW, 1.0 if d.armed else 0.0)
	_lamp("ramjet", RED, 1.0 if d.ramjet else 0.0)
	_lamp("turbines", GREEN, 1.0 if d.get("turbines", false) else 0.0)
	_lamp("backlight", BACKLIGHT, backlight)
	_lamp("lcd", BACKLIGHT, backlight)
	var g: int = d.get("gear", 0)
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
		_needle_mat.emission_energy_multiplier = 1.7 * backlight
