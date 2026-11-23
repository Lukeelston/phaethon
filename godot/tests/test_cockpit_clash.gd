## The cockpit's fittings do not pass through each other (Luke, after the flight of 22 November: "The map
## is good but is sticking through the drift switch mesh", "the mach gauge mesh collides with those on the
## sides of it"). In the production cockpit, with every mesh's real triangles (tests/clash_kit.gd):
##   the map's pod and the SLIDE switch stand apart, from the seat neither hides the other, and neither
##   stands where a hand works the other;
##   the levers' grips pass the switches and the drift slider through their whole travel, and never stand
##   between the seat and the slider's knob, legends or ramp; nothing of the slider is in the SLIDE switch's box;
##   no gauge's tube stands inside its neighbour's bore (the open space between a dial and its glass);
##   the map's controls strip is out of the roof's pillar, and the switches' panels out of the coaming;
##   and no two fittings pass through each other that are not on the list of those joined on purpose.
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_cockpit_clash.gd -- --mute
## Prints COCKPIT CLASH PASS. tests/probe_cockpit_clash.gd lists every crossing; tests/render_cockpit_clash.gd shows them.
## (The standard craft's cockpit. The Shrike RS has the same map, switches and gauges, and a seat, lever
## gaiters and strakes of its own that are joined in their own ways: the probe's --vehicle=shrike lists them.)
extends SceneTree

const VR := preload("res://vr/vr_cockpit.gd")
const Sim := preload("res://sim/craft_sim.gd")
const Kit := preload("res://view/mesh_kit.gd")
const ClashKit := preload("res://tests/clash_kit.gd")
const Layout := preload("res://vr/gauge_layout.gd")
const Switch := preload("res://vr/mode_switch.gd")
const MapPanel := preload("res://vr/minimap_panel.gd")
const Drift := preload("res://vr/drift_slider.gd")
# Which gauge's tube stands under which bigger neighbour's wall (tools/gauge_layout.py OVER).
const OVER := {1: 0, 2: 0, 3: 1, 4: 2}
# Fittings that are joined on purpose, one sunk into or standing on the other. Anything else that
# crosses is a fitting through another: move it, or (if it is meant) add it here.
const JOINED := [
	["PodHull", "canopy/field"], ["PodHull", "canopy/roof"],                          # the roof and the forcefield stand on the hull
	["cockpit_interior/RecessedConduits", "canopy/field"],                              # the hoses run out under the forcefield's skirt
	["cockpit_interior/SegmentedCoaming", "canopy/roof"],                               # the roof's feet in the coaming
	["cockpit_interior/Dashboard", "gauge_cluster/binnacle"],                           # the binnacle stands on the fascia
	["seat_cushion", "cockpit_interior/SeatTub"], ["seat_cushion", "cockpit_interior/HarnessWebbing"],
	["seat_cushion", "cockpit_interior/MachinedHardware"],                              # the lap belt and its buckle lie in the cushion
	["cockpit_interior/ConsoleR", "mode_switch/MeshInstance3D"], ["cockpit_interior/ConsoleL", "SlideSwitch/MeshInstance3D"],   # the switches' panels are let into the consoles
	["cockpit_interior/ConsoleL", "DriftSlider/rail"],                                  # the drift slider's rail sits over the console's inboard shoulder, its foot let into the top
]
var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	checks += 1
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _mm(m: float) -> String:
	return ("over %.0f" % (ClashKit.REACH * 1000.0)) if m >= ClashKit.REACH else ("%.1f" % (m * 1000.0))


## The fitting a part belongs to: the first of its names under the shell (the seat's two cushions are one).
func _fitting(label: String) -> String:
	var name := label.trim_prefix("shell/").get_slice("/", 0)
	return "seat" if name.begins_with("seat_") else name


func _joined(a: String, b: String) -> bool:
	a = a.trim_prefix("shell/")
	b = b.trim_prefix("shell/")
	for pair in JOINED:
		if (pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a):
			return true
	return false


