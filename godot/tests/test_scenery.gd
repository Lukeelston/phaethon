## Scenery gate: the environment pass (mountains, light, ground, asphalt, props) holds together.
##   mountains   three ranges each side plus the backdrop ring; each strip tiles seamlessly; mesas
##               stay mesa-sized, the high range is high and snow-capped; the feet are exactly the
##               fog's colour (they melt into the fogged desert)
##   light       filmic (ACES) tonemap, bloom, sky ambient; a shadow-casting sun with no disc and
##               two sky-only disc suns; the camera sees out to the backdrop
##   ground      the dry lake's shore keeps clear of the runway and repeats on the ground's period
##   faces       the range's flat quads face up (Godot fronts are clockwise), so the sun lights
##               the runway; they were face-down and lit only by the brown ground bounce
##   asphalt     UVs run on across every chunk seam; every lattice in the shader divides the period
##   plants      scrub and Joshua trees only past the shore and clear of every lane and corridor,
##               none on the airfield; the airfield is built; edge lights line the runway
##   GP          plants all >140 m from the track, floodlight towers round it, the pit building
##               off the track
##   budget      a range chunk's base build and a frame of queued plants stay small (no hitch)
## Prints SCENERY PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_scenery.gd -- --track=range --mute
extends SceneTree

const ViewScript := preload("res://view/craft_view.gd")
const RW := preload("res://view/range_world.gd")
const Horizon := preload("res://view/horizon.gd")
const GpWorld := preload("res://view/gp_world.gd")
const Props := preload("res://view/props.gd")
const Sim := preload("res://sim/craft_sim.gd")
const CHECKS := 12
var fails := 0
var passed := 0
var v
var frames := 0


func _initialize() -> void:
	v = ViewScript.new()
	root.add_child(v)


func _process(_d: float) -> bool:
	frames += 1
	if frames < 8:   # chunks stream in one a frame
		return false
	_mountains()
	_light()
	_ground_and_faces()
	_asphalt()
	_plants()
	_gp()
	_budget()
	var good: bool = fails == 0 and passed == CHECKS
	print("SCENERY ", "PASS" if good else "FAIL (%d failed, %d of %d passed)" % [fails, passed, CHECKS])
	quit(0 if good else 1)
	return true


func _mountains() -> void:
	var h = v.horizon
	_check("mountains: %d strip tiles (3 ranges x 2 sides x 3) and the backdrop ring, %d faces" % [h.tiles.size(), h.faces],
		h.tiles.size() == 18 and h.ring != null
		and h.faces == 6 * int(Horizon.PERIOD / Horizon.STEP) * Horizon.ROWS * 2 + Horizon.RING_COLS * 8 * 2)
	var seam := 0.0
	var tops := {}
	for layer in Horizon.LAYERS:
		var noise: FastNoiseLite = h._noise(layer[6])
		var top := 0.0
		for k in 11:
			var zf := 0.05 + 0.09 * k
			seam = maxf(seam, absf(h.height(layer, noise, 0.0, zf) - h.height(layer, noise, Horizon.PERIOD, zf)))
			for x in range(0, int(Horizon.PERIOD), 400):
				top = maxf(top, h.height(layer, noise, float(x), zf))
		tops[layer[0]] = top
	_check("each strip tiles without a seam (worst %.3f m); summits: mesas %.0f m, sierra %.0f m, high range %.0f m" % [seam, tops.mesa, tops.sierra, tops.high],
		seam < 0.5 and tops.mesa < 700.0 and tops.sierra > 900.0 and tops.high > 2300.0)
	# the high strip's colours: snow on top, and the foot exactly the fog colour
	var snow := 0
	var foot_err := 0.0
	var high_mesh: ArrayMesh = (h.tiles[12][0] as MeshInstance3D).mesh
	var arr := high_mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	for i in vs.size():
		if cs[i].r > 0.8 and cs[i].g > 0.8 and cs[i].b > 0.82 and vs[i].y > 2000.0:
			snow += 1
		if vs[i].y == 0.0:
			var hz: Color = ViewScript.HORIZON
			foot_err = maxf(foot_err, absf(cs[i].r - hz.r) + absf(cs[i].g - hz.g) + absf(cs[i].b - hz.b))
	_check("the high range is snow-capped (%d snowy summit vertices) and its foot is the fog's colour (off by %.4f)" % [snow, foot_err],
		snow > 50 and foot_err < 0.01)


