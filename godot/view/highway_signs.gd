## Network guide sign faces. The layout is sized in panel heights. Route markers,
## destination lettering and mile figures each keep their own column on paired exits.
extends RefCounted

const EM := preload("res://art/signs/RG2014EM.ttf")
const D := preload("res://art/signs/RG2014D.ttf")
const Sheet := preload("res://view/guide_sheet.gdshader")
const Gantry := preload("res://view/sign_gantry.gd")
const WHITE := Color("#f4f6ee")
const BLACK := Color("#182121")
const GREEN := Color("#076344")
const SERVICE := Color("#18507a")
const YELLOW := Color("#edb637")
const ID_SILVER := Color("#c6cac3")
const EXPRESSWAY_BLUE := Color("#123b74")
const SCENIC_BROWN := Color("#5c3a1f")   # the coast road's and the drop's boards (a scenic route's brown)
const SHEETING_LAYER := 1 << 9
const GLYPH_SIZE := 128
var hardware := Gantry.new()
var sheets := {}
var quads := {}

func sheet(size: Vector2, field: Color, side := 0, angle := 0.0, chase := false, band := 0.0, left_patch := 0.0, marker := false) -> ShaderMaterial:
	var key := [size,field,side,angle,chase,band,left_patch,marker]
	if not sheets.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = Sheet
		mat.set_shader_parameter("field", field)
		mat.set_shader_parameter("ink", BLACK if field in [YELLOW, ID_SILVER] else WHITE)
		mat.set_shader_parameter("aspect", size.x/size.y)
		mat.set_shader_parameter("arrow_side", float(side))
		mat.set_shader_parameter("arrow_angle", angle)
		mat.set_shader_parameter("beacons", chase)
		mat.set_shader_parameter("advisory", band)
		mat.set_shader_parameter("left_patch", left_patch)
		mat.set_shader_parameter("route_marker", marker)
		mat.set_shader_parameter("expressway", marker and field == EXPRESSWAY_BLUE)
		sheets[key] = mat
	return sheets[key]

func panel(parent: Node3D, tag: String, size: Vector2, pos: Vector3, mat: ShaderMaterial) -> MeshInstance3D:
	if not quads.has(size):
		var quad := QuadMesh.new()
		quad.size = size
		quads[size] = quad
	var face := MeshInstance3D.new()
	face.name = tag
	face.mesh = quads[size]
	face.position = pos
	face.material_override = mat
	face.layers |= SHEETING_LAYER
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(face)
	return face

## cap, center and width in physical units. The Series EM cap is 996/1750 em.
func legend(parent: Node3D, words: String, center: Vector2, width: float, cap: float, font: Font, color := WHITE) -> Label3D:
	var label := Label3D.new()
	label.font = font
	label.font_size = GLYPH_SIZE
	label.text = words
	var advance := font.get_string_size(words,HORIZONTAL_ALIGNMENT_LEFT,-1,GLYPH_SIZE).x
	label.pixel_size = minf(cap/(GLYPH_SIZE*0.569), width/maxf(advance,1.0))
	label.position = Vector3(center.x,center.y - 0.07*label.pixel_size*GLYPH_SIZE,0.22)
	label.outline_size = 0
	label.modulate = color
	label.layers |= SHEETING_LAYER
	label.shaded = true
	label.double_sided = false
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	parent.add_child(label)
	return label

func add_hardware(parent: Node3D, tag: String, mesh: Mesh, pose: Transform3D) -> MeshInstance3D:
	var frame := MeshInstance3D.new()
	frame.name = tag
	frame.mesh = mesh
	frame.material_override = hardware.metal
	frame.transform = pose
	parent.add_child(frame)
	return frame

