## What the podracer looks like. Two engines: intake lip and a fan that spins up with thrust,
## front speed brakes (a petal on each flank, out with the brakes at high speed),
## a nacelle in livery, a hot section that glows with heat (the old whole-engine heat colours,
## now where the heat is), fins, and four split air-brake flaps, red inside, around the hot
## section. Each engine's flaps follow that engine's own brake. The pod: one smooth lofted
## hull (pod_hull(): rounded-box sections swelling through the cockpit, a rounded nose, a
## headrest fairing; an open cockpit with a rubber lip; matte trim inside), polished metal
## below and its top decks and nose in clear-coated candy orange (from the seat the sills
## either side read as paint, not a black mirror of the road), a gunmetal racing stripe down
## each flank, white pinstripes where the paint meets the metal; a painted raked fin with a
## tip lamp, side intakes, trim thrusters with polished collars and exhaust cones, nav lights,
## tail lamps and a cyan repulsor underglow (as the engines'), the cable hardpoints on the
## nose, and two rounded flaps that follow the pod's brake, which (as in the sim) is the
## lesser of the two. The VR cockpit sits inside the same hull.
## Engines and pod list into turns like aircraft: each banks by its own lateral g (smoothed,
## easing toward BANK_MAX, roll rate capped so it builds rather than snaps), and the VR cockpit
## rolls with the pod. Visual only: the sim is flat.
## A tow link runs from the lug under each engine's tail to the bullring on the pod's nose, where
## the sim anchors it (either side of centre): a telescoping drawbar, jointed at both ends
## (view/tow_link.gd; they were ropes that sagged and twanged). The binder arc crackles between the
## engines. In VR the pod is hidden (you sit in it), so the view hands over its cockpit frame
## (pod_frame), which carries the same hull, nose and bullring. Each engine ends in a
## tailpipe you can see up, a nozzle whose flaps open and shut with the power, and three vanes that
## steer the jet; the jet is a volume of gas (view/flame.gdshader) on a centre line traced here
## (_trace_plume). What they do, and what in real engines each part of that rests on, is
## view/jet_exhaust.gd's. The fins answer a turn as well: the Phaethon's rudders and stabilisers, the
## Shrike's fin panels and rams (view/fin_steering.gd, view/shrike_airframe.gd).
## The Talon (sim/pilot_craft.gd TALON) is this craft, the Phaethon, in Codex's swept twin-tail starfighter body
## (view/talon_airframe.gd): the same hull and engines, his plating on the hull, his fins on the engines in place of
## the dorsal fin and stabiliser (and their moving parts), his ventral brakes in place of the pod's flaps, his lamps.
##   add_child(model); model.build(view)          once
##   model.sync(sim, inp, delta)                  every frame, after the floating origin moves
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")
const Fairings := preload("res://view/craft_fairings.gd")
const Finishes := preload("res://view/craft_materials.gd")
const TowLink := preload("res://view/tow_link.gd")
const Fins := preload("res://view/fin_steering.gd")
const STEEL := Color(0.60, 0.65, 0.70)
const HOT := Color(1.0, 0.54, 0.16)
const WHITE := Color(1.0, 0.96, 0.86)
const LIVERY := Color(0.86, 0.27, 0.09)
const DARK := Color(0.13, 0.13, 0.15)
const SILVER := Color(0.80, 0.82, 0.86)
# Pod hull keyframes, pod-local (forward -Z): [z, half-width, bottom y, top y]. Rounded-box
# sections (superellipse, HULL_N) swell through the cockpit, round off at the nose, and rise
# into a headrest fairing behind the seat. Catmull-Rom between keyframes.
const HULL := [[-2.22, 0.06, -0.19, -0.11], [-2.12, 0.30, -0.28, -0.05], [-1.90, 0.62, -0.40, -0.01],
	[-1.50, 0.90, -0.50, 0.00], [-1.00, 1.06, -0.56, -0.02], [-0.40, 1.13, -0.58, -0.05],
	[0.40, 1.15, -0.58, -0.06], [1.05, 1.11, -0.56, 0.04], [1.45, 0.98, -0.51, 0.17],
	[1.80, 0.68, -0.42, 0.12], [2.02, 0.42, -0.31, 0.03], [2.15, 0.18, -0.18, -0.04]]
const HULL_N := 2.6
const Livery := preload("res://view/livery.gd")   # the paint a craft is built in: these four are Ember's, the craft's own
const Accent := preload("res://view/accent.gd")
const PAINT := Color(0.95, 0.42, 0.08)    # the top decks' and nose's candy orange (clear-coated)
const STRIPE := Color(0.11, 0.12, 0.14)   # the flanks' racing stripe: gunmetal
const PIN := Color(0.96, 0.95, 0.9)       # the pinstripes where the paint meets the metal
const PAINT_SY := 0.42                    # paint above this share of the section's half-height
const UNDERGLOW := Color(0.2, 0.75, 1.0)  # the repulsor glow under the pod (the engines' colour)
const OPEN_ZC := 0.15        # cockpit opening: an egg in plan around the seat, widest at this station ...
const OPEN_AZ := 1.15        # ... its half-length aft of there ...
const OPEN_AZ_FRONT := 0.72  # ... and ahead of there: the rail is close in front of the pilot, over a true dashboard
                             # (Luke: "remove 12 inches of 'legroom' between the gauges and seat. The idea is to have good
                             # visibility through the smallest opening possible", and of the gauges, "move it up to the
                             # rail"). It was 1.15 either way: the rail 1.6 m ahead of the eye, the gauges alone in the well.
const OPEN_AX := 0.72
const SKIN := 0.035          # hull thickness (outer skin to inner trim)
const CAGE_Z0 := -0.6        # the nose is an open tube cage from here (the footwell) ...
const CAGE_Z1 := -1.95       # ... to here, where a solid cap carries the cable hardpoints, so
                             # you see the track coming through it (Luke: "a skeleton frame at the
                             # foot hull so that I can see what's coming")
const CAGE_R := 0.02         # hoop radius: covers the skin's cut edges (> SKIN / 2); longerons thinner
const RIB_IN := SKIN + 0.008 # (the closed nose) its frames stand this far in from the outer skin: on the trim's inner face ...
const RIB_R := 0.014         # ... and are this thick: proud of the trim inside, never through the skin outside
## The nose skinned over instead of an open cage: a spike option, to fly both (Luke: "I'm curious how
## it would look if we enclosed the front of the pod, now that the vehicle tilts and i can see apex
## lines"). The skin and the trim run through the cage's length, the top decks' paint and the
## pinstripes run on to the painted nose, and the cage's hoops and longerons stay as frames and
## stringers inside. Set it with set_nose_closed(): each hull is built once and kept.
static var nose_closed := false
static var _hulls := {}      # "livery:nose:machine" -> that hull, built once
const FLAP_OPEN := deg_to_rad(68.0)   # full brake
const FLAP_RATE := 9.0                # flap travel, full range per second (~0.11 s open or shut)
# The engines are flat rounded slabs (Luke: "horizontally flat, rounded rectangular prisms"),
# 2.4 m wide (the sim's 1.2 m collision radius) by 0.96 m tall. Air brakes: two flaps on top, two
# underneath, [x, top (+1) or bottom (-1)], hinged at the front edge on the skin.
const Fleet := preload("res://view/fleet_airframe.gd")
var fleet: Fleet
var turret = null    # the Basilisk's gun (view/turret.gd), on the pod; view/gunnery.gd lays and fires it
var weapon = null    # what view/gunnery.gd fires through (view/weapons/weapon_mount.gd): the Basilisk's, its turret's mount;
                     # the Phaethon's and the Talon's, their arms' fixed guns (view/weapons/fixed_guns_mount.gd); the
                     # Shrike's, its missiles (view/weapons/missile_mount.gd); the Kiln's, its lance
                     # (view/weapons/lance_mount.gd)
var arms = null      # the craft's weapon hardware, hidden in its hull until armed (view/arms/<craft>_arms.gd; sim/pilot_craft.gd
                     # WEAPONS): the Phaethon's cannons on its engines, the Talon's wing guns on its pod; null for the rest
                     # (the Basilisk's gun is its turret; the Shrike's and the Kiln's arms are their mounts', fitted on the
                     # hull the pilot sees at the first arming, or at load with Raids on)
const ARMS := {"cannons": preload("res://view/arms/phaethon_arms.gd"), "wing_guns": preload("res://view/arms/talon_arms.gd")}
const TurretScript := preload("res://view/turret.gd")
const TurretMountScript := preload("res://view/weapons/turret_mount.gd")
const FixedGunsMountScript := preload("res://view/weapons/fixed_guns_mount.gd")
const MissileMountScript := preload("res://view/weapons/missile_mount.gd")
const LanceMountScript := preload("res://view/weapons/lance_mount.gd")
const Shrike := preload("res://view/shrike_airframe.gd")
const Talon := preload("res://view/talon_airframe.gd")
const PilotCraft := preload("res://sim/pilot_craft.gd")
const ENG_W := 2.4
const ENG_H := 0.96
const FLAPS_AT := [[-0.58, 1.0], [0.58, 1.0], [-0.58, -1.0], [0.58, -1.0]]
const NAV_L := Color(1.0, 0.16, 0.12)   # nav lights: red on the left engine, green on the right (as the walls)
const NAV_R := Color(0.15, 1.0, 0.35)
const BINDER_COL := Color(0.45, 0.85, 1.0)
const FLAP_Z := 1.4                   # hinge station, engine-local (forward is -Z)
const FRONT_Z := -3.25                # front speed brakes' hinge station, just behind the intake lip
const FRONT_OPEN := deg_to_rad(70.0)  # their full swing out
const BANK_MAX := deg_to_rad(62.0)    # the lean eases toward this in the hardest turns
const BANK_G := 12.0                  # lateral g that gives ~76% of BANK_MAX (tanh knee)
const BANK_TAU := 0.32                # lateral-g smoothing, s: the lean eases in ...
const BANK_RATE := deg_to_rad(65.0)   # ... and never rolls in faster than this (Luke: "some sort of ramp to
                                      # the roll"; 55 then felt "artificially slow", so a hair up)
const BANK_TAU_OUT := 0.18            # unwinding: the lean lets go nearly twice as fast ...
const BANK_RATE_OUT := deg_to_rad(85.0)    # ... and rolls back toward level faster (Luke: "especially when
                                           # returning to horizontal")
const ROLL_MAX := deg_to_rad(70.0)    # lean plus the track's banking never rolls you past this

var view
var engines: Array[Node3D] = []
var hot_mats: Array[StandardMaterial3D] = []
var glow_mats: Array[StandardMaterial3D] = []
var fans: Array[Node3D] = []         # per engine: holds its twin intake rotors
var rotors := [[], []]               # per engine: the two fan rotors (spin about their own Z)
var vanes := [[], []]                # per engine: the thrust-vectoring vanes in the nozzle (they swing with the turn)
var vane_angle := 0.0                # their current deflection, radians (+ = trailing edges right, a right turn)
var jets: Array = []                 # per engine: its nozzle and its gas (view/jet_exhaust.gd)
var nozzle_flaps := [[], []]         # per engine: its upper and lower flaps' hinges (they open and shut with the power)
var metal_mats: Array[ShaderMaterial] = []   # per engine: the liner, the vanes and the flaps' faces (they glow when hot)
var strobes: Array[Node3D] = []      # the fin-tip strobes (double flash)
var fin_parts: Array = []            # the Shrike's: per engine [fin (its stub), ram cylinder, ram rod, the fin's outer panel] (view/shrike_airframe.gd)
var fin_cant := Shrike.FIN_REST      # ... where the speed stands its fins now, rad from upright: tall at rest, laid out at speed
var fin_stand := [Shrike.FIN_REST, Shrike.FIN_REST]   # ... where each engine's stands: that, and the turn's lean (the inside one laid out, the outside one stood up)
var fin_ram := [0.0, 0.0]            # ... and how much rod each ram shows, m (tests read it)
# The fins in a turn (view/fin_steering.gd; tests read these).
var fin_drive := 0.0                 # what they answer: g toward the right, eased
var fin_swing := 0.0                 # the rudders (the Shrike's fin panels): rad, + = trailing edges right, a right turn
var fin_pitch := 0.0                 # the Phaethon's stabilisers: rad, + = a right turn's (the starboard engine's trailing edge up, the port's down)
var rudders: Array[Node3D] = []      # the Phaethon's: per engine, where the dorsal fin's rudder stands on its post ...
var stabilisers: Array[Node3D] = []  # ... and the outboard fin's panel on its spindle (pivots: nothing is drawn at them)
var fin_batches: Array[MultiMesh] = []   # ... and what is drawn there: [both engines' rudders, both stabiliser panels], each pair one thing to draw
var _fin_posed := [0.0, 0.0]         # how the parts were last put (the Shrike: each panel's swing; the Phaethon: swing, pitch)
var binder_mats: Array[StandardMaterial3D] = []   # the binder emitters' glowing cores
const FlameShader := preload("res://view/flame.gdshader")
const FlowTexture := preload("res://art/engine/jet_flow.png")
const FlameHolder := preload("res://art/engine/flame_holder.png")
const EffectExclusion := preload("res://view/effect_exclusion.gd")
const Jets := preload("res://view/jet_exhaust.gd")
const NOZZLE_EXIT := 4.70            # the flaps' trailing edges (Jets.EXIT_Z): where the jet leaves
var _flap_phase := [0.0, 2.56]
const PLUME_STATIONS := 12           # the plume's centre line is traced at this many stations (flame.gdshader's STATIONS)
const PLUME_SLOT := Vector2(0.92, 0.25)   # the tailpipe's half-width and half-height, m (the exit's height moves with the flaps)
const PLUME_MAX := 11.1              # the longest plume, m (Jets.REACH_MAX)
static var plumes := true            # (timings: false before build() leaves the jets' gas undrawn)
var flame_mats := [[], []]           # per engine: [the plume's ShaderMaterial] (view/flame.gdshader)
var plume_len := [0.0, 0.0]          # per engine: the plume's length, m
var plume_line := [PackedFloat32Array(), PackedFloat32Array()]   # per engine: its centre line, m to the engine's right at each station
var nozzle_mats: Array[ShaderMaterial] = []   # per engine: the fire in the nozzle (view/nozzle_glow.gdshader)
var nozzle_lights: Array[OmniLight3D] = []   # light the track behind a burning engine
var _burn := [0.0, 0.0]              # eased burner and ramjet shares, per engine
var _ram := [0.0, 0.0]
var flaps := [[], []]                 # per engine: its four hinge nodes
var flap_open := [0.0, 0.0]           # per engine: current opening 0..1 (tests read this)
var front_flaps := [[], []]           # per engine: the front speed brakes' two hinges
var front_open := [0.0, 0.0]          # per engine: their opening 0..1 (the sim's e.front; tests read this)
var flames: Array[Node3D] = []
var pod: MeshInstance3D
var canopy: Node3D                   # the pod's windscreen and forcefield (view/canopy.gd)
const CanopyScript := preload("res://view/canopy.gd")
var pod_flaps: Array[Node3D] = []
var tail_lights: MeshInstance3D
var _brake_signal := Vector2.ZERO
var _tail_powered := true
var pod_flap_open := 0.0
# The tow links (view/tow_link.gd). They keep the names the ropes had, which the cockpit and the tests read.
var cables: Array[MeshInstance3D] = []          # each link's rod (the long lit member)
var cable_mats: Array[StandardMaterial3D] = []  # what each link's lit parts are made of: its thrust glow and strain colour
var cable_ends := [[Vector3.ZERO, Vector3.ZERO], [Vector3.ZERO, Vector3.ZERO]]   # [the engine's lug pin, the pod's swivel post] (tests read)
var cable_sag := [0.0, 0.0]          # how far each link's middle stands off the line between its pins, metres: nothing, it is rigid (tests read)
var cable_strain := [0.0, 0.0]       # each link's tension / CABLE_F_MAX
var link_parts := [[], []]           # each link's parts, pod end first: [swivel, barrel, rod, yoke]
var link_boots: Array[MeshInstance3D] = []   # the boot at each barrel's mouth: it hangs on the barrel, and its length is the telescope's
var link_boot := [0.0, 0.0]          # ... how long each stands, m (TowLink.boot_for)
var link_rod := TowLink.ROD          # how long this craft's rods are (TowLink.rod_for its links' taut length)
var _link_shown := [true, true]
var link_span := [0.0, 0.0]          # each link, pin to pin, metres ...
var link_exposed := [0.0, 0.0]       # ... and how much of its rod shows outside the barrel's gland
var link_travel := [0.0, 0.0]        # the sim's own span less the link's taut length: + stretched into the draft gear, - closed up
var link_angles := [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]]   # each link's joints, radians: [swivel yaw, barrel pitch, yoke pitch, rod yaw]
const BinderArc := preload("res://view/binder_arc.gd")
var arc: Mesh   # (the binder arc's mesh: an ArrayMesh rebuilt each frame)
var binder_arc: MeshInstance3D
# The start-up (vr/startup_sequence.gd), told by the cockpit. An engine that is `held` is dark, as a
# flamed-out one is: no fire, its fan run down, its cable dead. `shown_thrust` is the thrust to draw
# when it is not the sim's (-1: the sim's): the burst as an engine lights, and the run-up's, while the
# parking brake holds the sim's own at nothing. `energised` is the binder's charge, 0 dead .. 1: the
# arc between the engines and the glow in the cables. `lights_on` is the battery: the lamps and strobes.
var held := [false, false]
var shown_thrust := [-1.0, -1.0]
var energised := 1.0
var lights_on := true
var light_meshes: Array[MeshInstance3D] = []
var pod_frame: Node3D = null          # VR: the cockpit rig stands in for the hidden pod
var pod_frame_shift := Vector3.ZERO   # ... and its fittings stand this far from their place on it, rig metres (the speed rush eases
                                      # them fore and aft: vr/speed_rush.gd): the tow links hook to the nose where it is
