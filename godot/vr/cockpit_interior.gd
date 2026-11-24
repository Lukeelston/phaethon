## The pod's interior, for the VR cockpit (Luke: "add in some interior detail to the pod"). Built
## once in the rig's frame (the hull sits POD_FRAME_UP above the rig floor) and added to the
## cockpit's shell, so it shakes with the air-brake shudder like every other fitting. Everything
## stays inside the hull's inner trim or up in the cockpit opening (tests/test_cables.gd checks it):
##   floor     a grated deck plate under the seat and feet (without the dashboard: a footrest bar and
##             pedals out over the open nose cage)
##   dash      the dashboard, from the underside of the rim down to the deck and round to the
##             consoles; the instruments stand on its fascia (vr/gauge_cluster.gd)
##   frames    ribs round the inner walls every 0.4 m, hoses and conduits along the sides
##   consoles  a console down each side: toggle switches, backlit buttons, stencilled placards (the toggles and
##             two of the knobs work: vr/console_switches.gd, built here last as `switches`)
##   quadrant  a gate plate round each throttle lever, the burner gate marked in orange
##   harness   shoulder straps and a lap belt on the seat, a buckle
##   tub       a moulded carbon panel each side of the seat, from its flank up to the console and,
##             behind the console, up to the rim: the cabin is closed round the pilot's hips
##   rim light a strip just under the cockpit rim, coloured by mode (set_mode): cool blue in
##             SPEEDCRAFT, magenta in STARFIGHTER (following the live blend), amber on the
##             burner, violet on the ramjet
##   var inner := CockpitInterior.new(); shell.add_child(inner); inner.build()
##   inner.set_mode(sim.mode, sim.hblend)   # each frame
class_name CockpitInterior
extends Node3D

const CM := preload("res://view/craft_model.gd")
const Kit := preload("res://view/mesh_kit.gd")
const FleetThrottle := preload("res://vr/fleet_throttle.gd")
const Finish := preload("res://view/craft_materials.gd")
const Accent := preload("res://view/accent.gd")      # the livery's accent on the authored fittings' enamel and thread
const ConsoleSwitchesScript := preload("res://vr/console_switches.gd")   # the consoles' toggles and two knobs, live
static var _flight_deck_meshes: Dictionary = {}
const UP := CM.POD_FRAME_UP
const MODE_LIGHT := {"normal": Color(0.25, 0.6, 1.0), "burner": Color(1.0, 0.55, 0.12), "ramjet": Color(0.7, 0.3, 1.0)}

var rim_mat: StandardMaterial3D
var _mode := ""
var _sf := -1.0
var _power := 1.0     # the battery bus (the start-up): the rim light's level
const SF_LIGHT := Color(1.0, 0.3, 0.75)   # STARFIGHTER's resting colour (ModeSwitch.SF_COL)
var parts_built := 0   # tests read this
var switches           # vr/console_switches.gd: the consoles' toggles and live knobs (after build())


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
		if hd_parts:
			for name in HD_PARTS:
				if ResourceLoader.exists(HD_PARTS[name]):
					_flight_deck_meshes[name] = _hd_mesh(HD_PARTS[name], name)
	return _flight_deck_meshes[part]


## Realism spike (tools/art_*_hd.py): fittings rebuilt at headset texel density, each with the
## original's envelope and node name. Set hd_parts = false before the first deck_mesh() for
## v0.3.2's originals.
const HD_PARTS := {
	"Coaming": "res://art/cockpit/coaming_hd.glb",
	"Grip": "res://art/cockpit/grip_hd.glb",
	"Bezel": "res://art/cockpit/bezel_hd.glb",
}
static var hd_parts := true
static var instrument_rails := true   # the flat instrument panel's frame; false when the gauge cluster stands there
const HD_CONSOLE := "res://art/cockpit/console_hd.glb"
const HD_TUB := "res://art/cockpit/tub_hd.glb"     # the seat's tub (tools/art_tub_hd.py): the hip panels, the quarters behind the consoles, the side liners
const HD_DASH := "res://art/cockpit/dash_hd.glb"   # the dashboard (tools/art_dash_hd.py): a padded top under the rim, the fascia behind the instruments, its wings back to the consoles

