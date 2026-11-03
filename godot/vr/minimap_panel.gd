## The minimap in the headset (Luke: "a minimap overlay of upcoming path"): a translucent heads-up
## panel fixed in the cockpit, up and left of the instrument panel and turned to face the eye, so
## a glance down-left shows the track ahead. Heading-up, the craft near the bottom, the next
## LOOK_S seconds of track above it (view/minimap.gd: it zooms out with speed, ~21 km at
## 4,000 mph), the loop in SPEEDCRAFT blue and the towns in STARFIGHTER magenta, a bar where the
## next mode change is and a readout of how far ("STARFIGHTER  12.4 km"). Drawn over everything
## (no depth test), like the HUD it is. Circuits only; the range is one straight line.
## Panel-local: x across, y up, the face looks down +z at the pilot.
##   var mp := MinimapPanel.new(); shell.add_child(mp); mp.transform = MinimapPanel.mount(eye); mp.build()
##   mp.show_frame(minimap.update(heading, delta))      every frame
extends Node3D

const MiniMap := preload("res://view/minimap.gd")
const W := 0.22
const H := 0.22
const MARGIN := 0.007
const TOP := 0.026                  # the readout's band along the top
const LINE := 0.0024                # path half-width (m on the panel)
const DIST := 1.0                   # from the eye
const YAW := deg_to_rad(30.0)       # left of straight ahead, clear of the instrument panel (its end: 21 deg) ...
const PITCH := deg_to_rad(-10.0)    # ... and a little below the horizon, beside the instrument panel
const SP_COL := Color(0.25, 0.65, 1.0)
const SF_COL := Color(1.0, 0.3, 0.75)
const PRIORITY := 40                # over the windscreen and the forcefield

var lines: ArrayMesh     # rebuilt every frame from _v, _c (on the Network: ~5,000 vertices at a crossing;
var label: Label3D       # an ImmediateMesh's two calls a vertex cost ~0.7 ms of the headset's 8.3)
var _mat: StandardMaterial3D
var _v := PackedVector3Array()
var _roads: MeshInstance3D   # the whole country's roads, drawn once (the Network's whole map)
var _c := PackedColorArray()


## Where the panel sits in the cockpit rig (floor origin, forward -Z), facing `eye`.
static func mount(eye: Vector3) -> Transform3D:
	var dir := Vector3(-sin(YAW) * cos(PITCH), sin(PITCH), -cos(YAW) * cos(PITCH))
	return Transform3D(Basis.looking_at(dir, Vector3.UP), eye + dir * DIST)


func build() -> void:
	var back := MeshInstance3D.new()
	back.name = "backing"
	var q := QuadMesh.new()
	q.size = Vector2(W, H)
	back.mesh = q
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
	label.no_depth_test = true
	label.render_priority = PRIORITY + 2
	label.outline_render_priority = PRIORITY + 1
	label.position = Vector3(0, H / 2.0 - MARGIN - TOP / 2.0, 0.002)
	add_child(label)
	show_frame({"pts": PackedVector2Array(), "modes": PackedByteArray(), "ahead": MiniMap.MIN_AHEAD, "next": {}})


func _hud_mat(priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
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
		var zc := SF_COL if int(f.next.mode) == 0 else SP_COL
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
	for d in l.get("dots", []):   # the Network's traffic: small dots; the racer, a bigger magenta one
		var racer: bool = int(d[1]) == 4
		var r2 := 0.006 if racer else 0.0028
		var dq: Vector2 = d[0]
		_tri(dq + Vector2(0, r2), dq + Vector2(-r2, -r2 * 0.7), dq + Vector2(r2, -r2 * 0.7), Color(1.0, 0.3, 0.9) if racer else Color(0.9, 0.9, 0.95, 0.8))
	if l.get("target") != null:   # the Network's target city: a diamond on the map, smaller on its rim toward it
		var tq: Vector2 = l.target[0]
		var r := 0.011 if l.target[1] else 0.008
		_tri(tq + Vector2(0, r), tq + Vector2(-r, 0), tq + Vector2(r, 0), Color(MiniMap.TARGET_COL, 1.0))
		_tri(tq + Vector2(-r, 0), tq + Vector2(0, -r), tq + Vector2(r, 0), Color(MiniMap.TARGET_COL, 1.0))
	# the craft: a white arrowhead pointing up the map
	var cr: Vector2 = l.craft
	_tri(cr + Vector2(0, 0.011), cr + Vector2(-0.0075, -0.007), cr + Vector2(0.0075, -0.007), Color(1, 1, 1, 0.95))
	# the frame: a hairline round the edge
	var e := Color(0.6, 0.75, 0.9, 0.35)
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
	label.modulate = (SF_COL if int(f.next.mode) == 0 else SP_COL).lightened(0.3) if not (f.next as Dictionary).is_empty() else Color.WHITE


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
			"gp":
				_seg(q + Vector2(-0.007, 0.007), q + Vector2(0.007, -0.007), 0.0018, Color(MiniMap.GP_COL, 1.0))
				_seg(q + Vector2(-0.007, -0.007), q + Vector2(0.007, 0.007), 0.0018, Color(MiniMap.GP_COL, 1.0))
			"city":
				_tri(q + Vector2(0, 0.004), q + Vector2(-0.004, -0.003), q + Vector2(0.004, -0.003), Color(1, 1, 1, 0.9))
			"ramp":
				_seg(q + Vector2(-0.003, 0), q + Vector2(0.003, 0), 0.0016, Color(MiniMap.RAMP_COL, 1.0))
	if l.target != null:
		var tq: Vector2 = l.target[0]
		var r := 0.008
		_tri(tq + Vector2(0, r), tq + Vector2(-r, 0), tq + Vector2(r, 0), Color(MiniMap.TARGET_COL, 1.0))
		_tri(tq + Vector2(-r, 0), tq + Vector2(0, -r), tq + Vector2(r, 0), Color(MiniMap.TARGET_COL, 1.0))
	var cr: Vector2 = l.craft   # the craft: a white arrowhead pointing its way
	var dq: Vector2 = (l.craft_dir as Vector2).normalized() if (l.craft_dir as Vector2).length() > 0.0 else Vector2.UP
	var sd := dq.orthogonal()
	_tri(cr + dq * 0.011, cr - dq * 0.007 + sd * 0.0075, cr - dq * 0.007 - sd * 0.0075, Color(1, 1, 1, 0.95))
	var e := Color(0.6, 0.75, 0.9, 0.35)
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
	label.modulate = MiniMap.TARGET_COL


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
	var glow := [Color(SF_COL, 0.22), Color(SP_COL, 0.22)]
	var line := [Color(SF_COL.lightened(0.15), 0.95), Color(SP_COL.lightened(0.15), 0.95)]
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


func _tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	_v.append(Vector3(a.x, a.y, 0.0))
	_v.append(Vector3(b.x, b.y, 0.0))
	_v.append(Vector3(c.x, c.y, 0.0))
	_c.append(col)
	_c.append(col)
	_c.append(col)
