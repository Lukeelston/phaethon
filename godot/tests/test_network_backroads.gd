## Build the interior links in the playable Network and check their surfaces, scenery and signs.
extends SceneTree

const View := preload("res://view/craft_view.gd")
var failures := 0


func check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	failures += int(not ok)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_backroads_")
	var view = View.new()
	root.add_child(view)
	view.set_process(false)
	var world = view.network_world
	var land = view.landscape
	var sim = view.sim
	var biomes := {"SWash": "desert", "SFrost": "snow", "SReed": "swamp", "SRed": "mesa"}
	var found := 0
	for r in sim.roads.size():
		var road = sim.roads[r]
		if not biomes.has(road.name):
			continue
		found += 1
		var label: String = world.SCENIC_NAMES[road.name]
		var signs := 0
		var decisions := 0
		for specs in world._signs.values():
			for spec in specs:
				if spec[4].get("route", "") == world.SCENIC_ROUTES[road.name] and spec[4].get("scenic", false) and label in spec[3]:
					signs += 1
					decisions += int(spec[4].get("decision", false))
		check("%s has advance and exit signs on both highways" % label, signs == 4 and decisions == 2)
		var i := roundi(0.12 * (road.N - 1))
		var pos := Vector2(road.px[i], road.py[i])
		check("%s reaches %s" % [label, land.region_at(pos)], land.region_at(pos) == biomes[road.name])
		for f in [0.02, 0.20, 0.98]:
			var station := roundi(f * (road.N - 1))
			var k := int(station / world.CH)
			var key := Vector2i(r, k)
			if not world.chunks.has(key):
				world._build_chunk(r, k)
			var mesh: Mesh = world.chunks[key][0].get_node("road").mesh
			var expected = world._asph
			if is_equal_approx(f, 0.2) and road.name in ["SWash", "SRed"]:
				expected = world._unsealed[world.SAND if road.name == "SWash" else world.RED_GRAVEL]
			check("%s deck material at %.0f%%" % [label, f * 100], mesh.surface_get_material(0) == expected)
		if road.name == "SReed":
			var spans := 0
			for sample in range(int(road.N * 0.10), int(road.N * 0.28), world.PILLAR_EVERY):
				var pier_i: int = sample - sample % world.PILLAR_EVERY
				var point := Vector2(road.px[pier_i], road.py[pier_i])
				var tile := Node3D.new()
				land._water(Vector2i((point / land.TILE).floor()), tile)
				var piers: Array = world.pillar_specs(r, pier_i)
				if tile.get_child_count() > 0 and not piers.is_empty():
					var water_y: float = tile.get_child(0).position.y
					var bed: float = land.surface_at(point)
					if tile.get_child(0).material_override == land.water_material and piers[0].zMin < bed and bed < water_y and sim.net_height(r, pier_i) > water_y + 30:
						spans += 1
				tile.free()
			check("%d pier stations pass through visible water into the marsh bed" % spans, spans >= 12)
		if road.name == "SFrost":
			var crest := roundi(0.39 * (road.N - 1))
			var left: PackedFloat32Array = world.scenic.row(r, crest, true)
			var right: PackedFloat32Array = world.scenic.row(r, crest, false)
			var peak: float = sim.net_height(r, crest)
			check("Frostline has a %.0f m saddle cut into the mountain" % peak,
				world.scenic.on(r, crest) and peak >= 775 and maxf(left[-1], right[-1]) > peak + 200)
	check("all four named routes exist", found == 4)
	view.free()
	print("NETWORK BACKROADS ", "PASS" if failures == 0 else "FAIL")
	quit(int(failures > 0))
