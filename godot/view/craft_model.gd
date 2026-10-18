## What the podracer looks like. Two engines: intake lip and a fan that spins up with thrust,
## a nacelle in livery, a hot section that glows with heat (the old whole-engine heat colours,
## now where the heat is), fins, and four split air-brake flaps, red inside, around the hot
## section. Each engine's flaps follow that engine's own brake. The pod: one smooth lofted
## hull in polished metal with orange metallic speed stripes (pod_hull(): rounded-box sections
## swelling through the cockpit, a rounded nose, a headrest fairing; an open cockpit with a
## rubber lip; matte trim inside), a raked fin, side intakes, trim thrusters, the cable
## hardpoints on the nose, and two rounded flaps that follow the pod's brake, which (as in
## the sim) is the lesser of the two. The VR cockpit sits inside the same hull.
## Engines and pod list into turns like aircraft: each banks by its own lateral g (smoothed,
## easing toward BANK_MAX, roll rate capped so it builds rather than snaps), and the VR cockpit
## rolls with the pod. Visual only: the sim is flat.
## Steel cables run from an eye under each engine's tail to two hardpoint eyes on the pod's
## nose, exactly where the sim anchors them (the nose ring, either side of centre); the binder
## arc crackles between the engines. In VR the pod is hidden (you sit in it), so the view hands
## over its cockpit frame (pod_frame), which carries its own nose and eyes. Flames get a white core and, on afterburner or ramjet, shock diamonds.
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
const FLAP_ANGLES := [PI / 4.0, 3.0 * PI / 4.0, 5.0 * PI / 4.0, 7.0 * PI / 4.0]   # an X: clear of the fins
const FLAP_Z := 1.4                   # hinge station, engine-local (forward is -Z)
const BANK_MAX := deg_to_rad(62.0)    # the lean eases toward this in the hardest turns
const BANK_G := 12.0                  # lateral g that gives ~76% of BANK_MAX (tanh knee)
const BANK_TAU := 0.4                 # lateral-g smoothing, s: the lean eases in ...
const BANK_RATE := deg_to_rad(55.0)   # ... and never rolls faster than this (Luke: "some sort of ramp to the roll")
const ROLL_MAX := deg_to_rad(70.0)    # lean plus the track's banking never rolls you past this

