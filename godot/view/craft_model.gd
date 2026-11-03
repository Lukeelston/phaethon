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
## Steel cables run from an eye under each engine's tail to two hardpoint eyes on the pod's
## nose, exactly where the sim anchors them (the nose ring, either side of centre); the binder
## arc crackles between the engines. In VR the pod is hidden (you sit in it), so the view hands
## over its cockpit frame (pod_frame), which carries its own nose and eyes. Exhaust plumes are additive shader cones (view/flame.gdshader): faint on dry thrust, long with shock diamonds and a nozzle light on the burner.
##   add_child(model); model.build(view)          once
##   model.sync(sim, inp, delta)                  every frame, after the floating origin moves
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")
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
	[1.80, 0.76, -0.42, 0.15], [2.02, 0.48, -0.31, 0.06], [2.15, 0.18, -0.18, -0.04]]
const HULL_N := 2.6
const PAINT := Color(0.95, 0.42, 0.08)    # the top decks' and nose's candy orange (clear-coated)
const STRIPE := Color(0.11, 0.12, 0.14)   # the flanks' racing stripe: gunmetal
const PIN := Color(0.96, 0.95, 0.9)       # the pinstripes where the paint meets the metal
const PAINT_SY := 0.42                    # paint above this share of the section's half-height
const UNDERGLOW := Color(0.2, 0.75, 1.0)  # the repulsor glow under the pod (the engines' colour)
const OPEN_ZC := 0.15        # cockpit opening: an ellipse in plan around the seat
const OPEN_AZ := 1.15
const OPEN_AX := 0.72
const SKIN := 0.035          # hull thickness (outer skin to inner trim)
const CAGE_Z0 := -0.6        # the nose is an open tube cage from here (the footwell) ...
const CAGE_Z1 := -1.95       # ... to here, where a solid cap carries the cable hardpoints, so
                             # you see the track coming through it (Luke: "a skeleton frame at the
                             # foot hull so that I can see what's coming")
const CAGE_R := 0.02         # hoop radius: covers the skin's cut edges (> SKIN / 2); longerons thinner
static var _hull_cache: ArrayMesh
const FLAP_OPEN := deg_to_rad(68.0)   # full brake
const FLAP_RATE := 9.0                # flap travel, full range per second (~0.11 s open or shut)
# The engines are flat rounded slabs (Luke: "horizontally flat, rounded rectangular prisms"),
# 2.4 m wide (the sim's 1.2 m collision radius) by 0.96 m tall. Air brakes: two flaps on top, two
# underneath, [x, top (+1) or bottom (-1)], hinged at the front edge on the skin.
const ENG_W := 2.4
const ENG_H := 0.96
const FLAPS_AT := [[-0.58, 1.0], [0.58, 1.0], [-0.58, -1.0], [0.58, -1.0]]
const VANE_MAX := 0.45               # vectoring vanes' full deflection, radians
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
var vanes := [[], []]                # per engine: the thrust-vectoring vanes in the nozzle (swing with steering)
var vane_angle := 0.0                # their current deflection, radians (+ = trailing edges right, a right turn)
var strobes: Array[Node3D] = []      # the fin-tip strobes (double flash)
var binder_mats: Array[StandardMaterial3D] = []   # the binder emitters' glowing cores
const FlameShader := preload("res://view/flame.gdshader")
const FLAME_H := 0.62                # the plume's height at the nozzle (2 x 0.62 x scale 0.5)
var flame_mats := [[], []]           # per engine: [outer plume, inner core] ShaderMaterials (view/flame.gdshader)
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
var pod_flap_open := 0.0
var cables: Array[MeshInstance3D] = []
var cable_mats: Array[StandardMaterial3D] = []
var cable_ends := [[Vector3.ZERO, Vector3.ZERO], [Vector3.ZERO, Vector3.ZERO]]   # [engine eye, pod hardpoint] (tests read)
var cable_sag := [0.0, 0.0]          # each cable's current mid-span offset, metres (tests read)
var cable_strain := [0.0, 0.0]       # each cable's tension / CABLE_F_MAX
var _wob := [Vector3.ZERO, Vector3.ZERO]     # each cable's flex: offset of its middle ...
var _wob_v := [Vector3.ZERO, Vector3.ZERO]   # ... and how fast it's moving
var _prev_f := [0.0, 0.0]
var arc: ImmediateMesh
var pod_frame: Node3D = null          # VR: the cockpit rig stands in for the hidden pod
const POD_FRAME_UP := 0.6             # pod mesh centre above the rig floor
const POD_LIFT := 1.3                 # the pod rides this much higher than the sim's body (looks only:
                                      # Luke wanted it "sitting a bit higher up entirely", then "higher than
                                      # the engines just a little bit more - a few feet": 0.4 -> 1.3 m, +3 ft;
                                      # in VR your eye rides up with it, over the engines)
const POD_EYE_H := -0.05              # hardpoint height on the nose, pod-local
const ENGINE_EYE := Vector3(0, -0.95, 3.45)   # engine-local: the eye at the tail of the lug
var _fan_w := [0.0, 0.0]
var bank := [0.0, 0.0, 0.0]          # current lean, radians, + = left side down: eL, eR, pod (VR reads [2])
var _lat := [0.0, 0.0, 0.0]          # smoothed lateral acceleration, g
var roll_rate_peak := 0.0            # fastest pod roll so far, rad/s (tests read and reset it)
var _prev_v := []                    # last frame's [vx, vy] per body


