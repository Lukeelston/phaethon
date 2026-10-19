## Flat-screen view: chase camera over CraftSim. Sim (x, y, z) maps to world (x, z, -y),
## rendered relative to a floating origin at the pod so a 100-mile range stays precise
## (32-bit vertices are ~1.5 cm granular at 160 km; every position here is computed in 64-bit).
## User args after "--":
##   --track=range   the 100-mile test range (default: the circuit)
##   --track=gp      the grand prix: 29 km for STARFIGHTER at ~1,000 mph
##   --startx=M      range only: start M metres down the range
##   --starty=M      range only: start on this lane (0 runway, 400 jump lane, -400 twisty lane)
##   --replay        circuit only: fly the recorded parity lap instead of live input
##   --seek=S        pre-simulate S seconds before the first frame
##   --shot=PATH     save a screenshot after 90 rendered frames, then quit
##   --shotframe=N   take that screenshot after N frames instead
##   --mute          no engine or wind audio
##   --handling=H    speed (default: the 100-mile sprint model) or starfighter (tight, ~1,200 mph)
##   --brake=L,R     with --cruise: hold the air brakes too (screenshots)
##   --at=I          circuits: start at track sample I (screenshots of a given corner)
##   --cam=F,L,U     camera at this offset from the pod (metres forward, left, up), looking at
##                   the engines: close-ups for screenshots
##   --eye=X,Y,H --look=X,Y,H   a fixed camera at that sim point, aimed at the other (scenery shots)
extends Node3D

const CraftSimScript := preload("res://sim/craft_sim.gd")
const LeverInputScript := preload("res://input/lever_input.gd")
const RangeWorldScript := preload("res://view/range_world.gd")
const LandmarkScript := preload("res://view/landmark.gd")
const EngineAudioScript := preload("res://audio/engine_audio.gd")
const WindAudioScript := preload("res://audio/wind_audio.gd")
const SpeedCuesScript := preload("res://view/speed_cues.gd")
const TrafficScript := preload("res://view/traffic.gd")
const DustScript := preload("res://view/dust.gd")
const CraftModelScript := preload("res://view/craft_model.gd")
const HorizonScript := preload("res://view/horizon.gd")
const GpWorldScript := preload("res://view/gp_world.gd")
const DT := 1.0 / 480.0
const HAZE := Color(0.78, 0.66, 0.52)
const GROUND_PERIOD := 4096.0             # view/ground.gdshader's PERIOD
const SUN_ROT := Vector3(-30, 52, 0)       # the primary sun (DirectionalLight3D rotation, degrees)
const HORIZON := Color(0.86, 0.74, 0.58)   # fog colour = the sky at the horizon, so they meet seamlessly