var pod_frame_pose := Transform3D.IDENTITY   # ... and this is where the pod itself stands on the rig (the cockpit's pitch under the pilot: vr_cockpit.gd POD_PITCH)
const POD_FRAME_UP := 0.6             # pod mesh centre above the rig floor
const POD_LIFT := 1.3                 # the pod rides this much higher than the sim's body (looks only:
                                      # Luke wanted it "sitting a bit higher up entirely", then "higher than
                                      # the engines just a little bit more - a few feet": 0.4 -> 1.3 m, +3 ft;
                                      # in VR your eye rides up with it, over the engines)
const POD_EYE_H := 0.0                # the swivels' middles on the bullring's posts, pod-local (it was -0.05, on the skin:
                                      # a jointed fitting needs room under it to turn. No higher than it must be: from the
                                      # seat the swivels stand in front of the engines)
const ENGINE_EYE := Vector3(0, -0.95, 3.45)   # engine-local: the middle of the lug's pin, under the tail
const LUG_PLATE := [Vector2(-0.47, 3.6), Vector2(-0.93, 3.56), Vector2(-1.04, 3.45), Vector2(-0.97, 3.34), Vector2(-0.47, 2.65)]   # a hanger plate of the lug, (y, z), round the pin
var _fan_w := [0.0, 0.0]
var bank := [0.0, 0.0, 0.0]          # current lean, radians, + = left side down: eL, eR, pod (VR reads [2])
var _lat := [0.0, 0.0, 0.0]          # smoothed lateral acceleration, g
var roll_rate_peak := 0.0            # fastest pod roll so far, rad/s (tests read and reset it)
var _prev_v := []                    # last frame's [vx, vy] per body
var _prev_turn := 0.0                # ... and how far the shafts had turned the craft by then (CraftSim.carry_turn)


