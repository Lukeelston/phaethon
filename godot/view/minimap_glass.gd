## The map on the windscreen (Luke, 2026-11-22: "Will you please add a switch to the map that projects
## it via the hud?"): with the HUD switch on the map's pod thrown up, what the pod's screen shows is
## shown a second time in the roof's swept glass, low and to the left of the road ahead, so it is read
## without looking down and left at the pod. Lines of light and nothing behind them: no panel, no
## picture of its own. The pod's two meshes (the whole country's roads, drawn once; the marks, the
## craft and the roads round it, drawn every frame) are each drawn once more by
## view/minimap_glass.gdshader, which moves every vertex from the pod's flat screen to its place in
## the glass. So it follows GLOBAL / LOCAL and the colour scheme by being the same drawing (but a
## scheme's dark inks, PAPER's, are lifted to light in their own hue: glass can only be lit), and costs
## a draw call for each mesh that is up (two on the whole map, one on the local) and no work on the
## main thread but handing them over. The readout over the pod's screen (the target and how far) is not
## shown again: it is the pod's.
##   where    Square to the seated eye (ScreenReflection.EYE: the pilot's, not the cabin's layout point)
##            and upright from it: its middle AZIMUTH left of dead ahead and ELEVATION from eye level,
##            ACROSS on a side. Each spot of the drawing lies where the eye's line to it meets the screen
##            (INSET inside it, as the approach readout does), so it bows and lies back with the glass
##            (Luke, of the readout: "it should project onto the windscreen and bend with its curve") and
##            both eyes find it at the glass, which lies back there: 0.71 m from the eye at the map's top
##            edge, 1.12 m at its foot (the pod's own screen is 0.80 m off). It rides with the cabin, not
##            with the head.
##            Left of it is the port pillar, under it the coaming, right of it the port engine and then
##            the lane ahead; over it, with clear glass between, the approach readout's page. Neither
##            gives way to the other: tests/test_map_controls.gd holds them apart, and
##            tests/probe_map_glass.gd prints what the eye sees there.
##   whose    It is a patch of the glass, not the glass: nothing else drawn on or through the windscreen
##            is touched, hidden or assumed (the approach readout, the reflection, markers out in the
##            world). Things in front of the glass hide it, as they hide the glass.
##   off      Nothing of this is made until the switch is first thrown, and nothing is drawn or run
##            while it is off.
## Made by the map's pod (vr/minimap_panel.gd fit_glass, show_glass). `depth` is for looking at it
## another way: the same picture as a flat image that far from the eye, out over the nose.
extends Node3D

const Lay := preload("res://view/minimap_glass.gdshader")
const EYE: Vector3 = ScreenReflection.EYE
# Its place, from tests/probe_map_glass.gd's chart of what the eye sees there. Left of 32.5 degrees the
# map's own pod and the port pillar's foot stand in front of the glass; under 9.5 down, the coaming; from
# 7.1 up, as far out as 19 left, the approach readout's page lies in it; the port engine rides 13 to 4.5
# left of the lane ahead. The largest square that keeps a degree off the page and clear of the rest
# is 15 degrees: 32 to 17 left, 9.5 down to 5.4 up (the pod's own screen fills 13). Its foot lies
# over the pod's nose, which is beyond the glass, and its top third over the far country, above the horizon.
const AZIMUTH := deg_to_rad(-24.5)    # its middle: left of dead ahead (negative) ...
const ELEVATION := deg_to_rad(-1.8)   # ... and from eye level
const ACROSS := deg_to_rad(15.0)      # its side, at the eye
const PANEL := Vector2(0.22, 0.22)    # the pod's screen, which the drawing is laid out on (MinimapPanel.W, H)
const CELLS := 8                      # the grid the places are worked out on, across and up (a cell is 4 cm of glass: it bows a quarter of a millimetre in that)
const INSET := 0.004                  # it lies this far inside the glass, m (ApproachProjector.IMAGE_INSET)
const PRIORITY := 3                   # with the approach readout: over the roof's glass and the reflection
const GAIN := 1.5                     # brighter than the pod's inks: the day is behind it, not a dark screen
const NIGHT := 0.55                   # its share of that in the dark
const OPEN_TIME := 0.3                # s: it comes up and goes out over this long
static var depth := 0.0               # 0: in the glass. (Looking at it: a flat image this far from the eye, m.)
static var _places := PackedVector3Array()   # where each node of the grid lies, canopy space, row by row from the drawing's foot
static var _on_glass := true                 # every one of them met the screen
static var _made_at := -1.0                  # the `depth` they were worked out for

