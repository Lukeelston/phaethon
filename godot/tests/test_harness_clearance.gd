## Check the visible shoulder-webbing triangles against the actual imported seat.
extends SceneTree
const VR := preload("res://vr/vr_cockpit.gd")
const Sim := preload("res://sim/craft_sim.gd")
const Deck := preload("res://vr/fleet_flight_deck.gd")
const Model := preload("res://view/craft_model.gd")
const Fleet := preload("res://view/fleet_airframe.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for id in ["orrery", "kiln", "vesper", "basilisk"]:
		var cockpit := VR.new()
		cockpit.sim = Sim.new({"track":"range", "vehicle":id})
		cockpit.craft = Model.new()
		cockpit.craft.fleet = Fleet.new(id)
		cockpit.rig = Node3D.new()
		root.add_child(cockpit.rig)
		cockpit._build_cockpit()
		var seat := cockpit.shell.find_child("FleetSeat", true, false) as MeshInstance3D
		var harness := cockpit.interior.get_node("Harness") as MeshInstance3D
		var seats := [[seat.mesh.generate_triangle_mesh(), Deck._relative(seat, cockpit.interior)]]
		var a := harness.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var points := v.duplicate()
		# A strap can clip between its samples; inspect triangle centres as well.
		var normals := n.duplicate()
		var count := indices.size() if not indices.is_empty() else v.size()
		for i in range(0, count, 3):
			var j := [i,i+1,i+2] if indices.is_empty() else [indices[i],indices[i+1],indices[i+2]]
			points.append((v[j[0]]+v[j[1]]+v[j[2]])/3.0)
			normals.append((n[j[0]]+n[j[1]]+n[j[2]]).normalized())
		var checked := 0
		var buried := 0
		var worst := 0.0
		for i in points.size():
			var p := points[i]
			if p.y < .35 or p.y > .83 or absf(p.x) > .17 or normals[i].z > -.35:
				continue
			var hit := Deck._drop(seats, Vector3(p.x,p.y,.45),Vector3.BACK)
			if hit.is_empty():
				continue
			checked += 1
			var depth: float = p.z-hit.position.z
			worst = maxf(worst,depth)
			buried += int(depth > .001)
		var ok := checked > 100 and buried == 0
		print("PASS " if ok else "FAIL ", id, " shoulder webbing: ",checked," samples, ",buried," buried, worst ",worst*1000.0," mm")
		failures += int(not ok)
		cockpit.rig.free()
		cockpit.craft.free()
		cockpit.free()
	print("HARNESS CLEARANCE ","PASS" if failures==0 else "FAIL")
	quit(int(failures>0))
