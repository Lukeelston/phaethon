## What the pilot's inch forward and the pod's pitch under him change, in numbers (not a test: a table for
## the push-40 cockpit; vr_cockpit.gd SEAT_FWD, POD_PITCH, vr/speed_rush.gd's travel). The production
## cockpit's own meshes, every triangle (tests/clash_kit.gd), with the nose closed and with it open, as the
## pilot had it (the eye an inch further aft, the pod level, the rush's first travel), with the inch alone,
## and as it is now:
##   the road     how far under his level gaze the first thing that hides the road stands, dead ahead and to
##                either side; then the road itself, straight and in a firm left and right bend (the cockpit
##                rolled and stepped out as it is in one): how near the nearest of it he can see is, and how
##                many degrees of its middle line show over the nose and coaming; and how much of the ground
##                ahead is in sight at all, through whatever the nose leaves open (square degrees of it within
##                40 degrees of the craft's way and 40 under the horizon).
##   his face     the nearest solid thing to his eyes, at rest and with the speed rush's travel fully back.
##   his reach    from his shoulders to every control worked by hand.
##   the dash     where the instruments and the coaming's crest stand under his gaze.
## --headless --xr-mode off --audio-driver Dummy -s res://tests/probe_pod_pitch.gd -- --mute
extends SceneTree

const VR := preload("res://vr/vr_cockpit.gd")
const Sim := preload("res://sim/craft_sim.gd")
const CM := preload("res://view/craft_model.gd")
const ClashKit := preload("res://tests/clash_kit.gd")
const Rush := preload("res://vr/speed_rush.gd")
const Drift := preload("res://vr/drift_slider.gd")
const Switch := preload("res://vr/mode_switch.gd")
const Overhead := preload("res://vr/overhead_panel.gd")
const MapPanel := preload("res://vr/minimap_panel.gd")
const Layout := preload("res://vr/gauge_layout.gd")
const Kit := preload("res://view/mesh_kit.gd")
const AFT_WAS := 0.025           # the speed rush's travel toward the pilot as it first flew
const EYE_UP := 2.8              # m: the eye over the road in flight (the sim's body rides 1.5 m up, the pod's floor 0.5 m over that, the eye 0.81 m over the floor)
const REACH := 4.0               # m: nothing of the cockpit is further from the eye than this
# A firm bend as the cockpit shows it: 20 g at 3,350 mph. The craft's lean of 58 degrees is 25 of the
# cockpit's own roll, and the cockpit steps out 6 degrees into the turn (vr_cockpit.gd's slide).
const BEND_ROLL := deg_to_rad(25.0)
const BEND_SLIDE := deg_to_rad(6.0)
const BEND_RADIUS := 11500.0     # m

var kit
var space: PhysicsDirectSpaceState3D


func _initialize() -> void:
	_run.call_deferred()


## Does this part hide what is behind it? (The glass, the forcefield, the reflection and the projector's
## picture are looked through.)
func _hides(part: String) -> bool:
	if not part.contains("canopy/"):
		return true
	return part.contains("roof") or part.contains("overhead") or part.contains("Overhead") or part.contains("pod")


## What hides the way from `from` along `dir` (cockpit metres): the first part that does, "" none.
func _hidden_by(from: Vector3, dir: Vector3) -> String:
	for part in kit.sight(space, from, from + dir.normalized() * REACH):
		if _hides(part):
			return part
	return ""


## The nearest thing to a point: [metres, its name], looking no further than `limit`.
func _nearest(point: Vector3, limit := 1.2, solid_only := false) -> Array:
	var sphere := SphereShape3D.new()
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, point)
	var skip: Array[RID] = []
	if solid_only:
		for i in kit.names.size():
			if not _hides(kit.names[i]):
				skip.append(kit.rids[i])
	q.exclude = skip
	var lo := 0.0
	var hi := limit
	sphere.radius = hi
	if space.intersect_shape(q, 1).is_empty():
		return [limit, "nothing"]
	var who := ""
	while hi - lo > 0.0005:
		var mid := (lo + hi) * 0.5
		sphere.radius = mid
		var found := space.intersect_shape(q, 1)
		if found.is_empty():
			lo = mid
		else:
			hi = mid
			who = kit.names[int(kit._index.get((found[0].collider as Object).get_instance_id(), 0))]
	return [hi, who]


