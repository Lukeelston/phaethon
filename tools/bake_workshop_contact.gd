## Rebuild with Godot --headless --path godot --script ../tools/bake_workshop_contact.gd.
## The mask maps the complete floor in local X/Z. No runtime geometry is kept.
extends SceneTree

const Garage := preload("res://garage/garage_environment.gd")
const SIZE := Vector2i(1280, 864)
const FLOOR := Vector2(Garage.HALF_X * 2.0, Garage.HALF_Z * 2.0)
const OUTPUT := "res://garage/workshop_contact.png"

# Capture the physical footplates and low ties before they are instanced.
class BakeGarage extends Garage:
	var shoes: Array[PackedVector2Array] = []
	var ties: Array[PackedVector2Array] = []

	func _box(finish: String, at: Vector3, size: Vector3, frame := Basis.IDENTITY) -> void:
		super._box(finish, at, size, frame)
		if finish != "Steel" or at.y > .09 or size.x > 1.0 or size.z > 2.0:
			return
		var corners := PackedVector2Array()
		for x in [-.5, .5]:
			for z in [-.5, .5]:
				var p := at + frame * Vector3(size.x * x, 0.0, size.z * z)
				corners.append(Vector2(p.x, p.z))
		if at.y - size.y * .5 >= .01:
			ties.append(corners)

	func _batch_structure() -> void:
		var plate := _equipment_meshes["SaddleBase"].get_aabb()
		for mount: Transform3D in _instances["SaddleBase"]:
			var foot := PackedVector2Array()
			for x: float in [plate.position.x,plate.end.x]:
				for z: float in [plate.position.z,plate.end.z]:
					var corner := mount * Vector3(x,0,z)
					foot.append(Vector2(corner.x,corner.z))
			shoes.append(foot)
		super._batch_structure()

var mask := Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_L8)
var failed := false


func _initialize() -> void:
	call_deferred("_bake")


func _bake() -> void:
	mask.fill(Color.WHITE)
	var garage := BakeGarage.new()
	root.add_child(garage)
	for id: String in Garage.Pilot.ORDER:
		var bay := garage.bay_node(id)
		_stamp(_outline(bay.model.pod), .68, .88, .49)
		for engine: Node3D in bay.model.engines:
			_stamp(_outline(engine.get_child(0)), .73, 1.02, .40)
	for foot in garage.shoes:
		_stamp(foot, .025, .16, .76)
	for tie in garage.ties:
		_stamp(tie, .04, .19, .49)
	var cabinets := 0
	var benches := 0
	# In a headless bake the renderer does not retain MultiMesh transforms.
	# Use the six fixed collision feet for the bolted marker bases.
	var marker_feet := garage._building.find_children("MarkerFoot*", "CollisionShape3D", false, false)
	for shape: CollisionShape3D in marker_feet:
		var box := shape.shape as BoxShape3D
		var foot := PackedVector2Array()
		for x: float in [-.5, .5]:
			for z: float in [-.5, .5]:
				var corner := shape.transform * Vector3(x*box.size.x, 0, z*box.size.z)
				foot.append(Vector2(corner.x,corner.z))
		_stamp(foot,.035,.19,.71)
	for node in garage.get_children():
		if node is not MeshInstance3D:
			continue
		if str(node.name).begins_with("MachineBench"):
			_stamp(_outline(node, 0.0, .08), .12, .28, .73)
			benches += 1
		elif str(node.name).begins_with("RollCabinet"):
			_stamp(_outline(node, .18, .64), .12, .33, .50)
			for x in [-1, 1]:
				for z in [-1, 1]:
					_stamp(_outline(node, -.01, .06, Vector2i(x,z)), .025, .12, .73)
			cabinets += 1
	if garage.shoes.size() != 72 or marker_feet.size() != 6:
		push_error("Garage bake missing a trestle or bay marker footprint")
		failed = true
	if failed:
		garage.free()
		quit(1)
		return
	var result := mask.save_png(OUTPUT)
	print("Workshop contact bake: %d craft, %d footplates, %d marker feet, %d ties, %d cabinets, %d benches, %s" %
		[Garage.Pilot.ORDER.size(), garage.shoes.size(), marker_feet.size(), garage.ties.size(), cabinets, benches, error_string(result)])
	garage.free()
	quit(0 if result == OK else 1)


# Project the actual silhouette, including tapered tails and asymmetric fairings.
# For a cabinet, the low vertices in each quadrant isolate the individual tires.
func _outline(piece: MeshInstance3D, low := -INF, high := INF, quadrant := Vector2i.ZERO) -> PackedVector2Array:
	var points := PackedVector2Array()
	for surface in piece.mesh.get_surface_count():
		var arrays := piece.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var used := PackedByteArray()
		used.resize(vertices.size())
		for index in indices:
			used[index] = 1
		for i in vertices.size():
			if not indices.is_empty() and used[i] == 0:
				continue
			var vertex := vertices[i]
			if not vertex.is_finite() or vertex.length_squared() > 12.0 * 12.0:
				push_error("Implausible garage mesh vertex %s on %s. Correct the source mesh before rebuilding the contact mask." % [vertex,piece.get_path()])
				failed = true
				return PackedVector2Array()
			if vertex.y < low or vertex.y > high:
				continue
			if quadrant != Vector2i.ZERO and (vertex.x * quadrant.x <= 0.0 or vertex.z * quadrant.y <= 0.0):
				continue
			var world := piece.global_transform * vertex
			points.append(Vector2(world.x, world.z))
	return points


# Fade across both sides of the projected edge. Use the darker occluder where
# footprints meet so the saddle and hull do not count the same blocked light twice.
func _stamp(points: PackedVector2Array, inner: float, outer: float, density: float) -> void:
	if points.size() < 3:
		if not failed:
			push_error("Empty contact footprint")
		failed = true
		return
	var hull := Geometry2D.convex_hull(points)
	var bounds := Rect2(hull[0], Vector2.ZERO)
	var planes := PackedVector3Array()
	var center := Vector2.ZERO
	for i in hull.size()-1:
		center += hull[i]
		bounds = bounds.expand(hull[i])
	center /= hull.size()-1
	for i in hull.size()-1:
		var a := hull[i]
		var b := hull[i+1]
		var n := (b-a).orthogonal().normalized()
		if n.dot(center-a) > 0.0:
			n = -n
		planes.append(Vector3(n.x, n.y, -n.dot(a)))
	bounds = bounds.grow(outer)
	var lo := Vector2i(((bounds.position / FLOOR + Vector2(.5,.5)) * Vector2(SIZE)).floor()).max(Vector2i.ZERO)
	var hi := Vector2i(((bounds.end / FLOOR + Vector2(.5,.5)) * Vector2(SIZE)).ceil()).min(SIZE)
	for z in range(lo.y, hi.y):
		for x in range(lo.x, hi.x):
			var p := ((Vector2(x+.5,z+.5) / Vector2(SIZE)) - Vector2(.5,.5)) * FLOOR
			var distance_to_edge := -INF
			for plane in planes:
				distance_to_edge = maxf(distance_to_edge, plane.x*p.x + plane.y*p.y + plane.z)
			var visibility := 1.0 - density * (1.0 - smoothstep(-inner, outer, distance_to_edge))
			if visibility < mask.get_pixel(x,z).r:
				mask.set_pixel(x,z,Color(visibility,visibility,visibility))
