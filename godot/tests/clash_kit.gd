## Where the cockpit's meshes pass through each other, and how far apart two of them stand: the
## working parts of tests/probe_cockpit_clash.gd and tests/test_cockpit_clash.gd. Every drawn mesh under
## a node is given a triangle collider in that node's own frame; an edge of one mesh that crosses
## another's surface is a place where the two pass through each other.
##   var kit := ClashKit.new(); kit.gather(cockpit.rig); kit.arm(root)      then, after two physics frames:
##   kit.crossings(space)                  every pair that crosses: {"a|b": {a, b, n, lo, hi, samples}}
##   kit.gap(space, "pod", "SlideSwitch")  the least distance between two groups of parts (by name), m
##   kit.sight(space, eye, point)          the parts a straight line between two points passes through
##   kit.free_bodies()
extends RefCounted

const INSET := 0.0004   # m: an edge is cast this far short of each end, so it does not find its own neighbours
const REACH := 0.05     # m: gap() looks no further than this

var names: Array[String] = []            # part -> its label (the node's path under the root, scripts' names for unnamed nodes)
var soups: Array[PackedVector3Array] = []   # part -> its triangles, in the root's frame
var nodes: Array[MeshInstance3D] = []
var rids: Array[RID] = []
var _index := {}                         # collider instance id -> part
var _holder: Node3D


static func label(node: Node, top: Node) -> String:
	var parts := PackedStringArray()
	var n := node
	while n != null and n != top:
		var s := String(n.name)
		if s.begins_with("@") or s == n.get_class():
			var script: Script = n.get_script()
			s = script.resource_path.get_file().get_basename() if script != null and script.resource_path != "" else n.get_class()
		parts.insert(0, s)
		n = n.get_parent()
	return "/".join(parts)


## Every visible mesh under `top`, as triangles in top's frame.
func gather(top: Node3D) -> void:
	_gather(top, top, top.global_transform.affine_inverse())


## ... or just those under one of its fittings (still in top's frame, and named from it).
func gather_part(top: Node3D, part: Node) -> void:
	_gather(part, top, top.global_transform.affine_inverse())


func _gather(node: Node, top: Node3D, inv: Transform3D) -> void:
	if node is Node3D and not (node as Node3D).visible:
		return
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		var faces: PackedVector3Array = mi.mesh.get_faces()
		if faces.size() >= 3:
			var xf: Transform3D = inv * mi.global_transform
			var soup := PackedVector3Array()
			soup.resize(faces.size())
			for i in faces.size():
				soup[i] = xf * faces[i]
			names.append(label(mi, top))
			soups.append(soup)
			nodes.append(mi)
	for child in node.get_children():
		_gather(child, top, inv)


## The colliders, under `parent` (at the world's origin). Two physics frames later the space answers.
func arm(parent: Node) -> void:
	_holder = Node3D.new()
	parent.add_child(_holder)
	for i in soups.size():
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(soups[i])
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		_holder.add_child(body)
		_index[body.get_instance_id()] = i
		rids.append(body.get_rid())


func free_bodies() -> void:
	if _holder:
		_holder.free()
		_holder = null


func triangles() -> int:
	var n := 0
	for soup in soups:
		n += soup.size() / 3
	return n


## The parts whose label contains `word`.
func group(word: String) -> Array[int]:
	var out: Array[int] = []
	for i in names.size():
		if names[i].contains(word):
			out.append(i)
	return out