var sim
var levers
var engine_audio
var wind_audio
var replay: Array = []
var replay_i := 0
var shot_path := ""
var shot_frame := 90
var frames := 0
var acc := 0.0
var sub := 0
var inp := {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": false}
var start_at := -1   # --at=I: start at track sample I (circuits; screenshots of a given corner)
var cruise := -1.0   # --cruise=T holds both levers at T (demos, screenshots)
var hold_brake := [0.0, 0.0]
var cam_offset := Vector3.ZERO   # --cam: debug close-up (forward, left, up)
static var track_override := ""    # an in-game track switch (VR: hold the menu button) wins over --track;
                                   # static, so it survives the scene reload that does the switch
var eye := Vector3.INF            # --eye / --look: a fixed debug camera at sim (x, y, h), aimed at another point
var look := Vector3.ZERO
var best_saved := -1.0     # sprint best, persisted across launches
var flash_msg := ""        # DNF / new-best message, shown for a few seconds
var flash_until := -1.0
var brake_point := -1.0    # metres before the box where this run's hard braking began
var was_active := false
var org_x := 0.0   # floating origin, in sim metres
var org_y := 0.0
var top_kmh := 0.0

var craft: Node3D
var pod_mesh: MeshInstance3D
var cam: Camera3D
var hud: Label
var ground: MeshInstance3D
var ground_mat: ShaderMaterial
var circuit_root: Node3D
var range_world: Node3D
var landmark: Node3D
var cues: Node3D
var traffic: Node3D
var horizon: Node3D
var gp_world: Node3D
var dust: Node3D


func _ready() -> void:
	var opts := {}
	var seek := 0.0
	var mute := false
	for a in OS.get_cmdline_user_args():
		if a == "--replay":
			replay = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/lap_inputs.json"))
		elif a.begins_with("--seek="):
			seek = float(a.get_slice("=", 1))
		elif a.begins_with("--shot="):
			shot_path = a.get_slice("=", 1)
		elif a.begins_with("--shotframe="):
			shot_frame = int(a.get_slice("=", 1))
		elif a == "--track=range":
			opts["track"] = "range"
		elif a == "--track=gp":
			opts["track"] = "gp"
		elif a.begins_with("--startx="):
			opts["startX"] = float(a.get_slice("=", 1))
		elif a.begins_with("--starty="):
			opts["startY"] = float(a.get_slice("=", 1))
		elif a.begins_with("--cruise="):
			cruise = float(a.get_slice("=", 1))
		elif a == "--mute":
			mute = true
		elif a.begins_with("--handling="):
			opts["handling"] = a.get_slice("=", 1)
		elif a.begins_with("--brake="):
			var b := a.get_slice("=", 1).split(",")
			hold_brake = [float(b[0]), float(b[1])]
		elif a.begins_with("--at="):
			start_at = int(a.get_slice("=", 1))
		elif a.begins_with("--cam="):
			var c := a.get_slice("=", 1).split(",")
			cam_offset = Vector3(float(c[0]), float(c[1]), float(c[2]))
		elif a.begins_with("--eye="):
			var c := a.get_slice("=", 1).split(",")
			eye = Vector3(float(c[0]), float(c[1]), float(c[2]))
		elif a.begins_with("--look="):
			var c := a.get_slice("=", 1).split(",")
			look = Vector3(float(c[0]), float(c[1]), float(c[2]))
	if track_override != "":
		opts["track"] = track_override
		opts.erase("startX")
		opts.erase("startY")
	sim = CraftSimScript.new(opts)
	if start_at >= 0 and sim.kind == "circuit":
		sim.respawn(-1, start_at)
	if sim.kind != "circuit":
		replay = []
	levers = LeverInputScript.new()
	_load_best()
	if cruise >= 0.0:
		inp = {"thrL": cruise, "thrR": cruise, "brkL": hold_brake[0], "brkR": hold_brake[1], "repair": false, "reignite": true}
	_follow_origin()
	_build_world()
	_build_craft()
	cues = SpeedCuesScript.new()
	add_child(cues)
	cues.build(self)
	dust = DustScript.new()
	add_child(dust)
	dust.build(self)
	if not mute and shot_path == "":
		engine_audio = EngineAudioScript.new()
		add_child(engine_audio)
		engine_audio.setup(sim)
		wind_audio = WindAudioScript.new()
		add_child(wind_audio)
		wind_audio.setup(sim)
	for i in int(seek / DT):
		_sim_step()
	_follow_origin()
	_place_camera(1.0)


func _sim_step() -> void:
	if not replay.is_empty() and sub % 8 == 0:
		var u: Array = replay[mini(replay_i, replay.size() - 1)]
		inp = {"thrL": u[0], "thrR": u[1], "brkL": u[2], "brkR": u[3], "repair": false, "reignite": true}
		replay_i += 1
	sub += 1
	sim.step(inp, DT)
	for e in sim.events:
		_on_event(e)
	sim.events.clear()


func _on_event(e: Dictionary) -> void:
	if e.type != "land" and e.type != "scrape":   # every hit, crash, flameout, lap... in the log
		print("EVENT %s %s t=%.2f" % [e.type, e.get("who", ""), sim.time])
	if e.type == "hit":
		_on_hit(e.who, 1.0)
	elif e.type == "scrape":
		_on_hit(e.who, 0.35)
	if sim.track_name == "gp" and e.type == "lap":
		if best_saved < 0.0 or e.t < best_saved:
			best_saved = e.t
			var f := FileAccess.open(_best_path(), FileAccess.WRITE)
			if f:
				f.store_string(JSON.stringify({"best": best_saved}))
			_flash("LAP RECORD  %.2fs" % e.t)
		else:
			_flash("LAP  %.2fs" % e.t)
		return
	if sim.kind != "range":
		return
	match e.type:
		"finish":
			if best_saved < 0.0 or e.t < best_saved:
				best_saved = e.t
				var f := FileAccess.open(_best_path(), FileAccess.WRITE)
				if f:
					f.store_string(JSON.stringify({"best": best_saved}))
				_flash("NEW BEST")
		"overrun":
			_flash("OVERRUN  -  DNF")
		"crash":
			_flash("CRASHED  -  DNF")


## Sprint bests are kept per handling mode (the speed file keeps its original name).
func _best_path() -> String:
	var h: String = sim.P.handling
	if sim.track_name == "gp":
		return "user://gp_best_%s.json" % h
	return "user://sprint_best.json" if h == "speed" else "user://sprint_best_%s.json" % h


func _load_best() -> void:
	best_saved = -1.0
	if (sim.kind == "range" or sim.track_name == "gp") and FileAccess.file_exists(_best_path()):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(_best_path()))
		if saved is Dictionary and saved.has("best"):
			best_saved = float(saved.best)


