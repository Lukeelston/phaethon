## Where the left throttle lever meets the map's pod, and how far the pilot reaches to the power's controls (Luke,
## flight 34: "I think they should go somewhere more reachable up front. Pressing it beside the leg is awkward - also
## been meaning to tell you the left lever collides with the map at 90-100% throttle"). For each pilot craft's
## production cockpit (or --vehicle=<id>):
##   fittings  the boxes (cockpit metres: floor origin, forward -Z) of the parts near the left lever and the map
##   sweep     the left lever 0 to 100% in 5% steps: edges of its shaft, grip and boot through the map's pod and its
##             arm, and the least gap between them
##   reach     from the left grip at idle, mid and full throttle and from the left shoulder (the eye + (-0.18, -0.2,
##             0.05), as probe_pod_pitch.gd) to the POWER switch's bat and the button's cap, and to --at= points
##   spots     --spot=name:x,y,z (no spaces): from the eye toward it, the surface it meets (the levers looked through),
##             the reach to that, and at which throttles the left lever stands before it (the places weighed for the
##             power's controls: tests/test_cockpit_reach.gd)
## What ifs: --map=dist,yaw,pitch[,tilt] (m, degrees: the map's pod elsewhere, as MapPanel.mount), --lever=dx,dz[,dy]
## (both levers' pivots moved inboard, aft, up), --sweep-from=N (the sweep from N x 5%).
## --headless --xr-mode off --audio-driver Dummy -s res://tests/probe_power_reach.gd -- --mute [--vehicle=kiln]
##     [--at=name:x,y,z ...] [--spot=name:x,y,z ...] [--no-sweep]
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Craft := preload("res://sim/pilot_craft.gd")
const ClashKit := preload("res://tests/clash_kit.gd")
const Switch := preload("res://vr/mode_switch.gd")
const MapPanel := preload("res://vr/minimap_panel.gd")
var map_pose := []
var sweep_from := 0
var lever_shift := Vector3.ZERO
var spots := {}


func _initialize() -> void:
	View.track_override = "range"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("probe_power_reach_")
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true
	Cockpit._nose_loaded = true
	Cockpit._slide_loaded = true
	Cockpit._rush_loaded = true
	Cockpit._startup_loaded = true
	Cockpit._map_loaded = true
	Cockpit._school_loaded = true
	Cockpit._options_loaded = true
	Cockpit._power_loaded = true
	Cockpit.cold_start = false
	Cockpit.school = false
	_run.call_deferred()


func _box(rig: Node3D, node: Node) -> AABB:
	var inv := rig.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and not (n as Node3D).visible:
			continue
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var xf: Transform3D = inv * mi.global_transform
			for p in mi.mesh.get_faces():
				var q: Vector3 = xf * p
				if first:
					box = AABB(q, Vector3.ZERO)
					first = false
				else:
					box = box.expand(q)
		stack.append_array(n.get_children())
	return box


