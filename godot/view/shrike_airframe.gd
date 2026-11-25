## Shrike RS bodywork. Shared static meshes use the same pivots as the moving
## brakes, rotors and nozzle. Forward is local -Z, and out points away from the pilot.
extends RefCounted

const Kit := preload("res://view/mesh_kit.gd")
const Finish := preload("res://view/craft_materials.gd")
const FleetAirframe := preload("res://view/fleet_airframe.gd")
const Livery := preload("res://view/livery.gd")
const Accent := preload("res://view/accent.gd")
const PETROL := Color("#12666a")
const IVORY := Color("#f1e5c9")
const COPPER := Color("#e49749")
const CARBON := Color("#243236")
const ALLOY := Color("#9caead")
# The atlas's own colours (tools/art_shrike_finish.py: TEAL, IVORY, GOLD), as its livery mask's channels
# mark them (tools/art_livery_masks.py): in a livery the teal enamel takes its paint, the ivory bands its
# pin and the gold pinstripe its stripe, as the other pilot craft's do (FleetAirframe.colours()). Its
# numbers and names stay as printed, but for the dark ones on its bands when the bands go dark (they are
# printed in the paint then, to read: FleetAirframe.lettering()).
const ATLAS_TEAL := Color8(21, 90, 95)
const ATLAS_IVORY := Color8(218, 214, 191)
const ATLAS_GOLD := Color8(213, 140, 65)
const ATLAS_DARK := Color8(23, 33, 37)
const MASK := "res://art/shrike/livery_mask.png"
static var meshes: Dictionary
static var dressed := {}          # the parts again in a livery's finish: {livery: {part: mesh}} (the last livery asked for)
static var pod_paint: StandardMaterial3D
static var fittings: ShaderMaterial
static var _liveried := {}        # livery -> [its pod paint, its fittings]


## Only a selected Shrike loads these meshes and maps. Both engines, all four
## fans, the moving leaves and the pilot shell share one atlas and material,
## its factory finish; in a livery (view/livery.gd), copies of them share one in that livery.
static func part(id: StringName) -> Mesh:
	if meshes.is_empty():
		var scene := (load("res://art/shrike/bodywork.glb") as PackedScene).instantiate()
		var finish := FleetAirframe.finish_for(load("res://art/shrike/enamel.tres") as StandardMaterial3D)
		for node in scene.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = node.mesh
			mesh.surface_set_material(0, finish)
			meshes[node.name] = mesh
		scene.free()
	if Livery.is_factory():
		return meshes[id]
	var livery := Livery.table_id()
	if not dressed.has(livery):
		var finish := FleetAirframe.finish_for(load("res://art/shrike/enamel.tres") as StandardMaterial3D)
		FleetAirframe.repaint(finish, load(MASK), colours())
		var parts := {}
		for key in meshes:
			var own := (meshes[key] as Mesh).duplicate() as Mesh
			own.surface_set_material(0, finish)
			parts[key] = own
		dressed = {livery: parts}      # (a craft already built in another keeps its own copies)
	return dressed[livery][id]


## The atlas's colours in the current livery, as [own, livery's] for each of its mask's channels.
static func colours() -> Array:
	return [[ATLAS_TEAL, Livery.coat("paint")], [ATLAS_IVORY, Livery.coat("pin")], [ATLAS_GOLD, Livery.coat("stripe")],
		[ATLAS_DARK, FleetAirframe.lettering(ATLAS_DARK)]]


## Let go of what a Shrike loaded (the title does, when the flight starting is not in one).
static func release() -> void:
	meshes.clear()
	dressed.clear()
	_liveried.clear()


## The fin's tip as it was authored (at FIN_CANT), engine-local. It moves now: see fin_solve().
static func fin_tip(out: float) -> Vector3:
	return Vector3(out * (0.77 + 1.62*sin(FIN_CANT)), 0.25 + 1.62*cos(FIN_CANT), 1.98)


## The engine's fixed lamps (the fin's own tip lamp rides the fin: fin_lamp()).
static func lights(out: float) -> ArrayMesh:
	return Kit.compound([
		[Kit.box(Vector3(0.44, 0.04, 0.035)), Kit.at(Vector3(0, 0.39, 4.0)), Color("#e84432")],
		[Kit.box(Vector3(0.09, 0.045, 0.08)), Kit.at(Vector3(out * 0.81, -0.39, -3.92)), IVORY]])


