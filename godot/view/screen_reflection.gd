## The windscreen's reflection of the cockpit (Luke: "add some kind of reflection to the windscreen,
## without making it white out"): view/screen_reflection.gdshader on a sheet lying in the swept
## screen's inner face, showing a picture this script takes of the cockpit.
##   the picture   a small view of the cockpit's own parts (and nothing else: they are put on a
##                 layer of their own) from where the seated eye's mirror image in the glass is,
##                 looking down through the screen, under the world's own light. Taken again every
##                 few seconds, so the needles and the light on the leather keep up (one costs
##                 about 0.1 ms, 46 draws).
##   the sheet     the roof's screen (tools/art_roof_hd.py's screen(u, v)), facing in: seen only from
##                 inside. Only the parts of it that have something to show are drawn. Every part of
##                 the pane looks down on some part of the cabin, but most of the cabin is too dark
##                 to show in glass, and a sheet over the whole pane, shaded every frame to show
##                 nothing, cost a headset-sized frame 5 % of its GPU time. So the sheet is cut to
##                 where a head anywhere near the seat sees one of the things worth seeing: the
##                 coaming and the rim light along the foot of the screen, and whatever the cockpit
##                 names (`sights`: the instruments, the map).
## Built by the VR cockpit when the roof is fitted, after everything in the cockpit is in place:
##   reflection = ScreenReflection.new(); reflection.build(canopy, shell, [[centre, radius], ...])
class_name ScreenReflection
extends Node3D

const Glass := preload("res://view/screen_reflection.gdshader")
const CM := preload("res://view/craft_model.gd")
const LAYER := 1 << 11                       # the cockpit's own parts: what the picture is of
const SIZE := Vector2i(640, 400)
const EYE := Vector3(0.0, 0.12 + 0.089, 0.6 - 0.025) # the seated eye, canopy space: the point the cabin is laid out round, the pilot's rise over it and his inch ahead of it (vr_cockpit.gd SEAT, SEAT_RISE, SEAT_FWD; tests/test_vr_camera.gd holds the two together)
const A_DEG := 50.0                          # the screen's feet round the rim, either side of the nose (the roof's own)
const FIELD := 86.0                          # the picture's field of view, degrees up and down
const LIES_AT := 0.02                        # the height the reflected cockpit is taken to lie at (the dash and the coaming), canopy space
const REACH := Vector2(0.1, 0.32)            # how far aft it runs: all of it to the first z, none past the second (the seat and an absent pilot's lap are not shown)
const COLS := 48                             # the sheet's cells across and up the screen
const ROWS := 26
const HEADS: Array[Vector3] = [Vector3.ZERO, Vector3(0.08, 0, 0), Vector3(-0.08, 0, 0), Vector3(0, 0.06, 0), Vector3(0, -0.05, 0), Vector3(0, 0, -0.1)]   # the seated head, and leaning a little each way
const RIM := Vector2(0.74, -0.5)             # the coaming and the rim light: the cabin's plan from this share of the way out to its edge, ahead of this z
const CEILING := 0.5                         # the most of the picture the glass ever gives back (the shader's `ceiling`)
const LAMPS := 1.0                           # how much brighter than white the cockpit's own lights are (the shader's `lamps`)
const DARK := 0.4                            # the strength's share kept where the view outside is dark: there a bare pane's own is plenty, and more is a ghost over the road
const EVERY := 3.0                           # seconds between pictures
static var every := EVERY                    # (timings: 0 takes a picture every frame, to weigh one)
static var enabled := true                   # (timings: false before the cockpit is built leaves it out)
static var whole := false                    # (timings: true keeps the whole pane's sheet)
static var strength := 2.2                   # times a bare pane's own share: by day that is lost against the sky (3.0 as first flown; Luke: "dim the reflection just a bit")

var sheet := MeshInstance3D.new()
var surface := ShaderMaterial.new()
var port := SubViewport.new()
var lens := Camera3D.new()
var looks_from: Transform3D                  # the lens, canopy space
var seen_from: Projection                    # canopy space -> the picture's clip space
var pictures := 0
var cells := 0                               # the sheet's cells that are drawn ...
var share := 0.0                             # ... and their share of the whole screen's
var sights: Array = []                       # what the glass is to show besides the rim: [centre (canopy space), radius], ...
var _wait := 0.0
var _canopy: Node3D
var _dark := 0.0
var _cockpit: Node3D