## The title passes a checkpoint to divide assembly over frames while its menu is interactive.
## Flight builds use the synchronous path.
func build(v, checkpoint := Callable(), reuse_engine_body := Callable()) -> void:
	view = v
	var sim = v.sim
	var shrike: bool = sim.P.vehicle == PilotCraft.SHRIKE
	var talon: bool = sim.P.vehicle == PilotCraft.TALON      # (the Phaethon in Codex's body: what differs is asked of view/talon_airframe.gd)
	if Fleet.supports(sim.P.vehicle):
		fleet = Fleet.new(sim.P.vehicle)
	var nacelle_scene: PackedScene = null if shrike or fleet != null else load("res://art/engine/nacelle.glb")
	var finish := Finishes.machined()
	var lit_mat := Kit.vertex_colors(true)
	# the nozzle's parts, one of each for both engines (view/jet_exhaust.gd)
	var pipe_mesh: ArrayMesh = Jets.pipe_mesh()
	var vane_mesh: ArrayMesh = Jets.vane_mesh()
	var flap_skin: ArrayMesh = Jets.flap_skin(Jets.EXIT_Z - Jets.THROAT_Z)
	var flap_liner: ArrayMesh = Jets.flap_liner(Jets.EXIT_Z - Jets.THROAT_Z)
	var wall_skins: ArrayMesh = Jets.wall_skins()
	var hot_mesh: ArrayMesh = Jets.opened(Kit.rounded_box(Vector3(ENG_W - 0.2, ENG_H - 0.16, 2.2), 5.0), 2.9)
	# The binder emitter's ring and the nozzle's two side walls (whose gas side is in the tailpipe's own mesh):
	# one fixed mesh in the one finish, and the same mesh on both engines, the port engine's turned half round
	# about the engine's own line (the walls are the same either way up; the ring comes round to the inboard
	# side). The renderer draws a mesh that stands twice as one thing, so this is one thing to draw where the
	# two rings and the walls were three: it pays for the fins' moving parts (tests/probe_fins_cost.gd counts).
	var emitter_at := Kit.at(Vector3(-(ENG_W / 2.0 + 0.04), 0.0, -2.9), Vector3(0.0, 0.0, PI / 2.0))      # the starboard engine's: cylinders' axis (Y) across the gap
	var ring_and_walls := Kit.compound([
		[Kit.cyl(0.34, 0.34, 0.08, 24), emitter_at, DARK.lightened(0.35)],
		[Kit.cyl(0.38, 0.38, 0.03, 24), emitter_at * Kit.at(Vector3(0, -0.03, 0)), Livery.coat("engine")],
		[wall_skins, Transform3D.IDENTITY, Color.WHITE, true],
	])
	if not shrike and not fleet and not talon:
		# The Phaethon's rudders and stabiliser panels: one mesh of each for both engines, and each pair drawn
		# as one batch (with the ring and walls, the engines draw no more things than they did). The batches
		# are the model's own, since each spans both engines: sync() puts their two where the engines are.
		for mesh in [Fins.rudder_mesh(STEEL, Livery.coat("engine"), DARK), Fins.stabiliser_mesh(STEEL, DARK)]:
			var batch := MultiMeshInstance3D.new()
			batch.name = "Rudders" if fin_batches.is_empty() else "Stabilisers"
			batch.multimesh = MultiMesh.new()
			batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			batch.multimesh.mesh = mesh
			batch.multimesh.instance_count = 2
			batch.material_override = Finishes.painted_metal()
			add_child(batch)
			fin_batches.append(batch.multimesh)
	for k in 2:
		if checkpoint.is_valid():
			await checkpoint.call("engine body")
		var out := -1.0 if k == 0 else 1.0   # outboard side, engine-local X (eL rides on the left)
		var eng := Node3D.new()
		add_child(eng)
		engines.append(eng)
		var body := MeshInstance3D.new()
		var side_part := &"Port" if k == 0 else &"Starboard"
		if fleet:
			body.name = "FleetFairing"
			body.mesh = fleet.part(side_part)
		elif shrike:
			body.name = "ShrikeFairing"
			body.mesh = Shrike.part(side_part)
		else:
			body.name = "TalonFairing" if talon else "PhaethonFairing"
			# (without its rudder and stabiliser, which are their own parts; or the caller's own copy of that fixed mesh: title_stage._display_body.
			# The Talon's carries Codex's fins in their place, fixed)
			body.mesh = reuse_engine_body.call(out) if reuse_engine_body.is_valid() else _engine_body(out, false, talon)
			body.material_override = Finishes.painted_metal()
		eng.add_child(body)
		# One shared UV-mapped shell on each engine. The hot section, brakes and
		# vectoring vanes still use their independent pivots and materials.
		var aft_leaf: Mesh
		var front_leaf: Mesh
		if fleet:
			aft_leaf = fleet.part(&"AftBrake")
			front_leaf = fleet.part(&"FrontBrake")
		elif shrike:
			aft_leaf = Shrike.part(&"AftBrake")
			front_leaf = Shrike.part(&"ForwardBrake")
		else:
			var shell := nacelle_scene.instantiate()
			shell.name = "NacelleShell"
			aft_leaf = _take_brake_mesh(shell, "AftBrakeLeaf")
			front_leaf = _take_brake_mesh(shell, "FrontBrakeLeaf")
			eng.add_child(shell)
			Accent.dress_all(shell)      # its armour plates and fairing band are the livery's (Ember: as made)
		var lights := MeshInstance3D.new()   # nav, tail, landing lights and the repulsor underglow
		lights.mesh = fleet.lights(out) if fleet else (Shrike.lights(out) if shrike else _engine_lights(out, talon))
		lights.material_override = lit_mat
		lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eng.add_child(lights)
		light_meshes.append(lights)
		var fin: MeshInstance3D = null
		if shrike:
			# The fin on its hinge, its outer panel on the spindle at the fin's head, the ram that moves the fin,
			# and the nav lamp at the tip (view/shrike_airframe.gd: sync() stands the fin up or lays it out with
			# the speed and the turn, and swings the panel with the turn).
			fin = MeshInstance3D.new()
			fin.name = "ShrikeFin"
			fin.mesh = Shrike.part(&"PortFin" if k == 0 else &"StarboardFin")
			eng.add_child(fin)
			var panel := MeshInstance3D.new()
			panel.name = "ShrikeFinPanel"
			panel.mesh = Shrike.part(&"PortFinPanel" if k == 0 else &"StarboardFinPanel")
			fin.add_child(panel)
			var ram := MeshInstance3D.new()
			ram.name = "FinRam"
			ram.mesh = Shrike.part(&"FinRam")
			eng.add_child(ram)
			var rod := MeshInstance3D.new()
			rod.name = "FinRamRod"
			rod.mesh = Shrike.part(&"FinRamRod")
			rod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			eng.add_child(rod)
			var tip_lamp := MeshInstance3D.new()
			tip_lamp.name = "FinLamp"
			tip_lamp.mesh = Shrike.fin_lamp(out)
			tip_lamp.material_override = lit_mat
			tip_lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			panel.add_child(tip_lamp)
			light_meshes.append(tip_lamp)
			fin_parts.append([fin, ram, rod, panel])
			_place_fin(k, fin_cant)
		if checkpoint.is_valid():
			await checkpoint.call("fans")
		# hot section: its own material, coloured by heat
		var hot := MeshInstance3D.new()
		hot.mesh = hot_mesh      # (its tail is open: the tailpipe runs up inside it)
		hot.position.z = 2.9
		if shrike or fleet:
			hot.scale = Vector3(0.87, 0.75, 0.88)   # hot core inside the open exhaust petals
		var hm := StandardMaterial3D.new()
		hm.albedo_color = STEEL
		hm.metallic = 0.68
		hm.roughness = 0.49
		hm.emission_enabled = true
		hm.emission = Color.BLACK
		hot.material_override = hm
		eng.add_child(hot)
		hot_mats.append(hm)
		# The tailpipe: 0.8 m of liner from the flame holder back to the mouth, the holder's gutters
		# across it. (The holder's face stood flush in the mouth: a glowing grille, not a pipe.)
		var metal: ShaderMaterial = Jets.hot_material()
		metal_mats.append(metal)
		jets.append(Jets.new())
		var pipe := MeshInstance3D.new()
		pipe.name = "tailpipe"
		pipe.mesh = pipe_mesh
		pipe.material_override = metal
		pipe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eng.add_child(pipe)
		var glow := MeshInstance3D.new()   # the flame holder's face, at the pipe's floor
		var throat := QuadMesh.new()
		throat.size = Jets.SLOT * 2.0
		glow.mesh = throat
		glow.position.z = Jets.PIPE_Z + 0.004
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.albedo_color = DARK
		gm.albedo_texture = FlameHolder
		glow.material_override = gm
		eng.add_child(glow)
		glow_mats.append(gm)
		# twin intake fans: spinners and eight blades each, one painted so the spin reads
		var fan := Node3D.new()
		fan.position.z = 0.0 if fleet else -3.86
		eng.add_child(fan)
		fans.append(fan)
		var centres := fleet.rotor_centres() if fleet else [Vector3(-0.55, 0, 0), Vector3(0.55, 0, 0)]
		for centre: Vector3 in centres:
			var rotor := Node3D.new()
			rotor.position = centre
			fan.add_child(rotor)
			rotors[k].append(rotor)
			var fm := MeshInstance3D.new()
			if fleet:
				fm.mesh = fleet.part(&"Rotor")
				if centre.x > 0.0:
					fm.scale.x = -1.0
			elif shrike:
				fm.mesh = Shrike.part(&"Compressor")
				# Opposing rotor shafts need opposite blade pitch to pull air aft.
				if centre.x > 0.0:
					fm.scale.x = -1.0
			else:
				var parts := [[Kit.cyl(0.03, 0.15, 0.24, 12), Kit.at(Vector3(0, 0, -0.08), Vector3(-PI / 2.0, 0, 0)), Color(0.85, 0.85, 0.82)]]
				for b in 12:
					var a := TAU * b / 12.0
					parts.append([Fairings.fan_blade(), Transform3D(Basis(Vector3.BACK, -a), Vector3.ZERO),
						Livery.coat("engine") if b == 0 else Color(0.43, 0.46, 0.50)])
				fm.mesh = Kit.compound(parts)
				fm.material_override = Kit.polished(0.88, 0.31)
			rotor.add_child(fm)
		if not shrike and not fleet:
			var legend := Label3D.new()
			legend.text = "PHAETHON  /  " + ("L" if k == 0 else "R")
			legend.font_size = 48
			legend.pixel_size = 0.0018
			legend.outline_size = 0
			legend.modulate = Color(0.12, 0.14, 0.17)
			legend.rotation.x = -PI / 2.0
			legend.position = Vector3(0, ENG_H / 2.0 + 0.036, -0.15)
			eng.add_child(legend)
		if not shrike and not fleet and not talon:
			# Where the dorsal fin's rudder stands on its post and the outboard fin's panel on its spindle
			# (view/fin_steering.gd: sync() turns them with the turn). What they stand on is in the engine's fixed mesh.
			var rudder := Node3D.new()
			rudder.name = "Rudder"
			rudder.position = Vector3(0.0, ENG_H / 2.0, Fins.RUDDER_Z)
			eng.add_child(rudder)
			rudders.append(rudder)
			var stabiliser := Node3D.new()
			stabiliser.name = "Stabiliser"
			stabiliser.transform = Fins.stabiliser_place(out, ENG_W / 2.0, 0.0)
			eng.add_child(stabiliser)
			stabilisers.append(stabiliser)
		if checkpoint.is_valid():
			await checkpoint.call("flaps and jets")
		# split air brakes, two on top and two underneath: hinged at the front edge, the trailing
		# edge swings up (or down) into the airflow
		for fa in FLAPS_AT:
			var ring := Node3D.new()
			ring.position = Vector3(fa[0], 0.0, FLAP_Z)
			ring.rotation.z = 0.0 if fa[1] > 0.0 else PI
			eng.add_child(ring)
			var hinge := Node3D.new()
			hinge.position.y = ENG_H / 2.0 + 0.01
			ring.add_child(hinge)
			var fl := MeshInstance3D.new()
			fl.mesh = aft_leaf
			if not fleet:
				Accent.dress(fl)
			hinge.add_child(fl)
			flaps[k].append(hinge)
		# front speed brakes (Luke: "front speed brake flaps for braking done at high speed"): a
		# petal on each flank just behind the intake lip, hinged at its front edge, swinging out
		# into the air with the brakes above ~1,500 mph (the sim's e.front); amber inside
		for side in [-1.0, 1.0]:
			var fh := Node3D.new()
			fh.position = Vector3(side * (ENG_W / 2.0 + 0.04), 0.0, FRONT_Z)
			fh.set_meta("side", side)   # it swings out that way
			eng.add_child(fh)
			var fp := MeshInstance3D.new()
			fp.mesh = front_leaf
			if not fleet:
				Accent.dress(fp)
			fp.rotation.z = -side * PI / 2.0
			fp.scale = Vector3(0.73, 1.0, 0.88)
			fh.add_child(fp)
			front_flaps[k].append(fh)
		# thrust-vectoring vanes standing in the pipe's mouth: carbon wedges, pivoted at their leading
		# edges, that swing with the turn and glow with the gas
		for vx in Jets.VANES_AT:
			var vp := Node3D.new()
			vp.position = Vector3(vx, 0.0, Jets.VANE_Z)
			eng.add_child(vp)
			var vm := MeshInstance3D.new()
			vm.mesh = vane_mesh
			vm.material_override = metal
			vm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			vp.add_child(vm)
			vanes[k].append(vp)
		# the nozzle: an upper and a lower flap hinged at the pipe's mouth, saw-toothed at the trailing
		# edge, between two fixed side walls. The flaps set the exit: sync() swings them.
		for upper in [true, false]:
			var ring := Node3D.new()
			ring.position.z = Jets.THROAT_Z
			ring.rotation.z = 0.0 if upper else PI
			eng.add_child(ring)
			var hinge := Node3D.new()
			hinge.position.y = Jets.SLOT.y
			ring.add_child(hinge)
			var skin := MeshInstance3D.new()
			skin.mesh = flap_skin
			skin.material_override = finish
			hinge.add_child(skin)
			var face := MeshInstance3D.new()
			face.mesh = flap_liner
			face.material_override = metal
			face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			hinge.add_child(face)
			nozzle_flaps[k].append(hinge)
		# the fin-tip strobe: it rides the fin's tip (the Shrike's fin panel, the Phaethon's rudder, the Talon's dorsal fin)
		var strobe := MeshInstance3D.new()
		strobe.mesh = Kit.ball(0.08, 10)
		strobe.material_override = view._mat(Color(1.0, 1.0, 1.0), true)
		if talon:
			strobe.position = Talon.STROBE * Vector3(out, 1.0, 1.0)
		else:
			strobe.position = fleet.strobe_at(out) if fleet else (Shrike.panel_tip(out) if shrike else Vector3(0, 1.08 - ENG_H / 2.0, 1.35 - Fins.RUDDER_Z))
		strobe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if fleet or talon:
			eng.add_child(strobe)      # (the fleet's fins are fixed, in its airframe, and the Talon's in its engine: the strobe stands on the engine)
		elif shrike:
			(fin_parts[k][3] as Node3D).add_child(strobe)
		else:
			rudders[k].add_child(strobe)
		strobes.append(strobe)
		# the upgraded binder emitter on the inboard face: a ring round a glowing core, facing across
		var em := Node3D.new()
		em.position = Vector3(-out * (ENG_W / 2.0 + 0.04), 0.0, -2.9)
		em.rotation.z = PI / 2.0   # cylinders' axis (Y) across the gap
		eng.add_child(em)
		var ring_m := MeshInstance3D.new()      # (with the nozzle's side walls: ring_and_walls above)
		ring_m.name = "RingAndWalls"
		ring_m.mesh = ring_and_walls
		ring_m.rotation.z = 0.0 if out > 0.0 else PI
		ring_m.material_override = finish
		eng.add_child(ring_m)
		var core_m := MeshInstance3D.new()
		core_m.mesh = Kit.cyl(0.24, 0.24, 0.1, 20)
		core_m.position.y = -out * 0.02
		var cmat := StandardMaterial3D.new()
		cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cmat.albedo_color = BINDER_COL
		core_m.material_override = cmat
		core_m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		em.add_child(core_m)
		binder_mats.append(cmat)
		# The jet: one volume of gas behind the nozzle. The node stays square to the engine; the
		# vanes' deflection is in the plume's centre line, traced every frame (_trace_plume).
		var flame := Node3D.new()
		flame.position.z = NOZZLE_EXIT
		eng.add_child(flame)
		flames.append(flame)
		var plume := MeshInstance3D.new()
		plume.name = "plume"
		var tube := BoxMesh.new()            # a unit box, a row of faces per station: the shader lays it along the line
		tube.size = Vector3.ONE
		tube.subdivide_depth = PLUME_STATIONS - 2
		plume.mesh = tube
		plume.custom_aabb = AABB(Vector3(-8.0, -1.6, -0.2), Vector3(16.0, 3.2, 16.0))
		var fmat := ShaderMaterial.new()
		fmat.shader = FlameShader
		fmat.set_shader_parameter("seed", float(k) * 3.7)
		fmat.set_shader_parameter("flow_map", FlowTexture)
		fmat.set_shader_parameter("slot", PLUME_SLOT)
		plume.material_override = fmat
		plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		plume.visible = plumes
		flame.add_child(plume)
		flame_mats[k].append(fmat)
		plume_line[k].resize(PLUME_STATIONS)
		# The fire up the pipe (view/nozzle_glow.gdshader): a sheet across it just behind the flame
		# holder, as wide and as tall as the pipe. From the seat the pipe is what the pilot looks up.
		var fire := MeshInstance3D.new()
		fire.name = "nozzle_glow"
		var slot := QuadMesh.new()
		slot.size = Jets.SLOT * 2.0 - Vector2(0.02, 0.02)
		fire.mesh = slot
		fire.position.z = Jets.PIPE_Z + 0.31 - NOZZLE_EXIT      # behind the gutters: the flame stands on their lee
		var gmat := ShaderMaterial.new()
		gmat.shader = preload("res://view/nozzle_glow.gdshader")
		gmat.render_priority = -1   # under the plume it is seen through, from the seat
		gmat.set_shader_parameter("seed", float(k) * 3.7 + 1.9)
		fire.material_override = gmat
		fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.add_child(fire)
		nozzle_mats.append(gmat)
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(0, -0.2, sim.P.engineLen / 2.0 + 1.2)
		lamp.light_color = Color(1.0, 0.58, 0.25)
		lamp.omni_range = 10.0
		lamp.light_energy = 0.0
		lamp.shadow_enabled = false
		eng.add_child(lamp)
		nozzle_lights.append(lamp)

	if checkpoint.is_valid():
		await checkpoint.call("pod hull")
	pod = MeshInstance3D.new()
	if fleet:
		fleet.dress_cab(pod, nose_closed)
	else:
		pod.mesh = pod_hull(shrike, talon)
	if shrike:
		Shrike.dress_pod(pod)
		Shrike.fit_seat(pod, Vector3.DOWN * POD_FRAME_UP)
	if shrike or fleet:
		tail_lights = MeshInstance3D.new()
		tail_lights.name = "BrakeLights"
		tail_lights.mesh = fleet.part(&"BrakeLenses") if fleet else Shrike.part(&"TailLights")
		var lens := ShaderMaterial.new()
		lens.shader = preload("res://view/shrike_tail_lamps.gdshader")
		tail_lights.material_override = lens
		tail_lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tail_lights.add_to_group("exterior")
		pod.add_child(tail_lights)
	add_child(pod)
	if checkpoint.is_valid():
		await checkpoint.call("canopy")
	canopy = CanopyScript.build(fleet)   # windscreen and forcefield (view/canopy.gd)
	pod.add_child(canopy)
	if fleet and PilotCraft.weapon_of(sim.P.vehicle) == "turret":      # (the Basilisk's: not every armed craft's, since the Phaethons were armed)
		turret = TurretScript.new()
		pod.add_child(turret)
		turret.build(fleet)
		weapon = TurretMountScript.new(turret, self)
	if ARMS.has(PilotCraft.weapon_of(sim.P.vehicle)):      # (stowed: nothing of them is drawn till the GUN switch brings them out)
		arms = ARMS[PilotCraft.weapon_of(sim.P.vehicle)].new()
		arms.build(self)
		weapon = FixedGunsMountScript.new(arms, self)      # (aimed by pointing the craft; its fire control is made at the first arming)
	if PilotCraft.weapon_of(sim.P.vehicle) == "missiles":      # (the Shrike's: its arms are fitted at the first arming, or at load with Raids on)
		weapon = MissileMountScript.new(self)
	if PilotCraft.weapon_of(sim.P.vehicle) == "lance":      # (the Kiln's: as the Shrike's, on the hull last dressed: fleet.ensure_arms)
		weapon = LanceMountScript.new(self)
	var flap_mat := null if shrike or fleet else Kit.polished(0.85, 0.2)
	for s in [-1.0, 1.0]:
		var hinge := Node3D.new()
		var pm := MeshInstance3D.new()
		if fleet:
			hinge.position = fleet.CAB_HINGES[fleet.id] * Vector3(s, 1, 1)
			pm.mesh = fleet.part(&"CabBrake")
			pm.rotation.z = -s * PI / 2.0
		elif shrike:
			hinge.position = Vector3(s * 1.247, -0.185, 0.80)
			pm.mesh = Shrike.part(&"PortPodBrake" if s < 0 else &"StarboardPodBrake")
		elif talon:      # Codex's ventral split brakes, under the wing roots
			hinge.position = Talon.BRAKE_HINGE * Vector3(s, 1.0, 1.0)
			pm.mesh = Talon.pod_brake(s, Talon.palette())
			pm.material_override = Finishes.painted_metal()
		else:
			hinge.position = Vector3(s * 1.16, -0.28, 0.85)
			pm.mesh = Kit.compound([
				[Kit.rounded_box(Vector3(0.05, 0.42, 0.85), 6.0), Kit.at(Vector3(0, 0, 0.43)), SILVER],
				[Kit.rounded_box(Vector3(0.02, 0.36, 0.76), 6.0), Kit.at(Vector3(-0.03 * s, 0, 0.43)), Color(0.85, 0.08, 0.05)],
			])
			pm.material_override = flap_mat
		pod.add_child(hinge)
		pm.add_to_group("exterior")
		hinge.add_child(pm)
		pod_flaps.append(hinge)

	_place_fin_batches()
	if checkpoint.is_valid():
		await checkpoint.call("tow rod")
	link_rod = TowLink.rod_for(sim.P.cableLen)
	for k in 2:      # the tow links: four rigid parts each, placed every frame (sync_cables), their meshes made once
		if checkpoint.is_valid():
			await checkpoint.call("tow links")
		var cm: StandardMaterial3D = TowLink.lit(view._mat(Color(0.2, 0.21, 0.23)))   # energized: glows with its engine's thrust (cable_glow)
		cm.cull_mode = BaseMaterial3D.CULL_BACK
		cm.emission = CABLE_COOL
		cable_mats.append(cm)
		for part in [["TowSwivel", TowLink.swivel_mesh(), false], ["TowBarrel", TowLink.barrel_mesh(), true],
				["TowRod", TowLink.rod_mesh(link_rod), true], ["TowYoke", TowLink.yoke_mesh(), false]]:
			var c := MeshInstance3D.new()
			c.name = "%s%s" % [part[0], "L" if k == 0 else "R"]
			c.mesh = part[1]
			c.set_surface_override_material(0, TowLink.metal())
			if part[2]:
				c.set_surface_override_material(1, cm)
			if (part[1] as Mesh).get_surface_count() > 2:      # (the barrel's paint: its stencils, its conduit's sheath)
				c.set_surface_override_material(2, TowLink.dress())
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(c)
			link_parts[k].append(c)
		cables.append(link_parts[k][2])
		var boot := MeshInstance3D.new()      # the gaiter over the rod at the barrel's mouth: on the barrel, so it goes where that goes
		boot.name = "TowBoot%s" % ("L" if k == 0 else "R")
		boot.mesh = TowLink.boot_mesh()
		boot.material_override = TowLink.dress()
		boot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		boot.position = Vector3(0.0, 0.0, TowLink.BARREL)
		(link_parts[k][1] as Node3D).add_child(boot)
		link_boots.append(boot)
	binder_arc = BinderArc.new()
	arc = binder_arc.mesh
	add_child(binder_arc)


## The dress kit also carries the two UV-mapped movable mesh masters at their local hinge.
static func _take_brake_mesh(shell: Node3D, part: String) -> Mesh:
	var source := shell.find_child(part, true, false) as MeshInstance3D
	var mesh := source.mesh
	source.free()
	return mesh