func _light() -> void:
	var env: Environment = null
	var casters := 0
	var discs := 0
	for ch in v.get_children():
		if ch is WorldEnvironment:
			env = ch.environment
		elif ch is DirectionalLight3D:
			var l: DirectionalLight3D = ch
			if l.sky_mode == DirectionalLight3D.SKY_MODE_SKY_ONLY and l.light_angular_distance > 0.0:
				discs += 1
			elif l.sky_mode == DirectionalLight3D.SKY_MODE_LIGHT_ONLY and l.shadow_enabled:
				casters += 1
	var ok := env != null and env.tonemap_mode == Environment.TONE_MAPPER_ACES and env.glow_enabled \
		and env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY
	_check("light: ACES, bloom, sky ambient; %d shadow-casting sun, %d disc suns in the sky; camera sees %.0f km" % [casters, discs, v.cam.far / 1000.0],
		ok and casters == 1 and discs == 2 and v.cam.far >= 60000.0)


func _ground_and_faces() -> void:
	var lo := INF
	var hi := -INF
	var rep := 0.0
	for x in range(0, 8192, 16):
		for side in [1.0, -1.0]:
			var s := RW.shore(float(x), side)
			lo = minf(lo, s)
			hi = maxf(hi, s)
			rep = maxf(rep, absf(s - RW.shore(float(x) + RW.GROUND_PERIOD, side)))
	var gm: ShaderMaterial = v.ground_mat
	_check("ground: the lake's shore wanders %.0f-%.0f m out (runway edge %.0f m), repeats on the ground's period (off %.4f m); playa on" % [lo, hi, RW.RUNWAY_HALF, rep],
		lo > RW.RUNWAY_HALF + 30.0 and hi < 800.0 and rep < 0.01 and gm.get_shader_parameter("playa") == 1.0
		and is_equal_approx(gm.get_shader_parameter("playa_half"), RW.PLAYA_HALF))
	# a front face's (p1 - p0) x (p2 - p0) points into the surface: down, for ground facing up
	var rw = v.range_world
	var worst := -INF
	for k in 2:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		if k == 0:
			rw._quad(st, 0.0, 10.0, -5.0, 5.0)
		else:
			rw._quad_uv(st, 0.0, 0.0, 10.0, -5.0, 5.0, 0.0)
		var vs: PackedVector3Array = st.commit().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for t in range(0, vs.size(), 3):
			worst = maxf(worst, (vs[t + 1] - vs[t]).cross(vs[t + 2] - vs[t]).y)
	_check("the range's flat quads face up (winding check: %.1f, must be < 0)" % worst, worst < 0.0)


func _asphalt() -> void:
	var seam := 0.0
	for idx in range(0, 90):
		var cx := idx * RW.CHUNK
		var end_u := fposmod(cx, RW.ASPHALT_PERIOD) + RW.CHUNK
		var next_u := fposmod(cx + RW.CHUNK, RW.ASPHALT_PERIOD)
		seam = maxf(seam, absf(fposmod(end_u, RW.ASPHALT_PERIOD) - next_u))
	var lattices := [0.04, 0.25, 4.0, 16.0, 25.0, 40.0, 50.0]   # view/asphalt.gdshader's cells
	var divide := fposmod(RW.ASPHALT_PERIOD, RW.CHUNK) == 0.0
	for c in lattices:
		divide = divide and is_zero_approx(fposmod(RW.ASPHALT_PERIOD / c, 1.0))
	_check("asphalt UVs run on across 90 chunk seams (worst %.4f m); the period holds whole chunks and every lattice" % seam, seam < 0.001 and divide)


