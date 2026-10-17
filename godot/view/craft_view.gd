## Flat-screen view: chase camera over CraftSim. Sim (x, y, z) maps to world (x, z, -y),
## rendered relative to a floating origin at the pod so a 100-mile range stays precise
## (32-bit vertices are ~1.5 cm granular at 160 km; every position here is computed in 64-bit).
## User args after "--":
##   --track=range   the 100-mile test range (default: the circuit)
##   --startx=M      range only: start M metres down the range
##   --starty=M      range only: start on this lane (0 runway, 400 jump lane, -400 twisty lane)
##   --replay        circuit only: fly the recorded parity lap instead of live input
##   --seek=S        pre-simulate S seconds before the first frame
##   --shot=PATH     save a screenshot after 90 rendered frames, then quit
##   --mute          no engine audio
extends Node3D

const CraftSimScript := preload("res://sim/craft_sim.gd")
const LeverInputScript := preload("res://input/lever_input.gd")
const RangeWorldScript := preload("res://view/range_world.gd")
const LandmarkScript := preload("res://view/landmark.gd")
const EngineAudioScript := preload("res://audio/engine_audio.gd")
const DT := 1.0 / 480.0
const STEEL := Color(0.60, 0.65, 0.70)
const HOT := Color(1.0, 0.54, 0.16)
const WHITE := Color(1.0, 0.96, 0.86)
const HAZE := Color(0.78, 0.66, 0.52)

var sim
var levers
var engine_audio
var replay: Array = []
var replay_i := 0
var shot_path := ""
var frames := 0
var acc := 0.0
var sub := 0
var inp := {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": false}
var cruise := -1.0   # --cruise=T holds both levers at T (demos, screenshots)
const BEST_PATH := "user://sprint_best.json"
var best_saved := -1.0     # sprint best, persisted across launches
var flash_msg := ""        # DNF / new-best message, shown for a few seconds
var flash_until := -1.0
var brake_point := -1.0    # metres before the box where this run's hard braking began
var was_active := false
var org_x := 0.0   # floating origin, in sim metres
var org_y := 0.0
var top_kmh := 0.0

var engines: Array[MeshInstance3D] = []
var flames: Array[MeshInstance3D] = []
var pod_mesh: MeshInstance3D
var lines: ImmediateMesh
var cam: Camera3D
var hud: Label
var ground: MeshInstance3D
var ground_mat: StandardMaterial3D
var circuit_root: Node3D
var range_world: Node3D
var landmark: Node3D


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
		elif a == "--track=range":
			opts["track"] = "range"
		elif a.begins_with("--startx="):
			opts["startX"] = float(a.get_slice("=", 1))
		elif a.begins_with("--starty="):
			opts["startY"] = float(a.get_slice("=", 1))
		elif a.begins_with("--cruise="):
			cruise = float(a.get_slice("=", 1))
		elif a == "--mute":
			mute = true
	sim = CraftSimScript.new(opts)
	if sim.kind != "circuit":
		replay = []
	levers = LeverInputScript.new()
	if sim.kind == "range" and FileAccess.file_exists(BEST_PATH):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(BEST_PATH))
		if saved is Dictionary and saved.has("best"):
			best_saved = float(saved.best)
	if cruise >= 0.0:
		inp = {"thrL": cruise, "thrR": cruise, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
	_follow_origin()
	_build_world()
	_build_craft()
	if not mute and shot_path == "":
		engine_audio = EngineAudioScript.new()
		add_child(engine_audio)
		engine_audio.setup(sim)
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
	if sim.kind != "range":
		return
	match e.type:
		"finish":
			if best_saved < 0.0 or e.t < best_saved:
				best_saved = e.t
				var f := FileAccess.open(BEST_PATH, FileAccess.WRITE)
				if f:
					f.store_string(JSON.stringify({"best": best_saved}))
				_flash("NEW BEST")
		"overrun":
			_flash("OVERRUN  -  DNF")
		"crash":
			_flash("CRASHED  -  DNF")


func _flash(msg: String) -> void:
	flash_msg = msg
	flash_until = sim.time + 5.0


## Y / respawn: on the range it restarts the sprint at the start line.
func _respawn() -> void:
	if sim.kind == "range":
		sim.restart()
		brake_point = -1.0
		flash_until = -1.0
	else:
		sim.respawn()


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
	_follow_origin()
	_sync_craft()
	_place_camera(1.0 - exp(-delta * 6.0))
	_sync_world()   # after the camera: distant anchors scale about its current position
	top_kmh = maxf(top_kmh, _kmh())
	_update_hud()
	frames += 1
	if shot_path != "" and frames == 90:
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
	return Vector3(x - org_x, h, -(y - org_y))


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
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = HAZE
	env.environment.ambient_light_color = Color(0.85, 0.78, 0.7)
	env.environment.ambient_light_energy = 0.6
	env.environment.fog_enabled = true
	env.environment.fog_light_color = Color(0.86, 0.74, 0.58)
	env.environment.fog_density = 0.0012 if sim.kind == "circuit" else 0.00035
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 30, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400.0
	add_child(sun)

	# The ground rides along under the pod; its texture offset keeps the sand fixed in the world.
	# 60 km across so its far edge sits near the true horizon even 100+ m up a jump.
	ground = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60000, 60000)
	ground.mesh = plane
	ground_mat = _grain(Color(0.79, 0.64, 0.42), 10000.0)
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
	ground_mat.uv1_offset = Vector3(fposmod(org_x / 6.0, 1.0), fposmod(-org_y / 6.0, 1.0), 0)
	if circuit_root:
		circuit_root.position = w3(0.0, 0.0)
	if range_world:
		range_world.sync(org_x, org_y)
	if landmark:
		landmark.sync(org_x, org_y, sim.time, cam.global_position)


