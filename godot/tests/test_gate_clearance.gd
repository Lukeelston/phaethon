## Check the actual Network pickup placements against the built country's geometry.
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_gate_clearance.gd -- --mute
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Gates := preload("res://view/power_ups.gd")
const World := preload("res://view/network_world.gd")
const Land := preload("res://view/network_landscape.gd")
const Config := preload("res://release/release_config.gd")
const PREFS := "user://vr_prefs.json"
const CELL := 1024.0

var view
var bins := {} # cells containing a gate; an object can belong to a different road
var gates := []
var clashes := {}
var scanned := {"prop": 0, "lane": 0, "pillar": 0, "sign": 0, "pad": 0}
var saved_prefs := PackedByteArray()
var had_prefs := false


func _initialize() -> void:
	had_prefs = FileAccess.file_exists(PREFS)
	if had_prefs:
		saved_prefs = FileAccess.get_file_as_bytes(PREFS)
	View.track_override = "network"
	View.job_override = "none"
	View.spot_override = "city:ERIDANUS"
	View.best_dir = OS.get_user_data_dir().path_join("test_gate_clearance_")
	View.power_ups_on = true
	View.pad_start = true
	_run.call_deferred()


func _run() -> void:
	view = View.new()
	root.add_child(view)
	view.set_process(false)
	view.org_x = 0.0
	view.org_y = 0.0
	var sim = view.sim
	var roads := 0
	var closest := INF
	for r in sim.roads.size():
		var last := -1
		for g in view.power_ups.gates_on(r):
			if last < 0:
				roads += 1
			else:
				closest = minf(closest, (int(g.i) - last) * sim.NET_STEP)
			last = g.i
			_add_gate(g, view.power_ups.gate_xf(g))
	_lanes()
	_signs()
	_pillars()
	_props()
	_pads()
	print("checked %d gates on %d roads, minimum spacing %.0f m; objects scanned %s" % [gates.size(), roads, closest, scanned])
	for gate in clashes:
		print("CLASH %s: %s" % [gate, clashes[gate].keys()])
	var ok: bool = sim.track_name == "network" and gates.size() >= 30 and roads >= 5 and closest >= Gates.SPACING - sim.NET_STEP
	ok = ok and clashes.is_empty() and scanned.values().all(func(n): return n > 0) and scanned.pad == Config.INSERTIONS.size() - 1
	view.free()
	print("GATE CLEARANCE %s (%d obstructed gates)" % ["PASS" if ok else "FAIL", clashes.size()])
	quit(int(not ok))


func _finalize() -> void:
	if had_prefs:
		if not FileAccess.file_exists(PREFS) or FileAccess.get_file_as_bytes(PREFS) != saved_prefs:
			var file := FileAccess.open(PREFS, FileAccess.WRITE)
			file.store_buffer(saved_prefs)
	elif FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


func _add_gate(g: Dictionary, pose: Transform3D) -> void:
	# The frame includes the fly-through opening. Only the narrow beacon continues above the beam.
	var w := float(g.hw) + Gates.POST
	var h := Gates.HIGH + Gates.POST
	var frame := AABB(Vector3(-w, 0, -Gates.POST / 2), Vector3(2 * w, h, Gates.POST))
	var m := Gates.MAST_WIDE
	var mast := AABB(Vector3(-m / 2, h, -m / 2), Vector3(m, Gates.MAST, m))
	var gate := {"name": "%s@%d" % [view.sim.roads[g.road].name, g.i], "inverse": pose.affine_inverse(),
		"frame": frame, "mast": mast, "bounds": pose * frame.merge(mast)}
	gates.append(gate)
	var lo := _cell(gate.bounds.position)
	var hi := _cell(gate.bounds.end)
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			var cell := Vector2i(x, y)
			if not bins.has(cell):
				bins[cell] = []
			bins[cell].append(gate)


func _probe(category: String, label: String, pose: Transform3D, box: AABB) -> void:
	var bounds := pose * box
	var lo := _cell(bounds.position)
	var hi := _cell(bounds.end)
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for gate in bins.get(Vector2i(x, y), []):
				if not bounds.intersects(gate.bounds):
					continue
				var local: AABB = (gate.inverse * pose) * box
				if local.intersects(gate.frame) or local.intersects(gate.mast):
					if not clashes.has(gate.name):
						clashes[gate.name] = {}
					clashes[gate.name][category + " " + label] = true


