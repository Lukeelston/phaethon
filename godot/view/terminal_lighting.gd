## Eridanus concourse. One low-poly shell casts sunlight through the actual
## portals. A single shadowless fixture supplies the passing specular on the
## player's paint and instruments, paired with the baked pools on the road.
extends Node3D

const NetworkWorld := preload("res://view/network_world.gd")
const CRAFT_LAYER := 1 << 8

var road_id := -1
var first_sample := 0
var last_sample := 0
var anchor_x := 0.0
var anchor_y := 0.0
var shade: MeshInstance3D
var fixture: OmniLight3D
var enclosure := 0.0      # how far inside the hall the pod is: 0 outside, 1 well in


static func mark_craft(root: Node3D) -> void:
	for part: GeometryInstance3D in root.find_children("*", "GeometryInstance3D", true, false):
		part.layers |= CRAFT_LAYER


func build(sim, world) -> void:
	for city in sim.cities:
		if city.name == "ERIDANUS":
			road_id = city.road
			first_sample = world.halls[road_id][0]
			last_sample = world.halls[road_id][1]
			anchor_x = sim.roads[road_id].px[city.i]
			anchor_y = sim.roads[road_id].py[city.i]
			break
	if road_id < 0:
		return
	var road: CraftSim.TrackPath = sim.roads[road_id]
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in range(first_sample, last_sample + 1):
		var half_width := road.w[i] * 0.5
		var base_height: float = sim.net_height(road_id, float(i)) + CraftSim.net_edge(road.w[i], half_width).x
		var centre := Vector3(road.px[i] - anchor_x, base_height, anchor_y - road.py[i])
		var side := Vector3(road.nx[i], 0.0, -road.ny[i]) * half_width
		var roof := Vector3.UP * NetworkWorld.HALL_H
		vertices.append_array(PackedVector3Array([centre - side, centre - side + roof, centre + side + roof, centre + side]))
		if i == first_sample:
			continue
		var row := (i - first_sample - 1) * 4
		for panel in 3:
			var p := row + panel
			indices.append_array(PackedInt32Array([p, p + 4, p + 1, p + 1, p + 4, p + 5]))
	var surface := []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = vertices
	surface[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	var two_sided := StandardMaterial3D.new()
	two_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
	shade = MeshInstance3D.new()
	shade.mesh = mesh
	shade.material_override = two_sided
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	shade.name = "TerminalShadowShell"
	add_child(shade)

	fixture = OmniLight3D.new()
	fixture.name = "ConcourseFixtureReflection"
	fixture.light_color = Color(0.76, 0.88, 1.0)
	fixture.light_cull_mask = CRAFT_LAYER
	fixture.light_bake_mode = Light3D.BAKE_DISABLED
	fixture.light_specular = 0.62
	fixture.light_size = 1.3
	fixture.omni_range = 38.0
	fixture.omni_attenuation = 0.0
	fixture.shadow_enabled = false
	fixture.visible = false
	add_child(fixture)


func sync(sim, origin_x: float, origin_y: float) -> void:
	if road_id < 0:
		return
	# The shadow atlas only reaches 450 m. A 3.5 km radius contains both
	# ends of this 4 km hall plus its longest visible cast shadow.
	enclosure = 0.0
	shade.visible = maxf(absf(anchor_x - origin_x), absf(anchor_y - origin_y)) < 3500.0
	if not shade.visible:
		fixture.visible = false
		return
	shade.position = Vector3(anchor_x - origin_x, 0.0, origin_y - anchor_y)
	var pod = sim.pod
	var i: int = pod.hint
	if pod.off_road or pod.path != road_id or i < first_sample - 2 or i > last_sample + 2:
		fixture.visible = false
		return

	var road: CraftSim.TrackPath = sim.roads[road_id]
	var along: float = (pod.x - road.px[i]) * road.tx[i] + (pod.y - road.py[i]) * road.ty[i]
	var sample: float = i + along / road.len[i]
	# A broad penumbra lets the last bay spill out of the portal.
	enclosure = smoothstep(-1.4, 1.4, minf(sample - first_sample, last_sample - sample))
	fixture.visible = enclosure > 0.001
	if not fixture.visible:
		return
	var phase := TAU * (sample - first_sample) / NetworkWorld.HALL_LIGHT_EVERY
	var speed := absf(pod.vx * road.tx[i] + pod.vy * road.ty[i])
	var passes_per_second := speed / (road.len[i] * NetworkWorld.HALL_LIGHT_EVERY)
	# At high speed individual lamps integrate into a steady strip; keep both
	# the diffuse exposure and the reflected highlight free of rapid flashing.
	var separation := 1.0 - smoothstep(3.0, 8.0, passes_per_second)
	var axis := Vector3(road.tx[i], 0.0, -road.ty[i])
	var side := Vector3(road.nx[i], 0.0, -road.ny[i])
	var pod_pos := Vector3(pod.x - origin_x, pod.z, origin_y - pod.y)
	fixture.position = pod_pos + Vector3.UP * 7.0 + side * 3.0 - axis * sin(phase) * 8.0 * separation
	fixture.light_energy = enclosure * (0.82 + 0.22 * cos(phase) * separation)