func _build_craft() -> void:
	for k in 2:
		var e := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.7, 1.5, sim.P.engineLen)
		e.mesh = box
		e.material_override = _mat(STEEL)
		add_child(e)
		engines.append(e)
		var f := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.6
		cone.bottom_radius = 0.0
		cone.height = 1.0
		f.mesh = cone
		f.material_override = _mat(HOT, true)
		add_child(f)
		flames.append(f)
	pod_mesh = MeshInstance3D.new()
	var pbox := BoxMesh.new()
	pbox.size = Vector3(sim.P.podWidth, 1.2, sim.P.podLen)
	pod_mesh.mesh = pbox
	pod_mesh.material_override = _mat(Color(0.84, 0.86, 0.88))
	add_child(pod_mesh)
	lines = ImmediateMesh.new()
	var lmi := MeshInstance3D.new()
	lmi.mesh = lines
	var lm := _mat(Color.WHITE, true)
	lm.vertex_color_use_as_albedo = true
	lmi.material_override = lm
	add_child(lmi)
	_make_view()


## Overridable: the flat view's chase camera and 2D HUD.
func _make_view() -> void:
	cam = Camera3D.new()
	cam.fov = 70
	cam.far = 30000
	add_child(cam)
	var layer := CanvasLayer.new()
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 18)
	hud.add_theme_color_override("font_color", Color(0.1, 0.08, 0.06))
	layer.add_child(hud)
	add_child(layer)