func number_tab(parent: Node3D, size: Vector2, info: Dictionary) -> void:
	var left: bool = info.side < 0
	var tab_size := Vector2(size.y * (1.78 if left else 1.14), size.y * 0.30)
	var x: float = info.side * (size.x - tab_size.x) * 0.5
	var center := Vector3(x, (size.y + tab_size.y)*0.5 - size.y*0.012, 0.0)
	# A single folded sign blank and short stand-offs join the tab to the main panel.
	var backing := add_hardware(parent,"PlaqueBlank",hardware.carrier(tab_size),Transform3D.IDENTITY)
	backing.scale.z = 0.18
	backing.position = center - Vector3.BACK * Gantry.FACE_Z * 0.18
	var tab := panel(parent,"ExitPlaque", tab_size, center + Vector3.BACK*0.03,
		sheet(tab_size,GREEN,0,0.0,false,0.0,0.32 if left else 0.0))
	if left:
		legend(tab,"LEFT",Vector2(-0.34*tab_size.x,0),tab_size.x*0.25,tab_size.y*0.49,D,BLACK)
	legend(tab,"EXIT " + str(info.number),Vector2(tab_size.x*0.16 if left else 0.0,0),
		tab_size.x*(0.57 if left else 0.85),tab_size.y*0.52,D)

func face(parent: Node3D, pose: Transform3D, size: Vector2, kind: String, lines: Array, info: Dictionary, rear: bool, paired_corner := false) -> void:
	var root := Node3D.new()
	root.name = "Reverse" if rear else "Approach"
	root.transform = pose
	parent.add_child(root)
	var jump := kind in ["jump","fork"]
	if rear and kind != "terminal" and not paired_corner:
		_reverse_id(root, size, kind, lines)
		return
	var direction := 0 if rear else int(info.get("side",1))
	var arrow := direction if jump or (not rear and info.get("decision",false)) else 0
	var warning := kind in ["corner","brake","end","stunt"]
	var field := YELLOW if warning else (SERVICE if kind == "terminal" else (SCENIC_BROWN if info.get("scenic", false) else GREEN))
	var angle := PI/2.0 if kind == "fork" else PI/4.0
	var board := panel(root,"LegendPanel",size,Vector3.ZERO,sheet(size,field,arrow,angle,jump and not rear,0.245 if jump else 0.0))
	var w := size.x
	var h := size.y
	if not rear and info.has("number"):
		number_tab(root,size,info)
	if jump:
		var text_w := w - h*1.05 if arrow else w
		var x := -arrow*h*0.48
		var title := str(lines[0]).replace("ASCENT ","Ascent ")
		legend(board,title,Vector2(x,h*0.23),text_w*0.90,h*0.265,EM)
		var entry := _entry_text(lines[2])
		legend(board,entry,Vector2(x,-h*0.078),text_w*0.88,h*0.155,D)
		legend(board,lines[1],Vector2(0,-h*0.367),w*0.89,h*0.143,D,BLACK)
	elif kind == "terminal":
		legend(board,lines[0].capitalize(),Vector2(0,h*0.095),w*0.88,h*0.35,EM)
		legend(board,"TERMINAL",Vector2(0,-h*0.24),w*0.75,h*0.13,D)
	elif warning:
		var heading := str(lines[0])
		var subheading := str(lines[1])
		if kind == "corner": heading += " MPH"
		legend(board,heading,Vector2(0,h*0.13),w*0.86,h*0.31,D,BLACK)
		legend(board,subheading,Vector2(0,-h*0.205),w*0.87,h*0.175,D,BLACK)
	else:
		_destinations(board,size,kind,lines,info,arrow)