func build(v) -> void:
	view = v
	var sim = v.sim
	var shaded := Kit.vertex_colors()
	var finish := Kit.polished(0.55, 0.38)   # the slabs: satin metal, tinted by vertex colour
	var lit_mat := Kit.vertex_colors(true)
	for k in 2:
		var out := -1.0 if k == 0 else 1.0   # outboard side, engine-local X (eL rides on the left)
		var eng := Node3D.new()
		add_child(eng)
		engines.append(eng)
		var body := MeshInstance3D.new()
		body.mesh = _engine_body(out)
		body.material_override = finish
		eng.add_child(body)
		var lights := MeshInstance3D.new()   # nav, tail, landing lights and the repulsor underglow
		lights.mesh = _engine_lights(out)
		lights.material_override = lit_mat
		lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eng.add_child(lights)
		# hot section: its own material, coloured by heat
		var hot := MeshInstance3D.new()
		hot.mesh = Kit.rounded_box(Vector3(ENG_W - 0.2, ENG_H - 0.16, 2.2), 5.0)
		hot.position.z = 2.9
		var hm := StandardMaterial3D.new()
		hm.albedo_color = STEEL
		hm.emission_enabled = true
		hm.emission = Color.BLACK
		hot.material_override = hm
		eng.add_child(hot)
		hot_mats.append(hm)
		var glow := MeshInstance3D.new()   # the slot nozzle's glow
		glow.mesh = Kit.box(Vector3(ENG_W - 0.5, 0.5, 0.04))
		glow.position.z = 4.02
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.albedo_color = DARK
		glow.material_override = gm
		eng.add_child(glow)
		glow_mats.append(gm)
		# twin intake fans: spinners and eight blades each, one painted so the spin reads
		var fan := Node3D.new()
		fan.position.z = -3.86
		eng.add_child(fan)
		fans.append(fan)
		for fx in [-0.55, 0.55]:
			var rotor := Node3D.new()
			rotor.position.x = fx
			fan.add_child(rotor)
			rotors[k].append(rotor)
			var parts := [[Kit.cyl(0.03, 0.15, 0.24, 12), Kit.at(Vector3(0, 0, -0.08), Vector3(-PI / 2.0, 0, 0)), Color(0.85, 0.85, 0.82)]]
			for b in 8:
				var a := TAU * b / 8.0
				var radial := Vector3(sin(a), cos(a), 0.0)
				parts.append([Kit.box(Vector3(0.1, 0.3, 0.02)),
					Transform3D(Basis(Vector3.BACK, -a) * Basis(Vector3.UP, 0.55), radial * 0.2),
					LIVERY if b == 0 else Color(0.72, 0.74, 0.77)])
			var fm := MeshInstance3D.new()
			fm.mesh = Kit.compound(parts)
			fm.material_override = shaded
			rotor.add_child(fm)
		# split air brakes, two on top and two underneath: hinged at the front edge, the trailing
		# edge swings up (or down) into the airflow
		var flap_mesh := Kit.compound([
			[Kit.rounded_box(Vector3(1.0, 0.05, 1.3), 8.0), Kit.at(Vector3(0, 0.025, 0.65)), STEEL.darkened(0.1)],
			[Kit.box(Vector3(0.92, 0.02, 1.22)), Kit.at(Vector3(0, -0.012, 0.65)), Color(0.85, 0.08, 0.05)],
		])
		for fa in FLAPS_AT:
			var ring := Node3D.new()
			ring.position = Vector3(fa[0], 0.0, FLAP_Z)
			ring.rotation.z = 0.0 if fa[1] > 0.0 else PI
			eng.add_child(ring)
			var hinge := Node3D.new()
			hinge.position.y = ENG_H / 2.0 + 0.01
			ring.add_child(hinge)
			var fl := MeshInstance3D.new()
			fl.mesh = flap_mesh
			fl.material_override = shaded
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
			fp.mesh = Kit.compound([
				[Kit.rounded_box(Vector3(0.05, 0.72, 1.15), 6.0), Kit.at(Vector3(side * 0.025, 0, 0.575)), STEEL.darkened(0.1)],
				[Kit.box(Vector3(0.02, 0.64, 1.07)), Kit.at(Vector3(-side * 0.012, 0, 0.575)), Color(1.0, 0.6, 0.1)],   # amber, facing the engine
			])
			fp.material_override = shaded
			fh.add_child(fp)
			front_flaps[k].append(fh)
		# thrust-vectoring vanes across the nozzle: they swing with the steering
		var vane_mesh := Kit.compound([[Kit.rounded_box(Vector3(0.05, 0.62, 0.46), 6.0), Kit.at(Vector3(0, 0, 0.23)), DARK.lightened(0.3)]])
		for vx in [-0.7, 0.0, 0.7]:
			var vp := Node3D.new()
			vp.position = Vector3(vx, 0.0, 4.02)
			eng.add_child(vp)
			var vm := MeshInstance3D.new()
			vm.mesh = vane_mesh
			vm.material_override = shaded
			vp.add_child(vm)
			vanes[k].append(vp)
		# the fin-tip strobe
		var strobe := MeshInstance3D.new()
		strobe.mesh = Kit.ball(0.08, 10)
		strobe.material_override = view._mat(Color(1.0, 1.0, 1.0), true)
		strobe.position = Vector3(0, 1.5, 1.05)
		strobe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eng.add_child(strobe)
		strobes.append(strobe)
		# the upgraded binder emitter on the inboard face: a ring round a glowing core, facing across
		var em := Node3D.new()
		em.position = Vector3(-out * (ENG_W / 2.0 + 0.04), 0.0, -2.9)
		em.rotation.z = PI / 2.0   # cylinders' axis (Y) across the gap
		eng.add_child(em)
		var ring_m := MeshInstance3D.new()
		ring_m.mesh = Kit.compound([
			[Kit.cyl(0.34, 0.34, 0.08, 24), Kit.at(Vector3.ZERO), DARK.lightened(0.35)],
			[Kit.cyl(0.38, 0.38, 0.03, 24), Kit.at(Vector3(0, -out * 0.03, 0)), LIVERY],
		])
		ring_m.material_override = finish
		em.add_child(ring_m)
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
		# exhaust plume: two additive shader layers (a wide soft plume over a bright core),
		# flattened to the slot nozzle; dry thrust nearly invisible, the burner long with shock
		# diamonds (view/flame.gdshader); a flickering light for the burner
		var flame := Node3D.new()
		flame.position.z = sim.P.engineLen / 2.0
		flame.scale = Vector3(1.55, 0.5, 1.0)   # the outer cone's mouth fills the 1.9 x 0.6 m slot
		eng.add_child(flame)
		flames.append(flame)
		var cone_root := Node3D.new()   # cones hang along -Y; sync turns that to +Z (back) and stretches it
		cone_root.name = "cones"
		flame.add_child(cone_root)
		for layer in 2:
			var cone := MeshInstance3D.new()
			var cm: CylinderMesh = Kit.cyl(0.62, 0.06, 1.0, 24) if layer == 0 else Kit.cyl(0.3, 0.0, 0.75, 16)
			cm.cap_top = false
			cm.cap_bottom = false
			cone.mesh = cm
			cone.position.y = -0.5 if layer == 0 else -0.375
			var fmat := ShaderMaterial.new()
			fmat.shader = FlameShader
			fmat.set_shader_parameter("layer", float(layer))
			fmat.set_shader_parameter("seed", float(k) * 3.7)
			cone.material_override = fmat
			cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cone_root.add_child(cone)
			flame_mats[k].append(fmat)
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(0, -0.2, sim.P.engineLen / 2.0 + 1.2)
		lamp.light_color = Color(1.0, 0.58, 0.25)
		lamp.omni_range = 10.0
		lamp.light_energy = 0.0
		lamp.shadow_enabled = false
		eng.add_child(lamp)
		nozzle_lights.append(lamp)

	pod = MeshInstance3D.new()
	pod.mesh = pod_hull()   # materials live on its surfaces
	add_child(pod)
	canopy = CanopyScript.build()   # windscreen and forcefield (view/canopy.gd)
	pod.add_child(canopy)
	var flap_mat := Kit.polished(0.85, 0.2)
	for s in [-1.0, 1.0]:
		var pflap := Kit.compound([
			[Kit.rounded_box(Vector3(0.05, 0.42, 0.85), 6.0), Kit.at(Vector3(0, 0, 0.43)), SILVER],
			[Kit.rounded_box(Vector3(0.02, 0.36, 0.76), 6.0), Kit.at(Vector3(-0.03 * s, 0, 0.43)), Color(0.85, 0.08, 0.05)],   # red face inboard
		])
		var hinge := Node3D.new()
		hinge.position = Vector3(s * 1.16, -0.28, 0.85)
		pod.add_child(hinge)
		var pm := MeshInstance3D.new()
		pm.mesh = pflap
		pm.material_override = flap_mat
		hinge.add_child(pm)
		pod_flaps.append(hinge)

	for k in 2:
		var c := MeshInstance3D.new()
		c.mesh = ImmediateMesh.new()   # rebuilt each frame along its flexing curve (sync_cables)
		var cm: StandardMaterial3D = view._mat(Color(0.15, 0.16, 0.18))
		cm.emission_enabled = true   # energized: glows with its engine's thrust (cable_glow)
		cm.emission = CABLE_COOL
		cm.emission_energy_multiplier = 0.0
		c.material_override = cm
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(c)
		cables.append(c)
		cable_mats.append(cm)
	arc = ImmediateMesh.new()
	var ami := MeshInstance3D.new()
	ami.mesh = arc
	var am: StandardMaterial3D = view._mat(Color.WHITE, true)
	am.vertex_color_use_as_albedo = true
	ami.material_override = am
	add_child(ami)