## Engine shell, forward -Z, 8 m, a flat rounded slab: intake lip and twin-intake face, nacelle,
## livery band and pinstripe, dorsal fin, outboard stabiliser, binder housing, cable lug and eye;
## plus access covers with rivets, side intake louvres, top exhaust ports, coolant louvres and the
## nozzle's upper and lower lips.
## `fins` false: without the dorsal fin's rudder and the stabiliser's panel, which the pilot's own craft
## carries as parts that move (view/fin_steering.gd); what they stand on is here in their place.
## `talon`: the Talon's, with neither fin nor what they stand on, and Codex's fins, cheeks and eyebrows
## (view/talon_airframe.gd add_engine) in their place, fixed.
static func _engine_body(out: float, fins := true, talon := false) -> ArrayMesh:
	var top := ENG_H / 2.0
	var side := ENG_W / 2.0
	var surfaces := [
		[Fairings.fin(PackedVector2Array([Vector2(0,-0.65), Vector2(0.64,0.95), Vector2(0.59,1.45), Vector2(0,1.15)]), 0.07), Kit.at(Vector3(0, top, 0)), STEEL],
		[Fairings.fin(PackedVector2Array([Vector2(0.49,0.65), Vector2(0.64,0.95), Vector2(0.59,1.45), Vector2(0.49,1.35)]), 0.075), Kit.at(Vector3(0, top, 0)), Livery.coat("engine")],
		[Fairings.fin(PackedVector2Array([Vector2(0,-0.3),Vector2(1.05,0.95),Vector2(0.99,1.38),Vector2(0,1.05)]), 0.065), Kit.at(Vector3(out*side,-0.1,0), Vector3(0,0,-out*PI/2)), STEEL],
	]
	if talon:
		surfaces = []
	elif not fins:
		surfaces = Fins.rudder_fittings(top, STEEL, DARK, SILVER)
		surfaces.append_array(Fins.stabiliser_fittings(out, side, STEEL, DARK))
	var parts := [
		[Fairings.nacelle(), Transform3D.IDENTITY, STEEL],
		[Kit.rounded_box(Vector3(ENG_W + 0.1, ENG_H + 0.1, 0.45), 6.0, 32), Kit.at(Vector3(0, 0, -3.6)), DARK.lightened(0.15)],   # intake lip
		[Kit.box(Vector3(ENG_W - 0.3, ENG_H - 0.22, 0.04)), Kit.at(Vector3(0, 0, -3.84)), Color(0.05, 0.05, 0.06)],   # intake throat
		[Kit.box(Vector3(0.08, ENG_H - 0.22, 0.06)), Kit.at(Vector3(0, 0, -3.85)), DARK.lightened(0.3)],         # splitter between the twin intakes
		[Kit.rounded_box(Vector3(ENG_W + 0.06, ENG_H + 0.06, 0.6), 6.0, 24), Kit.at(Vector3(0, 0, -2.5)), Livery.coat("engine")],    # band
		[Kit.rounded_box(Vector3(ENG_W + 0.04, ENG_H + 0.04, 0.25), 6.0, 24), Kit.at(Vector3(0, 0, 0.6)), Livery.coat("engine")],    # pinstripe
	]
	parts.append_array(surfaces)      # the dorsal fin, its painted tip and the stabiliser (or what their moving parts stand on)
	parts.append_array([
		[Kit.rounded_box(Vector3(0.18, 0.72, 1.1), 5.0), Kit.at(Vector3(-out * (side - 0.02), 0.0, -2.9)), DARK.lightened(0.25)],   # binder housing
		[Kit.box(Vector3(ENG_W - 0.2, 0.06, 0.4)), Kit.at(Vector3(0, 0.36, 4.0)), DARK.lightened(0.2)],          # nozzle lips
		[Kit.box(Vector3(ENG_W - 0.2, 0.06, 0.4)), Kit.at(Vector3(0, -0.36, 4.0)), DARK.lightened(0.2)],
	])
	parts.append_array(_lug())
	# access covers: raised panels on top and both sides, a dark seam round each, rivets at the corners
	var cover := DARK.lightened(0.42)
	var seam := Color(0.08, 0.08, 0.09)
	for cx in [-0.6, 0.6]:
		parts.append([Kit.box(Vector3(0.84, 0.012, 1.24)), Kit.at(Vector3(cx, top + 0.004, -1.2)), seam])
		parts.append([Kit.rounded_box(Vector3(0.78, 0.022, 1.18), 8.0), Kit.at(Vector3(cx, top + 0.014, -1.2)), cover])
		for rz in [-0.54, 0.54]:
			for rx in [-0.34, 0.34]:
				parts.append([Kit.ball(0.02, 6), Kit.at(Vector3(cx + rx, top + 0.03, -1.2 + rz)), SILVER])
	parts.append([Kit.box(Vector3(0.22, 0.03, 0.05)), Kit.at(Vector3(0.6, top + 0.035, -0.75)), SILVER])   # a hatch handle
	for sx in [-1.0, 1.0]:
		parts.append([Kit.box(Vector3(0.012, 0.6, 1.04)), Kit.at(Vector3(sx * (side + 0.004), 0.0, -0.4)), seam])
		parts.append([Kit.rounded_box(Vector3(0.022, 0.54, 0.98), 8.0), Kit.at(Vector3(sx * (side + 0.012), 0.0, -0.4)), cover])
		# side intakes: a dark scoop with three louvres
		parts.append([Kit.rounded_box(Vector3(0.06, 0.3, 0.62), 6.0), Kit.at(Vector3(sx * (side + 0.02), -0.12, -1.9)), Color(0.06, 0.06, 0.07)])
		for li in 3:
			parts.append([Kit.box(Vector3(0.05, 0.03, 0.56)), Kit.at(Vector3(sx * (side + 0.05), -0.2 + li * 0.08, -1.9)), STEEL.darkened(0.2)])
	# top exhaust ports and coolant louvres toward the back
	for px in [-0.55, 0.55]:
		parts.append([Kit.cyl(0.14, 0.14, 0.03, 16), Kit.at(Vector3(px, top + 0.01, 1.75)), DARK.lightened(0.3)])
		parts.append([Kit.cyl(0.1, 0.1, 0.035, 16), Kit.at(Vector3(px, top + 0.015, 1.75)), Color(0.04, 0.04, 0.05)])
	for li in 6:
		parts.append([Kit.box(Vector3(1.5, 0.02, 0.07)), Kit.at(Vector3(0, top + 0.02, 2.0 + li * 0.08), Vector3(-0.5, 0, 0)), DARK.lightened(0.1)])
	if not talon:
		return Kit.compound(parts)
	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	Kit.add_parts(body, parts)
	Talon.add_engine(body, out, Talon.palette())
	body.index()
	return body.commit()


## The engine's lights (unshaded, so they read at any distance): a nav light at the stabiliser's
## tip (red on the left engine, green on the right), a red tail light, two landing lights under
## the intake lip, and a cyan repulsor underglow along the belly. (The Talon's nav light is at its outboard fin's tip.)
static func _engine_lights(out: float, talon := false) -> ArrayMesh:
	var nav := NAV_L if out < 0.0 else NAV_R
	return Kit.compound([
		[Kit.ball(0.065, 10), Kit.at(Talon.NAV_LAMP * Vector3(out, 1.0, 1.0) if talon else Vector3(out * (ENG_W / 2.0 + 1.02), -0.1, 1.1)), nav],
		[Kit.box(Vector3(0.5, 0.06, 0.05)), Kit.at(Vector3(0, ENG_H / 2.0 - 0.08, 4.0)), Color(1.0, 0.1, 0.08)],
		[Kit.box(Vector3(0.22, 0.08, 0.03)), Kit.at(Vector3(-0.8, -0.38, -3.84)), Color(1.0, 0.97, 0.88)],
		[Kit.box(Vector3(0.22, 0.08, 0.03)), Kit.at(Vector3(0.8, -0.38, -3.84)), Color(1.0, 0.97, 0.88)],
		[Kit.box(Vector3(ENG_W - 0.6, 0.02, 4.6)), Kit.at(Vector3(0, -ENG_H / 2.0 - 0.012, -0.4)), Color(0.2, 0.75, 1.0)],
	])


## Hull section at z: [half-width a, centre height c, half-height b] (Catmull-Rom on HULL).
static func hull_section(z: float) -> Array:
	var k := 0
	while k < HULL.size() - 2 and z > HULL[k + 1][0]:
		k += 1
	var t := clampf((z - HULL[k][0]) / (HULL[k + 1][0] - HULL[k][0]), 0.0, 1.0)
	var out := []
	for col in [1, 2, 3]:
		var p0: float = HULL[maxi(k - 1, 0)][col]
		var p1: float = HULL[k][col]
		var p2: float = HULL[k + 1][col]
		var p3: float = HULL[mini(k + 2, HULL.size() - 1)][col]
		out.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
			+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
	return [out[0], (out[1] + out[2]) / 2.0, (out[2] - out[1]) / 2.0]


## Top of the hull at (x, z), for laying the lip along the opening.
static func hull_top(x: float, z: float) -> float:
	var h := hull_section(z)
	var u := clampf(absf(x) / h[0], 0.0, 1.0)
	return h[1] + h[2] * pow(1.0 - pow(u, HULL_N), 1.0 / HULL_N)


## The opening's half-length on the side of its widest point that station z is on.
static func open_az(z: float) -> float:
	return OPEN_AZ_FRONT if z < OPEN_ZC else OPEN_AZ


## The opening's edge at angle ph round it (the nose at -90 degrees, the right side at 0), in plan: (x, z).
static func open_edge(ph: float) -> Vector2:
	var s := sin(ph)
	return Vector2(OPEN_AX * cos(ph), OPEN_ZC + (OPEN_AZ_FRONT if s < 0.0 else OPEN_AZ) * s)


static func _in_opening(x: float, z: float) -> bool:
	return pow(x / OPEN_AX, 2.0) + pow((z - OPEN_ZC) / open_az(z), 2.0) < 1.0


const LIP_R := 0.055


## The raked fin's frame (its leading edge and tip lamp sit in it).
static func _fin_xf() -> Transform3D:
	return Kit.at(Vector3(0, 0.42, 1.6), Vector3(-0.35, 0, 0))


## Is a pod-local point clear of the hull's material? "" if so, else why not. Clear means
## inside the inner trim surface (with `margin`), or up in the cockpit opening, and never
## within `margin` of the lip tube. For cockpit fittings (tests/test_dashboard.gd).
static func hull_clearance(p: Vector3, margin := 0.01) -> String:
	if p.z <= HULL[0][0] or p.z >= HULL[HULL.size() - 1][0]:
		return "beyond the hull's ends"
	var h := hull_section(p.z)
	var a: float = h[0] - SKIN - margin
	var b: float = h[2] - SKIN - margin
	var inside: bool = a > 0.0 and b > 0.0 and pow(absf(p.x) / a, HULL_N) + pow(absf(p.y - h[1]) / b, HULL_N) <= 1.0
	var in_open: bool = p.y > h[1] and pow(p.x / (OPEN_AX - margin), 2.0) + pow((p.z - OPEN_ZC) / (open_az(p.z) - margin), 2.0) < 1.0
	if not inside and not in_open:
		return "through the skin"
	for k in 192:
		var edge := open_edge(TAU * k / 192.0)
		if p.distance_to(Vector3(edge.x, hull_top(edge.x, edge.y), edge.y)) < LIP_R + margin:
			return "into the lip"
	return ""


## Append triangle (p0, p1, p2) as a front face whose outside is `out` (Godot fronts are clockwise).
static func _tri(st: SurfaceTool, i0: int, i1: int, i2: int, p0: Vector3, p1: Vector3, p2: Vector3, out: Vector3) -> void:
	if (p1 - p0).cross(p2 - p0).dot(out) > 0.0:
		st.add_index(i0)
		st.add_index(i2)
		st.add_index(i1)
	else:
		st.add_index(i0)
		st.add_index(i1)
		st.add_index(i2)


## The pod: polished-metal outer skin (surface 0), matte trim inside (1), the leather lip round
## the cockpit (2), fittings (3), the nose cage (4), the paint (5: _outer_skin), the pinstripes and
## the lip's piping (6), lamps (7). Built once and shared (the flat view's pod and the VR cockpit).
## `talon`: the Talon's: Codex's anti-glare panel on the decks, without the Phaethon's raked fin, side intakes and
## trim thrusters, with his lamps, and his plating (8: view/talon_airframe.gd add_pod, in Talon.paint's palette).
## Built in the current livery (Factory's is Ember's: the same hull). The Shrike's is always built as its
## factory one was: its paint and trim are its own materials over it, in its livery (view/shrike_airframe.gd).
static func pod_hull(shrike := false, talon := false) -> ArrayMesh:
	var livery := "ember" if shrike else Livery.table_id()
	var which := "%s:%s:%s" % [livery, "closed" if nose_closed else "open", "shrike" if shrike else ("talon/" + Talon.paint if talon else "phaethon")]
	if _hulls.has(which):
		return _hulls[which]
	var own := Livery.current
	Livery.current = livery
	var mesh := _build_hull(shrike, talon)
	Livery.current = own
	_hulls[which] = mesh
	return mesh


