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
		mat.set_shader_parameter("ink", BLACK if field == YELLOW else WHITE)
		mat.set_shader_parameter("aspect", size.x/size.y)
		mat.set_shader_parameter("arrow_side", float(side))
		mat.set_shader_parameter("arrow_angle", angle)
		mat.set_shader_parameter("beacons", chase)
		mat.set_shader_parameter("advisory", band)
		mat.set_shader_parameter("left_patch", left_patch)
		mat.set_shader_parameter("route_marker", marker)
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
	var direction := 0 if rear else int(info.get("side",1))
	var arrow := direction if jump or (not rear and info.get("decision",false)) else 0
	var warning := kind in ["corner","brake","end"]
	var field := YELLOW if warning else (SERVICE if kind == "terminal" else GREEN)
	var angle := PI/2.0 if kind == "fork" else PI/4.0
	var board := panel(root,"LegendPanel",size,Vector3.ZERO,sheet(size,field,arrow,angle,jump and not rear,0.245 if jump else 0.0))
	var w := size.x
	var h := size.y
	var ink := BLACK if warning else WHITE
	if not rear and info.has("number"):
		number_tab(root,size,info)
	if jump:
		var text_w := w - h*1.05 if arrow else w
		var x := -arrow*h*0.48
		var title := str(lines[0]).replace("ASCENT ","Ascent ")
		legend(board,title,Vector2(x,h*0.23),text_w*0.90,h*0.265,EM)
		var entry := "OPPOSITE APPROACH" if rear else _entry_text(lines[2])
		legend(board,entry,Vector2(x,-h*0.078),text_w*0.88,h*0.155,D)
		legend(board,lines[1],Vector2(0,-h*0.367),w*0.89,h*0.143,D,BLACK)
	elif rear and kind != "terminal" and not paired_corner:
		var title := str(lines[1] if kind=="brake" else lines[0])
		if title == "EXIT" and lines.size() > 1:
			title = str(lines[1]).get_slice("  ",0)
		legend(board,title.capitalize(),Vector2(0,h*0.14),w*0.86,h*0.26,EM,ink)
		legend(board,"OPPOSITE APPROACH",Vector2(0,-h*0.18),w*0.86,h*0.14,D,ink)
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

static func _entry_text(words: String) -> String:
	if words.begins_with("RIGHT EXIT  "):
		return words.trim_prefix("RIGHT EXIT  ").replace(" MI", " MILES")
	return words.replace("  1 MI", "  1 MILE")


func _destinations(board: Node3D, size: Vector2, kind: String, lines: Array, info: Dictionary, arrow: int) -> void:
	var w := size.x
	var h := size.y
	var content := w - (h*0.97 if arrow else 0.0)
	var cx := -arrow*h*0.47
	var route := str(info.get("route",""))
	var cardinal := str(info.get("cardinal",""))
	if not route.is_empty():
		var route_w := minf(content*0.30,h*0.68)
		var heading_w := route_w + (h*0.64 if not cardinal.is_empty() else 0.0)
		var marker_x := cx + (route_w-heading_w)*0.5
		var marker_size := Vector2(route_w,h*0.228)
		var marker := panel(board,"RouteMarker",marker_size,Vector3(marker_x,h*0.321,0.09),sheet(marker_size,WHITE,0,0.0,false,0.0,0.0,true))
		legend(marker,route,Vector2(0,h*0.006),route_w*0.75,h*0.136,D,BLACK)
		if not cardinal.is_empty():
			legend(board,cardinal,Vector2(cx+route_w*0.5,h*0.316),h*0.59,h*0.123,D)
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
		var title := "Side Road" if lines[0]=="SIDE ROAD" else str(lines[0]).capitalize()
		var center_y := h*0.06 if not route.is_empty() else h*0.20
		legend(board,title,Vector2(cx,center_y),content*0.85,h*0.245,EM)
		var distance := str(lines[1]).trim_prefix("EXIT  ").replace(" MI"," mi")
		var detail := distance+" to terminal" if kind=="city" else distance+" via side road"
		legend(board,detail,Vector2(cx,-h*0.126),content*0.84,h*0.119,D)
	if arrow == 0 and info.has("miles"):
		var miles := int(info.miles)
		legend(board,"%d MILE%s" % [miles,"" if miles==1 else "S"], Vector2(cx,-h*0.345),content*0.80,h*0.135,D)