## Engine shell, forward -Z, 8 m, a flat rounded slab: intake lip and twin-intake face, nacelle,
## livery band and pinstripe, dorsal fin, outboard stabiliser, binder housing, cable lug and eye;
## plus access covers with rivets, side intake louvres, top exhaust ports, coolant louvres and the
## nozzle's upper and lower lips.
static func _engine_body(out: float) -> ArrayMesh:
	var top := ENG_H / 2.0
	var side := ENG_W / 2.0
	var parts := [
		[Kit.rounded_box(Vector3(ENG_W, ENG_H, 6.0), 5.0), Kit.at(Vector3(0, 0, -0.55)), STEEL],                  # nacelle
		[Kit.rounded_box(Vector3(ENG_W + 0.1, ENG_H + 0.1, 0.45), 6.0), Kit.at(Vector3(0, 0, -3.6)), DARK.lightened(0.15)],   # intake lip
		[Kit.box(Vector3(ENG_W - 0.3, ENG_H - 0.22, 0.04)), Kit.at(Vector3(0, 0, -3.84)), Color(0.05, 0.05, 0.06)],   # intake throat
		[Kit.box(Vector3(0.08, ENG_H - 0.22, 0.06)), Kit.at(Vector3(0, 0, -3.85)), DARK.lightened(0.3)],         # splitter between the twin intakes
		[Kit.rounded_box(Vector3(ENG_W + 0.06, ENG_H + 0.06, 0.6), 6.0), Kit.at(Vector3(0, 0, -2.5)), LIVERY],    # band
		[Kit.rounded_box(Vector3(ENG_W + 0.04, ENG_H + 0.04, 0.25), 6.0), Kit.at(Vector3(0, 0, 0.6)), LIVERY],    # pinstripe
		[Kit.box(Vector3(0.09, 1.05, 1.7)), Kit.at(Vector3(0, top + 0.47, 0.2), Vector3(-0.35, 0, 0)), STEEL],    # dorsal fin
		[Kit.box(Vector3(0.06, 0.2, 1.5)), Kit.at(Vector3(0, top + 0.92, 0.42), Vector3(-0.35, 0, 0)), LIVERY],
		[Kit.rounded_box(Vector3(1.1, 0.07, 1.3), 6.0), Kit.at(Vector3(out * (side + 0.5), -0.1, 0.5), Vector3(0, 0, -out * 0.12)), STEEL],   # outboard stabiliser
		[Kit.rounded_box(Vector3(0.18, 0.72, 1.1), 5.0), Kit.at(Vector3(-out * (side - 0.02), 0.0, -2.9)), DARK.lightened(0.25)],   # binder housing
		[Kit.box(Vector3(0.3, 0.5, 0.7)), Kit.at(Vector3(0, -0.66, 3.0)), DARK.lightened(0.25)],                  # cable lug pylon
		[Kit.cyl(0.11, 0.11, 0.08, 10), Kit.at(Vector3(0, -0.95, 3.4), Vector3(0, 0, PI / 2.0)), Color(0.75, 0.77, 0.8)],   # cable eye
		[Kit.box(Vector3(ENG_W - 0.2, 0.06, 0.4)), Kit.at(Vector3(0, 0.36, 4.0)), DARK.lightened(0.2)],          # nozzle lips
		[Kit.box(Vector3(ENG_W - 0.2, 0.06, 0.4)), Kit.at(Vector3(0, -0.36, 4.0)), DARK.lightened(0.2)],
	]
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
	return Kit.compound(parts)