func _run() -> void:
	VR._nose_loaded = true
	var cockpit = VR.new()
	cockpit.sim = Sim.new({"track": "range"})
	cockpit.rig = Node3D.new()
	root.add_child(cockpit.rig)
	cockpit._build_cockpit()
	await process_frame
	var rig: Node3D = cockpit.rig
	var to_rig: Transform3D = rig.global_transform.affine_inverse()
	var slide: Node3D = cockpit.slide_switch
	var mode: Node3D = cockpit.mode_switch
	var map: Node3D = cockpit.minimap_panel
	_check("the cockpit has its map in a pod, a SLIDE switch and a handling switch", map != null and map.get_node_or_null("pod") != null and slide != null and mode != null)
	if map == null or slide == null or mode == null:
		print("COCKPIT CLASH FAIL (%d failures)" % failures)
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():      # (what if: the SLIDE switch back at the handling switch's mirrored place)
		if arg == "--slide-mirrored":
			slide.position.z = mode.position.z

	# ---- the levers pass the switches and the drift slider, through their whole travel
	var slider: Node3D = cockpit.drift_slider
	_check("the cockpit has its drift slider", slider != null and slider.get_script() == Drift)
	if slider == null:
		print("COCKPIT CLASH FAIL (%d failures)" % failures)
		quit(1)
		return
	# what of the slider is looked at from the seat: its knob at the ends and in its notch, its legends, its ramp's ends (panel metres)
	var slider_face := {"OFF legend": Vector3(Drift.place(0.0), -0.0128, 0.004), "DRIFT legend": Vector3(-0.014, -0.0128, 0.004), "MAX legend": Vector3(Drift.place(Drift.AMOUNT_MAX), -0.0128, 0.004),
		"ramp at OFF": Vector3(Drift.place(0.0), 0.007, 0.004), "ramp at MAX": Vector3(Drift.place(Drift.AMOUNT_MAX), 0.0107, 0.004),
		"knob at OFF": Vector3(Drift.place(0.0), 0.0, Drift.CAP_Z + Drift.CAP.z * 0.5 + 0.001), "knob in its notch": Vector3(Drift.place(Drift.STANDARD), 0.0, Drift.CAP_Z + Drift.CAP.z * 0.5 + 0.001),
		"knob at MAX": Vector3(Drift.place(Drift.AMOUNT_MAX), 0.0, Drift.CAP_Z + Drift.CAP.z * 0.5 + 0.001)}
	var least := [ClashKit.REACH, ClashKit.REACH, ClashKit.REACH]
	var behind_grip := []
	for at_amount in [Drift.AMOUNT_MAX, 0.0]:      # (the knob at each end of its slot: the forward end is the one the grips come nearest)
		slider.amount = at_amount
		slider.show_state(true, 1.0)
		for step in 5:
			for pivot: Node3D in cockpit.lever_pivots:
				pivot.rotation.x = deg_to_rad(lerpf(30.0, -30.0, step / 4.0))      # (idle to full burner: the live cockpit's swing)
			var near := ClashKit.new()
			for part in cockpit.lever_pivots + [slide, mode, slider]:
				near.gather_part(rig, part)
			near.arm(root)
			await physics_frame
			await physics_frame
			least[0] = minf(least[0], float(near.gap(root.world_3d.direct_space_state, "PilotGrip", "SlideSwitch")[0]))
			least[1] = minf(least[1], float(near.gap(root.world_3d.direct_space_state, "PilotGrip", "shell/mode_switch")[0]))
			least[2] = minf(least[2], float(near.gap(root.world_3d.direct_space_state, "PilotGrip", "DriftSlider")[0]))
			for what: String in slider_face:
				for part in near.sight(root.world_3d.direct_space_state, VR.EYE, to_rig * (slider.global_transform * (slider_face[what] as Vector3))):
					if not part.contains("DriftSlider"):
						behind_grip.append("%s behind %s, lever %d of 4" % [what, part, step])
						break
			near.free_bodies()
			await physics_frame
	slider.amount = Drift.STANDARD
	slider.show_state(true, 1.0)
	for pivot: Node3D in cockpit.lever_pivots:
		pivot.rotation.x = 0.0
	_check("the levers' grips pass the SLIDE switch by %s mm at the least through their travel, the handling switch by %s mm and the drift slider by %s mm" % [_mm(least[0]), _mm(least[1]), _mm(least[2])],
		least[0] >= 0.012 and least[1] >= 0.012 and least[2] >= 0.012)
	_check("and from the seat no lever, anywhere in its travel, stands before the drift slider's knob, legends or ramp (hidden: %s)" % [behind_grip], behind_grip.is_empty())

	# ---- everything else, as built (the two switches' levers thrown up, toward the map's pod)
	for sw in [slide, mode]:
		(sw.lever as Node3D).rotation.x = -Switch.THROW_ANGLE
	var kit := ClashKit.new()
	kit.gather(rig)
	kit.arm(root)
	await physics_frame
	await physics_frame
	var space := root.world_3d.direct_space_state

	# ---- the map's pod and the SLIDE switch
	var through := kit.crossing_edges(space, "minimap_panel", "SlideSwitch")
	var apart: Array = kit.gap(space, "minimap_panel", "SlideSwitch")
	_check("the map and the SLIDE switch do not pass through each other (%d edges of one through the other; %s mm apart at the nearest)" % [through, _mm(apart[0])],
		through == 0 and float(apart[0]) >= 0.008)
	through = kit.crossing_edges(space, "minimap_panel", "shell/mode_switch")
	_check("nor the map and the handling switch (%d edges)" % through, through == 0)
	var eye: Vector3 = VR.EYE
	var hidden := []
	var face := {"SLIDE lamp": Vector3(0, 0.05, 0.009), "GRIP lamp": Vector3(0, -0.05, 0.009), "SLIDE legend": Vector3(0, 0.067, 0.009), "GRIP legend": Vector3(0, -0.033, 0.009),
		"lever up": Vector3(0, 0.045, 0.082), "lever down": Vector3(0, -0.045, 0.082), "top inboard corner": Vector3(0.05, 0.066, 0.009), "top outboard corner": Vector3(-0.05, 0.066, 0.009),
		"foot inboard": Vector3(0.05, -0.066, 0.009), "foot outboard": Vector3(-0.05, -0.066, 0.009)}
	for what: String in face:
		for part in kit.sight(space, eye, to_rig * (slide.global_transform * (face[what] as Vector3))):
			if part.contains("minimap_panel"):
				hidden.append(what)
				break
	_check("from the seat the map hides none of the SLIDE switch's face: its lamps, legends, lever and corners (hidden: %s)" % [hidden], hidden.is_empty())
	hidden = []
	for sx in [-1.0, 0.0, 1.0]:
		for sy in [-1.0, 0.0, 1.0]:
			var at := Vector3(sx * (MapPanel.W / 2.0 - 0.004), sy * (MapPanel.H / 2.0 - 0.004), 0.002)
			for part in kit.sight(space, eye, to_rig * (map.global_transform * at)):
				if part.contains("SlideSwitch") or part.contains("shell/mode_switch"):
					hidden.append([Vector2(sx, sy), part])
					break
	_check("nor does a switch hide any of the map's screen (hidden: %s)" % [hidden], hidden.is_empty())
	# ... and each is worked by hand: nothing of the one stands in the box where a controller's tip works the other
	var into_slide: Transform3D = slide.global_transform.affine_inverse() * rig.global_transform
	var into_toggle: Transform3D = (map.map_switch as Node3D).global_transform.orthonormalized().affine_inverse() * rig.global_transform
	var in_slide := 0
	var in_toggle := 0
	for i in kit.group("minimap_panel"):
		for p in kit.soups[i]:
			var q := into_slide * p
			if absf(q.x) < Switch.ZONE.x and absf(q.y) < Switch.ZONE.y and q.z > -0.01 and q.z < Switch.ZONE.z:
				in_slide += 1
	for i in kit.group("SlideSwitch"):
		for p in kit.soups[i]:
			var q := into_toggle * p
			if absf(q.x) < MapPanel.SWITCH_ZONE.x and absf(q.y) < MapPanel.SWITCH_ZONE.y and q.z > -0.01 and q.z < MapPanel.SWITCH_ZONE.z:
				in_toggle += 1
	_check("nothing of the map stands in the box before the SLIDE switch where a hand throws it (%d of its vertices), nor of the switch in the box before the map's toggle (%d)" % [in_slide, in_toggle],
		in_slide == 0 and in_toggle == 0)
	# ---- the drift slider: out of the SLIDE switch's box, and in sight from the seat with everything else in the cockpit in place
	var slider_in_slide := 0
	for i in kit.group("DriftSlider"):
		for p in kit.soups[i]:
			var q := into_slide * p
			if absf(q.x) < Switch.ZONE.x and absf(q.y) < Switch.ZONE.y and q.z > -0.01 and q.z < Switch.ZONE.z:
				slider_in_slide += 1
	hidden = []
	for what: String in slider_face:
		for part in kit.sight(space, eye, to_rig * (slider.global_transform * (slider_face[what] as Vector3))):
			if not part.contains("DriftSlider"):
				hidden.append("%s behind %s" % [what, part])
				break
	_check("nothing of the drift slider stands in the box before the SLIDE switch (%d of its vertices), and from the seat nothing in the cockpit hides its knob, legends or ramp (hidden: %s)" % [slider_in_slide, hidden],
		slider_in_slide == 0 and hidden.is_empty())
	var legend_z := INF
	for child in cockpit.interior.get_children():
		if child is Label3D and (child as Label3D).text == "AUX PWR":
			legend_z = (to_rig * (child as Label3D).global_position).z
	var foot: Vector3 = to_rig * (slide.global_transform * Vector3(0, -0.075, 0))
	var up: Vector3 = (to_rig * slide.global_transform).basis.y   # (up the panel's face)
	var meets := foot.z + (0.386 - foot.y) * up.z / up.y           # (where the face comes down to the console's top, 0.386 up)
	_check("the SLIDE switch's panel meets the console's top %.0f mm short of the middle of its first legend (AUX PWR)" % ((legend_z - meets) * 1000.0),
		legend_z < INF and legend_z - meets >= 0.012)

	# ---- the gauges: nothing of the binnacle inside a tube's bore but its own hub (and, by design, the wall of the bigger neighbour it stands under)
	var binnacle := cockpit.dashboard.get_node_or_null("binnacle") as MeshInstance3D
	_check("the instruments are the gauge cluster, with its binnacle", binnacle != null)
	if binnacle != null:
		var tris: PackedVector3Array = binnacle.mesh.get_faces()
		var frames := []
		for g: Dictionary in Layout.GAUGES:
			frames.append(Kit.on_arc(g.x, g.y, 0.0, Layout.R).affine_inverse())
		var inside := [0, 0, 0, 0, 0]
		var deepest := [0.0, 0.0, 0.0, 0.0, 0.0]
		for t in range(0, tris.size(), 3):
			var a := tris[t]
			var b := tris[t + 1]
			var c := tris[t + 2]
			for p: Vector3 in [a, b, c, (a + b) * 0.5, (b + c) * 0.5, (c + a) * 0.5, (a + b + c) / 3.0]:
				for gi in 5:
					var g: Dictionary = Layout.GAUGES[gi]
					var q: Vector3 = (frames[gi] as Transform3D) * p
					var seat: float = g.mouth - Layout.SEAT
					if q.z <= g.face + 0.004 or q.z >= seat - 0.001:
						continue
					var r := Vector2(q.x, q.y).length()
					# the funnel as it is built (tools/art_gauges_hd.py): a cone from the dial's rim up to the glass's seat
					var wall: float = remap(q.z, g.face + 0.003, seat - 0.001, g.rf + 0.0015, g.rg - 0.0025)
					if r <= 0.19 * g.rf + 0.004 or r >= wall - 0.001:
						continue
					if OVER.has(gi):
						var over: Dictionary = Layout.GAUGES[OVER[gi]]
						var qo: Vector3 = (frames[OVER[gi]] as Transform3D) * p
						if Vector2(qo.x, qo.y).length() <= over.ro + 0.001:
							continue
					inside[gi] += 1
					deepest[gi] = maxf(deepest[gi], wall - r)
		for gi in 5:
			_check("nothing stands inside the %s tube's bore (%d points of the binnacle's %d triangles, the deepest %.1f mm in from its wall)" % [
				Layout.GAUGES[gi].key, inside[gi], tris.size() / 3, deepest[gi] * 1000.0], inside[gi] == 0)

	# ---- the sweep's two: the map's strip and the roof's pillar, the switches and the coaming
	through = kit.crossing_edges(space, "minimap_panel/controls", "canopy/roof")
	apart = kit.gap(space, "minimap_panel/controls", "canopy/roof")
	_check("the map's controls strip is clear of the roof's pillar behind it (%d edges through; %s mm apart)" % [through, _mm(apart[0])], through == 0 and float(apart[0]) >= 0.002)
	for sw: String in ["SlideSwitch", "shell/mode_switch"]:
		through = kit.crossing_edges(space, sw, "SegmentedCoaming")
		apart = kit.gap(space, sw, "SegmentedCoaming")
		# (its upper outboard corner lies close under the coaming's hem: under it, not in it)
		_check("%s's panel is out of the coaming (%d edges through; %s mm under its hem)" % [sw.trim_prefix("shell/"), through, _mm(apart[0])], through == 0 and float(apart[0]) >= 0.0005)

	# ---- and nothing else passes through anything it is not joined to
	var strangers := []
	var found := kit.crossings(space)
	for key: String in found:
		var rec: Dictionary = found[key]
		var size: Vector3 = (rec.hi as Vector3) - (rec.lo as Vector3)
		if size.length() < 0.002 or _fitting(rec.a) == _fitting(rec.b) or _joined(rec.a, rec.b):
			continue
		var mid: Vector3 = ((rec.hi as Vector3) + (rec.lo as Vector3)) * 0.5
		strangers.append("%s >< %s: %d edges in %.0f x %.0f x %.0f mm at (%.2f, %.2f, %.2f)" % [String(rec.a).trim_prefix("shell/"), String(rec.b).trim_prefix("shell/"), rec.n,
			size.x * 1000.0, size.y * 1000.0, size.z * 1000.0, mid.x, mid.y, mid.z])
	_check("no fitting passes through another that it is not joined to (%d meshes, %d triangles; %d pairs cross in all; strangers: %s)" % [
		kit.soups.size(), kit.triangles(), found.size(), strangers], strangers.is_empty())

	kit.free_bodies()
	rig.free()
	cockpit.free()
	print("COCKPIT CLASH %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