# ---- the engine fins ----
# Each engine's fin turns on a hinge along its root, moved by one hydraulic ram (Luke: "find a way to
# animate its engine fins with speed - they should angle via a hydraulic arm"). Standing tall parked and
# slow, it lays out as the craft gathers speed: FIN_REST from upright at rest, the angle it was drawn at
# at half FIN_FAST_MPH, FIN_FAST from FIN_FAST_MPH up, eased at both ends, and never faster than the
# ram can stroke. The parts are authored about their pins (tools/art_shrike_airframe.py, which holds
# these same numbers): the fin about its hinge line, the ram's cylinder about the bracket's pin on the
# nacelle's back, its rod about the pin in the fin's lug. Both pins and the hinge lie along the engine,
# so the ram works in one plane across it: a crank and a slider.
const FIN_CANT := 0.76                 # rad from upright, leaning outboard: as the fin was authored
const FIN_REST := 0.48                 # standing tall
const FIN_FAST := 1.04                 # laid out
const FIN_FAST_MPH := 5000.0           # (Luke's flying, 2026-11-21: median 2,800 to 3,400 mph, 90% under 5,300: mid-travel where he
                                       # mostly is, laid right out on the fast straights, standing up as he brakes for a corner)
const FIN_SLEW := 0.30                 # rad/s: the ram's own speed (the whole travel in under two seconds)
const FIN_HINGE := Vector3(0.9353, 0.4240, 0.0)    # engine-local, outboard +x: where the fin's line leaves the skin
const RAM_PIN := Vector3(0.2323, 0.4690, 0.80)     # the lug's pin, in the fin's frame (outboard +x)
const RAM_BASE := Vector3(0.30, 0.5907, 0.80)      # the bracket's pin, engine-local (outboard +x)
const RAM_BARREL := 0.52               # the cylinder, pin to gland
const RAM_ROD := 0.65                  # the rod, pin to piston
# The fins answer a turn as well (Luke: "The engine fins should rotate left/right as well as up/down with
# turning"; view/fin_steering.gd has what they answer and how it is eased).
# Left and right: the fin is in two parts. The stub keeps the hinge and the ram and does what the whole fin
# did. The panel above it (from PANEL_CUT up the fin: the upper half of what stands clear of the engine) stands on a spindle
# up the fin's own line through the stub's head, and a rotary actuator round the spindle swings it, trailing
# edge into the turn as a rudder goes: the drum at the stub's head, its two lines down the stub's inboard
# face. Nothing else could turn: the hinge's tube lies in three saddles along the engine, so the whole fin
# cannot; the cut is over the ram's lug so the ram never meets the panel; and the spindle is at the station
# where the engine's own air-brake leaf, open, stands nearest the fin, so the panel hardly moves there.
# Up and down: in a turn the inside engine's fin lays out FIN_LEAN further and the outside engine's stands
# up as much, on top of the speed's cant: the two lean into the turn together. Never past the ram's own
# travel (FIN_REST to FIN_FAST), so parked only the inside fin moves, and flat out only the outside one.
const PANEL_CUT := 0.70                # m up the fin from its hinge: the stub's head, the panel's foot
const PANEL_Z := 1.45                  # the spindle's station along the engine
const PANEL_SWING := deg_to_rad(20.0)  # as far as the panel swings either way, in the hardest turn
const PANEL_SLEW := deg_to_rad(60.0)   # ... and no faster than this, a second
const FIN_LEAN := 0.20                 # rad: the hardest turn's share of the cant


## Where the fin stands at a speed: rad from upright.
static func fin_cant(mph: float) -> float:
	return lerpf(FIN_REST, FIN_FAST, smoothstep(0.0, FIN_FAST_MPH, mph))


## One engine's fin and ram at a cant, engine-local (out: -1 the port engine, 1 the starboard):
## {fin, barrel, rod: Transform3D; hinge, pin, base: Vector3; span: the ram pin to pin; showing: the rod
## out of the gland; piston: the piston's place up the barrel from the bracket's pin}.
static func fin_solve(out: float, cant: float) -> Dictionary:
	var hinge := Vector3(out * FIN_HINGE.x, FIN_HINGE.y, FIN_HINGE.z)
	var fin := Transform3D(Basis(Vector3.BACK, -out * (cant - FIN_CANT)), hinge)
	var pin: Vector3 = fin * Vector3(out * RAM_PIN.x, RAM_PIN.y, RAM_PIN.z)
	var base := Vector3(out * RAM_BASE.x, RAM_BASE.y, RAM_BASE.z)
	var span := pin.distance_to(base)
	var y := (pin - base) / span           # along the ram, bracket to lug
	var x := y.cross(Vector3.BACK)
	return {"fin": fin, "barrel": Transform3D(Basis(x, y, Vector3.BACK), base), "rod": Transform3D(Basis(-x, -y, Vector3.BACK), pin),
		"hinge": hinge, "pin": pin, "base": base, "span": span, "showing": span - RAM_BARREL, "piston": span - RAM_ROD}


## The fin's tip in its own frame (about its hinge), unswung.
static func fin_tip_local(out: float) -> Vector3:
	return fin_tip(out) - Vector3(out * FIN_HINGE.x, FIN_HINGE.y, FIN_HINGE.z)


