## Actual fitting geometry: light strips must not emerge through console faces,
## the walking deck must not cut the cushion, and each throttle needs a real slot.
extends SceneTree
const Interior := preload("res://vr/cockpit_interior.gd")
const VR := preload("res://vr/vr_cockpit.gd")
const Sim := preload("res://sim/craft_sim.gd")
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	failures+=int(not ok)
func _run() -> void:
	var interior:=Interior.new()
	root.add_child(interior)
	interior.build()
	var collisions:=0
	for child in interior.get_children():
		if not child is MeshInstance3D or child.material_override!=interior.rim_mat: continue
		for point in child.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			if absf(absf(point.x)-0.615)<0.066 and point.y>0.11 and point.y<0.39 and point.z>0.0 and point.z<0.87:
				collisions+=1
	check("rim lighting stays outside console housing and face",collisions==0)
	var panels: MeshInstance3D=interior.get_node("PowderCoatedPanels")
	check("walking deck does not slice through seat cushion",not _hit(panels,Vector3(0,0.21,0.8),0.13))
	for side in [-1.0,1.0]:
		var blocked:=false
		for z in [0.14,0.2,0.26]:
			blocked=blocked or _hit(panels,Vector3(side*0.46,0.17,z),0.07)
		check("throttle slot is physically open on side %s"%side,not blocked)
	interior.free()
	for vehicle in ["phaethon", "shrike", "orrery", "kiln", "vesper"]:
		_sweep_levers(vehicle)
	print("COCKPIT ASSEMBLY ","PASS" if failures==0 else "FAIL")
	quit(int(failures>0))
func _hit(node: MeshInstance3D, origin: Vector3, reach: float) -> bool:
	var faces:=node.mesh.get_faces()
	for i in range(0,faces.size(),3):
		var hit=Geometry3D.ray_intersects_triangle(origin,Vector3.DOWN,faces[i],faces[i+1],faces[i+2])
		if hit!=null and origin.distance_to(hit)<reach: return true
	return false

func _sweep_levers(vehicle: String) -> void:
	var cockpit=VR.new()
	cockpit.sim=Sim.new({"track":"range", "vehicle":vehicle})
	cockpit.rig=Node3D.new()
	root.add_child(cockpit.rig)
	cockpit._build_cockpit()
	var panels: MeshInstance3D=cockpit.interior.get_node("PowderCoatedPanels")
	var faces:=panels.mesh.get_faces()
	for part in ["InstrumentBezel", "GuardAndGatePaint"]:
		var fitting := cockpit.interior.get_node(part) as MeshInstance3D
		for vertex in fitting.mesh.get_faces():
			faces.append(panels.to_local(fitting.to_global(vertex)))
	var nearby:=[]
	for i in range(0,faces.size(),3):
		var center: Vector3=(faces[i]+faces[i+1]+faces[i+2])/3.0
		if absf(absf(center.x)-0.46)<0.08 and center.y<0.18:
			nearby.append([faces[i],faces[i+1],faces[i+2]])
	var intersections:=0
	var segments:=0
	for pivot in cockpit.lever_pivots:
		var shaft: MeshInstance3D=pivot.get_child(0)
		var rim:={}
		# The shaft is a plain cylinder, or (realism spike) a compound with a ferrule up under the grip;
		# the ferrule never comes near the quadrant, so sweep the shaft's own radius.
		var arrays: Array=shaft.mesh.get_mesh_arrays() if shaft.mesh is PrimitiveMesh else shaft.mesh.surface_get_arrays(0)
		for vertex in arrays[Mesh.ARRAY_VERTEX]:
			if Vector2(vertex.x,vertex.z).length()<0.0165: rim[Vector2(vertex.x,vertex.z)]=true
		check("lever shaft outline found (%d points)"%rim.size(),rim.size()>=12)
		for step in 29:
			# Same idle-through-afterburner visual travel as the live cockpit.
			pivot.rotation.x=deg_to_rad(lerpf(30.0,-30.0,step*0.05))
			for point in rim:
				var a: Vector3=shaft.global_transform*Vector3(point.x,-0.16,point.y)
				var b: Vector3=shaft.global_transform*Vector3(point.x,0.16,point.y)
				for tri in nearby:
					if Geometry3D.segment_intersects_triangle(a,b,tri[0],tri[1],tri[2])!=null: intersections+=1
				segments+=1
	check("%s lever shafts clear the quadrant and gate trim across full travel (%d segments)"%[vehicle,segments],intersections==0)
	cockpit.rig.free()
	cockpit.free()
