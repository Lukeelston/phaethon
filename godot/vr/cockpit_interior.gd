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
##   rim light a strip just under the cockpit rim, coloured by mode (set_mode): cool blue,
##             amber on the burner, violet on the ramjet
##   var inner := CockpitInterior.new(); shell.add_child(inner); inner.build()
##   inner.set_mode(sim.mode)   # each frame
class_name CockpitInterior
extends Node3D

const CM := preload("res://view/craft_model.gd")
const Kit := preload("res://view/mesh_kit.gd")
const UP := CM.POD_FRAME_UP
const MODE_LIGHT := {"normal": Color(0.25, 0.6, 1.0), "burner": Color(1.0, 0.55, 0.12), "ramjet": Color(0.7, 0.3, 1.0)}

var rim_mat: StandardMaterial3D
var _mode := ""
var parts_built := 0   # tests read this


## A point on the inner wall at station z, angle th round the section, inset from the trim.
static func wall(z: float, th: float, inset: float) -> Vector3:
	var h := CM.hull_section(z)
	return Vector3((h[0] - CM.SKIN - inset) * Kit._sp(cos(th), 2.0 / CM.HULL_N),
		h[1] + (h[2] - CM.SKIN - inset) * Kit._sp(sin(th), 2.0 / CM.HULL_N) + UP, z)


