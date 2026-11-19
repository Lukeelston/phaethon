## The pod's interior, for the VR cockpit (Luke: "add in some interior detail to the pod"). Built
## once in the rig's frame (the hull sits POD_FRAME_UP above the rig floor) and added to the
## cockpit's shell, so it shakes with the air-brake shudder like every other fitting. Everything
## stays inside the hull's inner trim or up in the cockpit opening (tests/test_cables.gd checks it):
##   floor     a grated deck plate under the seat and feet, a footrest bar and pedals out over
##             the open nose cage
##   frames    ribs round the inner walls every 0.4 m, hoses and conduits along the sides
##   consoles  a console down each side: toggle switches, backlit buttons, stencilled placards
##   quadrant  a gate plate round each throttle lever, the burner gate marked in orange
##   harness   shoulder straps and a lap belt on the seat, a buckle
##   rim light a strip just under the cockpit rim, coloured by mode (set_mode): cool blue in
##             SPEEDCRAFT, magenta in STARFIGHTER (following the live blend), amber on the
##             burner, violet on the ramjet
##   var inner := CockpitInterior.new(); shell.add_child(inner); inner.build()
##   inner.set_mode(sim.mode, sim.hblend)   # each frame
class_name CockpitInterior
extends Node3D

const CM := preload("res://view/craft_model.gd")
const Kit := preload("res://view/mesh_kit.gd")
const Finish := preload("res://view/craft_materials.gd")
static var _flight_deck_meshes: Dictionary = {}
const UP := CM.POD_FRAME_UP
const MODE_LIGHT := {"normal": Color(0.25, 0.6, 1.0), "burner": Color(1.0, 0.55, 0.12), "ramjet": Color(0.7, 0.3, 1.0)}

var rim_mat: StandardMaterial3D
var _mode := ""
var _sf := -1.0
const SF_LIGHT := Color(1.0, 0.3, 0.75)   # STARFIGHTER's resting colour (ModeSwitch.SF_COL)
var parts_built := 0   # tests read this


## A point on the inner wall at station z, angle th round the section, inset from the trim.
static func wall(z: float, th: float, inset: float) -> Vector3:
	var h := CM.hull_section(z)
	return Vector3((h[0] - CM.SKIN - inset) * Kit._sp(cos(th), 2.0 / CM.HULL_N),
		h[1] + (h[2] - CM.SKIN - inset) * Kit._sp(sin(th), 2.0 / CM.HULL_N) + UP, z)


## Exported at the rig's scale and origin. Reuse the imported meshes (and their UVs,
## tangents and shared PBR atlas) on both levers and on replacement cockpits.
static func deck_mesh(part: String) -> Mesh:
	if _flight_deck_meshes.is_empty():
		var deck_scene := load("res://art/cockpit/flight_deck.glb") as PackedScene
		var source := deck_scene.instantiate()
		for child in source.find_children("*", "MeshInstance3D", true, false):
			_flight_deck_meshes[str(child.name)] = (child as MeshInstance3D).mesh
		source.free()
	return _flight_deck_meshes[part]