## The engine's lights (unshaded, so they read at any distance): a nav light at the stabiliser's
## tip (red on the left engine, green on the right), a red tail light, two landing lights under
## the intake lip, and a cyan repulsor underglow along the belly.
static func _engine_lights(out: float) -> ArrayMesh:
	var nav := NAV_L if out < 0.0 else NAV_R
	return Kit.compound([
		[Kit.ball(0.1, 10), Kit.at(Vector3(out * (ENG_W / 2.0 + 1.06), -0.04, 0.5)), nav],
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


static func _in_opening(x: float, z: float) -> bool:
	return pow(x / OPEN_AX, 2.0) + pow((z - OPEN_ZC) / OPEN_AZ, 2.0) < 1.0


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
	var in_open: bool = p.y > h[1] and pow(p.x / (OPEN_AX - margin), 2.0) + pow((p.z - OPEN_ZC) / (OPEN_AZ - margin), 2.0) < 1.0
	if not inside and not in_open:
		return "through the skin"
	for k in 192:
		var ph := TAU * k / 192.0
		var x := OPEN_AX * cos(ph)
		var z := OPEN_ZC + OPEN_AZ * sin(ph)
		if p.distance_to(Vector3(x, hull_top(x, z), z)) < LIP_R + margin:
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
static func pod_hull() -> ArrayMesh:
	if _hull_cache:
		return _hull_cache
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
	_outer_skin(grid, nz, na, mesh, paint, pins)   # surface 0
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
				if cen.z > CAGE_Z1 and cen.z < CAGE_Z0:
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
	var trim := StandardMaterial3D.new()
	trim.vertex_color_use_as_albedo = true
	trim.vertex_color_is_srgb = true
	trim.roughness = 0.85
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
		var ph := TAU * k / nl
		var x := OPEN_AX * cos(ph)
		var z := OPEN_ZC + OPEN_AZ * sin(ph)
		ring_pts.append(Vector3(x, hull_top(x, z), z))
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
	_tube(pins, crest, 0.007, PAINT, 6)
	var rubber := StandardMaterial3D.new()
	rubber.vertex_color_use_as_albedo = true
	rubber.vertex_color_is_srgb = true
	rubber.roughness = 0.62
	mesh.surface_set_material(2, rubber)

	# fittings
	Kit.compound([
		[Kit.rounded_box(Vector3(0.07, 0.62, 0.85), 4.0), Kit.at(Vector3(0, 0.42, 1.6), Vector3(-0.35, 0, 0)), PAINT],   # raked fin, painted
		[Kit.rounded_box(Vector3(0.076, 0.6, 0.09), 4.0), _fin_xf() * Transform3D(Basis(), Vector3(0, 0, -0.39)), DARK.lightened(0.15)],   # its leading edge
		[Kit.rounded_box(Vector3(0.078, 0.035, 0.66), 4.0), _fin_xf() * Transform3D(Basis(), Vector3(0, 0.2, 0.03)), PIN],   # a pinstripe along its top
		[Kit.rounded_box(Vector3(0.1, 0.2, 0.72), 4.0), Kit.at(Vector3(-1.1, -0.26, -0.15)), DARK],   # side intakes, behind the cage
		[Kit.rounded_box(Vector3(0.1, 0.2, 0.72), 4.0), Kit.at(Vector3(1.1, -0.26, -0.15)), DARK],
		[Kit.cyl(0.15, 0.19, 0.36, 28), Kit.at(Vector3(-0.5, -0.24, 2.1), Vector3(PI / 2.0, 0, 0)), DARK],   # trim thrusters
		[Kit.cyl(0.15, 0.19, 0.36, 28), Kit.at(Vector3(0.5, -0.24, 2.1), Vector3(PI / 2.0, 0, 0)), DARK],
		[Kit.cyl(0.168, 0.168, 0.035, 32), Kit.at(Vector3(-0.5, -0.24, 2.262), Vector3(PI / 2.0, 0, 0)), SILVER],   # their polished collars
		[Kit.cyl(0.168, 0.168, 0.035, 32), Kit.at(Vector3(0.5, -0.24, 2.262), Vector3(PI / 2.0, 0, 0)), SILVER],
		[Kit.cyl(0.025, 0.1, 0.12, 24), Kit.at(Vector3(-0.5, -0.24, 2.33), Vector3(PI / 2.0, 0, 0)), DARK.lightened(0.3)],   # and exhaust cones
		[Kit.cyl(0.025, 0.1, 0.12, 24), Kit.at(Vector3(0.5, -0.24, 2.33), Vector3(PI / 2.0, 0, 0)), DARK.lightened(0.3)],
		[Kit.cyl(0.035, 0.035, 0.56, 10), Kit.at(Vector3(0, -0.05, -2.06), Vector3(0, 0, PI / 2.0)), DARK.lightened(0.2)],   # nose ring bar
		[Kit.cyl(0.07, 0.07, 0.06, 14), Kit.at(Vector3(-0.18, -0.05, -2.1), Vector3(0, 0, PI / 2.0)), Color(0.75, 0.77, 0.8)],   # hardpoint eyes
		[Kit.cyl(0.07, 0.07, 0.06, 14), Kit.at(Vector3(0.18, -0.05, -2.1), Vector3(0, 0, PI / 2.0)), Color(0.75, 0.77, 0.8)],
	], mesh)
	mesh.surface_set_material(3, Kit.polished(0.6, 0.28))

	# the cage: hoops round the section and longerons along it, on the skin's mid-line, the
	# first and last hoops right on the cut edges. Nothing crosses the cockpit opening.
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
			var p := cage_point(z, TAU * j / 96.0)
			if p.y > hull_section(z)[1] and _in_opening(p.x, z):
				if run.size() > 1:
					_tube(cage, run, CAGE_R, SILVER)
				run = []
			else:
				run.append(p)
		if run.size() > 1:
			_tube(cage, run, CAGE_R, SILVER)
	for k in range(1, 10):   # longerons, the bottom keel among them; no top spine, so the
		var th := PI / 2.0 + TAU * k / 10.0   # middle of the view ahead stays clear
		var run: Array = []
		for m in 41:
			var z := lerpf(za, zb, float(m) / 40.0)
			var p := cage_point(z, th)
			if p.y > hull_section(z)[1] and _in_opening(p.x, z):
				if run.size() > 1:
					_tube(cage, run, CAGE_R * 0.8, SILVER)
				run = []
			else:
				run.append(p)
		if run.size() > 1:
			_tube(cage, run, CAGE_R * 0.8, SILVER)
	cage.commit(mesh)
	mesh.surface_set_material(4, Kit.polished(1.0, 0.18))
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
	pins.commit(mesh)
	mesh.surface_set_material(6, Kit.polished(0.3, 0.22))
	# lamps (unshaded, as the engines'): nav lights at the widest point (red left, green right),
	# tail lamps on the thrusters, the fin's tip lamp, the repulsor underglow
	Kit.compound([
		[Kit.ball(0.035, 10), Kit.at(Vector3(-1.155, -0.31, -0.3)), NAV_L],
		[Kit.ball(0.035, 10), Kit.at(Vector3(1.155, -0.31, -0.3)), NAV_R],
		[Kit.box(Vector3(0.11, 0.022, 0.07)), Kit.at(Vector3(-0.5, -0.07, 2.2)), Color(1.0, 0.1, 0.08)],
		[Kit.box(Vector3(0.11, 0.022, 0.07)), Kit.at(Vector3(0.5, -0.07, 2.2)), Color(1.0, 0.1, 0.08)],
		[Kit.ball(0.03, 10), _fin_xf() * Transform3D(Basis(), Vector3(0, 0.3, 0.38)), Color(1.0, 1.0, 1.0)],
		[Kit.box(Vector3(0.035, 0.01, 1.5)), Kit.at(Vector3(-0.5, -0.59, 0.3)), UNDERGLOW],
		[Kit.box(Vector3(0.035, 0.01, 1.5)), Kit.at(Vector3(0.5, -0.59, 0.3)), UNDERGLOW],
	], mesh)
	mesh.surface_set_material(7, Kit.vertex_colors(true))
	_hull_cache = mesh
	return mesh


## The outer skin (surface 0, polished metal) and its paint (into `paint`: the top decks and the
## nose candy orange, a gunmetal stripe down each flank), smooth normals across both so the seams
## don't show in the shading; a pinstripe (into `pins`) along each edge of the top decks' paint.
static func _outer_skin(grid: Array, nz: int, na: int, mesh: ArrayMesh, paint: SurfaceTool, pins: SurfaceTool) -> void:
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
			if cen.z > CAGE_Z1 and cen.z < CAGE_Z0:
				continue   # the open cage
			var ha: float = (grid[i][j][2] + grid[i + 1][j][2]) / 2.0
			var hb: float = (grid[i][j][3] + grid[i + 1][j][3]) / 2.0
			var col = _paint_at(absf(cen.x) / ha, (cen.y - cc) / hb, cen.z)
			var outward := Vector3(cen.x, cen.y - cc, 0.0)
			faces.append([a, b, c, outward, col])
			faces.append([b, d, c, outward, col])
	for e in 2:   # end caps: fans to a point just beyond each end (the nose's painted)
		var ri := 0 if e == 0 else nz
		var ti := pts.size()
		pts.append(Vector3(0.0, grid[ri][0][1], z0 - 0.02 if e == 0 else z1 + 0.02))
		var axis := Vector3(0, 0, -1.0 if e == 0 else 1.0)
		for j in na:
			faces.append([ri * na + j, ri * na + (j + 1) % na, ti, axis, PAINT if e == 0 else null])
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
		st.set_color(SILVER)
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
			if p.z < CAGE_Z0 + 0.02:
				continue
			run.append(p + nrm[i * na + jj] * 0.005)
		if run.size() > 1:
			_tube(pins, run, 0.008, PIN, 6)


## The paint at a skin quad: |x| over the half-width, height over the half-height (from the
## section's centre), station z. Null where it's bare metal.
static func _paint_at(ax: float, sy: float, z: float):
	if z < -1.98 or sy > PAINT_SY:
		return PAINT
	if ax > 0.7 and sy > -0.2 and sy < 0.22:
		return STRIPE
	return null


## A point on the skin's mid-line at station z, angle th round the section.
static func cage_point(z: float, th: float) -> Vector3:
	var h := hull_section(z)
	return Vector3((h[0] - SKIN / 2.0) * Kit._sp(cos(th), 2.0 / HULL_N), h[1] + (h[2] - SKIN / 2.0) * Kit._sp(sin(th), 2.0 / HULL_N), z)


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
	if _prev_v.is_empty() or delta <= 0.0:
		_prev_v = [[all[0].vx, all[0].vy], [all[1].vx, all[1].vy], [all[2].vx, all[2].vy]]
		return
	for k in 3:
		var b = all[k]
		var ax: float = (b.vx - _prev_v[k][0]) / delta
		var ay: float = (b.vy - _prev_v[k][1]) / delta
		_prev_v[k] = [b.vx, b.vy]
		var lat_g: float = (-sin(b.th) * ax + cos(b.th) * ay) / 9.81
		if sim.kind == "network" and not b.off_road and sim.roads[b.path].shaft:   # a shaft's bulb carries you: not a turn you lean into
			lat_g -= sim.roads[b.path].kap[b.hint] * (b.vx * b.vx + b.vy * b.vy) / 9.81
		if absf(lat_g) > 150.0 or sim.crash_t > 0.0:   # respawn / crash: not a turn
			lat_g = 0.0
		lat_g *= b.grip   # airborne: nothing to lean against
		var was: float = bank[k]
		var e := ease_bank(bank[k], _lat[k], lat_g, delta)
		bank[k] = e[0]
		_lat[k] = e[1]
		if k == 2:
			roll_rate_peak = maxf(roll_rate_peak, absf(bank[k] - was) / delta)


func sync(sim, inp: Dictionary, delta: float) -> void:
	_update_bank(sim, delta)
	var bodies := [sim.eL, sim.eR]
	var brakes := [inp.brkL, inp.brkR]   # each engine's flaps answer to its own brake
	for k in 2:
		var e = bodies[k]
		var eng := engines[k]
		eng.position = view.wz(e.x, e.y, e.z + 0.1)
		var vh: float = sqrt(e.vx * e.vx + e.vy * e.vy)
		var pitch: float = atan2(e.vz, maxf(vh, 1.0)) if vh > 5.0 else 0.0
		# nose follows the banking's rise and fall (on the Network the climb is in the body's own vz:
		# the deck lock, the jumps)
		var climb := 0.0 if sim.kind == "network" else slope_pitch(view, e.x, e.y, e.th, maxf(4.0, pitch_half(vh)))
		var lean := clampf(bank[k] + view.surface(e.x, e.y).y, -ROLL_MAX, ROLL_MAX)   # lean, plus the track's banking
		var Qe: Basis = view.shaft_carry_at(e.x, e.y) if sim.kind == "network" else Basis.IDENTITY
		if not Qe.is_equal_approx(Basis.IDENTITY):   # up a shaft: flat, carried onto its shape (its climb is the shape's)
			eng.basis = Qe * Basis.from_euler(Vector3(0.0, e.th - PI / 2.0, lean))
		elif sim.pod.path > 0 and sim.kind != "network":   # the shade line: flat, carried onto the twisted road
			eng.basis = road_attitude(sim, e.x, e.y, climb) * Basis.from_euler(Vector3(pitch, e.th - PI / 2.0, lean))
		else:
			eng.rotation = Vector3(pitch + climb, e.th - PI / 2.0, lean)
		var h: float = e.heat
		var col := Color(0.25, 0.25, 0.25) if e.flameout else heat_color(h)
		hot_mats[k].albedo_color = col
		hot_mats[k].emission = Color.BLACK if e.flameout else col * smoothstep(0.35, 1.0, h) * 1.4
		var t: float = 0.0 if e.flameout else minf(e.thrust, 1.0)
		glow_mats[k].albedo_color = DARK.lerp(HOT, minf(1.0, t * 1.5)).lerp(WHITE, maxf(0.0, t - 0.6) * 1.5)
		# fan: spins up with thrust, winds down on a flameout; capped below where it would strobe
		var w_target := 0.0 if e.flameout else 3.0 + 16.0 * t
		_fan_w[k] = lerpf(_fan_w[k], w_target, 1.0 - exp(-delta * 2.0))
		for r in 2:   # the twin rotors counter-rotate
			var rotor: Node3D = rotors[k][r]
			rotor.rotation.z = fposmod(rotor.rotation.z + _fan_w[k] * delta * (1.0 if r == 0 else -1.0), TAU)
		# air brakes
		flap_open[k] = move_toward(flap_open[k], clampf(brakes[k], 0.0, 1.0), FLAP_RATE * delta)
		for hinge in flaps[k]:
			(hinge as Node3D).rotation.x = -FLAP_OPEN * flap_open[k]
		front_open[k] = move_toward(front_open[k], clampf(float(e.front), 0.0, 1.0), FLAP_RATE * delta)
		for fh in front_flaps[k]:
			(fh as Node3D).rotation.y = FRONT_OPEN * front_open[k] * float(fh.get_meta("side"))
		# vectoring vanes: trailing edges swing to the side the craft is turning (a right turn
		# is the left engine harder), like rudders; both engines' together
		if k == 0:
			var split: float = clampf(sim.eL.thrust - sim.eR.thrust, -1.0, 1.0)
			vane_angle = lerpf(vane_angle, clampf(split * 1.2, -1.0, 1.0) * VANE_MAX, 1.0 - exp(-delta * 8.0))
		for vp in vanes[k]:
			(vp as Node3D).rotation.y = vane_angle
		# the fin strobe: a double flash every 1.2 s, the two engines a beat apart
		var ph := fposmod(Time.get_ticks_msec() / 1000.0 + 0.6 * k, 1.2)
		strobes[k].visible = ph < 0.05 or (ph > 0.14 and ph < 0.19)
		# binder emitters: a living glow, hotter and toward violet as the binder strains
		var strain := clampf(absf(sim.binder_stretch) / maxf(sim.P.binderBreak, 0.01), 0.0, 1.0)
		var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.012 + k)
		binder_mats[k].albedo_color = BINDER_COL.lerp(Color(0.8, 0.45, 1.0), strain) * (0.7 + 0.5 * pulse)
		# flame
		var flame := flames[k]
		var burning: bool = not e.flameout and e.thrust > 0.02
		flame.visible = burning
		var fade := 1.0 - exp(-delta * 6.0)   # the burner lights and dies over ~0.2 s, not in a frame
		_burn[k] = lerpf(_burn[k], 1.0 if burning and sim.mode != "normal" else 0.0, fade)
		_ram[k] = lerpf(_ram[k], 1.0 if burning and sim.mode == "ramjet" else 0.0, fade)
		var lamp: OmniLight3D = nozzle_lights[k]
		lamp.light_energy = _burn[k] * (2.2 + 0.8 * sin(Time.get_ticks_msec() * 0.031 + k * 2.0)) * minf(e.thrust, 1.2) if burning else 0.0
		if burning:
			# the plume's length: a short cone on dry thrust (the shader shows only its near part),
			# a long one on the burner, longer still on the ramjet
			var flame_len: float = lerpf(1.5 + 2.0 * e.thrust, 4.0 + 8.0 * e.thrust, _burn[k]) * (1.0 + 0.3 * _ram[k])
			var cones: Node3D = flame.get_node("cones")
			cones.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0) * Basis.from_scale(Vector3(1, flame_len, 1)), Vector3.ZERO)
			for fmat in flame_mats[k]:
				(fmat as ShaderMaterial).set_shader_parameter("thrust", e.thrust)
				(fmat as ShaderMaterial).set_shader_parameter("burner", _burn[k])
				(fmat as ShaderMaterial).set_shader_parameter("ramjet", _ram[k])
				(fmat as ShaderMaterial).set_shader_parameter("aspect", flame_len / FLAME_H)

	CanopyScript.update(canopy, sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy), sim.hblend, sim.mode, delta)
	pod.position = view.wz(sim.pod.x, sim.pod.y, sim.pod.z - 0.2 + POD_LIFT)
	var pvh: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
	var pclimb := (atan2(sim.pod.vz, maxf(pvh, 1.0)) if pvh > 5.0 else 0.0) if sim.kind == "network" else slope_pitch(view, sim.pod.x, sim.pod.y, sim.pod.th, pitch_half(pvh))
	var plean := clampf(bank[2] + view.surface(sim.pod.x, sim.pod.y).y, -ROLL_MAX, ROLL_MAX)
	var Qp: Basis = view.shaft_carry_at(sim.pod.x, sim.pod.y) if sim.kind == "network" else Basis.IDENTITY
	if not Qp.is_equal_approx(Basis.IDENTITY):
		pod.basis = Qp * Basis.from_euler(Vector3(0.0, sim.pod.th - PI / 2.0, plean))
	elif sim.pod.path > 0 and sim.kind != "network":
		pod.basis = road_attitude(sim, sim.pod.x, sim.pod.y, pclimb) * Basis.from_euler(Vector3(0.0, sim.pod.th - PI / 2.0, plean))
	else:
		pod.rotation = Vector3(pclimb, sim.pod.th - PI / 2.0, plean)
	pod_flap_open = move_toward(pod_flap_open, clampf(minf(inp.brkL, inp.brkR), 0.0, 1.0), FLAP_RATE * delta)
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		pod_flaps[i].rotation.y = s * FLAP_OPEN * 0.8 * pod_flap_open   # trailing edge swings out