var view
var engines: Array[Node3D] = []
var hot_mats: Array[StandardMaterial3D] = []
var glow_mats: Array[StandardMaterial3D] = []
var fans: Array[Node3D] = []
var flaps := [[], []]                 # per engine: its four hinge nodes
var flap_open := [0.0, 0.0]           # per engine: current opening 0..1 (tests read this)
var flames: Array[Node3D] = []
var diamonds := [[], []]
var pod: MeshInstance3D
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
const POD_LIFT := 0.4                 # the pod rides this much higher than the sim's body (looks only:
                                      # Luke wanted it "sitting a bit higher up entirely")
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
	for k in 2:
		var out := -1.0 if k == 0 else 1.0   # outboard side, engine-local X (eL rides on the left)
		var eng := Node3D.new()
		add_child(eng)
		engines.append(eng)
		var body := MeshInstance3D.new()
		body.mesh = _engine_body(out)
		body.material_override = shaded
		eng.add_child(body)
		# hot section: its own material, coloured by heat
		var hot := MeshInstance3D.new()
		hot.mesh = Kit.cyl(0.6, 0.8, 2.5, 20)
		hot.rotation.x = PI / 2.0   # +Y (narrow end) to the back
		hot.position.z = 2.75
		var hm := StandardMaterial3D.new()
		hm.albedo_color = STEEL
		hm.emission_enabled = true
		hm.emission = Color.BLACK
		hot.material_override = hm
		eng.add_child(hot)
		hot_mats.append(hm)
		var glow := MeshInstance3D.new()
		glow.mesh = Kit.cyl(0.5, 0.5, 0.04, 20)
		glow.rotation.x = PI / 2.0
		glow.position.z = 4.0
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.albedo_color = DARK
		glow.material_override = gm
		eng.add_child(glow)
		glow_mats.append(gm)
		# intake fan: spinner and eight blades, one painted so the spin reads
		var fan := Node3D.new()
		fan.position.z = -3.55
		eng.add_child(fan)
		fans.append(fan)
		var parts := [[Kit.cyl(0.04, 0.26, 0.4, 12), Kit.at(Vector3(0, 0, -0.15), Vector3(-PI / 2.0, 0, 0)), Color(0.85, 0.85, 0.82)]]
		for b in 8:
			var a := TAU * b / 8.0
			var radial := Vector3(sin(a), cos(a), 0.0)
			parts.append([Kit.box(Vector3(0.16, 0.56, 0.03)),
				Transform3D(Basis(Vector3.BACK, -a) * Basis(Vector3.UP, 0.55), radial * 0.5),
				LIVERY if b == 0 else Color(0.72, 0.74, 0.77)])
		var fm := MeshInstance3D.new()
		fm.mesh = Kit.compound(parts)
		fm.material_override = shaded
		fan.add_child(fm)
		# split air brakes: hinge at the front edge, trailing edge swings out into the airflow
		var flap_mesh := Kit.compound([
			[Kit.box(Vector3(0.62, 0.05, 1.3)), Kit.at(Vector3(0, 0.025, 0.65)), STEEL.darkened(0.1)],
			[Kit.box(Vector3(0.56, 0.02, 1.22)), Kit.at(Vector3(0, -0.012, 0.65)), Color(0.85, 0.08, 0.05)],
		])
		for a in FLAP_ANGLES:
			var ring := Node3D.new()
			ring.position.z = FLAP_Z
			ring.rotation.z = a
			eng.add_child(ring)
			var hinge := Node3D.new()
			hinge.position.y = 0.83
			ring.add_child(hinge)
			var fl := MeshInstance3D.new()
			fl.mesh = flap_mesh
			fl.material_override = shaded
			hinge.add_child(fl)
			flaps[k].append(hinge)
		# flame: alpha outer cone over a white core; shock diamonds for the burner
		var flame := Node3D.new()
		flame.position.z = sim.P.engineLen / 2.0
		eng.add_child(flame)
		flames.append(flame)
		var outer := MeshInstance3D.new()
		outer.mesh = Kit.cyl(0.55, 0.0, 1.0, 16)
		outer.position.y = -0.5
		var om := StandardMaterial3D.new()
		om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		om.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		om.albedo_color = Color(HOT.r, HOT.g, HOT.b, 0.72)
		outer.material_override = om
		outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var core := MeshInstance3D.new()
		core.mesh = Kit.cyl(0.32, 0.0, 0.6, 12)
		core.position.y = -0.3
		core.material_override = view._mat(Color(1.0, 0.93, 0.72), true)
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var cone_root := Node3D.new()   # cones hang along -Y; sync turns that to +Z (back) and stretches it
		cone_root.name = "cones"
		cone_root.add_child(outer)
		cone_root.add_child(core)
		flame.add_child(cone_root)
		for d in 4:
			var dm := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radius = 0.2
			sp.height = 0.4
			sp.radial_segments = 10
			sp.rings = 5
			dm.mesh = sp
			dm.material_override = view._mat(Color(1.0, 0.86, 0.78), true)
			dm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			flame.add_child(dm)
			diamonds[k].append(dm)

	pod = MeshInstance3D.new()
	pod.mesh = pod_hull()   # materials live on its surfaces
	add_child(pod)
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