static func _hd_mesh(path: String, node := "*") -> Mesh:
	var source := (load(path) as PackedScene).instantiate()
	var mesh: Mesh = (source.find_children(node, "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	source.free()
	var mat := mesh.surface_get_material(0) as StandardMaterial3D
	if mat:
		# The packed map's red channel is baked occlusion; the glTF material doesn't declare it.
		mat.ao_enabled = true
		mat.ao_texture = mat.roughness_texture
		mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		mat.ao_light_affect = 0.35
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mesh


func build(fleet_controls := false) -> void:
	var coaming := MeshInstance3D.new()
	coaming.name = "SegmentedCoaming"
	coaming.mesh = deck_mesh("Coaming")
	# This fitting wraps the existing exterior hull lip like the windscreen seal.
	coaming.add_to_group("exterior")
	Accent.dress(coaming)
	add_child(coaming)
	var bezel := MeshInstance3D.new()
	bezel.name = "InstrumentBezel"
	bezel.mesh = deck_mesh("Bezel")
	Accent.dress(bezel)
	add_child(bezel)
	if hd_parts and instrument_rails and ResourceLoader.exists(HD_PARTS.Bezel):
		var rails := MeshInstance3D.new()
		rails.name = "InstrumentRails"
		rails.mesh = _hd_mesh(HD_PARTS.Bezel, "InstrumentRails")
		add_child(rails)
	# Realism spike: the seat's tub (Luke: "close up the sides by the pilot's butt so that its more of
	# a monocoque design"). Either side of the seat the cabin was open down to the hull's floor, and
	# behind each console out to its wall.
	if hd_parts and ResourceLoader.exists(HD_TUB):
		var tub := MeshInstance3D.new()
		tub.name = "SeatTub"
		tub.mesh = _hd_mesh(HD_TUB, "Tub")
		Accent.dress(tub)
		add_child(tub)
	# Realism spike: the dashboard (Luke: "move it [the gauge cluster] up to the rail, and create a true
	# dash board"). The instruments stood alone in the footwell with the open nose showing round them.
	var dashed := hd_parts and ResourceLoader.exists(HD_DASH)
	if dashed:
		var dash := MeshInstance3D.new()
		dash.name = "Dashboard"
		dash.mesh = _hd_mesh(HD_DASH, "Dash")
		Accent.dress(dash)
		add_child(dash)
		# Its top's outer edge is turned up behind the rim light to the lip's underside (from a low head
		# the open nose showed through the slot between them). That lies against the lip, as the light does.
		var seal := MeshInstance3D.new()
		seal.name = "DashboardSeal"
		seal.mesh = _hd_mesh(HD_DASH, "DashSeal")
		add_child(seal)
		seal.add_to_group("under_the_lip")
	var dark := Color(0.09, 0.09, 0.1)
	var gunmetal := Color(0.28, 0.29, 0.31)
	var steel := Color(0.62, 0.64, 0.68)
	var solid := []   # [mesh, transform, colour] for the matte parts
	var metal := []   # ... the polished ones
	var rubber := []
	var paint := []
	var lit := []     # ... small indicator lenses
	var web: Array = [] if Finish.hd else rubber   # harness webbing gets its own weave

	# floor: a deck plate with raised treads, under the seat and the feet (to the cage's edge)
	var floor_y := UP - 0.47
	# Stop ahead of the cushion; the previous plate continued through its volume.
	solid.append([Kit.box(Vector3(0.84, 0.025, 1.1)), Kit.at(Vector3(0, floor_y, 0.0)), dark])
	# The two replaceable tread inserts on this backing are in the textured bezel mesh.
	# footrest bar and pedals, out over the open cage. (Not with the dashboard: it stands from the rim
	# to the deck 0.5 m nearer than they are, and no leg reaches round it. The feet rest at its foot.)
	if not dashed:
		metal.append([Kit.cyl(0.022, 0.022, 0.86, 12), Kit.at(Vector3(0, UP - 0.4, -0.95), Vector3(0, 0, PI / 2.0)), steel])
		for s in [-1.0, 1.0]:
			metal.append([Finish.beveled_plate(Vector3(0.13, 0.03, 0.26), 0.005), Kit.at(Vector3(0.2 * s, UP - 0.36, -0.86), Vector3(-0.6, 0, 0)), gunmetal])
			rubber.append([Kit.box(Vector3(0.11, 0.008, 0.2)), Kit.at(Vector3(0.2 * s, UP - 0.34, -0.865), Vector3(-0.6, 0, 0)), Color(0.15, 0.15, 0.16)])

	# Narrow service consoles beside the working levers. The front of the right console is
	# deliberately spare: the existing physical MODE switch lives above it at z = 0.08.
	# Realism spike (tools/art_console_hd.py): authored housings, faceplates, toggles, guards and
	# knobs replace the boxes and cylinders below. Legends, placards and lenses stay as they were.
	var hd_console := hd_parts and ResourceLoader.exists(HD_CONSOLE)
	for s in [-1.0, 1.0]:
		var cx: float = 0.615 * s
		if hd_console:
			var unit := MeshInstance3D.new()
			unit.name = "ConsoleR" if s > 0.0 else "ConsoleL"
			unit.mesh = _hd_mesh(HD_CONSOLE, str(unit.name))
			add_child(unit)
		else:
			solid.append([Kit.rounded_box(Vector3(0.13, 0.26, 0.95), 7.0, 6), Kit.at(Vector3(cx, UP - 0.36, 0.42)), Color(0.12, 0.13, 0.145)])
		# Separate black gasket, machined edge, and powder-coated removable faceplate.
		if not hd_console:
			rubber.append([Finish.beveled_plate(Vector3(0.116, 0.008, 0.866)), Kit.at(Vector3(cx, UP - 0.226, 0.435)), Color(0.022, 0.025, 0.028)])
			metal.append([Finish.beveled_plate(Vector3(0.113, 0.005, 0.858)), Kit.at(Vector3(cx, UP - 0.22, 0.435)), Color(0.37, 0.39, 0.42)])
			solid.append([Finish.beveled_plate(Vector3(0.108, 0.004, 0.852), 0.0015), Kit.at(Vector3(cx, UP - 0.216, 0.435)), Color(0.065, 0.077, 0.09)])
		var face_y := UP - 0.214
		for dx in [-0.043, 0.043]:
			for z in [0.026, 0.844]:
				if not hd_console:
					_fastener(Vector3(cx + dx, face_y, z), metal, rubber)
		# (push 44: the toggles' legends, their lenses and their bats are the live switches' own, built last;
		# vr/console_switches.gd. AUX PWR, COMMS, TRIM and BINDER, COOLANT, STAB are TAC HUD, FIELD,
		# AUTOPILOT and GATES, HEAT, RUSH.)
		for k in 3:
			var z := 0.28 + k * 0.14
			if not hd_console:
				_toggle(Vector3(cx, face_y, z), metal, rubber, paint)
			# Tiny inset status lens, with a metal socket: no luminous button slabs.
			metal.append([Finish.washer(0.0028, 0.0042, 0.0018, 10), Kit.at(Vector3(cx + 0.042 * s, face_y + 0.001, z)), gunmetal])
		for k in 2:
			var z := 0.70 + k * 0.135
			if not hd_console and not ConsoleSwitchesScript.live_knob(s, k):
				_knob(Vector3(cx, face_y, z), metal, rubber, paint)
			_top_legend(Vector3(cx, face_y + 0.001, z - 0.042), ConsoleSwitchesScript.knob_legend(s, k))
		# (the port console's placard under its POWER button and switch, 2026-11-24: they stand where it stood)
		_placard(Vector3(cx - 0.066 * s, UP - 0.31 if s > 0.0 else UP - 0.39, 0.48 if s > 0.0 else 0.385), ConsoleSwitchesScript.PLACARDS[int(s)], s)

	# throttle quadrant: a gate plate round each lever, slot and burner gate
	for s in [-1.0, 1.0]:
		var q := Vector3(0.46 * s, 0.125, 0.2)   # just above the lever pivots (the floor curves up out here)
		if fleet_controls:
			solid.append([FleetThrottle.quadrant(), Kit.at(q), Color("#3b3e42")])
			var screw := Finish.socket_screw(.004, Color("#a1a4a9"), true)
			for dx in [-.034,.034]:
				var marker := FleetThrottle.lens(.012,.002,.012)
				paint.append([marker, Kit.at(q+Vector3(dx,.019,-.105)),Color(1.0,.50,.1)])
				for z in [-.155,.155]:
					metal.append([screw, Kit.at(q+Vector3(dx,.015,z)), Color.WHITE,true])
			continue
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
	# (The pilot craft lay their own harness on their own seats: vr/fleet_flight_deck.gd fit_harness.)
	var strap := Color(0.6, 0.08, 0.06)
	for s in ([] if fleet_controls else [-1.0, 1.0]):
		web.append([Kit.box(Vector3(0.05, 0.62, 0.012)), Transform3D(Basis.from_euler(Vector3(-0.12, 0, 0)), Vector3(0.11 * s, 0.6, 1.012)), strap])
		web.append([Kit.box(Vector3(0.25, 0.05, 0.012)), Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0.35 * s, 0)), Vector3(0.14 * s, 0.215, 0.76)), strap])
	if not fleet_controls:
		metal.append([Kit.rounded_box(Vector3(0.08, 0.06, 0.02), 5.0, 5), Kit.at(Vector3(0, 0.222, 0.72), Vector3(-PI / 2.0, 0, 0)), steel])

	_batch(solid, Finish.powder_coat(), "PowderCoatedPanels")
	_batch(metal, Finish.machined(), "MachinedHardware")
	_batch(rubber, Finish.rubber(), "RubberAndHarness")
	_batch(paint, Finish.painted_metal(), "GuardAndGatePaint")
	if not lit.is_empty():      # (the consoles' lenses were its only parts: they are the live switches' now)
		_batch(lit, Finish.indicator(), "InsetIndicators")
	if Finish.hd:
		_batch(web, Finish.webbing(), "HarnessWebbing")

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

	# rim light: a slim bar tucked up under the coaming's hem, all the way round (Luke: "the blue line
	# that runs around the edge still looks low poly and floats in some places": it was a 96-sided
	# hexagonal tube hung in the air 0.16 m under the rim and 0.05 m inside it, touching nothing but
	# the consoles it ran through). A dark holder against the hem, the lens along its inner corner.
	var bars := _rim_bar()
	var holder := MeshInstance3D.new()
	holder.name = "RimLightHolder"
	holder.mesh = bars[0]
	holder.material_override = Finish.rubber()
	add_child(holder)
	var rmi := MeshInstance3D.new()
	rmi.name = "RimLighting"
	rmi.mesh = bars[1]
	rim_mat = StandardMaterial3D.new()
	rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim_mat.albedo_color = MODE_LIGHT.normal
	rmi.material_override = rim_mat
	rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rmi)
	for bar: MeshInstance3D in [holder, rmi]:
		bar.add_to_group("under_the_lip")    # fastened against the lip's underside: the fittings' check holds it out of the lip, not a margin clear of it (tests/test_cables.gd)
	parts_built = solid.size() + metal.size() + rubber.size() + paint.size() + lit.size() + 5 + hoses.size() + 1
	# the consoles' live switches: their bats and two knobs cut out of the consoles just built, their lenses and legends
	switches = ConsoleSwitchesScript.new()
	add_child(switches)
	switches.build(self)


