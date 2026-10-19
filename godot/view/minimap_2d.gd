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


func _ready() -> void:
	custom_minimum_size = Vector2(SIDE, SIDE)
	size = Vector2(SIDE, SIDE)
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	position = Vector2(get_viewport_rect().size.x - SIDE - 16.0, 16.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_frame(f: Dictionary) -> void:
	_f = f
	position = Vector2(get_viewport_rect().size.x - SIDE - 16.0, 16.0)
	queue_redraw()


## Panel space (origin at the centre, y up) to the control's pixels.
func _px(p: Vector2) -> Vector2:
	return Vector2(SIDE / 2.0 + p.x, SIDE / 2.0 - p.y)


func _draw() -> void:
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
	var cr: Vector2 = l.craft
	draw_colored_polygon(PackedVector2Array([_px(cr + Vector2(0, 12)), _px(cr + Vector2(-8, -8)), _px(cr + Vector2(8, -8))]), Color(1, 1, 1, 0.95))
	var text := MiniMap.readout(_f)
	if text != "":
		var col := (SF_COL if int(_f.next.mode) == 0 else SP_COL).lightened(0.3)
		var lines := text.split("
")
		draw_string(ThemeDB.fallback_font, Vector2(0, MARGIN + 14.0), lines[0], HORIZONTAL_ALIGNMENT_CENTER, SIDE, 15, col)
		if lines.size() > 1:   # the dawn's countdown, under it
			draw_string(ThemeDB.fallback_font, Vector2(0, SIDE - MARGIN - 4.0), lines[1], HORIZONTAL_ALIGNMENT_CENTER, SIDE, 15, MiniMap.DAWN_COL)