static func available() -> bool:
	return enabled and Canopy.roof_available()


## A point on the roof's windscreen: u across (left .. right), v from the rim up to the header.
static func screen(u: float, v: float) -> Vector3:
	var ph := deg_to_rad(-90.0 - A_DEG + 2.0 * A_DEG * u)
	var edge := CM.open_edge(ph)
	var x := edge.x
	var z := edge.y
	var foot := Vector3(x, CM.hull_top(x, z) + 0.052, z)
	var w := 2.0 * u - 1.0
	var head := Vector3(0.41 * w, 0.47 - 0.035 * w * w, 0.30 + 0.14 * w * w)
	var p := foot.lerp(head, v)
	return p + Vector3(p.x, 0.9, p.z - 0.15).normalized() * 0.045 * sin(PI * v)


## The screen's own normal there, toward the cabin.
static func facing(u: float, v: float) -> Vector3:
	var n := (screen(u + 0.01, v) - screen(u - 0.01, v)).cross(screen(u, v + 0.01) - screen(u, v - 0.01)).normalized()
	return n if n.dot(EYE - screen(u, v)) > 0.0 else -n


## A sight line from `eye` to the screen's point `p` (normal `n`), turned off the glass; Vector3.ZERO
## if the glass does not face that eye or turns the line upward.
static func turned(eye: Vector3, p: Vector3, n: Vector3) -> Vector3:
	var off := (p - eye).normalized().bounce(n)
	return Vector3.ZERO if off.y > -0.08 or n.dot(eye - p) <= 0.0 else off


## Where that line lands in the cabin (at the height the dash and the coaming lie at); Vector3.INF if
## it does not come down inside it.
static func lands(eye: Vector3, p: Vector3, n: Vector3) -> Vector3:
	var off := turned(eye, p, n)
	if off == Vector3.ZERO:
		return Vector3.INF
	var at := p + off * ((LIES_AT - p.y) / off.y)
	if at.z > REACH.y or plan(at) > 1.0:
		return Vector3.INF
	return at


## A cabin point in plan: 0 at the opening's middle, 1 at the coaming's outer edge.
static func plan(at: Vector3) -> float:
	return pow(at.x / (CM.OPEN_AX + 0.17), 2.0) + pow((at.z - CM.OPEN_ZC) / (CM.open_az(at.z) + 0.17), 2.0)


func build(canopy: Node3D, cockpit: Node3D, show: Array = []) -> void:
	sights = show
	name = "screen_reflection"
	_canopy = canopy
	canopy.add_child(self)
	add_to_group("exterior")       # in the glass, outside the cabin's own space: the fittings' checks leave it out
	_cockpit = cockpit
	# where the picture is taken from: the seated eye's mirror image in the screen's middle, looking
	# back down through it at what the eye sees reflected there
	var middle := screen(0.5, 0.55)
	var face := facing(0.5, 0.55)
	var image := EYE - face * 2.0 * (EYE - middle).dot(face)
	var gaze := (middle - EYE).normalized().bounce(face)   # the eye's line to the screen's middle, turned off the glass
	looks_from = Transform3D(Basis.looking_at(gaze, Vector3(0.0, 0.0, -1.0)), image)
	port.name = "picture"
	port.size = SIZE
	port.transparent_bg = true
	port.msaa_3d = Viewport.MSAA_4X    # (thin lit lines: the needles, the rim light)
	port.positional_shadow_atlas_size = 0
	port.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(port)
	lens.cull_mask = LAYER
	lens.fov = FIELD
	lens.near = 0.05
	lens.far = 6.0
	port.add_child(lens)
	lens.current = true
	seen_from = Projection.create_perspective(FIELD, float(SIZE.x) / float(SIZE.y), lens.near, lens.far) * Projection(looks_from.affine_inverse())
	surface.shader = Glass
	surface.set_shader_parameter("seen", port.get_texture())
	surface.set_shader_parameter("seen_from", seen_from)
	surface.set_shader_parameter("strength", strength)
	surface.set_shader_parameter("ceiling", CEILING)
	surface.set_shader_parameter("lamps", LAMPS)
	surface.set_shader_parameter("lies_at", LIES_AT)
	surface.set_shader_parameter("reach", REACH)
	surface.set_shader_parameter("opening", Vector4(CM.OPEN_AX + 0.17, CM.OPEN_AZ + 0.17, CM.OPEN_ZC, CM.OPEN_AZ_FRONT + 0.17))   # the opening and the coaming round it
	sheet.name = "sheet"
	sheet.material_override = surface
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sheet.add_to_group("exterior")
	add_child(sheet)
	_lay_sheet()
	# (the first picture waits for the first frame: the cockpit is not yet standing where it flies)