## Preserve the return-trip identification without presenting an oncoming
## driver's exit as a second green destination board.
func _reverse_id(root: Node3D, size: Vector2, kind: String, lines: Array) -> void:
	var plate := size * Gantry.ID_SCALE
	var board := panel(root, "LegendPanel", plate, Vector3.UP*size.y*Gantry.ID_HEIGHT, sheet(plate, ID_SILVER))
	var title := str(lines[1] if kind == "brake" else lines[0])
	if title == "EXIT" and lines.size() > 1:
		title = str(lines[1]).get_slice("  ", 0)
	var launch := kind in ["jump", "fork"]
	title = title.replace("ASCENT ", "Ascent ") if launch else title.capitalize()
	legend(board, "OPPOSITE APPROACH", Vector2(0,plate.y*0.29), plate.x*0.89, plate.y*0.17, D, BLACK)
	legend(board, title, Vector2(0,0 if launch else -plate.y*0.13), plate.x*0.89, plate.y*0.27, EM, BLACK)
	if launch:
		legend(board, lines[1], Vector2(0,-plate.y*0.30), plate.x*0.90, plate.y*0.15, D, BLACK)

static func _entry_text(words: String) -> String:
	if words.begins_with("RIGHT EXIT  "):
		var miles := words.trim_prefix("RIGHT EXIT  ").trim_suffix(" MI")
		return miles + (" MILE" if miles == "1" else " MILES")
	return words.replace("  1 MI", "  1 MILE")


func _destinations(board: Node3D, size: Vector2, kind: String, lines: Array, info: Dictionary, arrow: int) -> void:
	var w := size.x
	var h := size.y
	var content := w - (h*0.97 if arrow else 0.0)
	var cx := -arrow*h*0.47
	var route := str(info.get("route",""))
	var cardinal := str(info.get("cardinal",""))
	if not route.is_empty():
		var expressway := not route.begins_with("S")
		var route_w := h*(0.39 if route.length() <= 2 else 0.48)
		var heading_w := route_w + (h*0.62 if not cardinal.is_empty() else 0.0)
		var marker_x := cx + (route_w-heading_w)*0.5
		var marker_size := Vector2(route_w,h*0.265)
		var stock := EXPRESSWAY_BLUE if expressway else WHITE
		var marker := panel(board,"RouteMarker",marker_size,Vector3(marker_x,h*0.315,0.09),sheet(marker_size,stock,0,0.0,false,0.0,0.0,true))
		legend(marker,route,Vector2(0,-h*0.008),route_w*0.75,h*0.143,D,WHITE if expressway else BLACK)
		if not cardinal.is_empty():
			legend(board,cardinal,Vector2(cx+route_w*0.5+h*0.02,h*0.316),h*0.56,h*0.148,D)
	if lines[0] == "EXIT" and lines.size() > 1:
		for index in range(1, lines.size()):
			var pair := str(lines[index]).split("  ",false)
			var y := h*(0.083 - 0.235*(index-1))
			var name_label := legend(board,pair[0].capitalize(),Vector2(cx,y),content*0.67,h*0.188,EM)
			var mile_label := legend(board,pair[-1].trim_suffix(" MI"),Vector2(cx,y),content*0.21,h*0.179,EM)
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			name_label.position.x = cx - content*0.417
			mile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			mile_label.position.x = cx + content*0.417
	else:
		var title := str(lines[0]).capitalize()
		var center_y := h*0.06 if not route.is_empty() else h*0.20
		legend(board,title,Vector2(cx,center_y),content*0.85,h*0.245,EM)
		# The advance sign gives one distance: how far until the exit. At the
		# turn, use the secondary line for the onward distance instead.
		var detail := "Terminal" if kind == "city" else ""
		if arrow != 0 and lines.size() > 1:
			var distance := str(lines[1]).trim_prefix("EXIT  ").replace(" MI"," mi")
			detail = "Terminal  " + distance if kind == "city" else distance + " long"
		if not detail.is_empty():
			legend(board,detail,Vector2(cx,-h*0.116),content*0.84,h*0.153,D)
	if arrow == 0 and info.has("miles"):
		var miles := int(info.miles)
		legend(board,"%d MILE%s" % [miles,"" if miles==1 else "S"], Vector2(cx,-h*0.345),content*0.80,h*0.135,D)