## A direction in the pilot's level view (degrees to the right of ahead, degrees under level), rolled and
## turned as the cockpit is in a bend (`roll` + = left side down, `slide` + = the nose further left), in the
## cockpit's own axes when the pod stands `pitch` nose-down under him.
func _into_cabin(dir_world: Vector3, roll: float, slide: float, pitch: float) -> Vector3:
	# the view's frame in the world: turned by the slide, rolled about its own nose; the cabin pitched under it
	var view := Basis(Vector3.UP, slide) * Basis(Vector3.FORWARD, -roll)
	var cabin := view * Basis(Vector3.RIGHT, -pitch)
	return cabin.inverse() * dir_world


## The first thing that hides the ground under the pilot's level gaze, `az` degrees to the right of ahead:
## how far under level it stands, degrees (he sees the ground from there up to the horizon).
func _cut_off(eye: Vector3, az: float, pitch: float) -> float:
	for step in range(0, 700):
		var down := deg_to_rad(step * 0.1)
		var dir := Vector3(sin(deg_to_rad(az)) * cos(down), -sin(down), -cos(deg_to_rad(az)) * cos(down))
		if _hidden_by(eye, _into_cabin(dir, 0.0, 0.0, pitch)) != "":
			return step * 0.1
	return 70.0


## The road's middle line ahead of the craft as she goes (`bend` -1 a left bend, 1 a right one, 0 straight):
## [degrees of it in sight, the nearest of it in sight (m ahead), the first part that hides the rest].
func _road(eye: Vector3, pitch: float, bend: float) -> Array:
	var roll := -bend * BEND_ROLL             # a left bend: the left side down
	var slide := -bend * BEND_SLIDE           # ... and the nose further left
	var seen := 0.0
	var nearest := INF
	var by := ""
	var was: Variant = null
	var was_seen := false
	var s := 2.0
	while s < 6000.0:
		var across := 0.0 if bend == 0.0 else bend * s * s / (2.0 * BEND_RADIUS)      # m to the right of the craft's way
		var dir := Vector3(across, -EYE_UP, -s).normalized()
		var hid := _hidden_by(eye, _into_cabin(dir, roll, slide, pitch))
		if hid == "":
			nearest = minf(nearest, s)
			if was != null and was_seen:
				seen += rad_to_deg(dir.angle_to(was as Vector3))
		elif by == "" or nearest == INF:
			by = hid
		was = dir
		was_seen = hid == ""
		s *= 1.01
	return [seen, nearest, by]


## How much of the ground ahead is in sight: square degrees of it within 40 degrees either side of the
## craft's way and from the horizon to 40 degrees under it (a look every degree), in a bend as _road has it.
func _ground(eye: Vector3, pitch: float, bend: float) -> float:
	var roll := -bend * BEND_ROLL
	var slide := -bend * BEND_SLIDE
	var free := 0
	for i in range(-40, 41):
		for j in range(1, 41):
			var az := deg_to_rad(float(i))
			var down := deg_to_rad(float(j) - 0.5)
			var dir := Vector3(sin(az) * cos(down), -sin(down), -cos(az) * cos(down))
			free += int(_hidden_by(eye, _into_cabin(dir, roll, slide, pitch)) == "")
	return float(free)


func _cockpit(closed: bool):
	CM.nose_closed = closed
	var cockpit = VR.new()
	cockpit.sim = Sim.new({"track": "range"})
	cockpit.rig = Node3D.new()
	root.add_child(cockpit.rig)
	cockpit._build_cockpit()
	return cockpit