## Switch handling mode and start over (the range restarts the sprint).
func set_handling(name: String) -> void:
	if not CraftSimScript.HANDLING.has(name):
		return
	sim.set_handling(name)
	_load_best()
	_respawn()
	_flash("%s HANDLING" % name.to_upper())


## Overridable: feedback for wall contact, strength 1 for a damaging hit, less for a scrape
## (the VR cockpit buzzes a controller).
func _on_hit(_who: String, _strength: float) -> void:
	pass


func _flash(msg: String) -> void:
	flash_msg = msg
	flash_until = sim.time + 5.0


## Y: a fresh start. The range restarts the sprint at the start line, a circuit puts you back
## on the grid; both with whole engines (wall damage otherwise stays until you repair it).
func _respawn() -> void:
	sim.restart()
	brake_point = -1.0
	flash_until = -1.0


## Overridable: fill `inp` for this frame and handle arm/respawn edges.
func _read_input(delta: float) -> void:
	var p: Dictionary = levers.poll(delta)
	inp = {"thrL": p.thrL, "thrR": p.thrR, "brkL": p.brkL, "brkR": p.brkR, "repair": p.repair, "reignite": p.reignite}
	if p.arm:
		sim.armed = not sim.armed
	if p.respawn:
		_respawn()


func _process(delta: float) -> void:
	if replay.is_empty() and cruise < 0.0:
		_read_input(delta)
	acc += minf(delta, 0.05)
	while acc >= DT:
		_sim_step()
		acc -= DT
	_track_braking()
	if engine_audio:
		engine_audio.update(inp, delta)
	if wind_audio:
		wind_audio.update(inp, delta)
	_follow_origin()
	_sync_craft(delta)
	cues.sync(sim, delta)
	dust.sync(sim, delta)
	_place_camera(1.0 - exp(-delta * 6.0))
	craft.sync_cables(sim, delta)   # after the camera: in VR the cables' pod end rides the cockpit
	_sync_world()   # after the camera: distant anchors scale about its current position
	top_kmh = maxf(top_kmh, _kmh())
	_update_hud()
	frames += 1
	if shot_path != "" and frames == shot_frame:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot_path)
		get_tree().quit()


## Remember where this run's hard braking began (both brakes past half, still fast).
func _track_braking() -> void:
	if sim.kind != "range":
		return
	if sim.run_active and not was_active:
		brake_point = -1.0
	if sim.run_active and brake_point < 0.0 and inp.brkL >= 0.5 and inp.brkR >= 0.5 and _kmh() > 1000.0:
		brake_point = sim.BOX_X - sim.pod.x
	was_active = sim.run_active


func _follow_origin() -> void:
	org_x = sim.pod.x
	org_y = sim.pod.y


## Sim point -> render position, relative to the floating origin.
func w3(x: float, y: float, h := 0.0) -> Vector3:
	return Vector3(x - org_x, h + surface(x, y).x, -(y - org_y))


## The banked GP's surface under (x, y): Vector2(height, bank radians, + = down to the left).
## Everything placed with w3 rides it; (0, 0) off the GP.
func surface(x: float, y: float) -> Vector2:
	return sim.surface_at(x, y, sim.pod.hint) if sim else Vector2.ZERO