static func _build_hull(shrike: bool, talon := false) -> ArrayMesh:
	var nz := 76
	var na := 96
	var z0: float = HULL[0][0]
	var z1: float = HULL[HULL.size() - 1][0]
	var grid := []   # [ring][j] -> [outer Vector3, centre height c]
	for i in nz + 1:
		var z := lerpf(z0, z1, float(i) / nz)
		var h := hull_section(z)
		var ring := []
		for j in na:
			var th := TAU * j / na
			var x: float = h[0] * Kit._sp(cos(th), 2.0 / HULL_N)
			var y: float = h[1] + h[2] * Kit._sp(sin(th), 2.0 / HULL_N)
			ring.append([Vector3(x, y, z), h[1], h[0], h[2]])
		grid.append(ring)
	var mesh := ArrayMesh.new()
	var paint := SurfaceTool.new()   # the paint (surface 5) and the pinstripes (6), committed after the cage
	paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pins := SurfaceTool.new()
	pins.begin(Mesh.PRIMITIVE_TRIANGLES)
	_outer_skin(grid, nz, na, mesh, paint, pins, talon)   # surface 0
	for layer in [1]:   # the inner trim (the outer skin: _outer_skin)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var pts := []
		for i in nz + 1:
			for j in na:
				var g: Array = grid[i][j]
				var p: Vector3 = g[0]
				if layer == 1:   # pull in by the skin thickness
					var c: float = g[1]
					p = Vector3(p.x * maxf(g[2] - SKIN, 0.01) / g[2], c + (p.y - c) * maxf(g[3] - SKIN, 0.01) / g[3], p.z)
				var col := SILVER
				if layer == 0:
					var sy: float = (p.y - g[1]) / g[3]
					if (absf(p.x) > 0.7 * g[2] and sy > -0.2 and sy < 0.22) or p.z < -1.98:
						col = LIVERY.lightened(0.05)   # speed stripes and a painted nose
				else:
					col = Color(0.16, 0.16, 0.17)
				st.set_color(col)
				st.add_vertex(p)
				pts.append(p)
		for i in nz:
			for j in na:
				var j2 := (j + 1) % na
				var a := i * na + j
				var b := i * na + j2
				var c := (i + 1) * na + j
				var d := (i + 1) * na + j2
				var cen: Vector3 = (pts[a] + pts[b] + pts[c] + pts[d]) / 4.0
				var cc: float = (grid[i][j][1] + grid[i + 1][j][1]) / 2.0
				if cen.y > cc and _in_opening(cen.x, cen.z):
					continue   # the cockpit
				if not nose_closed and cen.z > CAGE_Z1 and cen.z < CAGE_Z0:
					continue   # the open cage
				var outward := Vector3(cen.x, cen.y - cc, 0.0) * (1.0 if layer == 0 else -1.0)
				_tri(st, a, b, c, pts[a], pts[b], pts[c], outward)
				_tri(st, b, d, c, pts[b], pts[d], pts[c], outward)
		# end caps: fans to a point just beyond each end
		for e in 2:
			var ri := 0 if e == 0 else nz
			var tip := Vector3(0.0, grid[ri][0][1], z0 - 0.02 if e == 0 else z1 + 0.02)
			st.set_color(LIVERY.lightened(0.05) if e == 0 and layer == 0 else (SILVER if layer == 0 else Color(0.16, 0.16, 0.17)))
			st.add_vertex(tip)
			var ti := pts.size()
			pts.append(tip)
			var axis := Vector3(0, 0, -1.0 if e == 0 else 1.0) * (1.0 if layer == 0 else -1.0)
			for j in na:
				var a := ri * na + j
				var b := ri * na + (j + 1) % na
				_tri(st, a, b, ti, pts[a], pts[b], tip, axis)
		st.generate_normals()
		st.commit(mesh)
	var trim := Finishes.powder_coat()
	mesh.surface_set_material(1, trim)

	# lip: a padded leather coaming round the opening, laid on the hull top, orange piping along its
	# crest (from the seat the lip hides the decks beyond it: the piping is the paint you see)
	var lip := SurfaceTool.new()
	lip.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nl := 96
	var nr := 10
	var r := LIP_R
	var ring_pts := []
	for k in nl + 1:
		var edge := open_edge(TAU * k / nl)
		ring_pts.append(Vector3(edge.x, hull_top(edge.x, edge.y), edge.y))
	var lip_pts := []
	var centres := []
	for k in nl + 1:
		var pk: Vector3 = ring_pts[k]
		var tan: Vector3 = (ring_pts[(k + 1) % nl] - ring_pts[(k - 1 + nl) % nl]).normalized()
		var side := tan.cross(Vector3.UP).normalized()
		var up := side.cross(tan).normalized()
		for m in nr:
			var ps := TAU * m / nr
			var nrm := side * cos(ps) + up * sin(ps)
			lip.set_color(Color(0.10, 0.085, 0.075))
			lip.set_normal(nrm)
			lip.add_vertex(pk + nrm * r)
			lip_pts.append(pk + nrm * r)
			centres.append(pk)
	for k in nl:
		for m in nr:
			var a := k * nr + m
			var b := k * nr + (m + 1) % nr
			var c := (k + 1) * nr + m
			var d := (k + 1) * nr + (m + 1) % nr
			_tri(lip, a, b, c, lip_pts[a], lip_pts[b], lip_pts[c], lip_pts[a] - centres[a])
			_tri(lip, b, d, c, lip_pts[b], lip_pts[d], lip_pts[c], lip_pts[b] - centres[b])
	lip.commit(mesh)
	var crest: Array = []
	for k in nl + 1:
		var pk: Vector3 = ring_pts[k]
		var tan: Vector3 = (ring_pts[(k + 1) % nl] - ring_pts[(k - 1 + nl) % nl]).normalized()
		var up := tan.cross(Vector3.UP).normalized().cross(tan).normalized()
		crest.append(pk + up * (r + 0.002))
	_tube(pins, crest, 0.007, Livery.coat("paint"), 6)
	var rubber := Finishes.rubber()
	mesh.surface_set_material(2, rubber)

	# fittings
	var hardware := [
	]
	hardware.append_array(_bullring())
	if not shrike and not talon:
		hardware.append_array([
			[Kit.rounded_box(Vector3(0.07, 0.62, 0.85), 4.0), Kit.at(Vector3(0, 0.42, 1.6), Vector3(-0.35, 0, 0)), Livery.coat("paint")],   # raked fin, painted
			[Kit.rounded_box(Vector3(0.076, 0.6, 0.09), 4.0), _fin_xf() * Transform3D(Basis(), Vector3(0, 0, -0.39)), DARK.lightened(0.15)],   # its leading edge
			[Kit.rounded_box(Vector3(0.078, 0.035, 0.66), 4.0), _fin_xf() * Transform3D(Basis(), Vector3(0, 0.2, 0.03)), Livery.coat("pin")],   # a pinstripe along its top
			[Kit.rounded_box(Vector3(0.1, 0.2, 0.72), 4.0), Kit.at(Vector3(-1.1, -0.26, -0.15)), DARK],   # side intakes, behind the cage
			[Kit.rounded_box(Vector3(0.1, 0.2, 0.72), 4.0), Kit.at(Vector3(1.1, -0.26, -0.15)), DARK],
			[Kit.cyl(0.15, 0.19, 0.36, 28), Kit.at(Vector3(-0.5, -0.24, 2.1), Vector3(PI / 2.0, 0, 0)), DARK],   # trim thrusters
			[Kit.cyl(0.15, 0.19, 0.36, 28), Kit.at(Vector3(0.5, -0.24, 2.1), Vector3(PI / 2.0, 0, 0)), DARK],
			[Kit.cyl(0.168, 0.168, 0.035, 32), Kit.at(Vector3(-0.5, -0.24, 2.262), Vector3(PI / 2.0, 0, 0)), SILVER],   # their polished collars
			[Kit.cyl(0.168, 0.168, 0.035, 32), Kit.at(Vector3(0.5, -0.24, 2.262), Vector3(PI / 2.0, 0, 0)), SILVER],
			[Kit.cyl(0.025, 0.1, 0.12, 24), Kit.at(Vector3(-0.5, -0.24, 2.33), Vector3(PI / 2.0, 0, 0)), DARK.lightened(0.3)],   # and exhaust cones
			[Kit.cyl(0.025, 0.1, 0.12, 24), Kit.at(Vector3(0.5, -0.24, 2.33), Vector3(PI / 2.0, 0, 0)), DARK.lightened(0.3)],
		])
	Kit.compound(hardware, mesh)
	mesh.surface_set_material(3, Kit.polished(0.6, 0.28))

	# the cage: hoops round the section and longerons along it, on the skin's mid-line, the
	# first and last hoops right on the cut edges. Nothing crosses the cockpit opening.
	# (The closed nose keeps them as its frames and stringers, on the trim's inner face.)
	var inset := RIB_IN if nose_closed else SKIN / 2.0
	var hoop_r := RIB_R if nose_closed else CAGE_R
	var bars := Color(0.21, 0.21, 0.225) if nose_closed else SILVER   # (closed: coated like the trim, a shade lighter. Left polished they still read as a cage, with panels behind it)
	var cage := SurfaceTool.new()
	cage.begin(Mesh.PRIMITIVE_TRIANGLES)
	var zs: Array[float] = []   # the ring stations that bound the cut
	for i in nz + 1:
		zs.append(lerpf(z0, z1, float(i) / nz))
	var za := 0.0
	var zb := 0.0
	for i in nz:
		var zc := (zs[i] + zs[i + 1]) / 2.0
		if zc > CAGE_Z1 and zc < CAGE_Z0:
			za = zs[i + 1] if za == 0.0 else za
			zb = zs[i + 1]
	za = zs[zs.find(za) - 1]   # the front edge is the ring before the first skipped quad's far side
	var hoops := 6
	for k in hoops:
		var z := lerpf(za, zb, float(k) / (hoops - 1))
		var run: Array = []
		for j in 97:
			var p := cage_point(z, TAU * j / 96.0, inset)
			if p.y > hull_section(z)[1] and _in_opening(p.x, z):
				if run.size() > 1:
					_tube(cage, run, hoop_r, bars)
				run = []
			else:
				run.append(p)
		if run.size() > 1:
			_tube(cage, run, hoop_r, bars)
	for k in range(1, 10):   # longerons, the bottom keel among them; no top spine, so the
		var th := PI / 2.0 + TAU * k / 10.0   # middle of the view ahead stays clear
		var run: Array = []
		for m in 41:
			var z := lerpf(za, zb, float(m) / 40.0)
			var p := cage_point(z, th, inset)
			if p.y > hull_section(z)[1] and _in_opening(p.x, z):
				if run.size() > 1:
					_tube(cage, run, hoop_r * 0.8, bars)
				run = []
			else:
				run.append(p)
		if run.size() > 1:
			_tube(cage, run, hoop_r * 0.8, bars)
	if shrike:
		cage.index()   # adjacent triangles share the tube's ring vertices and normals
	cage.commit(mesh)
	mesh.surface_set_material(4, trim if nose_closed else (Finishes.satin() if Finishes.hd else Kit.polished(1.0, 0.18)))
	paint.index()
	paint.commit(mesh)
	var coat := StandardMaterial3D.new()   # candy over metal flake, under a clear coat
	coat.vertex_color_use_as_albedo = true
	coat.vertex_color_is_srgb = true
	coat.metallic = 0.45
	coat.roughness = 0.34
	coat.metallic_specular = 0.6
	coat.clearcoat_enabled = true
	coat.clearcoat = 1.0
	coat.clearcoat_roughness = 0.06
	mesh.surface_set_material(5, coat)
	if shrike:
		pins.index()
	pins.commit(mesh)
	mesh.surface_set_material(6, Kit.polished(0.3, 0.22))
	# lamps (unshaded, as the engines'): nav lights at the widest point (red left, green right),
	# tail lamps on the thrusters, the fin's tip lamp, the repulsor underglow
	var lamps := [
		[Kit.ball(0.035, 10), Kit.at(Vector3(-1.155, -0.31, -0.3)), NAV_L],
		[Kit.ball(0.035, 10), Kit.at(Vector3(1.155, -0.31, -0.3)), NAV_R],
		[Kit.box(Vector3(0.035, 0.01, 1.5)), Kit.at(Vector3(-0.5, -0.59, 0.3)), UNDERGLOW],
		[Kit.box(Vector3(0.035, 0.01, 1.5)), Kit.at(Vector3(0.5, -0.59, 0.3)), UNDERGLOW],
	]
	if talon:      # Codex's: the wingtips' position lights, and tail lamps across the trim jets' mouths
		for side: float in [-1.0, 1.0]:
			lamps.append([Kit.box(Vector3(0.027, 0.018, 0.16)), Kit.at(Talon.WINGTIP_LAMP * Vector3(side, 1.0, 1.0)), NAV_L if side < 0 else NAV_R])
			lamps.append([Kit.box(Vector3(0.23, 0.021, 0.014)), Kit.at(Talon.JET_LAMP * Vector3(side, 1.0, 1.0)), Color(1.0, 0.13, 0.06)])
	elif not shrike:
		lamps.append_array([
			[Kit.box(Vector3(0.11, 0.022, 0.07)), Kit.at(Vector3(-0.5, -0.07, 2.2)), Color(1.0, 0.1, 0.08)],
			[Kit.box(Vector3(0.11, 0.022, 0.07)), Kit.at(Vector3(0.5, -0.07, 2.2)), Color(1.0, 0.1, 0.08)],
			[Kit.ball(0.03, 10), _fin_xf() * Transform3D(Basis(), Vector3(0, 0.3, 0.38)), Color(1.0, 1.0, 1.0)],
		])
	Kit.compound(lamps, mesh)
	mesh.surface_set_material(7, Kit.vertex_colors(true))
	if talon:
		Talon.add_pod(mesh, nose_closed, Talon.palette())      # surface 8
		mesh.set_meta(&"talon_hull", true)
	mesh.set_meta(&"shrike_hull", shrike)
	mesh.set_meta(&"livery", Livery.current)
	return mesh


## The engine's tow lug (view/tow_link.gd): a pad bolted up into the belly, two hanger plates down from
## it to the boss of the pin the link's yoke forks over, two spacers through the plates to hold them apart,
## and a gusset from the pad down each plate's outer face. Parts for _engine_body's compound.
static func _lug() -> Array:
	var plate := DARK.lightened(0.32)
	var parts := [
		[Kit.rounded_box(Vector3(0.36, 0.09, 1.0), 5.0, 8), Kit.at(Vector3(0, -0.49, 3.15)), DARK.lightened(0.25)],      # (behind the lower brake flaps, as the pylon it replaces was)
		[Fairings.fin(PackedVector2Array(LUG_PLATE), 0.035), Kit.at(Vector3(-0.085, 0, 0)), plate],
		[Fairings.fin(PackedVector2Array(LUG_PLATE), 0.035), Kit.at(Vector3(0.085, 0, 0)), plate],
		[Kit.cyl(0.068, 0.068, 0.22, 18), Kit.at(ENGINE_EYE, Vector3(0, 0, PI / 2.0)), TowLink.BRIGHT],                       # the pin's boss
	]
	var st := SurfaceTool.new()      # its fasteners and gussets: one part, in their own colours
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for at in [Vector2(-0.68, 3.2), Vector2(-0.63, 2.98)]:      # the spacers (y, z): a tube between the plates, a bolt through it, a head one side and a nut the other
		TowLink._turn(st, [[-0.0675, 0.026, TowLink.BRIGHT], [0.0675, 0.026, TowLink.BRIGHT]], 8, Transform3D(TowLink.ABOUT_X, Vector3(0, at.x, at.y)))
		for s in [-1.0, 1.0]:
			TowLink._head(st, TowLink._along(Vector3(s, 0, 0), Vector3(0.1025 * s, at.x, at.y)), 0.03, 0.016, TowLink.BRIGHT, 6, true)
	for s in [-1.0, 1.0]:
		for z in [2.76, 3.02, 3.28, 3.54]:      # the pad's bolts, up into the belly's hard points
			TowLink._head(st, TowLink._along(Vector3.DOWN, Vector3(0.142 * s, -0.52, z)), 0.017, 0.024, TowLink.BRIGHT, 6, true)
		for z in [2.92, 3.4]:                   # a gusset from the pad down the plate's outer face
			TowLink._web(st, Vector3(0.1025 * s, -0.525, z), Vector3(0.168 * s, -0.525, z), Vector3(0.1025 * s, -0.64, z), 0.014, plate)
	st.index()
	parts.append([st.commit(), Transform3D.IDENTITY, Color.WHITE, true])
	return parts