## Every pair of parts with an edge of one through the other's surface: "a|b" (part numbers, a < b) ->
## {a, b: labels; n: edges that cross; lo, hi: the box the crossings fill; samples: up to 400 of them}.
## `with_self`: a part's own edges through its own surface too (only square crossings count: an edge
## lying along a neighbouring face is not one). `only`: just the edges of these parts.
func crossings(space: PhysicsDirectSpaceState3D, with_self := false, only: Array[int] = []) -> Dictionary:
	var pairs := {}
	var q := PhysicsRayQueryParameters3D.new()
	q.hit_back_faces = true
	q.hit_from_inside = false
	for i in soups.size():
		if not only.is_empty() and not only.has(i):
			continue
		var soup := soups[i]
		for t in range(0, soup.size(), 3):
			for e in 3:
				var a: Vector3 = soup[t + e]
				var b: Vector3 = soup[t + (e + 1) % 3]
				var d := b - a
				var length := d.length()
				if length < INSET * 4.0:
					continue
				d /= length
				q.from = a + d * INSET
				q.to = b - d * INSET
				q.exclude = []
				for again in 4:
					var hit := space.intersect_ray(q)
					if hit.is_empty():
						break
					var j: int = _index.get((hit.collider as Object).get_instance_id(), -1)
					q.exclude = q.exclude + [hit.rid]
					if j < 0:
						continue
					if j == i and (not with_self or absf((hit.normal as Vector3).dot(d)) < 0.2):
						continue
					var key := "%d|%d" % [mini(i, j), maxi(i, j)]
					var p: Vector3 = hit.position
					if not pairs.has(key):
						pairs[key] = {"a": names[mini(i, j)], "b": names[maxi(i, j)], "n": 0, "lo": p, "hi": p, "samples": []}
					var rec: Dictionary = pairs[key]
					rec.n += 1
					rec.lo = (rec.lo as Vector3).min(p)
					rec.hi = (rec.hi as Vector3).max(p)
					if (rec.samples as Array).size() < 400:
						(rec.samples as Array).append(p)
	return pairs


## What stands between two points: the labels of the parts a straight line from one to the other passes through.
func sight(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Array[String]:
	var seen: Array[String] = []
	var q := PhysicsRayQueryParameters3D.new()
	q.hit_back_faces = true
	q.hit_from_inside = false
	q.from = from
	q.to = to
	for again in 24:
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		q.exclude = q.exclude + [hit.rid]
		var j: int = _index.get((hit.collider as Object).get_instance_id(), -1)
		if j >= 0:
			seen.append(names[j])
	return seen


## How many edges cross between the parts named `a` and those named `b` (0: the two groups are apart).
func crossing_edges(space: PhysicsDirectSpaceState3D, a: String, b: String) -> int:
	var ga := group(a)
	var gb := group(b)
	var n := 0
	var both: Array[int] = []
	both.append_array(ga)
	both.append_array(gb)
	var found := crossings(space, false, both)
	for key: String in found:
		var i := int(key.get_slice("|", 0))
		var j := int(key.get_slice("|", 1))
		if (ga.has(i) and gb.has(j)) or (ga.has(j) and gb.has(i)):
			n += int(found[key].n)
	return n


## The least distance between the parts named `a` and those named `b`: from every vertex of each to
## the other's surface, to half a millimetre; REACH when they are further apart than that. Answers
## [metres, where (a point on one of them)].
func gap(space: PhysicsDirectSpaceState3D, a: String, b: String) -> Array:
	var best := REACH
	var where := Vector3.ZERO
	var ga := group(a)
	var gb := group(b)
	for turn in 2:
		var from: Array[int] = ga if turn == 0 else gb
		var to: Array[int] = gb if turn == 0 else ga
		var others: Array[RID] = []
		var box := AABB()
		var first := true
		for j in to:
			for p in soups[j]:
				if first:
					box = AABB(p, Vector3.ZERO)
					first = false
				else:
					box = box.expand(p)
		box = box.grow(REACH)
		for k in rids.size():
			if not to.has(k):
				others.append(rids[k])
		var sphere := SphereShape3D.new()
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = sphere
		q.exclude = others
		var seen := {}
		for i in from:
			for p in soups[i]:
				if not box.has_point(p):
					continue
				var key := Vector3i(roundi(p.x * 5000.0), roundi(p.y * 5000.0), roundi(p.z * 5000.0))
				if seen.has(key):
					continue
				seen[key] = true
				q.transform = Transform3D(Basis.IDENTITY, p)
				sphere.radius = best
				if space.intersect_shape(q, 1).is_empty():
					continue
				var lo := 0.0
				var hi := best
				while hi - lo > 0.0005:
					var mid := (lo + hi) * 0.5
					sphere.radius = mid
					if space.intersect_shape(q, 1).is_empty():
						lo = mid
					else:
						hi = mid
				if hi < best:
					best = hi
					where = p
	return [best, where]
