## Where the Orrery's canopy stands from the seat's eye (Raids stage 2 Task 8: the orbs' orbit). The VR seat on the Range
## (XR off): the eye, Codex's FORMATION and SEATS (view/arms/orrery_arms.gd), the canopy's parts' boxes, all in the hull's
## frame; the canopy's profile along a few bearings (each part a line from the eye meets, where, and its face's normal);
## then for a ring of radius --r= (4) at heights over the cab's origin, the bearings whose line from the eye meets the
## roof's glass forward of z 0.27 (the start panel's front edge). What it showed (2026-11-26): the Orrery's roof glass is
## one bubble from the coaming over the head (its header bow some 55 degrees up from the eye), so no ring of a sane height
## keeps out of all its forward glass; tests/test_orbs.gd holds the orbs out of the windscreen's outline as the canopy
## keeps it for the gates (view/canopy.gd's oblong screen and frame, hidden in the fleet's cockpits: its top edge about 6
## degrees up ahead), which a ring at ORBIT_UP (view/weapons/orb_mount.gd) clears all the way round.
## --headless --xr-mode off --audio-driver Dummy -s res://tests/probe_orb_sight.gd -- --mute [--r=4]
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const ClashKit := preload("res://tests/clash_kit.gd")
const OrreryArms := preload("res://view/arms/orrery_arms.gd")


func _initialize() -> void:
	_run.call_deferred()


## Every part the line meets: [label, where (the hull's frame), its face's normal (the hull's frame)].
func _hits(kit, space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, to_hull: Transform3D) -> Array:
	var out := []
	var q := PhysicsRayQueryParameters3D.new()
	q.hit_back_faces = true
	q.from = from
	q.to = to
	for again in 24:
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		q.exclude = q.exclude + [hit.rid]
		var j: int = kit._index.get((hit.collider as Object).get_instance_id(), -1)
		if j >= 0:
			out.append([String(kit.names[j]).get_file(), to_hull * (hit.position as Vector3), (to_hull.basis * (hit.normal as Vector3)).normalized()])
	return out


func _run() -> void:
	var r := 4.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--r="):
			r = float(arg.trim_prefix("--r="))
	Seat.track_override = "range"
	Seat.job_override = "none"
	Seat.camera = "cockpit"
	Seat._camera_loaded = true
	Seat._nose_loaded = true
	Seat._slide_loaded = true
	Seat._startup_loaded = true
	Seat.cold_start = false
	Seat._map_loaded = true
	Seat._school_loaded = true
	Seat.vehicle_override = "orrery"
	var v = Seat.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	for i in 4:
		v._process(1.0 / 120.0)
	var rig: Node3D = v.rig
	var hull: Node3D = v.shell.get_node("PodHull")
	var to_hull_g: Transform3D = hull.global_transform.affine_inverse()
	var eye_g: Vector3 = rig.global_transform * Seat.EYE
	print("PROBE ORB SIGHT: eye in the hull's frame %s" % [to_hull_g * eye_g])
	var canopy: Node3D = v.canopy
	var header: Node3D = canopy.find_child("Header", true, false)
	var kit := ClashKit.new()
	kit.gather_part(rig, canopy)
	kit.arm(root)
	await physics_frame
	await physics_frame
	var space := root.world_3d.direct_space_state
	var to_rig: Transform3D = rig.global_transform.affine_inverse()
	var from_hull: Transform3D = to_rig * hull.global_transform
	var to_hull: Transform3D = from_hull.affine_inverse()
	var eye_h: Vector3 = to_hull * Seat.EYE
	for bearing in [90.0, 60.0, 30.0, 0.0, 270.0]:
		var said := []
		for el in range(-10, 90, 5):
			var a := deg_to_rad(bearing)
			var e := deg_to_rad(float(el))
			var d := Vector3(cos(a) * cos(e), sin(e), -sin(a) * cos(e))
			var parts := []
			for h: Array in _hits(kit, space, Seat.EYE, from_hull * (eye_h + d * 6.0), to_hull):
				if h[0] == "field":
					continue
				parts.append("%s at (%.2f, %.2f, %.2f) n (%.2f, %.2f, %.2f)" % [h[0], h[1].x, h[1].y, h[1].z, h[2].x, h[2].y, h[2].z])
			said.append("  el %d: %s" % [el, ", ".join(parts)])
		print(" bearing %.0f (0 right, 90 ahead):\n%s" % [bearing, "\n".join(said)])
	for h in [2.8, 3.0, 3.2, 3.4, 3.5, 3.6, 3.7, 3.8, 4.0]:
		var front := []
		for k in 72:
			var a := TAU * k / 72.0
			var p := from_hull * Vector3(r * cos(a), h, -r * sin(a))
			for hit: Array in _hits(kit, space, Seat.EYE, p, to_hull):
				if hit[0] == "roof_glass" and (hit[1] as Vector3).z < 0.27:
					front.append(k * 5)
					break
		print("  ring r %.1f at %.1f m over the cab: bearings through the glass forward of z 0.27: %s" % [r, h, front])
	kit.free_bodies()
	v.free()
	await process_frame
	quit(0)