## The bullring: what the tow links pull on (view/tow_link.gd). A forged hoop shrunk round the nose cap
## carries the load into the hull; a crown block across its top carries a swivel post either side of
## centre, where the sim anchors the links. (It was a bar across the nose with a disc on each end.)
## Its fittings, in their own colours: each post a bearing pedestal (a bright race ring under the swivel's
## thrust washer); the crown block bolted down between them, a rib along it; on the rib the tow-load
## amplifier (what the Shrike's coaming reads its TOW windows from), a conduit from it to each post's load
## cell through a bronze gland; and the clamps that hold the block's ends down onto the hoop.
static func _bullring() -> Array:
	var hoop := SurfaceTool.new()
	hoop.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring: Array = []
	for j in 51:      # from the keel round and a little past it, so the tube's ends meet out of sight
		ring.append(cage_point(TowLink.RING_Z, -PI / 2.0 + TAU * j / 48.0, 0.0))
	_tube(hoop, ring, TowLink.RING_R, TowLink.FORGED, 10)
	var z := -2.1                                   # the posts' station: the sim's anchors (_pod_anchor)
	var seat := POD_EYE_H - TowLink.HUB - 0.012     # the posts' tops: the swivels' thrust washers sit on them
	var mid := hull_top(0.0, z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := mid + 0.023                          # the crown block's top face
	TowLink._add(st, Finishes.beveled_plate(Vector3(0.21, 0.07, 0.15), 0.01), Kit.at(Vector3(0, mid - 0.012, z + 0.02)), TowLink.FORGED)      # the crown block, between the posts
	TowLink._add(st, Finishes.beveled_plate(Vector3(0.084, 0.02, 0.126), 0.005), Kit.at(Vector3(0, top + 0.009, z + 0.02)), TowLink.GUNMETAL)  # its rib
	TowLink._add(st, Finishes.beveled_plate(Vector3(0.05, 0.022, 0.058), 0.004), Kit.at(Vector3(0, top + 0.03, z + 0.024)), TowLink.BRIGHT)    # the tow-load amplifier
	for s in [-1.0, 1.0]:
		var x: float = 0.18 * s
		var skin := hull_top(x, z)
		# a post: its foot out of the skin, then the bearing's race ring the swivel's washer sits in
		TowLink._turn(st, [[skin - 0.03, 0.0, TowLink.GUNMETAL], [skin - 0.03, 0.09, TowLink.GUNMETAL], [seat - 0.012, 0.08, TowLink.GUNMETAL], [seat - 0.012, 0.0745, TowLink.BRIGHT],
			[seat, 0.0745, TowLink.BRIGHT], [seat, 0.06, TowLink.BRIGHT]], 16, Transform3D(TowLink.ABOUT_Y, Vector3(x, 0.0, z)))
		var out: float = 0.292 * s                                                                                                           # a clamp outboard of it, down onto the hoop
		var clamp_top := hull_top(out, z) + 0.03
		TowLink._add(st, Finishes.beveled_plate(Vector3(0.075, 0.07, 0.13), 0.01), Kit.at(Vector3(out, clamp_top - 0.035, z + 0.02)), TowLink.FORGED)
		for bz in [z + 0.058, z - 0.018]:
			TowLink._head(st, Transform3D(TowLink.ABOUT_Y, Vector3(out, clamp_top, bz)), 0.015, 0.011, TowLink.BRIGHT, 6, true)
			TowLink._head(st, Transform3D(TowLink.ABOUT_Y, Vector3(0.076 * s, top, bz)), 0.014, 0.011, TowLink.BRIGHT, 6, true)                 # the crown's bolts
		# the amplifier's lead to this post's load cell: out of a gland on its side, over the block's end and down through the skin beside the post
		var lead := Vector3(0.025 * s, top + 0.03, z + 0.024)
		TowLink._head(st, TowLink._along(Vector3(s, 0, 0), lead), 0.0085, 0.012, TowLink.BRONZE, 6, true)
		TowLink._pipe(st, [lead + Vector3(0.012 * s, 0, 0), Vector3(0.07 * s, top + 0.027, z + 0.032), Vector3(0.106 * s, top + 0.002, z + 0.05), Vector3(0.122 * s, seat - 0.018, z + 0.062)],
			0.005, TowLink.FORGED, 4)
	st.index()
	return [
		[hoop.commit(), Transform3D.IDENTITY, TowLink.FORGED],
		[st.commit(), Transform3D.IDENTITY, Color.WHITE, true],
	]


## The pod's hull in another livery than the craft's own (a patrol's black and white, say).
static func pod_hull_in(which: String, shrike := false, talon := false) -> ArrayMesh:
	var own := Livery.current
	Livery.current = which
	var mesh := pod_hull(shrike, talon)
	Livery.current = own
	return mesh


## Close the nose or open it again, on every pod already standing under `under` (the cockpit's own
## hull, the craft's, a driving partner's): each takes the other hull.
static func set_nose_closed(closed: bool, under: Node = null) -> void:
	if nose_closed == closed:
		return
	nose_closed = closed
	if under:
		for part: MeshInstance3D in under.find_children("*", "MeshInstance3D", true, false):
			if part.mesh and part.mesh.get_meta(&"shrike_hull",false) and part.has_node("Arms"):
				part.get_node("Arms").fit_pod(pod_hull_in(String(part.mesh.get_meta(&"livery",Livery.current)),true))
				continue
			if part.has_meta(&"service_bonnet"):
				part.visible = closed
			elif part.mesh and part.mesh.has_meta(&"shrike_hull"):
				var bays := String(part.mesh.get_meta(&"talon_bays", ""))      # (the Talon's gun bays, open or sealed: kept)
				part.mesh = pod_hull_in(String(part.mesh.get_meta(&"livery", Livery.current)), part.mesh.get_meta(&"shrike_hull"), part.mesh.get_meta(&"talon_hull", false))
				if bays != "":
					part.mesh = Talon.with_bays(part.mesh, bays)



## The outer skin (surface 0, polished metal) and its paint (into `paint`: the top decks and the
## nose candy orange, a gunmetal stripe down each flank), smooth normals across both so the seams
## don't show in the shading; a pinstripe (into `pins`) along each edge of the top decks' paint.
static func _outer_skin(grid: Array, nz: int, na: int, mesh: ArrayMesh, paint: SurfaceTool, pins: SurfaceTool, talon := false) -> void:
	var z0: float = HULL[0][0]
	var z1: float = HULL[HULL.size() - 1][0]
	var pts: Array[Vector3] = []
	for i in nz + 1:
		for j in na:
			pts.append(grid[i][j][0])
	var faces := []   # [i0, i1, i2, outward, its paint (null: metal)]
	for i in nz:
		for j in na:
			var j2 := (j + 1) % na
			var a := i * na + j
			var b := i * na + j2
			var c := (i + 1) * na + j
			var d := (i + 1) * na + j2
			var cen: Vector3 = (pts[a] + pts[b] + pts[c] + pts[d]) / 4.0
			var cc: float = (grid[i][j][1] + grid[i + 1][j][1]) / 2.0
			if cen.y > cc and _in_opening(cen.x, cen.z):
				continue   # the cockpit
			if not nose_closed and cen.z > CAGE_Z1 and cen.z < CAGE_Z0:
				continue   # the open cage
			var ha: float = (grid[i][j][2] + grid[i + 1][j][2]) / 2.0
			var hb: float = (grid[i][j][3] + grid[i + 1][j][3]) / 2.0
			var col = _paint_at(absf(cen.x) / ha, (cen.y - cc) / hb, cen.z, talon)
			var outward := Vector3(cen.x, cen.y - cc, 0.0)
			faces.append([a, b, c, outward, col])
			faces.append([b, d, c, outward, col])
	for e in 2:   # end caps: fans to a point just beyond each end (the nose's painted)
		var ri := 0 if e == 0 else nz
		var ti := pts.size()
		pts.append(Vector3(0.0, grid[ri][0][1], z0 - 0.02 if e == 0 else z1 + 0.02))
		var axis := Vector3(0, 0, -1.0 if e == 0 else 1.0)
		for j in na:
			faces.append([ri * na + j, ri * na + (j + 1) % na, ti, axis, Livery.coat("paint") if e == 0 else null])
	var nrm: Array[Vector3] = []
	nrm.resize(pts.size())
	nrm.fill(Vector3.ZERO)
	for f in faces:
		var fn: Vector3 = (pts[f[1]] - pts[f[0]]).cross(pts[f[2]] - pts[f[0]])
		if fn.dot(f[3]) < 0.0:
			fn = -fn
		for q in 3:
			nrm[f[q]] += fn
	for k in nrm.size():
		nrm[k] = nrm[k].normalized()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in pts.size():
		st.set_color(Livery.coat("skin"))
		st.set_normal(nrm[k])
		st.add_vertex(pts[k])
	for f in faces:
		var p0: Vector3 = pts[f[0]]
		var p1: Vector3 = pts[f[1]]
		var p2: Vector3 = pts[f[2]]
		if f[4] == null:
			_tri(st, f[0], f[1], f[2], p0, p1, p2, f[3])
			continue
		var order := [0, 2, 1] if (p1 - p0).cross(p2 - p0).dot(f[3]) > 0.0 else [0, 1, 2]
		for q in order:
			paint.set_color(f[4])
			paint.set_normal(nrm[f[q]])
			paint.add_vertex(pts[f[q]])
	st.commit(mesh)
	mesh.surface_set_material(0, Kit.polished(1.0, 0.14))
	# the pinstripes: along the first row of the top decks' paint, each side, from the cage back
	var jp := 0
	for j in na / 4:
		var s0 := Kit._sp(sin(TAU * j / na), 2.0 / HULL_N)
		var s1 := Kit._sp(sin(TAU * (j + 1) / na), 2.0 / HULL_N)
		if (s0 + s1) / 2.0 > PAINT_SY:
			jp = j
			break
	for jj in [jp, na / 2 - jp]:
		var run: Array = []
		for i in range(1, nz):
			var p: Vector3 = pts[i * na + jj]
			if p.z < (-1.96 if nose_closed else CAGE_Z0 + 0.02):    # (closed: on to the painted nose)
				continue
			run.append(p + nrm[i * na + jj] * 0.005)
		if run.size() > 1:
			_tube(pins, run, 0.008, Livery.coat("pin"), 6)


## The paint at a skin quad: |x| over the half-width, height over the half-height (from the
## section's centre), station z. Null where it's bare metal.
static func _paint_at(ax: float, sy: float, z: float, talon := false):
	if z < -1.98 or sy > PAINT_SY:
		# (The Talon's, Codex's: an anti-glare panel under the windshield, with a narrow painted shoulder
		# widening round the canopy's sills.)
		if talon and ax < clampf(0.64 + absf(z) * 0.11, 0.64, 0.90):
			return Livery.coat("stripe")
		return Livery.coat("paint")
	if ax > 0.7 and sy > -0.2 and sy < 0.22:
		return Livery.coat("stripe")
	return null


## A point on the skin's mid-line (or `inset` in from the outer skin) at station z, angle th round the section.
static func cage_point(z: float, th: float, inset := SKIN / 2.0) -> Vector3:
	var h := hull_section(z)
	return Vector3((h[0] - inset) * Kit._sp(cos(th), 2.0 / HULL_N), h[1] + (h[2] - inset) * Kit._sp(sin(th), 2.0 / HULL_N), z)


## A round tube along a polyline (parallel-transported frames, so it doesn't twist).
static func _tube(st: SurfaceTool, path: Array, r: float, col: Color, sides := 8) -> void:
	var n := path.size()
	var rings := []
	var nrm := Vector3.ZERO
	for i in n:
		var t: Vector3 = ((path[mini(i + 1, n - 1)] as Vector3) - (path[maxi(i - 1, 0)] as Vector3)).normalized()
		if i == 0:
			nrm = t.cross(Vector3.UP)
			if nrm.length() < 0.1:
				nrm = t.cross(Vector3.RIGHT)
		nrm = (nrm - t * nrm.dot(t)).normalized()
		var bn := t.cross(nrm)
		var ring := []
		for k in sides:
			var a := TAU * k / sides
			ring.append(nrm * cos(a) + bn * sin(a))
		rings.append(ring)
	for i in n - 1:
		for k in sides:
			var k2 := (k + 1) % sides
			var p0: Vector3 = path[i]
			var p1: Vector3 = path[i + 1]
			var quad := [[p0, rings[i][k]], [p1, rings[i + 1][k]], [p1, rings[i + 1][k2]], [p0, rings[i][k2]]]
			for q in [0, 1, 2, 0, 2, 3]:
				st.set_color(col)
				st.set_normal(quad[q][1])
				st.add_vertex((quad[q][0] as Vector3) + (quad[q][1] as Vector3) * r)


static func heat_color(h: float) -> Color:
	return STEEL.lerp(HOT, h / 0.6) if h < 0.6 else HOT.lerp(WHITE, minf(1.0, (h - 0.6) / 0.4))


## Lean for each body from its lateral acceleration (velocity change across the frame, along
## the body's left). A respawn's velocity jump is ignored rather than banked.
## One step of the lean: (bank rad, smoothed lateral g) after `delta` s of lateral g `lat_g`.
## The g is smoothed, the lean eases toward BANK_MAX * tanh(g / BANK_G) and its roll rate is
## capped. Asymmetric: rolling in is gentle (BANK_TAU, BANK_RATE); letting go and rolling back
## toward level is quicker (BANK_TAU_OUT, BANK_RATE_OUT), so coming out of a turn doesn't drag.
static func ease_bank(bank_now: float, lat_s: float, lat_g: float, delta: float) -> Array:   # [bank, lat] (64-bit: not a Vector2)
	var letting_go := absf(lat_g) < absf(lat_s) or signf(lat_g) != signf(lat_s)
	lat_s = lerpf(lat_s, lat_g, 1.0 - exp(-delta / (BANK_TAU_OUT if letting_go else BANK_TAU)))
	var target := BANK_MAX * tanh(lat_s / BANK_G)
	var to_level := bank_now != 0.0 and signf(target - bank_now) != signf(bank_now)
	return [move_toward(bank_now, target, (BANK_RATE_OUT if to_level else BANK_RATE) * delta), lat_s]


func _update_bank(sim, delta: float) -> void:
	var all := [sim.eL, sim.eR, sim.pod]
	# A shaft's bulb turns the craft with its road: not a turn you lean into. The sim counts that turn
	# (carry_turn), and the frame's share of it comes out of the velocity the frame began with before the
	# load is read. (It was the curvature under each body times its speed squared: right while the
	# curvature held, and a frame of up to 120 g where the plan's arcs change hands, which rocked the
	# craft at the foot and over the top.)
	var counted = sim.get("carry_turn")
	var turn_now: float = float(counted) if counted != null else 0.0
	if _prev_v.is_empty() or delta <= 0.0:
		_prev_v = [[all[0].vx, all[0].vy], [all[1].vx, all[1].vy], [all[2].vx, all[2].vy]]
		_prev_turn = turn_now
		return
	var turned := turn_now - _prev_turn
	_prev_turn = turn_now
	if absf(turned) > 1.0:   # (another sim's count)
		turned = 0.0
	var ct := cos(turned)
	var st := sin(turned)
	for k in 3:
		var b = all[k]
		var ax: float = (b.vx - (ct * _prev_v[k][0] - st * _prev_v[k][1])) / delta
		var ay: float = (b.vy - (st * _prev_v[k][0] + ct * _prev_v[k][1])) / delta
		_prev_v[k] = [b.vx, b.vy]
		var lat_g: float = (-sin(b.th) * ax + cos(b.th) * ay) / 9.81
		if absf(lat_g) > 150.0 or sim.crash_t > 0.0:   # respawn / crash: not a turn
			lat_g = 0.0
		lat_g *= b.grip   # airborne: nothing to lean against
		var was: float = bank[k]
		var e := ease_bank(bank[k], _lat[k], lat_g, delta)
		bank[k] = e[0]
		_lat[k] = e[1]
		if k == 2:
			roll_rate_peak = maxf(roll_rate_peak, absf(bank[k] - was) / delta)


## The Phaethon's rudders and stabiliser panels drawn where their pivots are on the engines, as the engines stand.
func _place_fin_batches() -> void:
	for k in rudders.size():
		fin_batches[0].set_instance_transform(k, engines[k].transform * rudders[k].transform)
		fin_batches[1].set_instance_transform(k, engines[k].transform * stabilisers[k].transform)


## One of the Shrike's fins stood at a cant, its ram's cylinder and rod with it (Shrike.fin_solve), and
## its outer panel swung on its spindle (`swing` rad; left out: as far as the turn has it, fin_swing).
func _place_fin(k: int, cant: float, swing := NAN) -> void:
	var out := -1.0 if k == 0 else 1.0
	var at: Dictionary = Shrike.fin_solve(out, cant)
	(fin_parts[k][0] as Node3D).transform = at.fin
	(fin_parts[k][1] as Node3D).transform = at.barrel
	(fin_parts[k][2] as Node3D).transform = at.rod
	_fin_posed[k] = fin_swing if is_nan(swing) else swing
	(fin_parts[k][3] as Node3D).transform = Shrike.panel_place(out, _fin_posed[k])
	fin_ram[k] = at.showing
	fin_stand[k] = cant


func sync(sim, inp: Dictionary, delta: float) -> void:
	_update_bank(sim, delta)
	# On a deck road (Mount Hyperion's) the craft's pitch is the deck's own under the pod, moving or stopped
	# (its climb is not its vz over its speed there, and a craft stopped on an 80 degree wall is not level).
	var on_deck: bool = sim.kind == "network" and not sim.pod.off_road and sim.roads[sim.pod.path].deck
	var deck_pitch: float = sim.deck_pitch(sim.pod) if on_deck else 0.0
	for k in 2:
		var e = sim.eL if k == 0 else sim.eR
		var eng := engines[k]
		eng.position = view.body_place(e, 0.1) if view.has_method("body_place") else view.wz(e.x, e.y, e.z + 0.1)
		var vh: float = sqrt(e.vx * e.vx + e.vy * e.vy)
		var pitch: float = atan2(e.vz, maxf(vh, 1.0)) if vh > 5.0 else 0.0
		if on_deck:
			pitch = deck_pitch
		# nose follows the banking's rise and fall (on the Network the climb is in the body's own vz:
		# the deck lock, the jumps)
		var climb := 0.0 if sim.kind == "network" else slope_pitch(view, e.x, e.y, e.th, maxf(4.0, pitch_half(vh)))
		var lean := clampf(bank[k] + view.surface(e.x, e.y).y, -ROLL_MAX, ROLL_MAX)   # lean, plus the track's banking
		var Qe: Basis = Basis.IDENTITY
		if sim.kind == "network":   # (its heading against the road's direction under the pod: the craft is carried whole)
			Qe = view.shaft_carry_body(e.x, e.y) if view.has_method("shaft_carry_body") else view.shaft_carry_at(e.x, e.y)
		if not Qe.is_equal_approx(Basis.IDENTITY):   # up a shaft: flat, carried onto its shape (its climb is the shape's)
			eng.basis = Qe * Basis.from_euler(Vector3(0.0, e.th - PI / 2.0, lean))
		elif sim.pod.path > 0 and sim.kind != "network":   # the shade line: flat, carried onto the twisted road
			eng.basis = road_attitude(sim, e.x, e.y, climb) * Basis.from_euler(Vector3(pitch, e.th - PI / 2.0, lean))
		else:
			eng.rotation = Vector3(pitch + climb, e.th - PI / 2.0, lean)
	CanopyScript.update(canopy, sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy), sim.hblend, sim.mode, delta)
	pod.position = view.wz(sim.pod.x, sim.pod.y, sim.pod.z - 0.2 + POD_LIFT)
	var pvh: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
	var pclimb := (atan2(sim.pod.vz, maxf(pvh, 1.0)) if pvh > 5.0 else 0.0) if sim.kind == "network" else slope_pitch(view, sim.pod.x, sim.pod.y, sim.pod.th, pitch_half(pvh))
	if on_deck:
		pclimb = deck_pitch
	var plean := clampf(bank[2] + view.surface(sim.pod.x, sim.pod.y).y, -ROLL_MAX, ROLL_MAX)
	var Qp: Basis = view.shaft_carry_at(sim.pod.x, sim.pod.y) if sim.kind == "network" else Basis.IDENTITY
	if not Qp.is_equal_approx(Basis.IDENTITY):
		pod.basis = Qp * Basis.from_euler(Vector3(0.0, sim.pod.th - PI / 2.0, plean))
	elif sim.pod.path > 0 and sim.kind != "network":
		pod.basis = road_attitude(sim, sim.pod.x, sim.pod.y, pclimb) * Basis.from_euler(Vector3(0.0, sim.pod.th - PI / 2.0, plean))
	else:
		pod.rotation = Vector3(pclimb, sim.pod.th - PI / 2.0, plean)
	sync_hardware(sim, inp, delta)