## Sim point -> absolute mesh-space position (for meshes anchored at the sim origin).
static func abs3(x: float, y: float, h := 0.0) -> Vector3:
	return Vector3(x, h, -y)


func _kmh() -> float:
	return sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) * 3.6


func _mat(c: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


# Sand grain: the speed cue. tiles > 0 uses the mesh UVs; 0 projects in object space
# (the circuit ribbon has no UVs) at one tile per 12 m. Object space, not world space:
# with a floating origin, world-space UVs would swim.
func _grain(c: Color, tiles: float) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.06
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	var m := _mat(c)
	m.albedo_texture = tex
	if tiles > 0.0:
		m.uv1_scale = Vector3(tiles, tiles, 1)
	else:
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE / 12.0
	return m


func _build_world() -> void:
	# Sky: dusty blue overhead, washing out to the haze at the horizon. The fog skips the sky
	# (it would paint it flat) and meets it at the horizon in the same colour.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.40, 0.55, 0.74)
	sky_mat.sky_horizon_color = HORIZON
	sky_mat.sky_curve = 0.09
	sky_mat.ground_horizon_color = HORIZON
	sky_mat.ground_bottom_color = Color(0.62, 0.5, 0.36)
	sky_mat.sun_angle_max = 1.5
	sky_mat.sun_curve = 0.05
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := WorldEnvironment.new()
	var en := Environment.new()
	env.environment = en
	en.background_mode = Environment.BG_SKY
	en.sky = sky
	# light: the sky's own colours fill the shadows (blue from above, warm bounce from the
	# sand), filmic tonemapping keeps the bright desert from clipping, and a soft bloom lets
	# the flames, nav strips, cables and lamps glow
	en.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	en.ambient_light_sky_contribution = 0.75
	en.ambient_light_color = Color(0.85, 0.78, 0.7)
	en.ambient_light_energy = 0.75
	en.tonemap_mode = Environment.TONE_MAPPER_ACES
	en.tonemap_exposure = 1.05
	en.tonemap_white = 6.0
	en.glow_enabled = true
	en.glow_intensity = 0.55
	en.glow_strength = 0.9
	en.glow_bloom = 0.02
	en.glow_hdr_threshold = 0.95
	en.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	for lv in 7:
		en.set_glow_level(lv, 1.0 if lv in [1, 2, 3, 4] else 0.0)
	en.adjustment_enabled = true
	en.adjustment_saturation = 1.08
	en.adjustment_contrast = 1.04
	en.fog_enabled = true
	en.fog_light_color = HORIZON
	en.fog_density = 0.0012 if sim.kind == "circuit" and sim.track_name != "gp" else 0.00035
	en.fog_sky_affect = 0.0
	en.fog_sun_scatter = 0.18   # the haze brightens toward the suns
	add_child(env)
	# Twin suns, ahead and to the right of the run, late afternoon: a white primary that casts
	# the shadows (long ones now, so ramps, props and the craft sit on the ground) and a smaller,
	# warmer companion a few degrees off it.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = SUN_ROT
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 450.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.5
	add_child(sun)
	var sun2 := DirectionalLight3D.new()
	sun2.rotation_degrees = Vector3(-24, 60, 0)
	sun2.light_color = Color(1.0, 0.72, 0.45)
	sun2.light_energy = 0.4
	sun2.light_angular_distance = 0.6
	add_child(sun2)
	# the suns' discs: sky-only lights, so the shadow caster stays a hard-edged (cheap) light
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sun2.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	for d in [[sun, Color(1.0, 0.98, 0.94), 0.55, 16.0], [sun2, Color(1.0, 0.66, 0.36), 0.35, 7.0]]:
		var disc := DirectionalLight3D.new()
		disc.rotation = (d[0] as DirectionalLight3D).rotation
		disc.light_color = d[1]
		disc.light_angular_distance = d[2]
		disc.light_energy = d[3]
		disc.sky_mode = DirectionalLight3D.SKY_MODE_SKY_ONLY
		add_child(disc)

	# The ground rides along under the pod; its texture offset keeps the sand fixed in the world.
	# 60 km across so its far edge sits near the true horizon even 100+ m up a jump.
	ground = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60000, 60000)
	ground.mesh = plane
	ground_mat = ShaderMaterial.new()
	ground_mat.shader = preload("res://view/ground.gdshader")
	ground_mat.set_shader_parameter("playa", 1.0 if sim.kind == "range" else 0.0)
	ground_mat.set_shader_parameter("playa_half", RangeWorldScript.PLAYA_HALF)   # the runway's dry lake; scrub beyond
	ground.material_override = ground_mat
	ground.position = Vector3(0, -0.05, 0)
	add_child(ground)

	if sim.kind == "range":
		range_world = RangeWorldScript.new()
		add_child(range_world)
		range_world.build(sim, self)
		landmark = LandmarkScript.new()
		add_child(landmark)
		landmark.build(self)
		traffic = TrafficScript.new()
		add_child(traffic)
		traffic.build(self)
		horizon = HorizonScript.new()
		add_child(horizon)
		horizon.build(self, HORIZON)
		return

	if sim.track_name == "gp":
		gp_world = GpWorldScript.new()
		add_child(gp_world)
		gp_world.build(sim, self)
		horizon = HorizonScript.new()
		add_child(horizon)
		horizon.build(self, HORIZON)
		return

	# Circuit: track surface and kerbed walls, built in absolute coordinates and
	# moved as one node relative to the floating origin.
	circuit_root = Node3D.new()
	add_child(circuit_root)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = sim.N
	for i in n:
		var j := (i + 1) % n
		var li := _edge(i, 1.0)
		var ri := _edge(i, -1.0)
		var lj := _edge(j, 1.0)
		var rj := _edge(j, -1.0)
		for v in [li, ri, lj, ri, rj, lj]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v + Vector3.UP * 0.02)
		var c := Color(0.91, 0.88, 0.82) if (i / 2) % 2 == 0 else Color(0.69, 0.27, 0.16)
		for e in [[li, lj], [ri, rj]]:
			var a: Vector3 = e[0]
			var b: Vector3 = e[1]
			for v in [a, b, a + Vector3.UP * 1.5, b, b + Vector3.UP * 1.5, a + Vector3.UP * 1.5]:
				walls.set_color(c)
				walls.set_normal(Vector3.UP)
				walls.add_vertex(v)
	var track := MeshInstance3D.new()
	track.mesh = st.commit()
	track.material_override = _grain(Color(0.88, 0.77, 0.58), 0.0)
	circuit_root.add_child(track)
	var wall_mi := MeshInstance3D.new()
	wall_mi.mesh = walls.commit()
	var wm := _mat(Color.WHITE)
	wm.vertex_color_use_as_albedo = true
	wall_mi.material_override = wm
	circuit_root.add_child(wall_mi)