func _run() -> void:
	VR._nose_loaded = true
	var now: Vector3 = VR.EYE                                  # (cockpit metres: the pod's own frame; the eye is the pitch's own pivot)
	var was: Vector3 = now + Vector3(0.0, 0.0, VR.SEAT_FWD)
	var pitch: float = VR.POD_PITCH
	print("POD PITCH: the eye %s (it was %s), the pod %.1f degrees nose-down under it; the speed rush's travel %.1f mm forward and %.1f mm back (it was 35.0 and %.1f)" % [
		now, was, rad_to_deg(pitch), Rush.FWD_MAX * 1000.0, Rush.AFT_MAX * 1000.0, AFT_WAS * 1000.0])
	var cases := [["as it was", was, 0.0], ["the inch alone", now, 0.0], ["the inch and the pitch", now, pitch]]
	for closed in [true, false]:
		var cockpit = _cockpit(closed)
		await process_frame
		kit = ClashKit.new()
		kit.gather(cockpit.rig)
		kit.arm(root)
		await physics_frame
		await physics_frame
		space = root.world_3d.direct_space_state
		print("")
		print("== the nose %s (%d meshes, %d triangles)" % ["closed" if closed else "open", kit.soups.size(), kit.triangles()])
		print("-- under his level gaze, the first thing that hides the ground (degrees under level; he sees the ground above that):")
		print("   degrees right of ahead:     -40    -30    -20    -10      0     10     20     30     40")
		for c in cases:
			var row := "   %-24s" % String(c[0])
			for az in [-40.0, -30.0, -20.0, -10.0, 0.0, 10.0, 20.0, 30.0, 40.0]:
				row += " %6.1f" % _cut_off(c[1], az, float(c[2]))
			print(row)
		print("-- the road's middle line (the eye %.1f m over it): degrees of it in sight, the nearest of it in sight, what hides the rest" % EYE_UP)
		for bend in [[0.0, "straight"], [-1.0, "a firm left bend (rolled %.0f, stepped out %.0f degrees)" % [rad_to_deg(BEND_ROLL), rad_to_deg(BEND_SLIDE)]], [1.0, "a firm right bend"]]:
			var first := 0.0
			for c in cases:
				var r := _road(c[1], float(c[2]), float(bend[0]))
				if c == cases[0]:
					first = float(r[0])
				print("   %-58s %-24s %5.1f degrees (%+.1f)   from %6.1f m ahead   [%s]" % [String(bend[1]), String(c[0]), float(r[0]), float(r[0]) - first, float(r[1]), String(r[2]).trim_prefix("shell/")])
		print("-- the ground ahead in sight, square degrees of the 3,240 within 40 degrees of her way and 40 under the horizon:")
		for bend in [[0.0, "straight"], [-1.0, "a firm left bend"], [1.0, "a firm right bend"]]:
			var row := "   %-22s" % String(bend[1])
			var first_ground := 0.0
			for c in cases:
				var g := _ground(c[1], float(c[2]), float(bend[0]))
				if c == cases[0]:
					first_ground = g
				row += "   %s %4.0f (%+.0f)" % [String(c[0]), g, g - first_ground]
			print(row)
		if closed:
			_his_face(was, now)
			_his_reach(cockpit, was, now)
			_the_dash(cockpit, was, now, pitch)
		kit.free_bodies()
		cockpit.rig.free()
		cockpit.free()
		await physics_frame
	print("")
	print("POD PITCH PROBE DONE")
	quit(0)


func _his_face(was: Vector3, now: Vector3) -> void:
	print("-- the nearest thing to his eyes (m; the cockpit moved back toward him is his eyes moved forward in it):")
	var places := [["as it was, at rest", was], ["as it was, the rush fully back", was - Vector3(0.0, 0.0, AFT_WAS)], ["now, at rest", now], ["now, the rush fully back", now - Vector3(0.0, 0.0, Rush.AFT_MAX)]]
	for p in places:
		var any := _nearest(p[1])
		var solid := _nearest(p[1], 1.2, true)
		var ahead := INF
		var ahead_by := ""
		# ... and in front of his face: the nearest thing within 50 degrees of straight ahead
		for i in range(-5, 6):
			for j in range(-5, 6):
				var dir := Vector3(sin(deg_to_rad(i * 10.0)), sin(deg_to_rad(j * 10.0)), -1.0).normalized()
				if dir.angle_to(Vector3.FORWARD) > deg_to_rad(50.0):
					continue
				var q := PhysicsRayQueryParameters3D.new()
				q.from = p[1]
				q.to = (p[1] as Vector3) + dir * REACH
				q.hit_back_faces = true
				var hit := space.intersect_ray(q)
				if not hit.is_empty() and (hit.position as Vector3).distance_to(p[1]) < ahead:
					ahead = (hit.position as Vector3).distance_to(p[1])
					ahead_by = kit.names[int(kit._index.get((hit.collider as Object).get_instance_id(), 0))]
		print("   %-34s anything %.3f (%s)   solid %.3f (%s)   within 50 degrees of ahead %.3f (%s)" % [String(p[0]), float(any[0]), String(any[1]).trim_prefix("shell/"), float(solid[0]), String(solid[1]).trim_prefix("shell/"),
			ahead, ahead_by.trim_prefix("shell/")])