## Where cable k hooks to the drawn pod: the sim's nose-ring anchor (podLen/2 ahead, podAnchorW
## of the half-width to that side; eL's cable on the left), from the pod's CURRENT pose. Not the
## sim's cables[k].px/py: those are taken mid-step, before integration, so they trail the pod
## by a step (half a metre at 500 mph, metres flat out). Out through the banked pod, or the VR
## cockpit frame standing in for it.
func _pod_anchor(sim, k: int) -> Vector3:
	var left: float = (1.0 if k == 0 else -1.0) * sim.P.podAnchorW * sim.P.podWidth / 2.0
	var local := Vector3(-left, POD_EYE_H, -sim.P.podLen / 2.0 - 0.1)   # onto the eye, just ahead of the nose
	if pod_frame:
		return pod_frame.transform * (local + Vector3(0, POD_FRAME_UP, 0))
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


const CABLE_R := 0.035
const CABLE_F_MAX := 120000.0                 # tension (N) that reads as "at the limit": red
const STRAIN_AMBER := Color(1.0, 0.55, 0.1)
const STRAIN_RED := Color(1.0, 0.12, 0.05)
const FLEX_HZ := 2.2                          # the cables' sway: a lightly damped twang ...
const FLEX_ZETA := 0.18


## A round tube from a to b along the quadratic curve through control point m, into `im`.
static func _tube_curve(im: ImmediateMesh, a: Vector3, b: Vector3, m: Vector3) -> void:
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 14
	var sides := 6
	var pts := []
	for i in segs + 1:
		var t := float(i) / segs
		pts.append(a * (1.0 - t) * (1.0 - t) + m * 2.0 * (1.0 - t) * t + b * t * t)
	var rings := []
	var nrm := Vector3.ZERO
	for i in segs + 1:
		var tg: Vector3 = ((pts[mini(i + 1, segs)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		if i == 0:
			nrm = tg.cross(Vector3.UP)
			if nrm.length() < 0.1:
				nrm = tg.cross(Vector3.RIGHT)
		nrm = (nrm - tg * nrm.dot(tg)).normalized()
		var bn := tg.cross(nrm)
		var ring := []
		for k in sides:
			var ang := TAU * k / sides
			ring.append(nrm * cos(ang) + bn * sin(ang))
		rings.append(ring)
	for i in segs:
		for k in sides:
			var k2 := (k + 1) % sides
			for q in [[i, k], [i + 1, k], [i + 1, k2], [i, k], [i + 1, k2], [i, k2]]:
				var r: Vector3 = rings[q[0]][q[1]]
				im.surface_set_normal(r)
				im.surface_add_vertex((pts[q[0]] as Vector3) + r * CABLE_R)
	im.surface_end()


## Rope sag (m) at the middle of a cable of rest length `rest` hung across `span` (parabola).
static func cable_sag_for(span: float, rest: float) -> float:
	var slack := maxf(0.0, rest - span)
	return minf(3.0, sqrt(3.0 * maxf(span, 1.0) * slack / 8.0)) + 0.05


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


## Cables and the binder arc. Call after the camera / cockpit rig has moved this frame: the
## pod end rides the rig in VR, and a frame of lag is 30 m at full speed. Each cable is a tube
## along a curve (Luke: "add flex and color to the cables"): it sags with its slack, sways and
## twangs when its tension jumps, and shifts from its thrust glow to amber then red with strain.
func sync_cables(sim, delta := 1.0 / 72.0) -> void:
	var dt := clampf(delta, 0.001, 0.05)
	for k in 2:
		var c: Dictionary = sim.cables[k] if k < sim.cables.size() else {}
		cables[k].visible = c.has("ex")
		if not cables[k].visible:
			continue
		var a: Vector3 = engines[k].transform * ENGINE_EYE
		var b := _pod_anchor(sim, k)
		var d := b - a
		var span := d.length()
		if span < 0.01:
			cables[k].visible = false
			continue
		var yb := d / span
		cable_ends[k] = [a, b]
		# flex: hang toward the ground by the rope's sag, sway about it like a plucked string
		var sim_span: float = Vector2(c.ex - c.px, c.ey - c.py).length()
		var target := Vector3.DOWN * cable_sag_for(sim_span, sim.P.cableLen)
		var f: float = c.get("f", 0.0)
		var side := yb.cross(Vector3.UP).normalized()
		_wob_v[k] += side * clampf((f - _prev_f[k]) / CABLE_F_MAX, -1.0, 1.0) * 1.6   # a tension jump twangs it
		_prev_f[k] = f
		var w := TAU * FLEX_HZ
		_wob_v[k] += ((target - _wob[k]) * w * w - _wob_v[k] * 2.0 * FLEX_ZETA * w) * dt
		_wob[k] += _wob_v[k] * dt
		_wob[k] = _wob[k] - yb * _wob[k].dot(yb)   # sideways and down only, never along the cable
		if _wob[k].length() > span * 0.25:
			_wob[k] = _wob[k].normalized() * span * 0.25
		cable_sag[k] = _wob[k].length()
		_tube_curve(cables[k].mesh as ImmediateMesh, a, b, (a + b) / 2.0 + _wob[k] * 2.0)
		cable_mats[k].albedo_color = Color(0.4, 0.4, 0.42) if c.slack else Color(0.15, 0.16, 0.18)
		# colour: its engine's thrust glow, turning amber then red as the tension nears its limit
		var eng = sim.eL if k == 0 else sim.eR
		var glow := cable_glow(eng.thrust, sim.hblend)
		cable_strain[k] = f / CABLE_F_MAX
		var crackle := 1.0 if eng.thrust < 0.8 else randf_range(0.8, 1.15)
		var energy: float = glow[0] * crackle
		if cable_strain[k] > 0.5:   # strain lights it even off the throttle; past the limit it pulses
			energy = maxf(energy, 1.5 + 2.5 * minf(cable_strain[k], 1.2))
			if cable_strain[k] > 1.0:
				energy *= 1.0 + 0.35 * sin(Time.get_ticks_msec() * 0.03)
		cable_mats[k].emission_energy_multiplier = energy
		cable_mats[k].emission = strain_color(glow[1], cable_strain[k])

	arc.clear_surfaces()
	if sim.binder_broken:
		return
	# the upgraded binder: a bright core beam between the emitters and three crackling strands
	# round it, drawn as thin tubes; toward violet as the binder strains
	var p0: Vector3 = engines[0].transform * Vector3(ENG_W / 2.0 + 0.1, 0.0, -2.9)
	var p1: Vector3 = engines[1].transform * Vector3(-ENG_W / 2.0 - 0.1, 0.0, -2.9)
	var strain := clampf(absf(sim.binder_stretch) / maxf(sim.P.binderBreak, 0.01), 0.0, 1.0)
	var hue := BINDER_COL.lerp(Color(0.8, 0.45, 1.0), strain)
	arc.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_beam(arc, [p0, p1], 0.045, Color(0.85, 0.97, 1.0))
	var axis := (p1 - p0).normalized()
	var up := axis.cross(Vector3.FORWARD).normalized()
	if up.length() < 0.1:
		up = Vector3.UP
	var side := axis.cross(up)
	for strand in 3:
		var pts := [p0]
		for sgm in range(1, 10):
			var t := sgm / 10.0
			var amp := sin(t * PI) * 0.35
			pts.append(p0.lerp(p1, t) + up * randf_range(-amp, amp) + side * randf_range(-amp, amp))
		pts.append(p1)
		_beam(arc, pts, 0.018, hue.lerp(Color.WHITE, 0.25 * strand))
	arc.surface_end()