func _edge(i: int, side: float) -> Vector3:
	return abs3(sim.tpx[i] + sim.tnx[i] * side * sim.tw[i] / 2.0, sim.tpy[i] + sim.tny[i] * side * sim.tw[i] / 2.0)


func _sync_world() -> void:
	# 6 m per sand tile; only the fractional offset matters, which keeps it precise.
	ground_mat.set_shader_parameter("org", Vector2(fposmod(org_x, GROUND_PERIOD), fposmod(org_y, GROUND_PERIOD)))
	ground_mat.set_shader_parameter("pod_y", org_y)
	if circuit_root:
		circuit_root.position = w3(0.0, 0.0)
	if range_world:
		range_world.sync(org_x, org_y, sim.time)
	if traffic:
		traffic.sync(sim.time)
	if horizon:
		horizon.sync(org_x, org_y)
	if gp_world:
		gp_world.sync(org_x, org_y)
	if landmark:
		landmark.sync(org_x, org_y, sim.time, cam.global_position)


func _build_craft() -> void:
	craft = CraftModelScript.new()
	add_child(craft)
	craft.build(self)
	pod_mesh = craft.pod
	_make_view()


## Overridable: the flat view's chase camera and 2D HUD.
func _make_view() -> void:
	cam = Camera3D.new()
	cam.fov = 70
	cam.far = 80000   # the backdrop peaks sit at 45-57 km
	add_child(cam)
	var layer := CanvasLayer.new()
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 18)
	hud.add_theme_color_override("font_color", Color(0.1, 0.08, 0.06))
	layer.add_child(hud)
	add_child(layer)