## The foot of the panel's spindle, in the fin's own frame.
static func panel_foot(out: float) -> Vector3:
	return Vector3(out * PANEL_CUT * sin(FIN_CANT), PANEL_CUT * cos(FIN_CANT), PANEL_Z)


## The panel on its spindle, in the fin's own frame: swung `swing` rad about the fin's own line
## (+ = its trailing edge to the engine's right, a right turn's).
static func panel_place(out: float, swing: float) -> Transform3D:
	return Transform3D(Basis(Vector3(out * sin(FIN_CANT), cos(FIN_CANT), 0.0), swing), panel_foot(out))


## The fin's tip in the panel's own frame (about its spindle's foot), and the nav lamp that rides there.
static func panel_tip(out: float) -> Vector3:
	return fin_tip_local(out) - panel_foot(out)


static func fin_lamp(out: float) -> ArrayMesh:
	return Kit.compound([[Kit.ball(0.057, 10), Kit.at(panel_tip(out) + Vector3(-0.08*out, -0.09, 0.09)),
		Color("#ef413b") if out < 0 else Color("#49dc91")]])


static func dress_pod(hull: MeshInstance3D) -> void:
	if pod_paint == null:
		pod_paint = Finish.painted_metal().duplicate()
		pod_paint.vertex_color_use_as_albedo = false
		pod_paint.albedo_color = PETROL
		pod_paint.clearcoat_enabled = true
		pod_paint.clearcoat = 0.8
		fittings = ShaderMaterial.new()
		fittings.shader = preload("res://view/shrike_trim.gdshader")
	var paint := pod_paint
	var piped := fittings
	if not Livery.is_factory():      # its paint, and the trim's enamel, in the livery's paint
		var livery := Livery.table_id()
		if not _liveried.has(livery):
			var coat := pod_paint.duplicate() as StandardMaterial3D
			coat.albedo_color = Livery.coat("paint")
			var piping := ShaderMaterial.new()
			piping.shader = fittings.shader
			piping.set_shader_parameter("enamel", Livery.coat("paint"))
			_liveried[livery] = [coat, piping]
		paint = _liveried[livery][0]
		piped = _liveried[livery][1]
	# The nose tow pins retain their machined metal finish.
	hull.set_surface_override_material(5, paint)
	hull.set_surface_override_material(6, piped)
	var trim := MeshInstance3D.new()
	trim.name = "ShrikeStrakes"
	trim.add_to_group("exterior")
	trim.mesh = part(&"PodStrakes")
	hull.add_child(trim)
	# The lamp carriers overhang the tapered tail. Tie them back to the actual
	# hull with six short stays; their curved backing used to hang in space.
	var host := hull.mesh.generate_triangle_mesh()
	var stays := []
	for side in [-1.0, 1.0]:
		for t in [.18, .50, .82]:
			var lamp := Vector3(side * (.08 + .81*t), -.041 + .092*t + .016*sin(PI*t), 2.29-.17*t-.33*t*t-.005)
			var hit := host.intersect_ray(Vector3(lamp.x, 1.0, lamp.z-.30), Vector3.DOWN)
			if hit.is_empty():
				push_error("Shrike tail lamp stay has no hull attachment")
				continue
			var foot: Vector3 = hit.position - Vector3.UP*.004
			var end := lamp - Vector3.UP*.012
			var span := end-foot
			var frame := Transform3D(Basis.looking_at(-span.normalized(),Vector3.UP),(end+foot)*.5)
			stays.append([Kit.rounded_box(Vector3(.042,.024,span.length()+.012),5.0,8),frame,CARBON])
			stays.append([Kit.rounded_box(Vector3(.072,.014,.074),5.0,8),Kit.at(foot),CARBON])
			stays.append([Kit.cyl(.010,.010,.012,10),Kit.at(foot+Vector3(0,.010,-.019)),ALLOY])
	var supports := MeshInstance3D.new()
	supports.name = "TailLampMounts"
	supports.add_to_group("exterior")
	supports.mesh = Kit.compound(stays)
	supports.material_override = Finish.powder_coat()
	hull.add_child(supports)


static func fit_seat(parent: Node3D, offset := Vector3.ZERO) -> void:
	for id in [&"SeatBack", &"SeatPan"]:
		var piece := MeshInstance3D.new()
		piece.name = "seat_back" if id == &"SeatBack" else "seat_cushion"
		piece.mesh = part(id)
		piece.position = offset
		parent.add_child(piece)