func _lanes() -> void:
	var world = view.network_world
	for r in world.exit_lanes:
		var road = view.sim.roads[r]
		for lane in world.exit_lanes[r]:
			scanned.lane += 1
			var label := "%s to %s [%d,%d]" % [road.name, lane[5], lane[0], lane[1]]
			for i in range(lane[0], lane[1]):
				var a: Vector3 = world._p(road, 0, 0, i, lane[3], world._h(r, i))
				var b: Vector3 = world._p(road, 0, 0, i + 1, lane[3], world._h(r, i + 1))
				var delta := b - a
				var tangent := Vector3(delta.x, 0, delta.z)
				if tangent.length_squared() < 0.0001:
					continue
				var pose := Transform3D(Basis.looking_at(tangent.normalized()), a)
				# The rails extend 1.2 m either side of their nominal line. Include both ends of bends.
				var inverse := pose.affine_inverse()
				var width := World.LANE_HALF + 1.2
				var box := AABB(Vector3.ZERO, Vector3.ZERO)
				for j in [i, i + 1]:
					for side in [-width, width]:
						var p: Vector3 = world._p(road, 0, 0, j, lane[3] + side, world._h(r, j))
						box = box.expand(inverse * p)
				box = box.grow(0.05) # paint and contact at the common pavement plane
				_probe("lane", label, pose, box)


func _signs() -> void:
	var world = view.network_world
	var before: int = world.boards
	for key in world._signs:
		var road = view.sim.roads[key.x]
		var holder := Node3D.new()
		root.add_child(holder)
		for spec in world._signs[key]:
			world._sign(holder, road, key.x, 0, 0, spec)
		_meshes(holder, "sign", road.name)
		holder.free()
	scanned.sign = world.boards - before


func _meshes(node: Node3D, category: String, label: String) -> int:
	var count := 0
	for child in node.find_children("*", "VisualInstance3D", true, false):
		if child.is_visible_in_tree() and (child is Label3D or (child is MeshInstance3D and child.mesh != null)):
			_probe(category, label + "/" + String(child.name), child.global_transform, child.get_aabb())
			count += 1
	return count


func _pillars() -> void:
	var world = view.network_world
	if not world._pillars_indexed:
		world._index_pillars()
	for pillars in world._pillar_cells.values():
		for p in pillars:
			var half: float = p.halfSize
			var pos := Vector3(p.x - half, p.zMin, -p.y - half)
			var size := Vector3(2 * half, p.zMax - p.zMin, 2 * half)
			_probe("pillar", str(p.id), Transform3D.IDENTITY, AABB(pos, size))
			scanned.pillar += 1


func _props() -> void:
	var land = view.landscape
	var keys := {}
	for gate in gates:
		var mid: Vector3 = gate.bounds.get_center()
		var own := Vector2i(floori(mid.x / Land.TILE), floori(-mid.z / Land.TILE))
		# Groups can scatter across their owner tile's edge. The full ring includes those neighbours.
		for x in range(-1, 2):
			for y in range(-1, 2):
				keys[own + Vector2i(x, y)] = true
	var meshes := {}
	for kind in land.prop_library.KINDS:
		meshes[kind] = land.prop_library.cache[kind].get_aabb().merge(land.prop_library.proxy[kind].get_aabb())
	for key in keys:
		for p in land.prop_records(key):
			var basis := Basis(Vector3.UP, p.yaw).scaled(Vector3.ONE * p.scale)
			var origin := Vector3(p.p.x, p.height + p.lift, -p.p.y)
			_probe("prop", p.kind, Transform3D(basis, origin), meshes[p.kind])
			scanned.prop += 1


func _pads() -> void:
	var sim = view.sim
	for entry in Config.INSERTIONS:
		var spot := View.start_spot(entry[2])
		if spot.is_empty():
			continue # "last city" uses one of the named terminal pads
		var city := spot.size() == 1
		sim.P.startRoad = -1 if city else spot[0]
		if city:
			sim.net.from = spot[0]
		else:
			sim.P.startSample = spot[1]
			sim.P.startDir = spot[2]
		sim.respawn()
		view.pad.sync(0)
		scanned.pad += int(_meshes(view.pad, "pad", entry[0]) > 0)
