## What fills the glass from Mount Hyperion's brink, and what it is not asked to do (push 36: the frame rate
## fell there in the headset; the GPU's time was the far land's: tests/render_terminal_art.gd --weigh=).
##   floor     on the Network the plane under the pod is painted by view/ground_network.gdshader: the
##             Network's answer of view/ground.gdshader and nothing else, with every parameter the views set
##             on a floor still there to be set and read back; on any other track it is ground.gdshader, as it was
##             (and that shader is as it was: it still has its own Network answer, which the windowed
##             tests/test_network_ground_render.gd holds this one to, pixel for pixel)
##   shadows   no shadow is asked of that plane or of the mountain's body, and none could reach either: the
##             sun's shadows end well short of where the terrain stops covering the plane, and well short of
##             where the mountain's body first shows beside its road (it lies under the road's own land
##             nearer than that)
## Prints FAR LAND PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Hyperion := preload("res://view/hyperion.gd")
const Outlook := preload("res://view/outlook.gd")
const FLOOR := "res://view/ground_network.gdshader"
const SAND := "res://view/ground.gdshader"
var fails := 0


func check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	fails += int(not ok)


func _initialize() -> void:
	_run.call_deferred()


func _build(track: String):
	View.track_override = track
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_far_land_%d_" % Time.get_ticks_usec())
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	var v = View.new()
	root.add_child(v)
	v.set_process(false)
	return v


func _run() -> void:
	var v = _build("network")
	var gm: ShaderMaterial = v.ground_mat
	print("floor: the Network's own shader")
	check("the Network's floor is painted by %s (it is %s)" % [FLOOR, gm.shader.resource_path], gm.shader.resource_path == FLOOR)
	var floor_code: String = gm.shader.code
	var sand_code := (load(SAND) as Shader).code
	# the Network's answer, a line at a time, is in both
	var same := true
	for line in ["vec2 world_p = absolute_org + vec2(lp.x,-lp.y);", "float d = max(length(world_p-regions[i].xy)/regions[i].z,0.035);",
			"float w = 1.0/(d*d*d*d);", "geographic += region_colors[i].rgb*w;", "pfbm(p / 16.0, PERIOD / 16.0)", "geographic/total*(0.88+0.16*n3)",
			"vec2 p = vec2(org.x + lp.x, org.y - lp.y);", "const float PERIOD = 4096.0;", "ROUGHNESS = 0.95;", "SPECULAR = 0.25;"]:
		if not floor_code.contains(line) or not sand_code.contains(line):
			same = false
			print("       not in both: ", line)
	check("its colour is worked out as view/ground.gdshader's Network answer is, line for line", same)
	check("... and that shader still has its own Network answer", sand_code.contains("if (network_on) {") and not sand_code.contains("shadows_disabled"))
	var regions = gm.get_shader_parameter("regions")
	var colours = gm.get_shader_parameter("region_colors")
	check("it is given the nine regions and their colours", regions != null and colours != null and regions.size() == 9 and colours.size() == 9)
	# every parameter a view or the dawn sets on a floor is one this shader has
	var has := {}
	for u in gm.shader.get_shader_uniform_list():
		has[String(u.name)] = true
	var missing := []
	for nm in ["org", "pod_y", "absolute_org", "playa", "playa_half", "verdant", "ice", "basalt", "mesa", "network_on", "regions", "region_colors", "dawn_on", "dawn_u", "dawn_f"]:
		if not has.has(nm):
			missing.append(nm)
	check("every parameter set on a floor is one it takes (missing: %s)" % [missing], missing.is_empty())
	v._net_biome()
	var weights: float = float(gm.get_shader_parameter("ice")) + float(gm.get_shader_parameter("basalt")) + float(gm.get_shader_parameter("mesa"))
	check("the landscapes' weights are set on it and read back as before (ice + basalt + mesa %.3f)" % weights, weights >= 0.0 and weights <= 1.0001 and gm.get_shader_parameter("verdant") != null)

	print("shadows: none asked where none can reach")
	var reach := 0.0
	for child in v.get_children():
		if child is DirectionalLight3D and (child as DirectionalLight3D).shadow_enabled:
			reach = maxf(reach, (child as DirectionalLight3D).directional_shadow_max_distance)
	check("the sun casts shadows, to a known distance (%.0f m)" % reach, reach > 0.0)
	check("no shadow is asked of the Network's floor", _mode(floor_code).contains("shadows_disabled"))
	var land = v.landscape
	# (the terrain's tiles are whole to 54 km: view/network_terrain.gdshader's fade)
	var covered: float = minf(float(land.RANGE) * float(land.TILE), 54000.0)
	check("... which lies under the terrain for %.0f km round the craft, %.0f times as far as a shadow reaches" % [covered / 1000.0, covered / reach],
		is_equal_approx(v.ground.position.y, -8.0) and covered > 20.0 * reach)
	check("the mountain is in this world", Hyperion.ready and land.hyperion != null)
	if Hyperion.ready and land.hyperion != null:
		var body_code: String = ((land.hyperion as MeshInstance3D).material_override as ShaderMaterial).shader.code
		check("no shadow is asked of the mountain's body", _mode(body_code).contains("shadows_disabled") and _mode(body_code).contains("fog_disabled"))
		# its body shows no nearer the road's line than where it comes up from under the road's own land
		var road = v.sim.roads[Hyperion.road]
		var widest := 0.0
		for i in range(int(Hyperion.at.ramp), int(Hyperion.at.end)):
			widest = maxf(widest, float(road.w[i]))
		var nearest: float = Hyperion.FACE - 350.0 - widest / 2.0
		check("... which first shows %.0f m from the road's edge (under the road's own land nearer): %.1f times as far as a shadow reaches" % [nearest, nearest / reach],
			nearest > 3.0 * reach)
	v.free()

	print("the other tracks' floor")
	var r = _build("range")
	check("the range's floor is painted by %s (it is %s)" % [SAND, r.ground_mat.shader.resource_path], r.ground_mat.shader.resource_path == SAND)
	check("... with its dry lake", r.ground_mat.get_shader_parameter("playa") == 1.0)
	r.free()
	print("FAR LAND %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(int(fails > 0))


## A shader's render_mode line.
func _mode(code: String) -> String:
	for line in code.split("\n"):
		if line.strip_edges().begins_with("render_mode"):
			return line
	return ""