var roads := MeshInstance3D.new()     # the whole country's roads (the pod draws them once)
var path := MeshInstance3D.new()      # what the pod draws every frame
var surface := ShaderMaterial.new()
var shown := 0.0                      # 0 dark .. 1 up


## The seated eye's line to a spot of the drawing (x across, y up: the pod's screen's own units).
static func sight(x: float, y: float) -> Vector3:
	var ahead := Vector3(sin(AZIMUTH) * cos(ELEVATION), sin(ELEVATION), -cos(AZIMUTH) * cos(ELEVATION))
	var right := Vector3(cos(AZIMUTH), 0.0, sin(AZIMUTH))
	var up := right.cross(ahead)
	var reach := 2.0 * tan(ACROSS * 0.5)
	return (ahead + right * (x / PANEL.x * reach) + up * (y / PANEL.y * reach)).normalized()


## How far the eye's line to the screen's point (u, v) is off the line along `dir`: across and up, as slopes.
static func _miss(uv: Vector2, dir: Vector3, side: Vector3, over: Vector3) -> Vector2:
	var to := ScreenReflection.screen(uv.x, uv.y) - EYE
	return Vector2(to.dot(side), to.dot(over)) / to.dot(dir)


## Where the eye's line along `dir` meets the roof's screen: (u, v, 1), or (u, v, 0) if it leaves the
## glass first (u and v are then the nearest it came). `from`: a guess to start at.
static func meet(dir: Vector3, from := Vector2(0.3, 0.3)) -> Vector3:
	var side := dir.cross(Vector3.UP).normalized()
	var over := side.cross(dir)
	var uv := from
	const H := 0.001
	for turn in 24:
		var off := _miss(uv, dir, side, over)
		if off.length() < 1e-6:
			return Vector3(uv.x, uv.y, 1.0 if uv.x > 0.0 and uv.x < 1.0 and uv.y > 0.0 and uv.y < 1.0 else 0.0)
		var du := (_miss(uv + Vector2(H, 0.0), dir, side, over) - off) / H
		var dv := (_miss(uv + Vector2(0.0, H), dir, side, over) - off) / H
		var det := du.x * dv.y - du.y * dv.x
		if absf(det) < 1e-12:
			break
		var move := Vector2(off.x * dv.y - off.y * dv.x, du.x * off.y - du.y * off.x) / det
		uv = (uv - move.limit_length(0.25)).clamp(Vector2(-0.3, -0.3), Vector2(1.3, 1.3))
	return Vector3(uv.x, uv.y, 0.0)