func _v(p: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [p.x, p.y, p.z]


func _b(b: AABB) -> String:
	return "%s .. %s" % [_v(b.position), _v(b.end)]


func _run() -> void:
	var only := ""
	var extra := {}
	var sweep := true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--vehicle="):
			only = arg.trim_prefix("--vehicle=")
		if arg.begins_with("--at="):
			var bits := arg.trim_prefix("--at=").split(":")
			var f := bits[1].split_floats(",")
			extra[bits[0]] = Vector3(f[0], f[1], f[2])
		if arg == "--no-sweep":
			sweep = false
		if arg.begins_with("--spot="):
			var bits := arg.trim_prefix("--spot=").split(":")
			var f := bits[1].split_floats(",")
			spots[bits[0]] = Vector3(f[0], f[1], f[2])
		if arg.begins_with("--map="):      # what if: the map's pod at another distance, yaw, pitch, tilt (m, degrees)
			var f := arg.trim_prefix("--map=").split_floats(",")
			map_pose = [f[0], deg_to_rad(f[1]), deg_to_rad(f[2]), MapPanel.SCALE, deg_to_rad(f[3]) if f.size() > 3 else MapPanel.TILT]
		if arg.begins_with("--lever="):      # what if: both levers' pivots moved inboard (dx, mirrored) and aft (dz), and dy up
			var f := arg.trim_prefix("--lever=").split_floats(",")
			lever_shift = Vector3(f[0], f[2] if f.size() > 2 else 0.0, f[1])
		if arg.begins_with("--sweep-from="):
			sweep_from = int(arg.trim_prefix("--sweep-from="))
	for id: String in Craft.ORDER:
		if only != "" and id != only:
			continue
		View.vehicle_override = id
		var v = Cockpit.new()
		root.add_child(v)
		await process_frame
		v.set_process(false)
		if not map_pose.is_empty():
			var was: Node3D = v.minimap_panel
			var fresh = MapPanel.new()
			was.get_parent().add_child(fresh)
			var dir := Vector3(-sin(map_pose[1]) * cos(map_pose[2]), sin(map_pose[2]), -cos(map_pose[1]) * cos(map_pose[2]))
			var face := Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.RIGHT, float(map_pose[4]))
			fresh.transform = Transform3D(face.scaled(Vector3.ONE * float(map_pose[3])), Cockpit.SEAT + dir * float(map_pose[0]))
			fresh.build(v.aux_meter != null)
			was.free()
			v.minimap_panel = fresh
			print("REACH %s: the map's pod at %.3f m, %.1f deg left, %.1f deg down, from the seat, tipped %.0f deg" % [id, map_pose[0], rad_to_deg(map_pose[1]), -rad_to_deg(map_pose[2]), rad_to_deg(map_pose[4])])
		var rig: Node3D = v.rig
		var to_rig := rig.global_transform.affine_inverse()
		if lever_shift != Vector3.ZERO:
			for k in 2:
				var s := -1.0 if k == 0 else 1.0
				v.lever_pivots[k].position += Vector3(-s * lever_shift.x, lever_shift.y, lever_shift.z)
				if not v.throttle_gaiters.is_empty():
					v.throttle_gaiters[k].position = v.lever_pivots[k].position
			print("REACH %s: the levers moved %s" % [id, lever_shift])
		print("== %s" % id)
		var pivot: Node3D = v.lever_pivots[0]
		var boot: Node3D = v.throttle_gaiters[0] if not v.throttle_gaiters.is_empty() else null
		print("REACH %s lever pivot L %s, boot %s" % [id, _v(pivot.position), "yes" if boot else "no"])
		var named := {"map panel": v.minimap_panel, "map pod": v.minimap_panel.get_node_or_null("pod"), "map arm": v.minimap_panel.get_node_or_null("arm"),
			"map controls": v.minimap_panel.get_node_or_null("controls"), "SLIDE switch": v.slide_switch, "MODE switch": v.mode_switch, "drift slider": v.drift_slider,
			"POWER switch": v.power_switch, "POWER button": v.power_button, "dashboard": v.dashboard, "console L": v.interior.get_node_or_null("ConsoleL"),
			"dash": v.interior.get_node_or_null("Dashboard"), "coaming": v.interior.get_node_or_null("SegmentedCoaming"), "hull": v.shell.get_node_or_null("PodHull"),
			"aux meter": v.aux_meter, "sill fittings": v.interior.get_node_or_null("SillFittings"), "canopy": v.canopy}
		for k: String in named:
			if named[k] != null:
				print("REACH %s box %-14s %s" % [id, k, _b(_box(rig, named[k]))])
		for k in v.dashboard.get_children():
			if k is Node3D:
				print("REACH %s   dashboard part %-20s %s" % [id, k.name, _b(_box(rig, k))])
		for thr in [0.0, 0.5, 0.9, 1.0]:
			pivot.rotation.x = deg_to_rad(lerpf(30.0, -30.0, thr))
			if boot:
				(boot as Skeleton3D).set_bone_pose_rotation(1, pivot.quaternion)
			var grip: Node3D = pivot.get_node("PilotGrip")
			print("REACH %s lever L at %3.0f%%: grip %s, box %s" % [id, thr * 100.0, _v(to_rig * grip.global_position), _b(_box(rig, grip))])

		# ---- reach
		var eye: Vector3 = Cockpit.EYE
		var shoulder := eye + Vector3(-0.18, -0.2, 0.05)
		var targets := {"POWER switch bat": to_rig * (v.power_switch.global_transform * Vector3(0.0, 0.0, 0.07)),
			"POWER button cap": to_rig * (v.power_button.global_transform * v.power_button.face_at()),
			"SLIDE switch bat": to_rig * (v.slide_switch.global_transform * Vector3(0.0, 0.0, 0.07))}
		for k: String in extra:
			targets[k] = extra[k]
		var froms := {}
		for thr in [0.0, 0.5, 1.0]:
			pivot.rotation.x = deg_to_rad(lerpf(30.0, -30.0, thr))
			froms["grip %.0f%%" % (thr * 100.0)] = to_rig * (pivot.global_transform * Vector3(0.0, 0.36, 0.0))
		froms["shoulder"] = shoulder
		for t: String in targets:
			var line := "REACH %s %-18s %s:" % [id, t, _v(targets[t])]
			for f: String in froms:
				line += "  from %s %.3f" % [f, (froms[f] as Vector3).distance_to(targets[t])]
			var seen: Vector3 = (targets[t] as Vector3) - eye
			line += "  | from the eye %.0f deg left, %.0f deg down" % [rad_to_deg(atan2(-seen.x, -seen.z)), rad_to_deg(-asin(seen.y / seen.length()))]
			print(line)

		# ---- the spots: from the eye toward each --spot=name:x,y,z, the surface it meets (what part, where, which way it
		# faces), and the reach to it; with the left lever at idle, half and full, what (if anything) of it hides the spot
		if not spots.is_empty():
			var kit := ClashKit.new()
			kit.gather(rig)
			kit.arm(root)
			await physics_frame
			await physics_frame
			var space := root.world_3d.direct_space_state
			var q := PhysicsRayQueryParameters3D.new()
			q.hit_back_faces = true
			var aims := spots.duplicate()
			for name: String in aims:
				var aim: Vector3 = aims[name]
				q.from = eye
				q.to = eye + (aim - eye).normalized() * 2.0
				q.exclude = []
				var hit := {}
				for again in 16:      # (the first hit that is not one of the levers: they move)
					var h := space.intersect_ray(q)
					if h.is_empty():
						break
					var part := String(kit.names[int(kit._index.get((h.collider as Object).get_instance_id(), 0))])
					if part.contains("PilotGrip") or part.begins_with("shell/Node3D") or part.contains("ThrottleBoot") or part.contains("XROrigin3D"):
						q.exclude = q.exclude + [h.rid]
						continue
					hit = h
					hit["part"] = part
					break
				if hit.is_empty():
					print("SPOT %s %-22s nothing toward %s" % [id, name, _v(aim)])
					continue
				var at: Vector3 = hit.position
				spots[name] = at
				var line := "SPOT %s %-22s on %s at %s facing %s:" % [id, name, String(hit.part).trim_prefix("shell/"), _v(at), _v(hit.normal)]
				for f: String in froms:
					line += " %s %.3f," % [f, (froms[f] as Vector3).distance_to(at)]
				var seen: Vector3 = at - eye
				line += " | %.0f deg left, %.0f deg down, %.2f m from the eye" % [rad_to_deg(atan2(-seen.x, -seen.z)), rad_to_deg(-asin(seen.y / seen.length())), seen.length()]
				print(line)
			kit.free_bodies()
			# what of the left lever (grip, shaft) hides each spot, through its travel
			for name: String in spots:
				var hidden := []
				for thr in [0.0, 0.25, 0.5, 0.75, 0.9, 1.0]:
					pivot.rotation.x = deg_to_rad(lerpf(30.0, -30.0, thr))
					if boot:
						(boot as Skeleton3D).set_bone_pose_rotation(1, pivot.quaternion)
					var lk := ClashKit.new()
					lk.gather_part(rig, pivot)
					lk.arm(root)
					await physics_frame
					await physics_frame
					if not lk.sight(root.world_3d.direct_space_state, eye, eye + ((spots[name] as Vector3) - eye) * 0.98).is_empty():
						hidden.append("%.0f%%" % (thr * 100.0))
					lk.free_bodies()
				print("SPOT %s %-22s behind the left grip at: %s" % [id, name, hidden])

		# ---- the sweep: the left lever against the map's pod and arm
		if sweep:
			var worst := ClashKit.REACH
			var worst_at := -1.0
			for step in range(sweep_from, 21):
				var thr := step / 20.0
				pivot.rotation.x = deg_to_rad(lerpf(30.0, -30.0, thr))
				if boot:
					(boot as Skeleton3D).set_bone_pose_rotation(1, pivot.quaternion)
				pivot.name = "LeverL"
				var kit := ClashKit.new()
				kit.gather_part(rig, pivot)
				if boot:
					kit.gather_part(rig, boot)
				kit.gather_part(rig, v.minimap_panel)
				kit.arm(root)
				await physics_frame
				await physics_frame
				var space := root.world_3d.direct_space_state
				var parts := []
				for word in ["LeverL", "ThrottleBootL"]:
					if kit.group(word).is_empty():
						continue
					var through: int = kit.crossing_edges(space, word, "minimap_panel")
					var g: Array = kit.gap(space, word, "minimap_panel")
					parts.append("%s %d edges through, %s mm at %s" % [word, through, ("over 50" if float(g[0]) >= ClashKit.REACH else "%.1f" % (float(g[0]) * 1000.0)), _v(g[1])])
					worst = minf(worst, -1.0 if through > 0 else float(g[0]))
					if through > 0 and worst_at < 0.0:
						worst_at = thr
				var hits := kit.crossings(space)
				var who := []
				for key: String in hits:
					var rec: Dictionary = hits[key]
					var a := String(rec.a)
					var b := String(rec.b)
					if (a.contains("minimap_panel")) != (b.contains("minimap_panel")):
						who.append("%s >< %s (%d)" % [a.trim_prefix("shell/"), b.trim_prefix("shell/"), rec.n])
				# how deep the grip goes in behind the screen's glass, inside its outline (panel metres, unscaled)
				var into_panel: Transform3D = v.minimap_panel.global_transform.affine_inverse()
				var deepest := 0.0
				var low_y := INF
				var stack: Array = [pivot]
				while not stack.is_empty():
					var n: Node = stack.pop_back()
					if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
						var xf: Transform3D = into_panel * (n as MeshInstance3D).global_transform
						for p in (n as MeshInstance3D).mesh.get_faces():
							var q: Vector3 = xf * p
							if absf(q.x) < MapPanel.W / 2.0 and absf(q.y) < MapPanel.H / 2.0 and q.z < 0.0:
								deepest = minf(deepest, q.z)
								low_y = minf(low_y, q.y)
					stack.append_array(n.get_children())
				if deepest < 0.0:
					parts.append("in behind the glass %.1f mm (panel units x%.2f), from %.0f mm under its middle" % [-deepest * 1000.0, MapPanel.SCALE, -low_y * 1000.0])
				print("SWEEP %s %3.0f%%: %s %s" % [id, thr * 100.0, "; ".join(parts), who])
				kit.free_bodies()
				await physics_frame
			print("SWEEP %s: %s" % [id, ("first through the map at %.0f%%" % (worst_at * 100.0)) if worst_at >= 0.0 else "clear, %.1f mm at the least" % (worst * 1000.0)])
		v.free()
		await process_frame
	View.vehicle_override = ""
	quit()