func build() -> void:
	var coaming := MeshInstance3D.new()
	coaming.name = "SegmentedCoaming"
	coaming.mesh = deck_mesh("Coaming")
	# This fitting wraps the existing exterior hull lip like the windscreen seal.
	coaming.add_to_group("exterior")
	add_child(coaming)
	var bezel := MeshInstance3D.new()
	bezel.name = "InstrumentBezel"
	bezel.mesh = deck_mesh("Bezel")
	add_child(bezel)
	var dark := Color(0.09, 0.09, 0.1)
	var gunmetal := Color(0.28, 0.29, 0.31)
	var steel := Color(0.62, 0.64, 0.68)
	var solid := []   # [mesh, transform, colour] for the matte parts
	var metal := []   # ... the polished ones
	var rubber := []
	var paint := []
	var lit := []     # ... small indicator lenses

	# floor: a deck plate with raised treads, under the seat and the feet (to the cage's edge)
	var floor_y := UP - 0.47
	# Stop ahead of the cushion; the previous plate continued through its volume.
	solid.append([Kit.box(Vector3(0.84, 0.025, 1.1)), Kit.at(Vector3(0, floor_y, 0.0)), dark])
	# The two replaceable tread inserts on this backing are in the textured bezel mesh.
	# footrest bar and pedals, out over the open cage
	metal.append([Kit.cyl(0.022, 0.022, 0.86, 12), Kit.at(Vector3(0, UP - 0.4, -0.95), Vector3(0, 0, PI / 2.0)), steel])
	for s in [-1.0, 1.0]:
		metal.append([Finish.beveled_plate(Vector3(0.13, 0.03, 0.26), 0.005), Kit.at(Vector3(0.2 * s, UP - 0.36, -0.86), Vector3(-0.6, 0, 0)), gunmetal])
		rubber.append([Kit.box(Vector3(0.11, 0.008, 0.2)), Kit.at(Vector3(0.2 * s, UP - 0.34, -0.865), Vector3(-0.6, 0, 0)), Color(0.15, 0.15, 0.16)])

	# Narrow service consoles beside the working levers. The front of the right console is
	# deliberately spare: the existing physical MODE switch lives above it at z = 0.08.
	for s in [-1.0, 1.0]:
		var cx: float = 0.615 * s
		solid.append([Kit.rounded_box(Vector3(0.13, 0.26, 0.95), 7.0, 6), Kit.at(Vector3(cx, UP - 0.36, 0.42)), Color(0.12, 0.13, 0.145)])
		# Separate black gasket, machined edge, and powder-coated removable faceplate.
		rubber.append([Finish.beveled_plate(Vector3(0.116, 0.008, 0.866)), Kit.at(Vector3(cx, UP - 0.226, 0.435)), Color(0.022, 0.025, 0.028)])
		metal.append([Finish.beveled_plate(Vector3(0.113, 0.005, 0.858)), Kit.at(Vector3(cx, UP - 0.22, 0.435)), Color(0.37, 0.39, 0.42)])
		solid.append([Finish.beveled_plate(Vector3(0.108, 0.004, 0.852), 0.0015), Kit.at(Vector3(cx, UP - 0.216, 0.435)), Color(0.065, 0.077, 0.09)])
		var face_y := UP - 0.214
		for dx in [-0.043, 0.043]:
			for z in [0.026, 0.844]:
				_fastener(Vector3(cx + dx, face_y, z), metal, rubber)
		var names: Array = ["AUX PWR", "COMMS", "TRIM"] if s < 0.0 else ["BINDER", "COOLANT", "STAB"]
		for k in 3:
			var z := 0.28 + k * 0.14
			_toggle(Vector3(cx, face_y, z), metal, rubber, paint)
			_top_legend(Vector3(cx, face_y + 0.001, z - 0.045), names[k])
			# Tiny inset status lens, with a metal socket: no luminous button slabs.
			metal.append([Finish.washer(0.0028, 0.0042, 0.0018, 10), Kit.at(Vector3(cx + 0.042 * s, face_y + 0.001, z)), gunmetal])
			lit.append([Kit.cyl(0.0027, 0.0027, 0.0018, 10), Kit.at(Vector3(cx + 0.042 * s, face_y + 0.0015, z)), Color(0.25, 0.58, 0.34) if k < 2 else Color(0.68, 0.4, 0.15)])
		for k in 2:
			var z := 0.70 + k * 0.135
			_knob(Vector3(cx, face_y, z), metal, rubber, paint)
			_top_legend(Vector3(cx, face_y + 0.001, z - 0.042), ("CABIN" if k == 0 else "DIMMER") if s < 0.0 else ("SENS" if k == 0 else "BALANCE"))
		_placard(Vector3(cx - 0.066 * s, UP - 0.31, 0.48), "AUXILIARY  /  01" if s < 0.0 else "PROPULSION  /  02", s)

	# throttle quadrant: a gate plate round each lever, slot and burner gate
	for s in [-1.0, 1.0]:
		var q := Vector3(0.46 * s, 0.125, 0.2)   # just above the lever pivots (the floor curves up out here)
		# Four rails surround an actual opening. A dark rectangle over a solid
		# plate looked like a slot until the lever visibly passed through it.
		for dx in [-0.031,0.031]:
			solid.append([Finish.beveled_plate(Vector3(0.028,0.05,0.36),0.003),Kit.at(q+Vector3(dx,-0.01,0)),Color(0.12,0.12,0.13)])
			paint.append([Kit.box(Vector3(0.024,0.006,0.012)),Kit.at(q+Vector3(dx,0.02,-0.105)),Color(1.0,0.5,0.1)])
		for z in [-0.165,0.165]:
			solid.append([Kit.box(Vector3(0.034,0.05,0.03)),Kit.at(q+Vector3(0,-0.01,z)),Color(0.12,0.12,0.13)])
		for z in [-0.155, 0.155]:
			for dx in [-0.032, 0.032]:
				_fastener(q + Vector3(dx, 0.016, z), metal, rubber)

	# harness on the seat: shoulder straps down the seat back, a lap belt across the cushion
	var strap := Color(0.6, 0.08, 0.06)
	for s in [-1.0, 1.0]:
		rubber.append([Kit.box(Vector3(0.05, 0.62, 0.012)), Transform3D(Basis.from_euler(Vector3(-0.12, 0, 0)), Vector3(0.11 * s, 0.6, 1.012)), strap])
		rubber.append([Kit.box(Vector3(0.25, 0.05, 0.012)), Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0.35 * s, 0)), Vector3(0.14 * s, 0.215, 0.76)), strap])
	metal.append([Kit.rounded_box(Vector3(0.08, 0.06, 0.02), 5.0, 5), Kit.at(Vector3(0, 0.222, 0.72), Vector3(-PI / 2.0, 0, 0)), steel])

	_batch(solid, Finish.powder_coat(), "PowderCoatedPanels")
	_batch(metal, Finish.machined(), "MachinedHardware")
	_batch(rubber, Finish.rubber(), "RubberAndHarness")
	_batch(paint, Finish.painted_metal(), "GuardAndGatePaint")
	_batch(lit, Finish.indicator(), "InsetIndicators")

	# frames and hoses: tubes along the inner walls, the lower half (below the deck line)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 5:
		var z := -0.4 + k * 0.4
		var rib := []
		for j in 25:
			rib.append(wall(z, deg_to_rad(198.0 + j * 6.0), 0.03))
		_clear_tube(st, rib, 0.014, gunmetal)
	var hoses := [[deg_to_rad(205.0), Color(0.75, 0.12, 0.08), 0.045], [deg_to_rad(212.0), Color(0.85, 0.65, 0.1), 0.05],
		[deg_to_rad(335.0), Color(0.15, 0.35, 0.8), 0.045], [deg_to_rad(328.0), Color(0.18, 0.18, 0.2), 0.05]]
	for hs in hoses:
		var run := []
		for m in 31:
			var z := lerpf(-0.5, 1.25, float(m) / 30.0)
			run.append(wall(z, hs[0], hs[2] + 0.012 * sin(m * 0.7)))
		_clear_tube(st, run, 0.011, hs[1])
	var tubes := MeshInstance3D.new()
	tubes.name = "RecessedConduits"
	tubes.mesh = st.commit()
	tubes.material_override = Finish.rubber()
	add_child(tubes)

	# rim light: just under the cockpit rim, inset into the opening, all the way round
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := []
	for k in 97:
		var ph := TAU * k / 96.0
		var x := (CM.OPEN_AX - 0.05) * cos(ph)
		var z := CM.OPEN_ZC + (CM.OPEN_AZ - 0.05) * sin(ph)
		ring.append(Vector3(x, CM.hull_top(x, z) - 0.16 + UP, z))
	_clear_tube(rim, ring, 0.0035, Color.WHITE, 6)
	var rmi := MeshInstance3D.new()
	rmi.name = "RimLighting"
	rmi.mesh = rim.commit()
	rim_mat = StandardMaterial3D.new()
	rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim_mat.albedo_color = MODE_LIGHT.normal
	rmi.material_override = rim_mat
	add_child(rmi)
	parts_built = solid.size() + metal.size() + rubber.size() + paint.size() + lit.size() + 5 + hoses.size() + 1