func build() -> void:
	var dark := Color(0.09, 0.09, 0.1)
	var gunmetal := Color(0.28, 0.29, 0.31)
	var steel := Color(0.62, 0.64, 0.68)
	var solid := []   # [mesh, transform, colour] for the matte parts
	var metal := []   # ... the polished ones
	var lit := []     # ... the backlit ones

	# floor: a deck plate with raised treads, under the seat and the feet (to the cage's edge)
	var floor_y := UP - 0.47
	solid.append([Kit.box(Vector3(0.84, 0.025, 1.7)), Kit.at(Vector3(0, floor_y, 0.3)), dark])
	for k in 15:
		solid.append([Kit.box(Vector3(0.8, 0.012, 0.035)), Kit.at(Vector3(0, floor_y + 0.018, -0.48 + k * 0.11)), gunmetal])
	# footrest bar and pedals, out over the open cage
	metal.append([Kit.cyl(0.022, 0.022, 0.86, 12), Kit.at(Vector3(0, UP - 0.4, -0.95), Vector3(0, 0, PI / 2.0)), steel])
	for s in [-1.0, 1.0]:
		metal.append([Kit.rounded_box(Vector3(0.13, 0.03, 0.26), 6.0), Kit.at(Vector3(0.2 * s, UP - 0.36, -0.86), Vector3(-0.6, 0, 0)), gunmetal])
		solid.append([Kit.box(Vector3(0.11, 0.008, 0.2)), Kit.at(Vector3(0.2 * s, UP - 0.34, -0.865), Vector3(-0.6, 0, 0)), Color(0.15, 0.15, 0.16)])

	# console down each side, beside the levers
	for s in [-1.0, 1.0]:
		var cx: float = 0.615 * s
		solid.append([Kit.rounded_box(Vector3(0.13, 0.26, 0.95), 7.0), Kit.at(Vector3(cx, UP - 0.36, 0.42)), Color(0.14, 0.14, 0.16)])
		solid.append([Kit.box(Vector3(0.11, 0.012, 0.9)), Kit.at(Vector3(cx, UP - 0.226, 0.42)), Color(0.05, 0.05, 0.06)])   # top plate
		for k in 6:   # toggle switches
			var z := 0.05 + k * 0.075
			metal.append([Kit.cyl(0.008, 0.008, 0.045, 8), Kit.at(Vector3(cx, UP - 0.2, z), Vector3(0.45, 0, 0)), steel])
			metal.append([Kit.ball(0.012, 8), Kit.at(Vector3(cx, UP - 0.18, z - 0.01)), steel])
		var leds := [Color(0.2, 1.0, 0.3), Color(1.0, 0.7, 0.1), Color(1.0, 0.15, 0.1), Color(0.2, 0.6, 1.0)]
		for k in 4:   # backlit buttons
			lit.append([Kit.box(Vector3(0.05, 0.012, 0.035)), Kit.at(Vector3(cx, UP - 0.218, 0.58 + k * 0.06)), leds[k]])
		_placard(Vector3(cx - 0.066 * s, UP - 0.33, 0.42), "AUX PWR    TRIM    COMMS" if s < 0.0 else "BINDER    ARC    HOVER", s)

	# throttle quadrant: a gate plate round each lever, slot and burner gate
	for s in [-1.0, 1.0]:
		var q := Vector3(0.46 * s, 0.125, 0.2)   # just above the lever pivots (the floor curves up out here)
		solid.append([Kit.rounded_box(Vector3(0.09, 0.05, 0.36), 6.0), Kit.at(q + Vector3(0, -0.01, 0)), Color(0.12, 0.12, 0.13)])
		solid.append([Kit.box(Vector3(0.022, 0.01, 0.3)), Kit.at(q + Vector3(0, 0.016, 0)), Color(0.02, 0.02, 0.02)])   # the slot
		lit.append([Kit.box(Vector3(0.07, 0.006, 0.012)), Kit.at(q + Vector3(0, 0.02, -0.105)), Color(1.0, 0.5, 0.1)])   # burner gate

	# harness on the seat: shoulder straps down the seat back, a lap belt across the cushion
	var strap := Color(0.6, 0.08, 0.06)
	for s in [-1.0, 1.0]:
		solid.append([Kit.box(Vector3(0.05, 0.62, 0.012)), Transform3D(Basis.from_euler(Vector3(-0.12, 0, 0.05 * s)), Vector3(0.11 * s, 0.6, 1.025)), strap])
		solid.append([Kit.box(Vector3(0.25, 0.05, 0.012)), Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0.35 * s, 0)), Vector3(0.14 * s, 0.215, 0.76)), strap])
	metal.append([Kit.rounded_box(Vector3(0.08, 0.06, 0.02), 5.0), Kit.at(Vector3(0, 0.222, 0.72), Vector3(-PI / 2.0, 0, 0)), steel])

	var m1 := MeshInstance3D.new()
	m1.mesh = Kit.compound(solid)
	m1.material_override = Kit.vertex_colors()
	add_child(m1)
	var m2 := MeshInstance3D.new()
	m2.mesh = Kit.compound(metal)
	m2.material_override = Kit.polished(0.8, 0.3)
	add_child(m2)
	var m3 := MeshInstance3D.new()
	m3.mesh = Kit.compound(lit)
	m3.material_override = Kit.vertex_colors(true)
	add_child(m3)

	# frames and hoses: tubes along the inner walls, the lower half (below the deck line)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 5:
		var z := -0.4 + k * 0.4
		var rib := []
		for j in 25:
			rib.append(wall(z, deg_to_rad(198.0 + j * 6.0), 0.03))
		CM._tube(st, rib, 0.014, gunmetal)
	var hoses := [[deg_to_rad(205.0), Color(0.75, 0.12, 0.08), 0.045], [deg_to_rad(212.0), Color(0.85, 0.65, 0.1), 0.05],
		[deg_to_rad(335.0), Color(0.15, 0.35, 0.8), 0.045], [deg_to_rad(328.0), Color(0.18, 0.18, 0.2), 0.05]]
	for hs in hoses:
		var run := []
		for m in 31:
			var z := lerpf(-0.5, 1.25, float(m) / 30.0)
			run.append(wall(z, hs[0], hs[2] + 0.012 * sin(m * 0.7)))
		CM._tube(st, run, 0.011, hs[1])
	var tubes := MeshInstance3D.new()
	tubes.mesh = st.commit()
	tubes.material_override = Kit.polished(0.5, 0.4)
	add_child(tubes)

	# rim light: just under the cockpit rim, inset into the opening, all the way round
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := []
	for k in 97:
		var ph := TAU * k / 96.0
		var x := (CM.OPEN_AX - 0.05) * cos(ph)
		var z := CM.OPEN_ZC + (CM.OPEN_AZ - 0.05) * sin(ph)
		ring.append(Vector3(x, CM.hull_top(x, z) - 0.11 + UP, z))
	CM._tube(rim, ring, 0.008, Color.WHITE, 6)
	var rmi := MeshInstance3D.new()
	rmi.mesh = rim.commit()
	rim_mat = StandardMaterial3D.new()
	rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim_mat.albedo_color = MODE_LIGHT.normal
	rmi.material_override = rim_mat
	add_child(rmi)
	parts_built = solid.size() + metal.size() + lit.size() + 5 + hoses.size() + 1


## The rim light follows the mode: "normal", "burner" or "ramjet".
func set_mode(mode: String) -> void:
	if mode == _mode or rim_mat == null:
		return
	_mode = mode
	rim_mat.albedo_color = MODE_LIGHT.get(mode, MODE_LIGHT.normal)


func _placard(pos: Vector3, text: String, side: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 40
	l.pixel_size = 0.0007
	l.modulate = Color(0.85, 0.85, 0.8)
	l.outline_size = 0
	l.position = pos
	l.rotation.y = -PI / 2.0 * side   # facing in, toward the seat
	add_child(l)