## Engine shell, forward -Z, 8 m: intake lip and face, nacelle, livery band, fins, mounts.
static func _engine_body(out: float) -> ArrayMesh:
	var along := Vector3(PI / 2.0, 0, 0)   # cylinder +Y to the back
	return Kit.compound([
		[Kit.cyl(0.93, 0.93, 0.45, 24), Kit.at(Vector3(0, 0, -3.72), along), DARK.lightened(0.15)],   # intake lip
		[Kit.cyl(0.8, 0.88, 5.0, 24), Kit.at(Vector3(0, 0, -1.0), along), STEEL],                       # nacelle
		[Kit.cyl(0.9, 0.9, 0.6, 24), Kit.at(Vector3(0, 0, -2.5), along), LIVERY],                        # band
		[Kit.cyl(0.83, 0.86, 0.25, 24), Kit.at(Vector3(0, 0, 0.6), along), LIVERY],                      # pinstripe
		[Kit.cyl(0.74, 0.74, 0.1, 24), Kit.at(Vector3(0, 0, -3.5), along), Color(0.05, 0.05, 0.06)],     # intake throat
		[Kit.box(Vector3(0.09, 1.05, 1.7)), Kit.at(Vector3(0, 1.25, 0.2), Vector3(-0.35, 0, 0)), STEEL], # dorsal fin
		[Kit.box(Vector3(0.06, 0.2, 1.5)), Kit.at(Vector3(0, 1.7, 0.42), Vector3(-0.35, 0, 0)), LIVERY],
		[Kit.box(Vector3(1.1, 0.07, 1.3)), Kit.at(Vector3(out * 1.3, -0.1, 0.5), Vector3(0, 0, -out * 0.12)), STEEL], # outboard stabiliser
		[Kit.box(Vector3(0.55, 0.35, 0.8)), Kit.at(Vector3(-out * 0.95, 0.35, -3.0)), DARK.lightened(0.25)],  # binder emitter
		[Kit.box(Vector3(0.3, 0.3, 0.7)), Kit.at(Vector3(0, -0.92, 3.0)), DARK.lightened(0.25)],         # cable lug
		[Kit.cyl(0.11, 0.11, 0.08, 10), Kit.at(Vector3(0, -0.95, 3.4), Vector3(0, 0, PI / 2.0)), Color(0.75, 0.77, 0.8)],  # cable eye
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


## The pod: polished-metal outer skin (surface 0), matte trim inside (1), rubber lip round the
## cockpit (2), fittings (3). Built once and shared (the flat view's pod and the VR cockpit).
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
	for layer in 2:   # 0 outer skin, 1 inner trim
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
	mesh.surface_set_material(0, Kit.polished(1.0, 0.14))
	var trim := StandardMaterial3D.new()
	trim.vertex_color_use_as_albedo = true
	trim.vertex_color_is_srgb = true
	trim.roughness = 0.85
	mesh.surface_set_material(1, trim)

	# lip: a rubber tube round the opening, laid on the hull top
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
			lip.set_color(Color(0.07, 0.07, 0.08))
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
	var rubber := StandardMaterial3D.new()
	rubber.vertex_color_use_as_albedo = true
	rubber.vertex_color_is_srgb = true
	rubber.roughness = 0.55
	mesh.surface_set_material(2, rubber)

	# fittings
	Kit.compound([
		[Kit.rounded_box(Vector3(0.07, 0.62, 0.85), 4.0), Kit.at(Vector3(0, 0.42, 1.6), Vector3(-0.35, 0, 0)), SILVER],   # raked fin
		[Kit.rounded_box(Vector3(0.012, 0.16, 0.5), 4.0), Kit.at(Vector3(0, 0.62, 1.66), Vector3(-0.35, 0, 0)), LIVERY],
		[Kit.rounded_box(Vector3(0.1, 0.2, 0.72), 4.0), Kit.at(Vector3(-1.1, -0.26, -0.15)), DARK],   # side intakes, behind the cage
		[Kit.rounded_box(Vector3(0.1, 0.2, 0.72), 4.0), Kit.at(Vector3(1.1, -0.26, -0.15)), DARK],
		[Kit.cyl(0.15, 0.19, 0.36, 16), Kit.at(Vector3(-0.5, -0.24, 2.1), Vector3(PI / 2.0, 0, 0)), DARK],   # trim thrusters
		[Kit.cyl(0.15, 0.19, 0.36, 16), Kit.at(Vector3(0.5, -0.24, 2.1), Vector3(PI / 2.0, 0, 0)), DARK],
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
	_hull_cache = mesh
	return mesh


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
		if absf(lat_g) > 150.0 or sim.crash_t > 0.0:   # respawn / crash: not a turn
			lat_g = 0.0
		lat_g *= b.grip   # airborne: nothing to lean against
		_lat[k] = lerpf(_lat[k], lat_g, 1.0 - exp(-delta / BANK_TAU))
		var was: float = bank[k]
		bank[k] = move_toward(bank[k], BANK_MAX * tanh(_lat[k] / BANK_G), BANK_RATE * delta)
		if k == 2:
			roll_rate_peak = maxf(roll_rate_peak, absf(bank[k] - was) / delta)


func sync(sim, inp: Dictionary, delta: float) -> void:
	_update_bank(sim, delta)
	var bodies := [sim.eL, sim.eR]
	var brakes := [inp.brkL, inp.brkR]   # each engine's flaps answer to its own brake
	for k in 2:
		var e = bodies[k]
		var eng := engines[k]
		eng.position = view.w3(e.x, e.y, e.z + 0.1)
		var vh: float = sqrt(e.vx * e.vx + e.vy * e.vy)
		var pitch: float = atan2(e.vz, maxf(vh, 1.0)) if vh > 5.0 else 0.0
		pitch += slope_pitch(view, e.x, e.y, e.th, 4.0)   # nose follows the banking's rise and fall
		eng.rotation = Vector3(pitch, e.th - PI / 2.0, clampf(bank[k] + view.surface(e.x, e.y).y, -ROLL_MAX, ROLL_MAX))   # lean, plus the track's banking
		var h: float = e.heat
		var col := Color(0.25, 0.25, 0.25) if e.flameout else heat_color(h)
		hot_mats[k].albedo_color = col
		hot_mats[k].emission = Color.BLACK if e.flameout else col * smoothstep(0.35, 1.0, h) * 1.4
		var t: float = 0.0 if e.flameout else minf(e.thrust, 1.0)
		glow_mats[k].albedo_color = DARK.lerp(HOT, minf(1.0, t * 1.5)).lerp(WHITE, maxf(0.0, t - 0.6) * 1.5)
		# fan: spins up with thrust, winds down on a flameout; capped below where it would strobe
		var w_target := 0.0 if e.flameout else 3.0 + 16.0 * t
		_fan_w[k] = lerpf(_fan_w[k], w_target, 1.0 - exp(-delta * 2.0))
		fans[k].rotation.z = fposmod(fans[k].rotation.z + _fan_w[k] * delta, TAU)
		# air brakes
		flap_open[k] = move_toward(flap_open[k], clampf(brakes[k], 0.0, 1.0), FLAP_RATE * delta)
		for hinge in flaps[k]:
			(hinge as Node3D).rotation.x = 0.06 - FLAP_OPEN * flap_open[k]
		# flame
		var flame := flames[k]
		var burning: bool = not e.flameout and e.thrust > 0.02
		flame.visible = burning
		if burning:
			var hot_mode: bool = sim.mode != "normal"
			var flame_len: float = 0.2 + e.thrust * (8.0 if hot_mode else 4.0)
			var cones: Node3D = flame.get_node("cones")
			cones.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0) * Basis.from_scale(Vector3(1, flame_len, 1)), Vector3.ZERO)
			for d in 4:
				var dm: MeshInstance3D = diamonds[k][d]
				dm.visible = hot_mode
				dm.position = Vector3(0, 0, flame_len * (0.16 + 0.17 * d))
				dm.scale = Vector3.ONE * (1.0 - 0.18 * d)

	pod.position = view.w3(sim.pod.x, sim.pod.y, sim.pod.z - 0.2 + POD_LIFT)
	pod.rotation = Vector3(slope_pitch(view, sim.pod.x, sim.pod.y, sim.pod.th, 2.0), sim.pod.th - PI / 2.0,
		clampf(bank[2] + view.surface(sim.pod.x, sim.pod.y).y, -ROLL_MAX, ROLL_MAX))
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


## How hard cable k glows for its engine's thrust (0..1 lever, more on the burner): nothing at
## idle, rising with thrust, crackling at the top. Follows real thrust, so a damaged engine's
## sputter flickers its cable and a flameout goes dark (Luke: "make the cables glow like they're
## energized with the amount of throttle").
static func cable_glow(thrust: float) -> Array:
	if thrust < 0.02:
		return [0.0, CABLE_COOL]
	var g := clampf(thrust, 0.0, 1.6)
	var energy := 0.4 + 3.2 * pow(minf(g, 1.0), 1.3) + 2.0 * maxf(0.0, g - 1.0)
	return [energy, CABLE_COOL.lerp(CABLE_HOT, clampf((g - 0.85) / 0.6, 0.0, 1.0))]   # blue until the burner


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
		var glow := cable_glow(eng.thrust)
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
	arc.surface_begin(Mesh.PRIMITIVE_LINES)
	var p0: Vector3 = engines[0].transform * Vector3(0.95, 0.35, -3.0)
	var p1: Vector3 = engines[1].transform * Vector3(-0.95, 0.35, -3.0)
	var prev := p0
	for s in range(1, 9):
		var p := p0.lerp(p1, s / 8.0) + (Vector3(0, randf_range(-0.35, 0.35), randf_range(-0.2, 0.2)) if s < 8 else Vector3.ZERO)
		for q in [prev, p]:
			arc.surface_set_color(Color(0.55, 0.88, 1.0))
			arc.surface_add_vertex(q)
		prev = p
	arc.surface_end()