func _plants() -> void:
	var rw = v.range_world
	var bad := 0
	var why := ""
	var bushes := 0
	var trees := 0
	var blocks := 0
	for idx in [0, 1, 7, 33, 64]:
		var cx: float = idx * RW.CHUNK
		var bx := 0.0
		while bx < RW.CHUNK:
			for side in [1.0, -1.0]:
				var veg: Array = rw.veg_xforms(idx, cx, bx, bx + RW.VEG_BLOCK, side)
				blocks += 1
				bushes += veg[2].size()
				trees += veg[0].size() + veg[1].size()
				for kind in veg:
					for t in kind:
						var x: float = cx + (t as Transform3D).origin.x
						var y: float = -(t as Transform3D).origin.z
						if absf(y) < RW.shore(x, signf(y)) + 30.0 or not rw._clear(x, y, 0.0):
							bad += 1
							why = "plant at (%.0f, %.0f)" % [x, y]
			bx += RW.VEG_BLOCK
	var rocks_in_af := 0
	for t in rw.rock_xforms(0, 0.0, 0.0, RW.CHUNK):
		if RW.AIRFIELD.has_point(Vector2(t.origin.x, -t.origin.z)):
			rocks_in_af += 1
	_check("plants past the shore and clear of every lane: %d bushes, %d trees in %d blocks, %d misplaced%s; %d rocks on the airfield" % [
		bushes, trees, blocks, bad, "" if why == "" else " (" + why + ")", rocks_in_af],
		bad == 0 and bushes > blocks * 300 and trees > blocks * 30 and rocks_in_af == 0)
	# the airfield and the edge lights, in the real chunk 0
	var c0: Node3D = rw.chunks.get(0)
	var placed := {}
	var lights := 0
	if c0 != null:
		for ch in c0.get_children():
			if ch is MeshInstance3D and ch.mesh != null:
				for name in ["hangar", "tower", "tank", "radar_dish", "windsock", "truck"]:
					if ch.mesh == Props.mesh(name):
						placed[name] = placed.get(name, 0) + 1
			if ch is MultiMeshInstance3D and ch.multimesh.mesh == Props.mesh("edge_light"):
				lights += ch.multimesh.instance_count
	_check("the airfield stands in chunk 0 (%s, spinning dish %s) and %d edge lights line its runway" % [placed, "yes" if c0 != null and c0.has_meta("spin") else "no", lights],
		placed.get("hangar", 0) == 3 and placed.get("tower", 0) == 1 and placed.get("tank", 0) == 2 and placed.get("radar_dish", 0) == 1
		and placed.get("windsock", 0) == 1 and lights >= 2 * int(RW.CHUNK / RW.EDGE_LIGHT_DX) - 2)


func _gp() -> void:
	var sim = Sim.new({"track": "gp", "handling": "starfighter"})
	var gp = GpWorld.new()
	root.add_child(gp)
	gp.build(sim, v)
	var pits := []
	for ch in gp.get_children():
		if ch is MeshInstance3D and ch.mesh == Props.mesh("pit_building"):
			pits.append(ch.position)
	# plants: headless MultiMeshes keep no transforms, so re-draw 600 points from the placement's
	# own distribution, drop the ones its near-track grid rejects, and measure the rest against
	# every centreline sample
	var near := INF
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var grid: Dictionary = gp._near_track(150.0)
	for k in 600:
		var i := rng.randi_range(0, sim.N - 1)
		var d := 150.0 + 1500.0 * pow(rng.randf(), 1.7)
		var x: float = sim.tpx[i] + sim.tnx[i] * d
		var y: float = sim.tpy[i] + sim.tny[i] * d
		if grid.has(Vector2i(floori(x / 50.0), floori(y / 50.0))):
			continue
		for j in sim.N:
			near = minf(near, Vector2(x - sim.tpx[j], y - sim.tpy[j]).length())
	var pit_clear := INF
	for p in pits:
		for j in sim.N:
			pit_clear = minf(pit_clear, Vector2(p.x - sim.tpx[j], -p.z - sim.tpy[j]).length())
	_check("GP: %d plants and boulders, none nearer the track than %.0f m; %d floodlight towers; pit buildings %d, %.0f m off the centreline" % [
		gp.plants, near, gp.floodlights, pits.size(), pit_clear],
		gp.plants > 9000 and near > 140.0 and gp.floodlights >= 30 and pits.size() == 2 and pit_clear > sim.tw[0] / 2.0 + 20.0)
	gp.queue_free()


func _budget() -> void:
	var rw = v.range_world
	var worst_chunk := 0.0
	for idx in [5, 6, 41]:
		var t0 := Time.get_ticks_usec()
		var n: Node3D = rw._make_chunk(idx)
		worst_chunk = maxf(worst_chunk, (Time.get_ticks_usec() - t0) / 1000.0)
		n.queue_free()
	var worst_veg := 0.0
	while not rw.veg_queue.is_empty():
		var t1 := Time.get_ticks_usec()
		for k in 2:
			if not rw.veg_queue.is_empty():
				rw._build_veg(rw.veg_queue.pop_front())
		worst_veg = maxf(worst_veg, (Time.get_ticks_usec() - t1) / 1000.0)
	_check("streaming stays smooth: a chunk's base build %.1f ms, a frame of queued plants %.1f ms (budget 10 / 5)" % [worst_chunk, worst_veg],
		worst_chunk < 10.0 and worst_veg < 5.0)
	var ok := true
	for name in Props.MESHES:
		var m: Mesh = Props.mesh(name)
		ok = ok and m != null and m.get_surface_count() > 0 and (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 0
	_check("every prop mesh builds (%d)" % Props.MESHES.size(), ok)


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