func _his_reach(cockpit, was: Vector3, now: Vector3) -> void:
	print("-- his reach (m): from the shoulder on that side, as it was and now; and from his eyes now")
	var to_rig: Transform3D = (cockpit.rig as Node3D).global_transform.affine_inverse()
	var canopy: Transform3D = to_rig * (cockpit.canopy as Node3D).global_transform
	var map: Node3D = cockpit.minimap_panel
	var controls := {}
	for control: String in ["batt", "engine", "start", "park"]:
		controls["start panel: " + control] = canopy * Overhead.control_point(control)
	controls["SLIDE / GRIP switch"] = to_rig * ((cockpit.slide_switch as Node3D).global_transform * Vector3(0.0, 0.0, 0.07))
	controls["drift slider, OFF end"] = to_rig * ((cockpit.drift_slider as Node3D).global_transform * Vector3(Drift.place(0.0), 0.0, Drift.CAP_Z))
	controls["drift slider, notch"] = to_rig * ((cockpit.drift_slider as Node3D).global_transform * Vector3(Drift.place(Drift.STANDARD), 0.0, Drift.CAP_Z))
	controls["drift slider, MAX end"] = to_rig * ((cockpit.drift_slider as Node3D).global_transform * Vector3(Drift.place(Drift.AMOUNT_MAX), 0.0, Drift.CAP_Z))
	controls["handling switch"] = to_rig * ((cockpit.mode_switch as Node3D).global_transform * Vector3(0.0, 0.0, 0.07))
	if map.get("map_switch") != null and map.map_switch != null:
		controls["map: GLOBAL / LOCAL"] = to_rig * (map.map_switch as Node3D).global_position
		controls["map: HUD"] = to_rig * (map.hud_switch as Node3D).global_position
		controls["map: colour button"] = to_rig * (map.global_transform * MapPanel.BUTTON_AT)
	for k in 2:
		var pivot: Node3D = cockpit.lever_pivots[k]
		for throttle in [0.0, 1.0]:
			pivot.rotation.x = deg_to_rad(lerpf(30.0, -30.0, throttle))
			controls["%s lever's grip, %s" % ["left" if k == 0 else "right", "idle" if throttle == 0.0 else "full"]] = to_rig * (pivot.global_transform * Vector3(0.0, 0.36, 0.0))
		pivot.rotation.x = 0.0
	for name: String in controls:
		var at: Vector3 = controls[name]
		var side := -1.0 if at.x < 0.0 else 1.0
		var off := Vector3(0.18 * side, -0.2, 0.05)
		var seen := at - now
		print("   %-28s %.3f -> %.3f (%+.0f mm)   from the eyes %.3f, %5.1f degrees %s of ahead, %5.1f degrees %s in the cabin" % [name, (was + off).distance_to(at), (now + off).distance_to(at),
			((now + off).distance_to(at) - (was + off).distance_to(at)) * 1000.0, seen.length(), absf(rad_to_deg(atan2(seen.x, -seen.z))), "right" if seen.x > 0.0 else "left",
			absf(rad_to_deg(asin(seen.y / seen.length()))), "up" if seen.y > 0.0 else "down"])


func _the_dash(cockpit, was: Vector3, now: Vector3, pitch: float) -> void:
	print("-- the dash: where things stand under his gaze (degrees under level: as it was; now in the cabin's own level; now under his level gaze), and how far off (m)")
	var to_rig: Transform3D = (cockpit.rig as Node3D).global_transform.affine_inverse()
	var mount: Transform3D = to_rig * (cockpit.dashboard as Node3D).global_transform
	var things := {}
	for g in Layout.GAUGES:
		things["the %s dial's middle" % String(g.key)] = mount * Kit.on_arc(g.x, g.y, 0.0, Layout.R) * Vector3(0.0, 0.0, float(g.face))
	things["the map's screen, its middle"] = to_rig * (cockpit.minimap_panel as Node3D).global_position
	var front: Vector2 = CM.open_edge(-PI / 2.0)
	things["the coaming's lip dead ahead"] = Vector3(front.x, CM.hull_top(front.x, front.y) + CM.POD_FRAME_UP + CM.LIP_R, front.y)
	things["the header rail, its middle"] = to_rig * ((cockpit.canopy as Node3D).global_transform * Overhead.header_at(0.0))
	things["the tow links' hooks"] = Vector3(0.0, CM.POD_FRAME_UP + CM.POD_EYE_H, -2.1)
	for name: String in things:
		var at: Vector3 = things[name]
		var a := at - was
		var b := at - now
		var level := Basis(Vector3.RIGHT, -pitch) * b      # the same place as his level gaze has it, the pod pitched under him
		print("   %-30s %6.1f  %6.1f  %6.1f      %.3f -> %.3f m" % [name, -rad_to_deg(asin(a.y / a.length())), -rad_to_deg(asin(b.y / b.length())), -rad_to_deg(asin(level.y / level.length())), a.length(), b.length()])
	var hook := Vector3(0.18, CM.POD_FRAME_UP + CM.POD_EYE_H, -2.1)
	var pitched: Vector3 = VR.pod_pose() * hook
	print("   the hooks themselves stand %.0f mm lower and %.0f mm further aft on the rig than they did (the links' pod ends go with them)" % [(hook.y - pitched.y) * 1000.0, (pitched.z - hook.z) * 1000.0])