# The HD coaming's colour map carries the Phaethon's own nameplate on its facing (tools/art_coaming_hd.py
# paints it there; the Shrike's map is that one re-enamelled). In the cabin it is this rectangle, found by
# following the map's texels through the model: 183 by 46 mm, upright. The Shrike's badge goes over it.
const NAMEPLATE := [Vector3(-0.0915, 0.5331, -0.5002), Vector3(0.0915, 0.5795, -0.5002)]
const COAMING_Y := 0.558               # the badge's and the tow-load windows' height on the HD coaming


static func dress_coaming(coaming: MeshInstance3D, hd: bool) -> ShaderMaterial:
	if hd and Livery.is_factory():
		var original := coaming.mesh.surface_get_material(0) as BaseMaterial3D
		var livery := original.duplicate() as BaseMaterial3D
		livery.albedo_texture = load("res://art/cockpit/shrike_coaming.webp")
		coaming.set_surface_override_material(0, livery)
	elif hd:      # in a livery: the coaming's own enamel, which its teal map re-enamels, in the livery's paint
		coaming.set_surface_override_material(0, Accent.turned(coaming.mesh.surface_get_material(0), Livery.coat("paint")))
	var plate := MeshInstance3D.new()
	plate.name = "ShrikePlate"
	# The HD coaming follows the shorter, egg-shaped opening. The original
	# flight-deck mesh still has the longer nose and its nearly upright face.
	if hd:
		# (16 mm lower than first remounted: there it left the bottom third of the map's own PHAETHON
		# nameplate showing under its edge, NAMEPLATE below. tests/test_shrike_preflight.gd looks.)
		plate.transform = Kit.at(Vector3(0, COAMING_Y, -0.496), Vector3(-0.22, 0, 0))
	else:
		plate.position = Vector3(0, 0.578, -0.911)
	plate.mesh = Kit.compound([
		[Finish.beveled_plate(Vector3(0.216, 0.057, 0.014), 0.003), Transform3D.IDENTITY, ALLOY],
		[Finish.beveled_plate(Vector3(0.211, 0.052, 0.008), 0.002), Kit.at(Vector3(0, 0, 0.006)), CARBON],
		[Kit.cyl(0.003, 0.003, 0.003), Kit.at(Vector3(-0.097, 0, 0.011), Vector3(PI/2, 0, 0)), COPPER],
		[Kit.cyl(0.003, 0.003, 0.003), Kit.at(Vector3(0.097, 0, 0.011), Vector3(PI/2, 0, 0)), COPPER]])
	plate.material_override = Finish.machined()
	plate.add_to_group("exterior")
	coaming.add_child(plate)
	var mark := Label3D.new()
	mark.text = "SHRIKE  RS"
	mark.font_size = 60
	mark.pixel_size = 0.00047
	mark.outline_size = 0
	mark.modulate = IVORY
	mark.position.z = 0.0115
	mark.add_to_group("exterior")
	plate.add_child(mark)

	# Recessed load windows on either side of the badge follow the coaming's arc.
	var bars := SurfaceTool.new()
	bars.begin(Mesh.PRIMITIVE_TRIANGLES)
	var housings := []
	for side in [-1.0, 1.0]:
		var mount := Kit.at(Vector3(side*0.180, 0.578, -0.888), Vector3(0, -side*0.34, 0))
		if hd:
			mount = Kit.at(Vector3(side*0.180, COAMING_Y, -0.476), Vector3(-0.22, -side*0.29, 0))
		housings.append([Finish.beveled_plate(Vector3(0.139,0.048,0.012),0.003), mount, CARBON])
		var legend := Label3D.new()
		legend.text = "L  TOW" if side < 0.0 else "TOW  R"
		legend.font_size = 40
		legend.pixel_size = 0.00030
		legend.outline_size = 0
		legend.modulate = IVORY
		legend.transform = mount * Transform3D(Basis.IDENTITY, Vector3(0,-0.011,0.008))
		legend.add_to_group("exterior")
		coaming.add_child(legend)
		for corner in [0,2,1,0,3,2]:
			var x := -0.063 if corner in [0,3] else 0.063
			var y := 0.001 if corner in [0,1] else 0.016
			bars.set_uv(Vector2(0.5 + side*x/0.126, 0.25 if side < 0.0 else 0.75))
			bars.set_normal(mount.basis.z)
			bars.add_vertex(mount * Vector3(x,y,0.007))
	var surround := MeshInstance3D.new()
	surround.mesh = Kit.compound(housings)
	surround.material_override = Finish.powder_coat()
	surround.add_to_group("exterior")
	coaming.add_child(surround)
	var glass := MeshInstance3D.new()
	glass.name = "TowLoad"
	glass.mesh = bars.commit()
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glass.add_to_group("exterior")
	var meter := ShaderMaterial.new()
	meter.shader = preload("res://view/shrike_tow_meter.gdshader")
	glass.material_override = meter
	coaming.add_child(glass)
	return meter