const RIM_STATIONS := 384         # round the opening: 12 mm apart at most, no facet wider than a quarter of a degree from the seat
const RIM_INSET := 0.0195         # the bar's middle, in from the opening's edge ...
const RIM_DROP := 0.0590          # ... and under the hull's top there: against the coaming's lower hem (0.020 m in, 0.050 m down)
const RIM_HOLDER := [Vector2(-0.0046, 0.0052), Vector2(0.0030, 0.0052), Vector2(0.0046, 0.0036), Vector2(0.0046, -0.0010),
	Vector2(0.0022, -0.0052), Vector2(-0.0030, -0.0052), Vector2(-0.0046, -0.0036), Vector2(-0.0046, 0.0036)]   # its section: (toward the seat, up), m
const RIM_LENS := [Vector2(0.0047, 0.0026), Vector2(0.0060, 0.0002), Vector2(0.0054, -0.0024), Vector2(0.0034, -0.0048), Vector2(0.0012, -0.0058)]   # the lens along its inner lower corner, a millimetre proud


const RIM_REACH := deg_to_rad(136.5)   # it runs this far round from the nose each way: as far as the coaming it hangs under (138 degrees)


## The rim light's holder and lens as two meshes, swept round the opening from the coaming's one end
## to its other (behind the seat's shoulders there is no hem to hang it from, and nobody to see it).
func _rim_bar() -> Array:
	var frames := []      # [the bar's middle, toward the seat, up] or null where it is cut
	for k in RIM_STATIONS + 1:
		var ph := TAU * k / RIM_STATIONS
		var edge := CM.open_edge(ph)
		var x := edge.x
		var z := edge.y
		var inward := Vector3(-cos(ph) / CM.OPEN_AX, 0.0, -sin(ph) / (CM.OPEN_AZ_FRONT if sin(ph) < 0.0 else CM.OPEN_AZ)).normalized()
		var at := Vector3(x, CM.hull_top(x, z) + UP - RIM_DROP, z) + inward * RIM_INSET
		var from_nose := absf(angle_difference(-PI / 2.0, ph))
		frames.append(null if from_nose > RIM_REACH or _occupied(at, 0.012) else [at, inward, Vector3.UP])
	var out := []
	for section: Array in [RIM_HOLDER, RIM_LENS]:
		var closed: bool = section == RIM_HOLDER
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(0)
		st.set_color(Color(0.035, 0.037, 0.042))     # (the holder's rubber takes its colour from the vertices)
		var m := section.size()
		for k in RIM_STATIONS + 1:
			# an end cap wherever a run of the holder starts or stops
			var here: bool = frames[k] != null
			var before: bool = k > 0 and frames[k - 1] != null
			var after: bool = k < RIM_STATIONS and frames[k + 1] != null
			if closed and here and (not before or not after) and (before or after):
				var along: Vector3 = (frames[k + 1][0] - frames[k][0]) if after else (frames[k][0] - frames[k - 1][0])
				var facing: Vector3 = -along if after else along
				for j in range(1, m - 1):
					var tri := [0, j, j + 1].map(func(i): return frames[k][0] + frames[k][1] * section[i].x + frames[k][2] * section[i].y)
					var flip: bool = (tri[1] - tri[0]).cross(tri[2] - tri[0]).dot(facing) > 0.0
					for p: Vector3 in ([tri[0], tri[2], tri[1]] if flip else tri):
						st.add_vertex(p)
		for k in RIM_STATIONS:
			if frames[k] == null or frames[k + 1] == null:
				continue
			for j in (m if closed else m - 1):
				var a: Vector2 = section[j]
				var b: Vector2 = section[(j + 1) % m]
				var p0: Vector3 = frames[k][0] + frames[k][1] * a.x + frames[k][2] * a.y
				var p1: Vector3 = frames[k][0] + frames[k][1] * b.x + frames[k][2] * b.y
				var q0: Vector3 = frames[k + 1][0] + frames[k + 1][1] * a.x + frames[k + 1][2] * a.y
				var q1: Vector3 = frames[k + 1][0] + frames[k + 1][1] * b.x + frames[k + 1][2] * b.y
				var outward: Vector3 = frames[k][1] * (a.x + b.x) + frames[k][2] * (a.y + b.y)
				for tri in [[p0, p1, q0], [p1, q1, q0]]:
					var flip: bool = (tri[1] - tri[0]).cross(tri[2] - tri[0]).dot(outward) > 0.0   # (Godot's fronts wind clockwise)
					for p: Vector3 in ([tri[0], tri[2], tri[1]] if flip else tri):
						st.add_vertex(p)
		st.index()
		st.generate_normals()
		out.append(st.commit())
	return out


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
	# (the bat itself, a stem and its ball, is the live switch's: vr/console_switches.gd)
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
	rim_mat.albedo_color = (rest if mode == "normal" else MODE_LIGHT.get(mode, rest)) * _power
	rim_mat.albedo_color.a = 1.0


## The battery bus, 0 dead .. 1 (vr/startup_sequence.gd): no power, no rim light.
func set_power(level: float) -> void:
	if is_equal_approx(level, _power):
		return
	_power = level
	_mode = ""      # (so the next set_mode draws it again)


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