## Animate the installed equipment independently of the body poses. A craft on
## its service stands has the same nozzles, vanes, brakes, rotors and tail lights.
func sync_hardware(sim, inp: Dictionary, delta: float) -> void:
	var bodies := [sim.eL, sim.eR]
	var brakes := [inp.brkL, inp.brkR]   # each engine's flaps answer to its own brake
	var steer: float = sim.eL.thrust - sim.eR.thrust + 0.72*(inp.brkR-inp.brkL)
	# The vanes: the levers' split asks at once, and the turn's own load holds them over (_lat is each
	# engine's cornering load along its own left, so a right turn's is negative). On the split alone
	# they never moved for the way the craft is flown: a few per cent of split, tens of g.
	var turn_g: float = -0.5 * (float(_lat[0]) + float(_lat[1]))
	if delta > 0.0:
		vane_angle = Jets.slew(vane_angle, Jets.command(steer, turn_g, 0.5 * (sim.eL.thrust + sim.eR.thrust)), delta)
	for lights in light_meshes:
		lights.visible = lights_on
	# The fins answer the turn (view/fin_steering.gd): the levers' split at once and the turn's own load,
	# eased, as a share of each surface's travel. Nothing while the battery is off.
	if delta > 0.0:
		fin_drive = Fins.ease(fin_drive, Fins.ask(steer, turn_g) if lights_on else 0.0, delta)
	var share: float = Fins.share(fin_drive)
	if not fin_parts.is_empty():      # the Shrike's fins: with the craft's speed and the turn, no faster than their rams
		var mph: float = 0.5 * (Vector2(sim.eL.vx, sim.eL.vy).length() + Vector2(sim.eR.vx, sim.eR.vy).length()) * 2.2369363
		var want: float = Shrike.fin_cant(mph)
		if want != fin_cant:
			fin_cant = want if delta <= 0.0 else move_toward(fin_cant, want, Shrike.FIN_SLEW * delta)
		if delta > 0.0:
			fin_swing = move_toward(fin_swing, Shrike.PANEL_SWING * share, Shrike.PANEL_SLEW * delta)
		for k in fin_parts.size():      # (the inside engine's lays out and the outside engine's stands up, inside the ram's travel)
			var stand: float = clampf(fin_cant + (-1.0 if k == 0 else 1.0) * Shrike.FIN_LEAN * share, Shrike.FIN_REST, Shrike.FIN_FAST)
			if delta > 0.0:
				stand = move_toward(fin_stand[k], stand, Shrike.FIN_SLEW * delta)
			if stand != fin_stand[k] or fin_swing != _fin_posed[k]:
				_place_fin(k, stand)
	elif not rudders.is_empty() and delta > 0.0:      # the Phaethon's: its rudders and its stabilisers
		fin_swing = move_toward(fin_swing, Fins.SWING_MAX * share, Fins.SWING_SLEW * delta)
		fin_pitch = move_toward(fin_pitch, Fins.PITCH_MAX * share, Fins.PITCH_SLEW * delta)
		if fin_swing != _fin_posed[0] or fin_pitch != _fin_posed[1]:
			_fin_posed = [fin_swing, fin_pitch]
			for k in 2:
				rudders[k].rotation.y = fin_swing
				stabilisers[k].transform = Fins.stabiliser_place(-1.0 if k == 0 else 1.0, ENG_W / 2.0, fin_pitch)
	for k in 2:
		var e = bodies[k]
		var vh: float = sqrt(e.vx * e.vx + e.vy * e.vy)
		var h: float = e.heat
		var out: bool = e.flameout or held[k]                                           # dark: flamed out, or not started
		var thrust: float = shown_thrust[k] if shown_thrust[k] >= 0.0 else e.thrust     # (the start-up's, while the sim's own is held at nothing)
		var col := Color(0.25, 0.25, 0.25) if out else heat_color(h)
		hot_mats[k].albedo_color = col
		hot_mats[k].emission = Color.BLACK if out else col * smoothstep(0.35, 1.0, h) * 1.4
		var t: float = 0.0 if out else minf(thrust, 1.0)
		# fan: spins up with thrust, winds down on a flameout; capped below where it would strobe
		var w_target := 0.0 if out else 3.0 + 16.0 * t
		_fan_w[k] = lerpf(_fan_w[k], w_target, 1.0 - exp(-delta * 2.0))
		for r in rotors[k].size():   # paired rotors counter-rotate
			var rotor: Node3D = rotors[k][r]
			rotor.rotation.z = fposmod(rotor.rotation.z + _fan_w[k] * delta * (1.0 if r == 0 else -1.0), TAU)
		# Hinge travel follows the actuator. The pressure face only buffets when
		# deployed in fast air; the two frequencies keep adjacent leaves off beat.
		var pressure := smoothstep(180.0, 760.0, vh)
		_flap_phase[k] = fposmod(_flap_phase[k] + TAU*(5.2+3.6*pressure)*delta, TAU*5.0)
		flap_open[k] = move_toward(flap_open[k], clampf(brakes[k], 0.0, 1.0), FLAP_RATE * delta)
		for i in flaps[k].size():
			var hinge: Node3D = flaps[k][i]
			hinge.rotation.x = -FLAP_OPEN*flap_open[k] - _flutter(_flap_phase[k], i, flap_open[k], pressure)
		# (parked, the front speed brakes stand out with the rest: Luke, flying the fourteenth, "the
		# parking brake should engage all flaps, not just the low speed ones". `park` is the cockpit's.)
		var front_ask: float = 1.0 if bool(inp.get("park", false)) else clampf(float(e.front), 0.0, 1.0)
		front_open[k] = move_toward(front_open[k], front_ask, FLAP_RATE * delta)
		for i in front_flaps[k].size():
			var fh: Node3D = front_flaps[k][i]
			var flex := 0.78 * _flutter(_flap_phase[k], i+4, front_open[k], pressure)
			fh.rotation.y = (FRONT_OPEN*front_open[k] + flex) * float(fh.get_meta("side"))
		for vp in vanes[k]:
			(vp as Node3D).rotation.y = vane_angle
		# the fin strobe: a double flash every 1.2 s, the two engines a beat apart
		var ph := fposmod(Time.get_ticks_msec() / 1000.0 + 0.6 * k, 1.2)
		strobes[k].visible = lights_on and (ph < 0.05 or (ph > 0.14 and ph < 0.19))
		# binder emitters: a living glow, hotter and toward violet as the binder strains
		var strain := clampf(absf(sim.binder_stretch) / maxf(sim.P.binderBreak, 0.01), 0.0, 1.0)
		var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.012 + k)
		binder_mats[k].albedo_color = BINDER_COL.lerp(Color(0.8, 0.45, 1.0), strain) * (0.7 + 0.5 * pulse) * energised
		# The nozzle and the gas (view/jet_exhaust.gd): the flaps open and shut with the power and lead
		# the burner's light, which comes zone by zone; the metal the gas washes heats, and cools slowly.
		var flame := flames[k]
		var burning: bool = not out and thrust > 0.02
		flame.visible = burning
		var jet = jets[k]
		if delta > 0.0:
			jet.step(delta, burning, "ramjet" if sim.boost > 0 else sim.mode, thrust, h, vh)   # (boosted, the nozzle shows all it has)
		_burn[k] = jet.lit
		_ram[k] = jet.ram
		Jets.set_metal(metal_mats[k], jet.metal)
		for hinge in nozzle_flaps[k]:
			(hinge as Node3D).rotation.x = -Jets.flap_angle(jet.exit)
		# the flame holder's face: the turbine's dull glow behind its holes, the burner's fire on it
		var behind := Color(0.95, 0.30, 0.07) * (0.10 + 0.5 * t)
		glow_mats[k].albedo_color = DARK if not burning else behind.lerp(Color(2.4, 1.7, 1.0), _burn[k]).lerp(Color(1.7, 1.9, 2.5), _ram[k])
		var lamp: OmniLight3D = nozzle_lights[k]
		lamp.light_color = Color(1.0,0.48,0.19).lerp(Color(0.34,0.61,1.0),_ram[k])
		lamp.light_energy = _burn[k] * (2.2 + 0.14 * sin(Time.get_ticks_msec() * 0.19 + k * 2.0) + 1.6 * jet.flash) * minf(thrust, 1.2) if burning else 0.0
		if burning:
			# (the pod's nose is 12.6 m behind the nozzles: the flame stops short of it)
			var reach: float = maxf(jet.reach, 0.3)
			plume_len[k] = reach
			var swing: Vector2 = _trace_plume(k, e, reach, vh)
			lamp.position = flame.position + Vector3(plume_at(k, 1.2), -0.2, 1.2)
			var across: float = (PLUME_SLOT.x * 1.04 + 0.03 * reach) * 1.3    # the tube's half-width at its widest (flame.gdshader's girth and MARGIN)
			var fmat: ShaderMaterial = flame_mats[k][0]
			fmat.set_shader_parameter("centre", plume_line[k])
			fmat.set_shader_parameter("reach", reach)
			fmat.set_shader_parameter("thrust", thrust)
			fmat.set_shader_parameter("burner", _burn[k])
			fmat.set_shader_parameter("ramjet", _ram[k])
			fmat.set_shader_parameter("slot", Vector2(PLUME_SLOT.x, jet.exit))
			fmat.set_shader_parameter("cell", jet.cell)
			fmat.set_shader_parameter("shock", jet.shock)
			fmat.set_shader_parameter("flash", jet.flash)
			fmat.set_shader_parameter("teb", jet.teb)
			(flame.get_node("plume") as MeshInstance3D).custom_aabb = AABB(Vector3(swing.x - across, -across, -0.2), Vector3(swing.y - swing.x + across * 2.0, across * 2.0, reach + 0.4))
			nozzle_mats[k].set_shader_parameter("thrust", thrust)
			nozzle_mats[k].set_shader_parameter("burner", _burn[k])
			nozzle_mats[k].set_shader_parameter("ramjet", _ram[k])
			nozzle_mats[k].set_shader_parameter("flash", jet.flash)
			nozzle_mats[k].set_shader_parameter("teb", jet.teb)

	_place_fin_batches()      # (after the engines: the Phaethon's rudders and stabiliser panels go where they are)
	if tail_lights:
		var lens := tail_lights.material_override as ShaderMaterial
		if lights_on != _tail_powered:
			lens.set_shader_parameter("powered", lights_on)
			_tail_powered = lights_on
		var signal_level := Vector2(inp.brkL, inp.brkR).clamp(Vector2.ZERO, Vector2.ONE)
		if signal_level != _brake_signal:
			lens.set_shader_parameter("brakes", signal_level)
			_brake_signal = signal_level
	pod_flap_open = move_toward(pod_flap_open, clampf(minf(inp.brkL, inp.brkR), 0.0, 1.0), FLAP_RATE * delta)
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		pod_flaps[i].rotation.y = s * FLAP_OPEN * 0.8 * pod_flap_open   # trailing edge swings out


## The jet's centre line: metres to the engine's right at PLUME_STATIONS stations down its length
## (into plume_line[k]); returns its leftmost and rightmost reach. The gas leaves the nozzle turned
## by the vanes, though by less than the vanes themselves (Jets.turning()); the air it is thrown
## into is going straight back past the engine (and across it, in a slide: it comes from where the
## engine is going, not where it points), and carries the jet round into itself along Margason's
## line (Jets.across()): a kink at the nozzle that bends away downstream, sooner the faster the
## air against the jet. Standing still there is no slipstream and the jet is a straight line.
## (The gas takes a hundredth of a second to run the jet's length, so the whole of it answers the
## vanes at once: the old plume's tail trailed them by a third of a second, for show.)
func _trace_plume(k: int, e, reach: float, speed: float) -> Vector2:
	var jet = jets[k]
	var air := 0.0      # the slipstream's own line past the engine, radians to its right
	if speed > 20.0:
		air = clampf(wrapf(atan2(e.vy, e.vx) - e.th, -PI, PI), -0.4, 0.4)
	var leave: float = Jets.turning(jet.lit) * vane_angle      # the way the gas leaves, against the engine's own line
	var line: PackedFloat32Array = plume_line[k]
	var x0 := (NOZZLE_EXIT - Jets.VANE_Z - Jets.VANE_CHORD) * tan(leave)    # the vanes' trailing edges are that far up the nozzle
	var dz := reach / float(PLUME_STATIONS - 1)
	var swing := Vector2(x0, x0)
	for i in PLUME_STATIONS:
		var z := i * dz
		var x: float = x0 + z * tan(air) + Jets.across(z, leave - air, jet.j)
		line[i] = x
		swing = Vector2(minf(swing.x, x), maxf(swing.y, x))
	plume_line[k] = line
	return swing


