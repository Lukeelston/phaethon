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

var lines: ImmediateMesh
var label: Label3D
var _mat: StandardMaterial3D


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
	lines = ImmediateMesh.new()
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
	var l := MiniMap.layout(f, W, H, MARGIN, TOP)
	lines.clear_surfaces()
	lines.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for seg in l.segs:
		var c := SP_COL if int(seg[2]) == 1 else SF_COL
		_seg(seg[0], seg[1], LINE * 2.8, Color(c, 0.22))   # a soft glow under the line
	for seg in l.segs:
		var c := SP_COL if int(seg[2]) == 1 else SF_COL
		_seg(seg[0], seg[1], LINE, Color(c.lightened(0.15), 0.95))
	if l.zone != null:
		var z: Vector2 = l.zone
		var zc := SF_COL if int(f.next.mode) == 0 else SP_COL
		_seg(z + Vector2(-0.014, 0), z + Vector2(0.014, 0), 0.0022, Color(zc.lightened(0.4), 1.0))
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
	lines.surface_end()
	label.text = MiniMap.readout(f)
	label.modulate = (SF_COL if int(f.next.mode) == 0 else SP_COL).lightened(0.3) if not (f.next as Dictionary).is_empty() else Color.WHITE


func _seg(a: Vector2, b: Vector2, w: float, c: Color) -> void:
	var d := b - a
	if d.length_squared() < 1e-12:
		return
	var n := d.orthogonal().normalized() * w
	var p := [a + n, a - n, b - n, b + n]
	for k in [0, 1, 2, 0, 2, 3]:
		lines.surface_set_color(c)
		lines.surface_add_vertex(Vector3((p[k] as Vector2).x, (p[k] as Vector2).y, 0.0))


func _tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	for p in [a, b, c]:
		lines.surface_set_color(col)
		lines.surface_add_vertex(Vector3((p as Vector2).x, (p as Vector2).y, 0.0))