## Where each node of the grid lies (canopy space): (CELLS + 1) squared points, row by row from the
## drawing's lower left. Worked out once.
static func places() -> PackedVector3Array:
	if not _places.is_empty() and _made_at == depth:
		return _places
	_places = PackedVector3Array()
	_on_glass = true
	_made_at = depth
	var first := Vector2(0.3, 0.3)      # a start for the first: the nearest of a coarse look over the pane
	var nearest := INF
	var corner := sight(-PANEL.x * 0.5, -PANEL.y * 0.5)
	for i in 10:
		for j in 10:
			var uv := Vector2(0.05 + 0.1 * i, 0.05 + 0.1 * j)
			var off := (ScreenReflection.screen(uv.x, uv.y) - EYE).normalized().distance_to(corner)
			if off < nearest:
				nearest = off
				first = uv
	var last := first
	for j in CELLS + 1:
		for i in CELLS + 1:
			var dir := sight((float(i) / CELLS - 0.5) * PANEL.x, (float(j) / CELLS - 0.5) * PANEL.y)
			if depth > 0.0:
				_places.append(EYE + dir * depth)
				continue
			var hit := meet(dir, first if i == 0 else last)
			if hit.z < 0.5:
				_on_glass = false
			last = Vector2(hit.x, hit.y)
			if i == 0:
				first = last
			_places.append(ScreenReflection.screen(hit.x, hit.y) + ScreenReflection.facing(hit.x, hit.y) * INSET)
	return _places


## Is the whole of it on the roof's screen? (False if a corner's line of sight leaves the glass.)
static func on_glass() -> bool:
	places()
	return _on_glass


## Where a spot of the drawing lies (canopy space), as the shader puts it: between the grid's four nearest.
static func lies_at(x: float, y: float) -> Vector3:
	var p := places()
	var n := CELLS + 1
	var at := Vector2(clampf(x / PANEL.x + 0.5, 0.0, 1.0), clampf(y / PANEL.y + 0.5, 0.0, 1.0)) * float(CELLS)
	var ci := mini(int(floor(at.x)), CELLS - 1)
	var cj := mini(int(floor(at.y)), CELLS - 1)
	var f := at - Vector2(ci, cj)
	return p[cj * n + ci].lerp(p[cj * n + ci + 1], f.x).lerp(p[(cj + 1) * n + ci].lerp(p[(cj + 1) * n + ci + 1], f.x), f.y)


## Fit it in the canopy (hidden, dark).
func build(canopy: Node3D) -> void:
	name = "MapGlass"
	add_to_group("exterior")      # in the glass, outside the cabin's own space (as the reflection's sheet is)
	canopy.add_child(self)
	var p := places()
	var n := CELLS + 1
	var data := PackedFloat32Array()
	data.resize(n * n * 4)
	var box := AABB(p[0], Vector3.ZERO)
	for k in p.size():
		data[4 * k] = p[k].x
		data[4 * k + 1] = p[k].y
		data[4 * k + 2] = p[k].z
		data[4 * k + 3] = 1.0
		box = box.expand(p[k])
	surface.shader = Lay
	surface.render_priority = PRIORITY
	surface.set_shader_parameter("lies", ImageTexture.create_from_image(Image.create_from_data(n, n, false, Image.FORMAT_RGBAF, data.to_byte_array())))
	surface.set_shader_parameter("panel", PANEL)
	surface.set_shader_parameter("level", 0.0)
	surface.set_shader_parameter("gain", GAIN)
	for part: MeshInstance3D in [roads, path]:
		part.name = "roads" if part == roads else "path"
		part.material_override = surface
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		part.custom_aabb = box.grow(0.01)      # (the mesh's own box is the pod's screen: it is drawn here)
		part.add_to_group("exterior")
		add_child(part)
	visible = false


## Each frame: `on` and it shows the pod's drawing (`drawn`: what the pod draws every frame; `country`:
## the whole map's roads when they are up, else null), `dark` 0 by day .. 1 at night.
func show_map(on: bool, drawn: Mesh, country: Mesh, dark: float, delta: float) -> void:
	shown = move_toward(shown, 1.0 if on else 0.0, delta / OPEN_TIME)
	if shown <= 0.0:
		if visible:
			visible = false
			path.mesh = null
			roads.mesh = null
		return
	visible = true
	if path.mesh != drawn:
		path.mesh = drawn
	if roads.mesh != country:
		roads.mesh = country
	surface.set_shader_parameter("level", smoothstep(0.0, 1.0, shown) * lerpf(1.0, NIGHT, clampf(dark, 0.0, 1.0)))