## Hide structural runs behind occupied fittings, including their tube radius.
## End caps disappear inside the console rather than emerging through its face.
func _occupied(p: Vector3, margin: float) -> bool:
	for side in [-1.0,1.0]:
		var console := AABB(Vector3(side*0.615-0.065,0.105,-0.055),Vector3(0.13,0.29,0.95)).grow(margin)
		if console.has_point(p): return true
	var floor_box := AABB(Vector3(-0.42,0.117,-0.55),Vector3(0.84,0.045,1.1)).grow(margin)
	var seat_box := AABB(Vector3(-0.31,0.08,0.60),Vector3(0.62,0.85,0.59)).grow(margin)
	return floor_box.has_point(p) or seat_box.has_point(p)

func _clear_tube(st: SurfaceTool, points: Array, radius: float, color: Color, sides := 8) -> void:
	var run := []
	for i in points.size():
		var blocked := _occupied(points[i],radius+0.008)
		if i>0: blocked=blocked or _occupied((points[i-1]+points[i])*0.5,radius+0.008)
		if blocked:
			if run.size()>1: CM._tube(st,run,radius,color,sides)
			run=[]
		else: run.append(points[i])
	if run.size()>1: CM._tube(st,run,radius,color,sides)


func _batch(parts: Array, material: Material, node_name: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = Kit.compound(parts)
	mi.material_override = material
	add_child(mi)


func _fastener(at: Vector3, metal: Array, rubber: Array) -> void:
	rubber.append([Kit.cyl(0.0045, 0.0045, 0.0007, 12), Kit.at(at), Color(0.015, 0.018, 0.022)])
	metal.append([Finish.slotted_screw(), Kit.at(at + Vector3(0, 0.0006, 0), Vector3(0, 0.4, 0)), Color(0.57, 0.6, 0.63)])


func _toggle(at: Vector3, metal: Array, rubber: Array, paint: Array) -> void:
	metal.append([Finish.washer(0.005, 0.0115, 0.0022, 14), Kit.at(at + Vector3(0, 0.0011, 0)), Color(0.5, 0.53, 0.57)])
	metal.append([Finish.washer(0.0044, 0.008, 0.0045, 6), Kit.at(at + Vector3(0, 0.004, 0)), Color(0.72, 0.74, 0.77)])
	rubber.append([Kit.cyl(0.0045, 0.006, 0.008, 10), Kit.at(at + Vector3(0, 0.009, 0)), Color(0.025, 0.028, 0.03)])
	metal.append([Kit.cyl(0.0035, 0.003, 0.027, 10), Kit.at(at + Vector3(0, 0.023, -0.003), Vector3(-0.3, 0, 0)), Color(0.7, 0.73, 0.77)])
	metal.append([Kit.ball(0.0048, 8), Kit.at(at + Vector3(0, 0.036, -0.007)), Color(0.7, 0.73, 0.77)])
	for s in [-1.0, 1.0]:
		for z in [-0.02, 0.02]:
			paint.append([Kit.cyl(0.0022, 0.0022, 0.034, 8), Kit.at(at + Vector3(s * 0.024, 0.019, z)), Color(0.49, 0.11, 0.055)])
		paint.append([Kit.cyl(0.0022, 0.0022, 0.04, 8), Kit.at(at + Vector3(s * 0.024, 0.036, 0), Vector3(PI / 2.0, 0, 0)), Color(0.62, 0.16, 0.065)])


func _knob(at: Vector3, metal: Array, rubber: Array, paint: Array) -> void:
	metal.append([Finish.washer(0.013, 0.022, 0.002, 24), Kit.at(at + Vector3(0, 0.001, 0)), Color(0.38, 0.41, 0.44)])
	rubber.append([Finish.knurled_knob(0.018, 0.023), Kit.at(at + Vector3(0, 0.014, 0)), Color(0.08, 0.09, 0.10)])
	metal.append([Kit.cyl(0.014, 0.015, 0.002, 24), Kit.at(at + Vector3(0, 0.0265, 0)), Color(0.45, 0.48, 0.51)])
	paint.append([Kit.box(Vector3(0.0022, 0.0005, 0.009)), Kit.at(at + Vector3(0, 0.0277, -0.006)), Color(0.88, 0.86, 0.72)])
	for k in 7:
		var angle := -PI * 0.75 + k * PI / 4.0
		var pos := at + Vector3(sin(angle) * 0.027, 0.0005, -cos(angle) * 0.027)
		paint.append([Kit.box(Vector3(0.0012, 0.0005, 0.003)), Kit.at(pos, Vector3(0, -angle, 0)), Color(0.55, 0.56, 0.53)])


func _top_legend(at: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 40
	label.pixel_size = 0.00030
	label.modulate = Color(0.72, 0.75, 0.72)
	label.outline_size = 0
	label.shaded = true
	label.position = at
	label.rotation.x = -PI / 2.0
	add_child(label)


## The rim light follows the mode: "normal", "burner" or "ramjet".
func set_mode(mode: String, sf := 0.0) -> void:
	if (mode == _mode and absf(sf - _sf) < 0.01) or rim_mat == null:
		return
	_mode = mode
	_sf = sf
	var rest: Color = MODE_LIGHT.normal.lerp(SF_LIGHT, clampf(sf, 0.0, 1.0))
	rim_mat.albedo_color = rest if mode == "normal" else MODE_LIGHT.get(mode, rest)


func _placard(pos: Vector3, text: String, side: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 40
	l.pixel_size = 0.00036
	l.modulate = Color(0.7, 0.73, 0.71)
	l.outline_size = 0
	l.shaded = true
	l.position = pos
	l.rotation.y = -PI / 2.0 * side   # facing in, toward the seat
	add_child(l)
