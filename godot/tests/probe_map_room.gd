## The room round the map's pod (Luke, flight 34: "the left lever collides with the map at 90-100% throttle"): where
## the roof's port pillar runs behind the pod's controls strip, by height (the middle of its section, and its
## extent), and where the coaming's inner face stands beside the pod, in the standard cockpit's frame (floor
## origin, forward -Z, metres; the shell's own, before the pod's pitch).
## --headless --xr-mode off --audio-driver Dummy -s res://tests/probe_map_room.gd -- --mute
extends SceneTree

const VR := preload("res://vr/vr_cockpit.gd")
const Sim := preload("res://sim/craft_sim.gd")


func _initialize() -> void:
	_run.call_deferred()


func _points(top: Node3D, node: Node, box: AABB) -> PackedVector3Array:
	var out := PackedVector3Array()
	var inv := top.global_transform.affine_inverse()
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as Node3D).visible:
			var xf: Transform3D = inv * (n as MeshInstance3D).global_transform
			for p in (n as MeshInstance3D).mesh.get_faces():
				var q: Vector3 = xf * p
				if box.has_point(q):
					out.append(q)
		stack.append_array(n.get_children())
	return out


func _run() -> void:
	VR._nose_loaded = true
	var cockpit = VR.new()
	cockpit.sim = Sim.new({"track": "range"})
	cockpit.rig = Node3D.new()
	root.add_child(cockpit.rig)
	cockpit._build_cockpit()
	await process_frame
	var shell: Node3D = cockpit.shell
	var roof: Node = cockpit.canopy.get_node_or_null("roof")
	var box := AABB(Vector3(-0.75, 0.5, -0.3), Vector3(0.5, 0.4, 0.5))
	if roof:
		var pts := _points(shell, roof, box)
		print("ROOM roof points in the box: %d" % pts.size())
		for k in 16:
			var y0 := 0.5 + k * 0.025
			var lo := Vector3(INF, INF, INF)
			var hi := -lo
			var n := 0
			for p in pts:
				if p.y >= y0 and p.y < y0 + 0.025:
					lo = lo.min(p)
					hi = hi.max(p)
					n += 1
			if n > 0:
				print("ROOM pillar y %.3f..%.3f: x %.3f..%.3f  z %.3f..%.3f  (%d)" % [y0, y0 + 0.025, lo.x, hi.x, lo.z, hi.z, n])
	var coaming: Node = cockpit.interior.get_node_or_null("SegmentedCoaming")
	if coaming:
		var pts := _points(shell, coaming, AABB(Vector3(-0.8, 0.4, -0.2), Vector3(0.4, 0.35, 0.45)))
		for k in 8:
			var z0 := -0.2 + k * 0.05
			for j in 7:
				var y0 := 0.4 + j * 0.05
				var inner := -INF
				for p in pts:
					if p.z >= z0 and p.z < z0 + 0.05 and p.y >= y0 and p.y < y0 + 0.05:
						inner = maxf(inner, p.x)
				if inner > -INF:
					print("ROOM coaming z %.2f..%.2f y %.2f..%.2f: inner face at x %.3f" % [z0, z0 + 0.05, y0, y0 + 0.05, inner])
	# the port console's inboard face, forward: how far out it stands (a ray from inboard), by height and station
	var console := cockpit.interior.get_node_or_null("ConsoleL") as MeshInstance3D
	if console:
		var tm := console.mesh.generate_triangle_mesh()
		var into: Transform3D = (shell.global_transform.affine_inverse() * console.global_transform).affine_inverse()
		for zi in 14:
			var z := -0.02 + zi * 0.025
			var line := "ROOM console face z %.3f:" % z
			for yi in 8:
				var y := 0.2 + yi * 0.025
				var hit := tm.intersect_ray(into * Vector3(-0.3, y, z), into.basis * Vector3.LEFT)
				line += "  y %.3f %s" % [y, ("x %.3f" % (into.affine_inverse() * (hit.position as Vector3)).x) if not hit.is_empty() else "-"]
			print(line)
	cockpit.rig.free()
	cockpit.free()
	quit()