func _sync_craft(delta: float) -> void:
	craft.sync(sim, inp, delta)


var cam_th := 0.0

# Rigidly follow the pod; smooth only the heading. Lerping position lags tens of
# metres at 700 km/h and the craft shrinks to a toy.
func _place_camera(k: float) -> void:
	cam_th = sim.pair_th if k >= 1.0 else cam_th + CraftSimScript.wrap_angle(sim.pair_th - cam_th) * k
	var fwd := Vector3(cos(cam_th), 0, -sin(cam_th))
	var pod_p := w3(sim.pod.x, sim.pod.y, sim.pod.z)
	if eye != Vector3.INF:
		cam.position = w3(eye.x, eye.y, eye.z)
		cam.look_at(w3(look.x, look.y, look.z), Vector3.UP)
		return
	if cam_offset != Vector3.ZERO:
		var left := Vector3(-sin(cam_th), 0, -cos(cam_th))
		var mid := w3((sim.eL.x + sim.eR.x) / 2.0, (sim.eL.y + sim.eR.y) / 2.0, (sim.eL.z + sim.eR.z) / 2.0)
		cam.position = pod_p + fwd * cam_offset.x + left * cam_offset.y + Vector3.UP * cam_offset.z
		cam.look_at(mid, Vector3.UP)
		return
	cam.position = pod_p - fwd * 12.0 + Vector3.UP * 4.5
	cam.look_at(pod_p + fwd * 40.0 + Vector3.UP * 1.0, Vector3.UP)


## Second HUD line: lap info on the circuit, mileage and top speed on the range.
func _progress_text() -> String:
	if sim.kind == "range":
		var best := "--" if best_saved < 0.0 else "%.2fs" % best_saved
		var braked := "" if brake_point < 0.0 else "   braked %.2f km out" % (brake_point / 1000.0)
		if sim.time < flash_until:
			return "%s   BEST %s" % [flash_msg, best]
		if sim.run_active:
			var togo: float = sim.BOX_X - sim.pod.x
			var dist := "%.2f km" % (togo / 1000.0) if absf(togo) >= 1000.0 else "%d m" % int(togo)
			return "TO BOX %s   RUN %.1fs   BEST %s" % [dist, sim.time - sim.run_start, best]
		if sim.result.get("type", "") == "finish":
			return "STOPPED IN BOX  %.2fs   %.1f m off%s\nBEST %s   (Y: go again)" % [
				sim.result.t, sim.result.err, braked, best]
		return "READY: push the levers   BEST %s" % best
	var cur: float = 0.0 if sim.lap_start < 0.0 else sim.time - sim.lap_start
	if sim.track_name == "gp":
		var rec := "--" if best_saved < 0.0 else "%.2f" % best_saved
		if sim.time < flash_until:
			return "%s   RECORD %s" % [flash_msg, rec]
		return "LAP %d  %.2fs   LAST %s   RECORD %s" % [sim.lap + 1, cur, "--" if sim.last_lap < 0.0 else "%.2f" % sim.last_lap, rec]
	return "LAP %d  %.2fs   LAST %s  BEST %s" % [sim.lap + 1, cur,
		"--" if sim.last_lap < 0.0 else "%.2f" % sim.last_lap, "--" if sim.best_lap < 0.0 else "%.2f" % sim.best_lap]


func _update_hud() -> void:
	var mode_txt: String = {"ramjet": "RAMJET", "burner": "AFTERBURNER"}.get(sim.mode, "RAMJET ARMED" if sim.armed else "")
	hud.text = "%4d km/h   %s   %s\nTHR %.2f | %.2f   BRK %.2f | %.2f   HEAT %d%% | %d%%   HP %d%% | %d%%   BAT %d%%   %s\n%s" % [
		_kmh(), cues.readout(), _progress_text(), inp.thrL, inp.thrR, inp.brkL, inp.brkR,
		sim.eL.heat * 100, sim.eR.heat * 100, sim.eL.health * 100, sim.eR.health * 100, sim.battery * 100, mode_txt,
		("Replay: parity lap" if not replay.is_empty() else levers.source) + "   %s handling" % String(sim.P.handling).to_upper()]