func _sync_craft() -> void:
	var bodies := [sim.eL, sim.eR]
	for k in 2:
		var e = bodies[k]
		engines[k].position = w3(e.x, e.y, e.z + 0.1)
		var vh: float = sqrt(e.vx * e.vx + e.vy * e.vy)
		var pitch: float = atan2(e.vz, maxf(vh, 1.0)) if vh > 5.0 else 0.0
		engines[k].rotation = Vector3(pitch, e.th - PI / 2.0, 0)
		var h: float = e.heat
		var col := STEEL.lerp(HOT, h / 0.6) if h < 0.6 else HOT.lerp(WHITE, minf(1.0, (h - 0.6) / 0.4))
		(engines[k].material_override as StandardMaterial3D).albedo_color = Color(0.25, 0.25, 0.25) if e.flameout else col
		var flame_len: float = 0.2 + e.thrust * (4.0 if sim.mode == "normal" else 8.0)
		var back: Vector3 = engines[k].basis.z   # engine forward is -Z
		flames[k].visible = not e.flameout and e.thrust > 0.02
		flames[k].position = engines[k].position + back * (sim.P.engineLen / 2.0 + flame_len / 2.0)
		# cone's wide end (+Y) against the nozzle, tip trailing behind
		flames[k].basis = engines[k].basis * Basis(Vector3.RIGHT, -PI / 2.0)
		flames[k].scale = Vector3(1, flame_len, 1)
	pod_mesh.position = w3(sim.pod.x, sim.pod.y, sim.pod.z - 0.2)
	pod_mesh.rotation = Vector3(0, sim.pod.th - PI / 2.0, 0)

	lines.clear_surfaces()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	var bz := [sim.eL.z + 0.1, sim.eR.z + 0.1]
	for k in sim.cables.size():
		var c: Dictionary = sim.cables[k]
		if not c.has("ex"):
			continue
		var col := Color(0.15, 0.16, 0.18) if not c.slack else Color(0.4, 0.4, 0.4)
		lines.surface_set_color(col)
		lines.surface_add_vertex(w3(c.ex, c.ey, bz[k]))
		lines.surface_set_color(col)
		lines.surface_add_vertex(w3(c.px, c.py, sim.pod.z - 0.2))
	if not sim.binder_broken:
		var o: float = sim.P.engineLen / 2.0 - 1.0
		var a := w3(sim.eL.x + cos(sim.eL.th) * o, sim.eL.y + sin(sim.eL.th) * o, bz[0] + 0.4)
		var b := w3(sim.eR.x + cos(sim.eR.th) * o, sim.eR.y + sin(sim.eR.th) * o, bz[1] + 0.4)
		var prev := a
		for s in range(1, 7):
			var p := a.lerp(b, s / 6.0) + (Vector3(0, randf_range(-0.4, 0.4), 0) if s < 6 else Vector3.ZERO)
			lines.surface_set_color(Color(0.5, 0.85, 1.0))
			lines.surface_add_vertex(prev)
			lines.surface_set_color(Color(0.5, 0.85, 1.0))
			lines.surface_add_vertex(p)
			prev = p
	lines.surface_end()


var cam_th := 0.0

# Rigidly follow the pod; smooth only the heading. Lerping position lags tens of
# metres at 700 km/h and the craft shrinks to a toy.
func _place_camera(k: float) -> void:
	cam_th = sim.pair_th if k >= 1.0 else cam_th + CraftSimScript.wrap_angle(sim.pair_th - cam_th) * k
	var fwd := Vector3(cos(cam_th), 0, -sin(cam_th))
	var pod_p := w3(sim.pod.x, sim.pod.y, sim.pod.z)
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
	return "LAP %d  %.2fs   LAST %s  BEST %s" % [sim.lap + 1, cur,
		"--" if sim.last_lap < 0.0 else "%.2f" % sim.last_lap, "--" if sim.best_lap < 0.0 else "%.2f" % sim.best_lap]


func _update_hud() -> void:
	var mode_txt: String = {"ramjet": "RAMJET", "burner": "AFTERBURNER"}.get(sim.mode, "RAMJET ARMED" if sim.armed else "")
	hud.text = "%4d km/h   %s\nTHR %.2f | %.2f   BRK %.2f | %.2f   HEAT %d%% | %d%%   BAT %d%%   %s\n%s" % [
		_kmh(), _progress_text(), inp.thrL, inp.thrR, inp.brkL, inp.brkR,
		sim.eL.heat * 100, sim.eR.heat * 100, sim.battery * 100, mode_txt,
		"Replay: parity lap" if not replay.is_empty() else levers.source]