## Build the sheet: wound to face the seated eye, its normals the curved screen's own (a mirror of
## flat facets breaks every line it shows at each facet's edge), and only the cells where a head
## near the seat sees the rim or one of the `sights` (all of the pane that looks into the cabin, if
## `whole`).
func _lay_sheet() -> void:
	var at := PackedVector3Array()
	var normal := PackedVector3Array()
	var shows := PackedByteArray()
	for j in ROWS + 1:
		for i in COLS + 1:
			var u := lerpf(0.03, 0.97, float(i) / COLS)
			var v := lerpf(0.08, 0.985, float(j) / ROWS)
			var p := screen(u, v)
			var n := facing(u, v)
			var seen := false
			for head in HEADS:
				var spot := lands(EYE + head, p, n)
				if spot == Vector3.INF:
					continue
				if whole or (plan(spot) > RIM.x and spot.z < RIM.y):
					seen = true
					break
				var off := turned(EYE + head, p, n)
				for sight in sights:      # does the turned line pass through it?
					var to: Vector3 = (sight[0] as Vector3) - p
					var along := to.dot(off)
					seen = seen or (along > 0.0 and (to - off * along).length() < float(sight[1]))
				if seen:
					break
			at.append(p)
			normal.append(n)
			shows.append(int(seen))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	cells = 0
	for i in COLS:
		for j in ROWS:
			var corners := [j * (COLS + 1) + i, j * (COLS + 1) + i + 1, (j + 1) * (COLS + 1) + i + 1, (j + 1) * (COLS + 1) + i]
			if shows[corners[0]] + shows[corners[1]] + shows[corners[2]] + shows[corners[3]] == 0:
				continue
			cells += 1
			for k: int in [0, 2, 1, 0, 3, 2]:
				st.set_normal(normal[corners[k]])
				st.add_vertex(at[corners[k]])
	share = float(cells) / float(COLS * ROWS)
	sheet.mesh = st.commit() if cells > 0 else null


## How dark the view outside is, 0 (day) .. 1 (a hall, night): the reflection eases off with it.
func set_dark(dark: float) -> void:
	dark = clampf(dark, 0.0, 1.0)
	if absf(dark - _dark) > 0.01:
		_dark = dark
		surface.set_shader_parameter("strength", strength * lerpf(1.0, DARK, dark))


## Take the picture again, now.
func take() -> void:
	# what the picture is of: every part of the cockpit, but not the canopy over it. (Marked each
	# time: some parts are made late, the map's roads among them.)
	for part: VisualInstance3D in _cockpit.find_children("*", "VisualInstance3D", true, false):
		if not _canopy.is_ancestor_of(part):
			part.layers |= LAYER
	lens.global_transform = _canopy.global_transform * looks_from
	# Under the light the pilot sees the cockpit by: the world's own sky and sun and its grading, so the
	# leather in the glass is as bright as the leather under it (a plain dim room of its own left only
	# the lamps bright enough to show, and they read as stray sparks). Without the glow, the fog and
	# the sky itself: there is nothing behind the cockpit in the picture.
	var world := _canopy.get_world_3d().environment if _canopy.is_inside_tree() else null
	if world:
		var room: Environment = world.duplicate()
		room.background_mode = Environment.BG_COLOR
		room.background_color = Color(0, 0, 0, 0)
		room.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		room.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		room.glow_enabled = false
		room.fog_enabled = false
		room.volumetric_fog_enabled = false
		room.ssao_enabled = false
		room.ssil_enabled = false
		room.ssr_enabled = false
		room.sdfgi_enabled = false
		lens.environment = room
	port.render_target_update_mode = SubViewport.UPDATE_ONCE
	pictures += 1
	_wait = every


func _process(delta: float) -> void:
	_wait -= delta
	if _wait <= 0.0:
		take()