## The plume's centre, metres to the engine's right, `z` metres behind the nozzle.
func plume_at(k: int, z: float) -> float:
	var f := clampf(z / maxf(plume_len[k], 0.01), 0.0, 1.0) * float(PLUME_STATIONS - 1)
	var i := mini(int(f), PLUME_STATIONS - 2)
	return lerpf(plume_line[k][i], plume_line[k][i + 1], f - float(i))


static func _flutter(phase: float, leaf: int, opening: float, pressure: float) -> float:
	var vibration := 0.70*sin(phase + leaf*1.41) + 0.30*sin(phase*1.6 + leaf*2.25)
	return deg_to_rad(1.85) * pressure * opening * opening * vibration


func update_jet_clearance() -> void:
	for k in 2:
		if flames[k].visible:
			EffectExclusion.apply(view, flame_mats[k])


## Where link k hooks to the drawn pod (the middle of its swivel post on the bullring): the sim's anchor
## (podLen/2 ahead, podAnchorW of the half-width to that side; eL's link on the left), from the pod's CURRENT pose. Not the
## sim's cables[k].px/py: those are taken mid-step, before integration, so they trail the pod
## by a step (half a metre at 500 mph, metres flat out). Out through the banked pod, or the VR
## cockpit frame standing in for it.
func _pod_anchor(sim, k: int) -> Vector3:
	var left: float = (1.0 if k == 0 else -1.0) * sim.P.podAnchorW * sim.P.podWidth / 2.0
	var local := Vector3(-left, POD_EYE_H, -sim.P.podLen / 2.0 - 0.1)   # onto the post, just ahead of the sim's nose
	if pod_frame:
		return pod_frame.transform * (pod_frame_pose * (local + Vector3(0, POD_FRAME_UP, 0) + pod_frame_shift))
	return pod.transform * local


const CABLE_COOL := Color(0.25, 0.65, 1.0)    # energized blue at low thrust ...
const CABLE_HOT := Color(0.85, 0.95, 1.0)     # ... white-hot on the burner
const CABLE_SF := Color(1.0, 0.3, 0.75)       # STARFIGHTER's energized magenta (ModeSwitch.SF_COL)


## How hard cable k glows for its engine's thrust (0..1 lever, more on the burner): nothing at
## idle, rising with thrust, crackling at the top. Follows real thrust, so a damaged engine's
## sputter flickers its cable and a flameout goes dark (Luke: "make the cables glow like they're
## energized with the amount of throttle").
## Its colour follows the handling: energized blue in SPEEDCRAFT, magenta in STARFIGHTER (sf: the
## sim's live blend, 0..1), white-hot on the burner either way.
static func cable_glow(thrust: float, sf := 0.0) -> Array:
	var base := CABLE_COOL.lerp(CABLE_SF, clampf(sf, 0.0, 1.0))
	if thrust < 0.02:
		return [0.0, base]
	var g := clampf(thrust, 0.0, 1.6)
	var energy := 0.4 + 3.2 * pow(minf(g, 1.0), 1.3) + 2.0 * maxf(0.0, g - 1.0)
	return [energy, base.lerp(CABLE_HOT, clampf((g - 0.85) / 0.6, 0.0, 1.0))]   # the mode's colour until the burner


const CABLE_F_MAX := 120000.0                 # tension (N) that reads as "at the limit": red
const STRAIN_AMBER := Color(1.0, 0.55, 0.1)
const STRAIN_RED := Color(1.0, 0.12, 0.05)


## The cable's colour for its strain (tension / CABLE_F_MAX) on top of its thrust glow colour:
## the glow below ~0.5, amber by ~0.8, red at the limit.
static func strain_color(glow: Color, strain: float) -> Color:
	if strain < 0.5:
		return glow
	if strain < 0.85:
		return glow.lerp(STRAIN_AMBER, (strain - 0.5) / 0.35)
	return STRAIN_AMBER.lerp(STRAIN_RED, clampf((strain - 0.85) / 0.25, 0.0, 1.0))


## A thin square-section tube along a polyline into an ImmediateMesh already begun (TRIANGLES),
## coloured by vertex: the binder's beam and strands.
static func _beam(im: ImmediateMesh, pts: Array, r: float, col: Color) -> void:
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var d := (b - a).normalized()
		var n1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized() * r
		var n2 := d.cross(n1).normalized() * r
		for q in [[n1, n2], [n2, -n1], [-n1, -n2], [-n2, n1]]:
			var u: Vector3 = q[0]
			var v: Vector3 = q[1]
			for pv in [a + u, b + u, b + v, a + u, b + v, a + v]:
				im.surface_set_color(col)
				im.surface_add_vertex(pv)


## How far ahead and behind (m) to read the surface for pitch: 2 m slow, growing with speed to
## 60 m (from ~3,800 mph). The surface is a 12 m polyline, and at speed a short baseline crosses
## ~150 of its joints a second, each a centimetre step, so the nose twitched (Luke: "going over
## hills makes the camera very shaky"; tests/test_ride.gd).
static func pitch_half(speed: float) -> float:
	return clampf(speed * 0.035, 2.0, 60.0)


const RIDE_TAU := 0.15   # s: the cockpit's pitch and the bank under it, low-passed
const ROLL_TAU := 0.05   # s: the corkscrews' roll under it (eased already; a frame's polish, no lag to speak of)

## The cockpit's ride over the banked track: Vector3(surface height under the pod, pitch, the
## track's bank), smoothed in `st` (an empty Dictionary to start). Pitch reads the surface over
## pitch_half(speed) and eases with RIDE_TAU, the bank too; the height follows the surface up at
## once (never below it: the cockpit can't sink into the road) and eases down over a third of that.
## st.roll: the corkscrews' roll under the pod (the shade line; 0 on the main road), eased over
## ROLL_TAU (onto_road carries the cockpit onto the twisted road with it).
static func ride(v, sim, st: Dictionary, delta: float) -> Vector3:
	var spd: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
	var s: Vector2 = v.surface(sim.pod.x, sim.pod.y)
	var p := slope_pitch(v, sim.pod.x, sim.pod.y, sim.pod.th, pitch_half(spd))
	if sim.kind == "network":   # the climb is the pod's own (the deck lock, the jumps); up a shaft, the shape's
		p = atan2(sim.pod.vz, maxf(spd, 1.0)) if spd > 5.0 else 0.0
		if v.shaft_carry_at(sim.pod.x, sim.pod.y) != Basis.IDENTITY:
			p = 0.0
		elif not sim.pod.off_road and sim.roads[sim.pod.path].deck:
			p = sim.deck_pitch(sim.pod)      # (Mount Hyperion's road: the deck's own pitch, moving or stopped)
	var rr := pod_roll(sim)
	if st.is_empty() or delta <= 0.0:
		st.merge({"h": s.x, "p": p, "b": s.y, "roll": rr}, true)
	else:
		var k := 1.0 - exp(-delta / RIDE_TAU)
		st.h = s.x if sim.kind == "network" else maxf(lerpf(st.h, s.x, minf(1.0, 3.0 * k)), s.x)
		st.p = lerpf(st.p, p, k)
		st.b = lerpf(st.b, s.y, k)
		st.roll = lerpf(st.get("roll", rr), rr, 1.0 - exp(-delta / ROLL_TAU))
	return Vector3(st.h, st.p, st.b)


## The corkscrews' roll of the road under the pod, radians (0 on the main road).
static func pod_roll(sim) -> float:
	if sim.pod.path <= 0 or sim.kind == "network":
		return 0.0
	sim._nearest_on(sim.pod.path, sim.pod.x, sim.pod.y, sim.pod.hint, 40)
	return sim.roll_at(sim.pod.path, sim._n_i + sim._n_t)


## Where sim (x, y) is on the pod's branch road: [the centreline point there (render axes, against
## the floating origin at org), its tangent (interpolated between samples, so a turned-over
## craft's heading doesn't step at the joints: rolled 180 deg, a heading mirrors about the road's),
## the fractional sample].
static func _road_at(sim, x: float, y: float, org_x: float, org_y: float) -> Array:
	var path: int = sim.pod.path
	var B = sim.branches[path - 1]
	sim._nearest_on(path, x, y, sim.pod.hint, 40)
	var i: int = sim._n_i
	var t: float = sim._n_t
	var j := mini(i + 1, B.N - 1)
	var tv := Vector3(lerpf(B.tx[i], B.tx[j], t), 0.0, -lerpf(B.ty[i], B.ty[j], t)).normalized()
	var c := Vector3(B.px[i] + B.tx[i] * B.len[i] * t - org_x, 0.0, -(B.py[i] + B.ty[i] * B.len[i] * t - org_y))
	return [c, tv, i + t]


## The road's frame at sim (x, y) on the pod's road, for the view (the sim is flat): on a branch
## (the shade line), the rigid motion that takes the flat road (the sim's plane at height 0, render
## axes, the floating origin at org) onto the twisted one: a roll about the centreline
## (sim.roll_at, or `roll`) and the corkscrews' climb (sim.branch_height). A point lat m left of
## the centreline and up m off the road lands lat along the rolled road's left and up along its
## up. Identity on the main road.
static func road_xf(sim, x: float, y: float, org_x: float, org_y: float, roll := NAN) -> Transform3D:
	if sim.pod.path <= 0 or sim.kind == "network":
		return Transform3D.IDENTITY
	var at := _road_at(sim, x, y, org_x, org_y)
	var c: Vector3 = at[0]
	var r: float = sim.roll_at(sim.pod.path, at[2]) if is_nan(roll) else roll
	var b := Basis(at[1], -r)
	return Transform3D(b, c + Vector3.UP * sim.branch_height(sim.pod.path, at[2]) - b * c)


## A body's attitude on the pod's road: the road's roll at (x, y), tilted by its climb (rad, nose up).
## Multiply a flat attitude by it.
static func road_attitude(sim, x: float, y: float, climb: float) -> Basis:
	var at := _road_at(sim, x, y, 0.0, 0.0)
	var tv: Vector3 = at[1]
	return Basis(tv.cross(Vector3.UP).normalized(), climb) * Basis(tv, -sim.roll_at(sim.pod.path, at[2]))


## The VR cockpit on the shade line: its rig worked out flat (xf), carried onto the twisted road.
## `anchor` (a flat point of the rig: its floor under the pod) lands exactly where the road puts it,
## so the cockpit rides the road however it's turned; the rig turns with the eased roll (st.roll)
## and tilts with the eased climb (ride's pitch).
static func onto_road(sim, xf: Transform3D, anchor: Vector3, roll: float, climb: float, org_x: float, org_y: float) -> Transform3D:
	var q := road_xf(sim, sim.pod.x, sim.pod.y, org_x, org_y) * anchor
	var at := _road_at(sim, sim.pod.x, sim.pod.y, org_x, org_y)
	var tv: Vector3 = at[1]
	var b := Basis(tv.cross(Vector3.UP).normalized(), climb) * Basis(tv, -roll)
	return Transform3D(b, q - b * anchor) * xf


## How steeply the (banked) surface rises along heading th at (x, y), radians, + = nose up:
## the height `half` metres ahead against `half` behind. 0 on flat tracks.
static func slope_pitch(v, x: float, y: float, th: float, half: float) -> float:
	var c := cos(th)
	var s := sin(th)
	var hf: float = v.surface(x + c * half, y + s * half).x
	var hb: float = v.surface(x - c * half, y - s * half).x
	return atan2(hf - hb, 2.0 * half)


## The tow links and the binder arc. Call after the camera / cockpit rig has moved this frame: the
## pod end rides the rig in VR, and a frame of lag is 30 m at full speed. Each link is rigid parts on
## pins (view/tow_link.gd), placed from the engine's lug and the pod's swivel post as they are drawn:
## its joints turn with the engines' and pod's attitudes, and its rod runs in and out of its barrel
## with the distance between them, which is the sim's span. (Luke: "more mechanical than loose
## swinging cable". They sagged with their slack and twanged at 2.2 Hz; a drawbar does neither.)
## Their lit parts keep the ropes' light: the thrust glow, amber then red with strain.
func sync_cables(sim, delta := 1.0 / 72.0) -> void:
	var pod_basis: Basis = ((pod_frame.transform.basis * pod_frame_pose.basis) if pod_frame else pod.transform.basis).orthonormalized()
	for k in 2:
		var c: Dictionary = sim.cables[k] if k < sim.cables.size() else {}
		var a: Vector3 = engines[k].transform * ENGINE_EYE
		var b := _pod_anchor(sim, k)
		var shown: bool = c.has("ex") and a.distance_to(b) > 0.7
		if shown != _link_shown[k]:      # (told only when it changes: a part hidden by hand, to time the frame without it, stays hidden)
			_link_shown[k] = shown
			for part in link_parts[k]:
				(part as MeshInstance3D).visible = shown
		if not shown:
			continue
		cable_ends[k] = [a, b]
		var at: Dictionary = TowLink.solve(a, engines[k].transform.basis.orthonormalized(), b, pod_basis, link_rod)
		(link_parts[k][0] as MeshInstance3D).transform = at.swivel
		(link_parts[k][1] as MeshInstance3D).transform = at.barrel
		(link_parts[k][2] as MeshInstance3D).transform = at.rod
		(link_parts[k][3] as MeshInstance3D).transform = at.yoke
		link_span[k] = at.span
		link_exposed[k] = at.exposed
		link_angles[k] = at.angles
		link_boot[k] = at.boot      # the boot's folds open and close with the telescope
		link_boots[k].scale = Vector3(1.0, 1.0, link_boot[k] / TowLink.BOOT)
		link_travel[k] = Vector2(c.ex - c.px, c.ey - c.py).length() - sim.P.cableLen
		cable_sag[k] = 0.0
		var f: float = c.get("f", 0.0)
		# colour: its engine's thrust glow, turning amber then red as the tension nears its limit
		var eng = sim.eL if k == 0 else sim.eR
		var thrust: float = 0.0 if held[k] else (shown_thrust[k] if shown_thrust[k] >= 0.0 else eng.thrust)
		var glow := cable_glow(thrust, sim.hblend)
		cable_strain[k] = f / CABLE_F_MAX
		var crackle := 1.0 if thrust < 0.8 else randf_range(0.8, 1.15)
		var energy: float = glow[0] * crackle * energised      # (the start-up: dead until the binder is charged)
		if cable_strain[k] > 0.5:   # strain lights it even off the throttle; past the limit it pulses
			energy = maxf(energy, 1.5 + 2.5 * minf(cable_strain[k], 1.2))
			if cable_strain[k] > 1.0:
				energy *= 1.0 + 0.35 * sin(Time.get_ticks_msec() * 0.03)
		cable_mats[k].emission_energy_multiplier = energy
		cable_mats[k].emission = strain_color(glow[1], cable_strain[k])

	sync_binder(sim, delta)


## The physical emitters are already in model space, including on a stationary mount.
func sync_binder(sim, delta: float) -> void:
	var p0: Vector3 = engines[0].transform * Vector3(ENG_W / 2.0 + 0.1, 0.0, -2.9)
	var p1: Vector3 = engines[1].transform * Vector3(-ENG_W / 2.0 - 0.1, 0.0, -2.9)
	var strain := clampf(absf(sim.binder_stretch) / maxf(sim.P.binderBreak, 0.01), 0.0, 1.0)
	binder_arc.update_arc(p0, p1, strain, sim.binder_broken or energised < 0.35, delta)   # (it strikes a third of the way into its charge)
