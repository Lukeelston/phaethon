## The minimap on the flat view: the same heading-up path ahead as the headset's panel
## (view/minimap.gd lays it out; vr/minimap_panel.gd draws it in the cockpit), drawn in the
## screen's top-right corner. Circuits only.
##   var mm2 := Minimap2D.new(); layer.add_child(mm2)      once (the view sizes and places it)
##   mm2.show_frame(minimap.update(heading, delta))        every frame
extends Control

const MiniMap := preload("res://view/minimap.gd")
const SIDE := 240.0
const MARGIN := 10.0
const TOP := 26.0
const SP_COL := Color(0.25, 0.65, 1.0)
const SF_COL := Color(1.0, 0.3, 0.75)

var _f := {}
var _whole_segs: Array = []   # the whole map's roads, laid out once (the Network)
var _roads: Control           # ... drawn once, behind the marks, in their own canvas item: redrawn
                              # every frame they cost 8.7 ms (thousands of draw_line calls)
const ROAD_PX := 2.0           # the whole map's roads: a segment every this many pixels
var road_segs_drawn := 0      # (tests read: how many it drew)


func _ready() -> void:
	custom_minimum_size = Vector2(SIDE, SIDE)
	size = Vector2(SIDE, SIDE)
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	position = Vector2(get_viewport_rect().size.x - SIDE - 16.0, 16.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roads = Control.new()
	_roads.size = Vector2(SIDE, SIDE)
	_roads.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roads.show_behind_parent = true
	_roads.visible = false
	_roads.draw.connect(_draw_roads)
	add_child(_roads)


func show_frame(f: Dictionary) -> void:
	_f = f
	position = Vector2(get_viewport_rect().size.x - SIDE - 16.0, 16.0)
	var whole := f.has("whole")
	if whole and _whole_segs.is_empty():
		_whole_segs = MiniMap.whole_layout(f, SIDE, SIDE, MARGIN, TOP, true).segs
		_roads.queue_redraw()
	_roads.visible = whole
	queue_redraw()


## The whole country's panel and roads (once: the canvas item keeps them), a batch a colour, each
## road's run thinned to a segment every ROAD_PX pixels (its ~480 m points are a fifth of a pixel
## apart here: 10,600 antialiased segments cost 4 ms a frame to draw).
func _draw_roads() -> void:
	_roads.draw_rect(Rect2(Vector2.ZERO, Vector2(SIDE, SIDE)), Color(0.02, 0.03, 0.05, 0.55))
	_roads.draw_rect(Rect2(Vector2.ZERO, Vector2(SIDE, SIDE)), Color(0.6, 0.75, 0.9, 0.35), false, 1.0)
	var by_col := {1: PackedVector2Array(), 0: PackedVector2Array()}
	var last := Vector2.INF   # the run's last point kept
	var tail := Vector2.INF   # ... and its last point
	var mode := -1
	for seg in _whole_segs:
		var a := _px(seg[0])
		var b := _px(seg[1])
		var m := 1 if int(seg[2]) == 1 else 0
		if a != tail or m != mode:   # a new run (another road, or a mode change): finish the last
			if tail != Vector2.INF and tail != last:
				by_col[mode].append_array(PackedVector2Array([last, tail]))
			last = a
			mode = m
		tail = b
		if last.distance_to(b) >= ROAD_PX:
			by_col[m].append_array(PackedVector2Array([last, b]))
			last = b
	if tail != Vector2.INF and tail != last:
		by_col[mode].append_array(PackedVector2Array([last, tail]))
	road_segs_drawn = (by_col[0].size() + by_col[1].size()) / 2
	for k in by_col:
		if (by_col[k] as PackedVector2Array).size() > 1:
			var c := SP_COL if k == 1 else SF_COL
			_roads.draw_multiline(by_col[k], Color(c.lightened(0.15), 0.9), 1.5, true)


## The whole country (the Network): over its roads (_draw_roads), the marks, the target, the craft.
func _draw_whole() -> void:
	var l := MiniMap.whole_layout(_f, SIDE, SIDE, MARGIN, TOP, false)
	for m in l.marks:
		var q: Vector2 = m[0]
		match m[1]:
			"jump":
				draw_colored_polygon(PackedVector2Array([_px(q + Vector2(0, 6)), _px(q + Vector2(-5, -4)), _px(q + Vector2(5, -4))]), MiniMap.JUMP_COL)
			"gp":
				draw_line(_px(q + Vector2(-6, 6)), _px(q + Vector2(6, -6)), MiniMap.GP_COL, 2.5, true)
				draw_line(_px(q + Vector2(-6, -6)), _px(q + Vector2(6, 6)), MiniMap.GP_COL, 2.5, true)
			"city":
				draw_circle(_px(q), 3.0, Color(1, 1, 1, 0.9))
			"ramp":
				draw_line(_px(q + Vector2(-4, 0)), _px(q + Vector2(4, 0)), MiniMap.RAMP_COL, 2.5, true)
	if l.target != null:
		var tq: Vector2 = l.target[0]
		draw_colored_polygon(PackedVector2Array([_px(tq + Vector2(0, 8)), _px(tq + Vector2(8, 0)), _px(tq + Vector2(0, -8)), _px(tq + Vector2(-8, 0))]), MiniMap.TARGET_COL)
	var cr: Vector2 = l.craft
	var dq: Vector2 = (l.craft_dir as Vector2).normalized() if (l.craft_dir as Vector2).length() > 0.0 else Vector2.UP
	var sd := dq.orthogonal()
	draw_colored_polygon(PackedVector2Array([_px(cr + dq * 11.0), _px(cr - dq * 7.0 + sd * 7.0), _px(cr - dq * 7.0 - sd * 7.0)]), Color(1, 1, 1, 0.95))
	if _f.has("target"):
		draw_string(ThemeDB.fallback_font, Vector2(0, MARGIN + 14.0), "%s  %.0f mi" % [_f.target.name, float(_f.target.dist) / 1609.344], HORIZONTAL_ALIGNMENT_CENTER, SIDE, 15, MiniMap.TARGET_COL)


## Panel space (origin at the centre, y up) to the control's pixels.
func _px(p: Vector2) -> Vector2:
	return Vector2(SIDE / 2.0 + p.x, SIDE / 2.0 - p.y)


func _draw() -> void:
	if _f.has("whole"):   # (its panel and roads: _roads, behind)
		_draw_whole()
		return
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIDE, SIDE)), Color(0.02, 0.03, 0.05, 0.55))
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIDE, SIDE)), Color(0.6, 0.75, 0.9, 0.35), false, 1.0)
	if _f.is_empty():
		return
	var l := MiniMap.layout(_f, SIDE, SIDE, MARGIN, TOP)
	for pass_ in 2:
		for seg in l.segs:
			var c := SP_COL if int(seg[2]) == 1 else SF_COL
			if pass_ == 0:
				draw_line(_px(seg[0]), _px(seg[1]), Color(c, 0.22), 9.0, true)
			else:
				draw_line(_px(seg[0]), _px(seg[1]), Color(c.lightened(0.15), 0.95), 3.0, true)
	if l.zone != null:
		var z: Vector2 = l.zone
		var zc := SF_COL if int(_f.next.mode) == 0 else SP_COL
		draw_line(_px(z + Vector2(-15, 0)), _px(z + Vector2(15, 0)), zc.lightened(0.4), 4.0, true)
	if l.dawn != null:   # the dawn's front, across the map
		draw_line(_px(l.dawn[0]), _px(l.dawn[1]), Color(MiniMap.DAWN_COL, 0.25), 10.0, true)
		draw_line(_px(l.dawn[0]), _px(l.dawn[1]), MiniMap.DAWN_COL, 3.0, true)
	if l.pad != null:   # the medical pad: a red cross
		var pq: Vector2 = l.pad
		for ax in [Vector2(1, 0), Vector2(0, 1)]:
			draw_line(_px(pq - ax * 9.0), _px(pq + ax * 9.0), Color(1, 1, 1, 0.9), 6.0, true)
			draw_line(_px(pq - ax * 8.0), _px(pq + ax * 8.0), MiniMap.PAD_COL, 3.5, true)
	for d in l.get("dots", []):   # the Network's traffic: small dots; the racer, a bigger magenta one
		var racer: bool = int(d[1]) == 4
		draw_circle(_px(d[0]), 4.5 if racer else 2.0, Color(1.0, 0.3, 0.9) if racer else Color(0.9, 0.9, 0.95, 0.75))
	if l.get("target") != null:   # the Network's target city: a diamond on the map, an arrowhead on its rim
		var tq: Vector2 = l.target[0]
		var r := 9.0 if l.target[1] else 7.0
		draw_colored_polygon(PackedVector2Array([_px(tq + Vector2(0, r)), _px(tq + Vector2(r, 0)), _px(tq + Vector2(0, -r)), _px(tq + Vector2(-r, 0))]), MiniMap.TARGET_COL)
	var cr: Vector2 = l.craft
	draw_colored_polygon(PackedVector2Array([_px(cr + Vector2(0, 12)), _px(cr + Vector2(-8, -8)), _px(cr + Vector2(8, -8))]), Color(1, 1, 1, 0.95))
	var text := MiniMap.readout(_f)
	if text != "":
		var col := (SF_COL if int(_f.next.mode) == 0 else SP_COL).lightened(0.3) if not (_f.next as Dictionary).is_empty() else Color.WHITE
		var lines := text.split("
")
		draw_string(ThemeDB.fallback_font, Vector2(0, MARGIN + 14.0), lines[0], HORIZONTAL_ALIGNMENT_CENTER, SIDE, 15, col)
		if lines.size() > 1:   # the dawn's countdown, under it
			draw_string(ThemeDB.fallback_font, Vector2(0, SIDE - MARGIN - 4.0), lines[1], HORIZONTAL_ALIGNMENT_CENTER, SIDE, 15, MiniMap.DAWN_COL)
