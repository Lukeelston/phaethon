## Flat-screen view: chase camera over CraftSim. Sim (x, y, z) maps to world (x, z, -y),
## rendered relative to a floating origin at the pod so a 100-mile range stays precise
## (32-bit vertices are ~1.5 cm granular at 160 km; every position here is computed in 64-bit).
## User args after "--":
##   --track=range   the 100-mile test range (default: the circuit)
##   --track=gp      the grand prix: 29 km for STARFIGHTER at ~1,000 mph
##   --track=eridanus  the dual-purpose course: 199 km, a SPEEDCRAFT loop and two STARFIGHTER towns
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
const CourseAudioScript := preload("res://audio/course_audio.gd")
const TrafficAudioScript := preload("res://audio/traffic_audio.gd")
const CanopyFlash := preload("res://view/canopy.gd")
const SpeedCuesScript := preload("res://view/speed_cues.gd")
const TrafficScript := preload("res://view/traffic.gd")
const DustScript := preload("res://view/dust.gd")
const MiniMapScript := preload("res://view/minimap.gd")
const Minimap2DScript := preload("res://view/minimap_2d.gd")
const CraftModelScript := preload("res://view/craft_model.gd")
const HorizonScript := preload("res://view/horizon.gd")
const GpWorldScript := preload("res://view/gp_world.gd")
const CourseWorldScript := preload("res://view/course_world.gd")
const DawnScript := preload("res://view/dawn.gd")
const VerdantWorldScript := preload("res://view/verdant_world.gd")
const NetworkWorldScript := preload("res://view/network_world.gd")
const NetworkTrafficScript := preload("res://view/network_traffic.gd")
const DT := 1.0 / 480.0
const HAZE := Color(0.78, 0.66, 0.52)
const GROUND_PERIOD := 4096.0             # view/ground.gdshader's PERIOD
const SUN_ROT := Vector3(-30, 52, 0)       # the primary sun (DirectionalLight3D rotation, degrees)
const HORIZON := Color(0.86, 0.74, 0.58)   # fog colour = the sky at the horizon, so they meet seamlessly
const HORIZON_GREEN := Color(0.72, 0.80, 0.86)   # Eridanus: a soft blue-grey haze over the valley
# The Network's city GPs (tools/sync_gp_variants.py): the grand prix four ways, one per city, each
# in its city's landscape, entered from the city's STARFIGHTER zone (hold A; G on the keyboard)
const CITY_GP := {"DUNES": "gp_dunes", "GLACIER": "gp_glacier", "BASALT": "gp_basalt", "MESA": "gp_mesa"}
const GP_BIOME := {"gp_dunes": "desert", "gp_glacier": "ice", "gp_basalt": "basalt", "gp_mesa": "mesa"}
const BIOME_HAZE := {"desert": Color(0.86, 0.74, 0.58), "ice": Color(0.80, 0.87, 0.95), "basalt": Color(0.58, 0.55, 0.56), "mesa": Color(0.88, 0.68, 0.52)}
const TWILIGHT_HORIZON := Color(0.27, 0.27, 0.38)   # the emergency run, before dawn: a dusky violet haze ...
const TWILIGHT_TOP := Color(0.04, 0.06, 0.15)       # ... under a deep blue sky
const TWILIGHT_AMBIENT := 1.6                       # the sky's light carries the ground ...
const TWILIGHT_FILL := 0.45                         # ... with a cool shadowless fill from overhead ...
const TWILIGHT_EXPOSURE := 1.3                      # ... and the eye opened up a little

var sim
var levers
var engine_audio
var wind_audio
var course_audio             # the halls' and canopy's acoustics, the emergency run's sounds (audio/course_audio.gd)
var traffic_audio            # the Network's traffic going by (audio/traffic_audio.gd)
var replay: Array = []
var replay_i := 0
var shot_path := ""
var shot_frame := 90
var frames := 0
var acc := 0.0
var sub := 0
var cpu := {"sim": 0.0, "world": 0.0, "hud": 0.0}   # this frame's main-thread work by part, ms (the headset's FRAMES report)
var inp := {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": false}
var start_at := -1   # --at=I: start at track sample I (circuits; screenshots of a given corner)
var branch_at := -1  # --branch-at=J: start on the shade line at its sample J (with --job=emergency; screenshots)
var cruise := -1.0   # --cruise=T holds both levers at T (demos, screenshots)
var hold_brake := [0.0, 0.0]
var cam_offset := Vector3.ZERO   # --cam: debug close-up (forward, left, up)
var handling_ask := ""             # the live handling switch: "speed" / "starfighter" (VR: the console
                                   # toggle or Y-hold; keyboard: M), sent with every step
static var track_override := ""    # an in-game track switch (VR: hold the menu button) wins over --track;
                                   # static, so it survives the scene reload that does the switch
static var job_override := ""      # the job to fly ("emergency": the emergency run; "none": no job), wins over --job; static too
var eye := Vector3.INF            # --eye / --look: a fixed debug camera at sim (x, y, h), aimed at another point
var look := Vector3.ZERO
var best_saved := -1.0     # sprint best, persisted across launches
static var best_dir := "user://"   # where the emergency run's best lives; static so tests point it elsewhere before a view's build
var _job_started := false  # the emergency run's clock has started (the SPEED AUTHORIZED flash)
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
var minimap                  # the path ahead (view/minimap.gd), for the overlays
var minimap_2d: Control      # the flat view's (the headset has vr/minimap_panel.gd)
var cues: Node3D
var traffic: Node3D
var horizon: Node3D
var gp_world: Node3D
var course_world: Node3D     # Eridanus: the chunked trackside (view/course_world.gd)
var network_world: Node3D    # the Network: its streamed roads, signs and skylines (view/network_world.gd)
var net_target := -1         # the Network: the city the dash and the minimap point to
var net_found := {}          # the Network: the cities found (best_dir + network.json, with the bests)
var net_best := {}           # the Network: "FROM>TO" -> best time, s
var net_beaten := {}         # the Network: racer -> times you've beaten them
var traffic_net: Node3D      # the Network: its traffic and racers (view/network_traffic.gd)
var dawn: Node3D             # the emergency run: the dawn's front (view/dawn.gd)
var stars: MeshInstance3D    # the emergency run: the night still over the twilight (view/stars.gdshader)
var light_preset := "afternoon"   # "afternoon", or "twilight" on a job (the emergency run: before dawn)
var burn_rect: ColorRect     # the flat view's burn to white when the dawn catches you
var verdant_world: Node3D    # ... and the green valley round it (view/verdant_world.gd)
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
		elif a.begins_with("--track="):   # range, gp, eridanus, network, a city GP (gp_dunes, gp_glacier, gp_basalt, gp_mesa)
			opts["track"] = a.get_slice("=", 1)
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
		elif a.begins_with("--branch-at="):
			branch_at = int(a.get_slice("=", 1))
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
	var job := resolve_job(OS.get_cmdline_user_args(), job_override)
	if job != "" and opts.get("track", "") != "network":
		opts["job"] = job
	if opts.get("track", "") == "network":   # back where you last arrived; what you've found, your bests
		var saved = JSON.parse_string(FileAccess.get_file_as_string(_net_path())) if FileAccess.file_exists(_net_path()) else null
		if saved is Dictionary:
			for k in saved.get("found", []):
				net_found[int(k)] = true
			net_best = saved.get("best", {})
			net_beaten = saved.get("beaten", {})
			if int(saved.get("last", -1)) >= 0 and int(saved.get("last", -1)) < CraftSimScript.NET_CITIES.size():
				opts["startCity"] = int(saved.last)
	if "--pod=heavy" in OS.get_cmdline_user_args():   # the heavy pod (Luke: "giving the pod some weight"): 1,500 kg, not
		opts["podMass"] = 1500.0                       # 500, with thrust and drag scaled to the total mass so the
		opts["forceScale"] = 3900.0 / 2900.0          # speed and acceleration are as before
	sim = CraftSimScript.new(opts)
	if sim.kind == "network":
		for k in sim.net.found:
			net_found[k] = true
		net_target = _net_next_target()
	if start_at >= 0 and sim.kind == "circuit":
		sim.respawn(-1, start_at)
	if branch_at >= 0 and not sim.branches.is_empty():
		_place_on_branch(branch_at)
	if sim.kind != "circuit":
		replay = []
	levers = LeverInputScript.new()
	minimap = MiniMapScript.new()
	minimap.gp_cities = CITY_GP.keys()   # (the whole map marks their GPs)
	minimap.setup(sim)
	minimap.target = net_target
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
	if sim.kind == "network":
		dust.road_spray()
	if not mute and shot_path == "":
		engine_audio = EngineAudioScript.new()
		add_child(engine_audio)
		engine_audio.setup(sim)
		wind_audio = WindAudioScript.new()
		add_child(wind_audio)
		wind_audio.setup(sim)
		if sim.kind == "network":
			traffic_audio = TrafficAudioScript.new()
			add_child(traffic_audio)
			traffic_audio.setup()
			course_audio = CourseAudioScript.new()   # the cities' halls ring as Eridanus' do
			add_child(course_audio)
			course_audio.setup(sim)
			if network_world:
				course_audio.net_halls = network_world.halls
		if sim.course and (not sim.covered_ramps.is_empty() or not sim.job.is_empty()):
			var t0 := Time.get_ticks_msec()
			course_audio = CourseAudioScript.new()
			add_child(course_audio)
			course_audio.setup(sim)
			print("AUDIO: CourseAudio up in %d ms (%s)" % [Time.get_ticks_msec() - t0, "the job" if not sim.job.is_empty() else "the halls"])
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
	if handling_ask != "":
		inp["handling"] = handling_ask
	sim.step(inp, DT)
	for e in sim.events:
		_on_event(e)
	sim.events.clear()


func _on_event(e: Dictionary) -> void:
	if e.type == "bump":   # traffic's forcefield: a shove you feel, not a hit (and see: the field flares)
		_on_hit(e.who, 0.5)
		_field_flash(1.0)
		return
	if e.type == "hit" or e.type == "scrape":
		_field_flash(1.0 if e.type == "hit" else 0.45)
	if e.type == "smash":
		_flash("SMASHED")
	if e.type != "land" and e.type != "scrape":   # every hit, crash, flameout, lap... in the log
		print("EVENT %s %s t=%.2f" % [e.type, e.get("who", ""), sim.time])
	if e.type == "hit":
		_on_hit(e.who, 1.0)
	elif e.type == "scrape":
		_on_hit(e.who, 0.35)
	if sim.kind == "network" and e.type == "arrive":
		_net_arrived(e)
	if sim.kind == "network":
		_net_jump_event(e)
		return
	if not sim.job.is_empty():   # the emergency run: its best is the run's time, made, never a lap
		if e.type == "job" and e.stage == "done" and (best_saved < 0.0 or float(sim.job.t) < best_saved):
			best_saved = sim.job.t
			var fj := FileAccess.open(_best_path(), FileAccess.WRITE)
			if fj:
				fj.store_string(JSON.stringify({"best": best_saved}))
		return
	if sim.course and e.type == "lap":
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
	if sim.kind == "network":
		return _net_path()
	if not sim.job.is_empty():
		return best_dir + "%s_emergency_best.json" % sim.track_name
	var h: String = sim.P.handling
	if sim.track_name == "gp":
		return "user://gp_best_%s.json" % h
	if GP_BIOME.has(sim.track_name):
		return "user://%s_best_%s.json" % [sim.track_name, h]
	if sim.course:
		return "user://%s_best.json" % sim.track_name   # one record: every lap flies both modes
	return "user://sprint_best.json" if h == "speed" else "user://sprint_best_%s.json" % h


func _load_best() -> void:
	best_saved = -1.0
	if (sim.kind == "range" or sim.course) and FileAccess.file_exists(_best_path()):
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


## What the engine sound hears: the levers, or with the gearbox the gear's revs (they climb through
## each gear and fall when you shift up: Luke, "rise and fall like actual gears"), eased by how hard
## you're on each lever (lifting off drops the note toward idle; the revs stay with the speed).
func _engine_inp() -> Dictionary:
	if not inp.has("gearRpm"):
		return inp
	var gate: float = sim.P.gate
	var out := inp.duplicate()
	for k in ["thrL", "thrR"]:
		var lever := minf(float(inp[k]), gate) / gate
		var spool: float = preload("res://input/quest_controls.gd").engine_spool(float(inp.gearRpm), lever)
		out[k] = (spool * gate) if float(inp[k]) < gate else float(inp[k])   # (the burner's detent: as it was)
	return out


## The forcefield flares on a bump or a wall's push (view/canopy.gd flash).
func _field_flash(amount: float) -> void:
	if craft and craft.canopy:
		CanopyFlash.flash(craft.canopy, amount)


## The handling as the pilot sees it: SPEEDCRAFT / STARFIGHTER, and STARFIGHTER waiting for the
## craft to slow below 1,250 mph.
func handling_text() -> String:
	if handling_ask == "starfighter" and sim.hblend == 0.0:
		return "STARFIGHTER AT 1,250"
	return "STARFIGHTER" if sim.hblend >= 0.5 else "SPEEDCRAFT"


const FLIP_COOLDOWN_MS := 1000   # between handling flips, whatever throws them (Luke: "a 1 second cool down between flips")
var _flip_at := -100000

## Ask for a handling: refused (false) within FLIP_COOLDOWN_MS of the last flip, from the MODE
## switch, the Y hold or the M key alike.
func ask_handling(mode: String) -> bool:
	var now := Time.get_ticks_msec()
	if now - _flip_at < FLIP_COOLDOWN_MS:
		return false
	_flip_at = now
	handling_ask = mode
	return true


## Flip the live handling switch: SPEEDCRAFT <-> STARFIGHTER (STARFIGHTER waits for 1,250 mph).
func toggle_handling() -> void:
	var cur: String = handling_ask if handling_ask != "" else String(sim.hwant)
	if not ask_handling("speed" if cur == "starfighter" else "starfighter"):
		return
	_flash("%s%s" % ["STARFIGHTER" if handling_ask == "starfighter" else "SPEEDCRAFT",
		"  (below 1,250 mph)" if handling_ask == "starfighter" and sim.hblend == 0.0 else ""])


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_M:
		toggle_handling()
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_T:
		net_cycle_target()
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_G:
		enter_city_gp()


# --- the Network: the target city, arrivals, bests ---

func _net_path() -> String:
	return best_dir + "network.json"


## The nearest city you haven't found (straight line), or once you've found them all the nearest
## other than the one you're at.
func _net_next_target() -> int:
	var best := -1
	var bd := INF
	for pass_ in 2:
		for k in sim.cities.size():
			if k == int(sim.net.from) or (pass_ == 0 and net_found.has(k)):
				continue
			var d := Vector2(sim.cities[k].cx - sim.pod.x, sim.cities[k].cy - sim.pod.y).length()
			if d < bd:
				bd = d
				best = k
		if best >= 0:
			return best
	return best


## The city GP you can drop into from here: in a city's STARFIGHTER zone (its road, its mode 0), the
## city's GP ("" elsewhere, or a city without one).
func net_city_gp() -> String:
	if sim.kind != "network":
		return ""
	var R = sim.roads[sim.pod.path]
	if R.mode[clampi(sim.pod.hint, 0, R.N - 1)] != 0:
		return ""
	for c in sim.cities:
		if int(c.road) == sim.pod.path:
			return CITY_GP.get(c.name, "")
	return ""


## Into the city's GP: the scene again on its track (the menu hold brings you back to the Network).
func enter_city_gp() -> void:
	var gp := net_city_gp()
	if gp == "":
		return
	print("TRACK: switching network -> %s" % gp)
	track_override = gp
	job_override = "none"
	get_tree().call_deferred("reload_current_scene")


var gp_skyline: Node3D   # a city GP's towers round the circuit


## A city GP's towers: a ring of them round the circuit, 1.5-7 km off its bounds, in the city's
## colours (view/network_world.gd's palette and view/skyline.gdshader).
func _gp_skyline(biome: String) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in sim.N:
		lo = Vector2(minf(lo.x, sim.tpx[i]), minf(lo.y, sim.tpy[i]))
		hi = Vector2(maxf(hi.x, sim.tpx[i]), maxf(hi.y, sim.tpy[i]))
	var pal: Array = NetworkWorldScript.PALETTE.get(biome, NetworkWorldScript.PALETTE.verdant)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(biome)
	var xfs := []
	var cols := []
	var tries := 0
	while xfs.size() < 420 and tries < 6000:
		tries += 1
		var x := rng.randf_range(lo.x - 7000.0, hi.x + 7000.0)
		var y := rng.randf_range(lo.y - 7000.0, hi.y + 7000.0)
		var out := maxf(maxf(lo.x - x, x - hi.x), maxf(lo.y - y, y - hi.y))   # how far outside the bounds
		if out < 1500.0:
			continue
		var tall := lerpf(900.0, 160.0, clampf((out - 1500.0) / 5500.0, 0.0, 1.0)) * rng.randf_range(0.55, 1.15)
		var foot := rng.randf_range(70.0, 190.0)
		xfs.append(Transform3D(Basis.from_scale(Vector3(foot, tall, foot * rng.randf_range(0.6, 1.4))).rotated(Vector3.UP, rng.randf() * PI), Vector3(x, tall / 2.0, -y)))
		cols.append((pal[0] as Color).lerp(pal[1], rng.randf()))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = NetworkWorldScript.Kit.box(Vector3.ONE)
	mm.instance_count = xfs.size()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
		mm.set_instance_color(k, cols[k])
	gp_skyline = Node3D.new()
	gp_skyline.name = "gp_skyline"
	add_child(gp_skyline)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = preload("res://view/skyline.gdshader")
	m.set_shader_parameter("crown", Vector3(pal[2].r, pal[2].g, pal[2].b))
	m.set_shader_parameter("haze_col", Vector3(BIOME_HAZE[biome].r, BIOME_HAZE[biome].g, BIOME_HAZE[biome].b))
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(lo.x - 8000.0, 0.0, -hi.y - 8000.0), Vector3(hi.x - lo.x + 16000.0, 1200.0, hi.y - lo.y + 16000.0))
	gp_skyline.add_child(mmi)


## The next city round as the target (the T key; in the headset the right A button).
func net_cycle_target() -> void:
	if sim.kind != "network":
		return
	for step in range(1, sim.cities.size() + 1):
		var k: int = (net_target + step) % sim.cities.size()
		if k != int(sim.net.from):
			net_target = k
			break
	if minimap:
		minimap.target = net_target
	_flash("TARGET  %s" % sim.cities[net_target].name)


func _net_arrived(e: Dictionary) -> void:
	var to: String = sim.cities[int(e.city)].name
	var from: String = sim.cities[int(e.from)].name
	var key := "%s>%s" % [from, to]
	var t := float(e.t)
	var prev: float = float(net_best.get(key, -1.0))
	var record := prev < 0.0 or t < prev
	if record:
		net_best[key] = t
	net_found[int(e.city)] = true
	_flash("ARRIVED %s  %s%s" % [to, _mmss(t, true), "  NEW BEST" if record else "  BEST %s" % _mmss(prev, true)])
	_net_save(int(e.city))
	net_target = _net_next_target()
	if minimap:
		minimap.target = net_target


func _net_save(last: int) -> void:
	var fj := FileAccess.open(_net_path(), FileAccess.WRITE)
	if fj:
		fj.store_string(JSON.stringify({"found": net_found.keys(), "last": last, "best": net_best, "beaten": net_beaten}))


## A race's end (the traffic reports it once): the flash, the tally.
func _net_race_result() -> void:
	var res: String = traffic_net.race_result
	traffic_net.race_result = ""
	var who: String = traffic_net.race_name
	match res:
		"won":
			net_beaten[who] = int(net_beaten.get(who, 0)) + 1
			_flash("RACE WON  %s  (beaten %dx)" % [who, int(net_beaten[who])])
			_net_save(int(sim.net.from))
		"lost":
			_flash("RACE LOST  %s" % who)
		"peeled":
			_flash("%s PEELED OFF" % who)


## The dash on the Network: the target city and how far (straight line), where you left and your
## clock since; a racer's line while one's about.
func _net_text() -> String:
	if sim.time < flash_until:
		return flash_msg
	if sim.pod.off_road:   # in the air, or down on the open ground
		if net_air_t0 >= 0.0 and sim.pod.z - sim.P.rideH > 4.0:
			return "AIRBORNE  %.1f s   %d FT" % [sim.time - net_air_t0, roundi(sim.pod.z / 0.3048)]
		var k := _net_nearest_ramp()
		if k != net_ramp:
			net_ramp = k
		if k >= 0:
			var R = sim.roads[int(sim.onramps[k][1])]
			var city: String = sim.cities[int(sim.onramps[k][0])].name
			minimap.waypoint = {"name": "%s ON-RAMP" % city, "x": R.px[0], "y": R.py[0]}
			return "OFF THE ROAD   %s ON-RAMP  %s   (OR RESTART)" % [city, _far(Vector2(R.px[0] - sim.pod.x, R.py[0] - sim.pod.y).length())]
		return "OFF THE ROAD   RESTART FOR THE LAST CITY"
	if not minimap.waypoint.is_empty():
		minimap.waypoint = {}
	if traffic_net and traffic_net.race_text() != "":
		return traffic_net.race_text()
	var line := ""
	if net_target >= 0:
		var c: Dictionary = sim.cities[net_target]
		line = "%s  %s" % [c.name, _far(Vector2(c.cx - sim.pod.x, c.cy - sim.pod.y).length())]
	var since: String = sim.cities[int(sim.net.from)].name
	var gp := net_city_gp()
	if gp != "":
		line += "   HOLD A: %s GP" % gp.substr(3).to_upper()
	if float(sim.net.t0) >= 0.0:
		return "%s   FROM %s  %s" % [line, since, _mmss(sim.time - float(sim.net.t0))]
	return "%s   AT %s: push the levers" % [line, since]


## The jumps and the open ground (phase 3): off a lip, the airtime counts on the dash; caught by a
## deck, how long you flew; on the open ground, the nearest city's on-ramp on the dash and the map.
var net_air_t0 := -1.0     # when the pod left a lip (-1: not in the air off one)
var net_ramp := -1         # the on-ramp the dash points to (off the roads), -1 none


func _net_jump_event(e: Dictionary) -> void:
	if e.type == "airborne":
		net_air_t0 = sim.time if e.lip else -1.0
	elif e.type == "catch":
		if net_air_t0 >= 0.0:
			_flash("CAUGHT  %.1f s IN THE AIR  %s MPH" % [sim.time - net_air_t0, _grouped_mph()])
		net_air_t0 = -1.0
	elif e.type == "ground":
		net_air_t0 = -1.0
		_flash("OFF THE ROAD  -  FIND AN ON-RAMP  (OR RESTART)")
	elif e.type == "onroad":
		net_ramp = -1
		minimap.waypoint = {}
		_flash("BACK ON THE ROAD")


func _grouped_mph() -> String:
	var mph := roundi(sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) * 2.236936)
	return ("%d,%03d" % [mph / 1000, mph % 1000]) if mph >= 1000 else str(mph)


## Off the roads: the nearest on-ramp's start, set as the minimap's waypoint. -> its index, -1 none.
func _net_nearest_ramp() -> int:
	var best := -1
	var bd := INF
	for k in sim.onramps.size():
		var R = sim.roads[int(sim.onramps[k][1])]
		var d := Vector2(R.px[0] - sim.pod.x, R.py[0] - sim.pod.y).length()
		if d < bd:
			bd = d
			best = k
	return best


func _flash(msg: String) -> void:
	flash_msg = msg
	flash_until = sim.time + 5.0


## Y: a fresh start. The range restarts the sprint at the start line, a circuit puts you back
## on the grid; both with whole engines (wall damage otherwise stays until you repair it).
func _respawn() -> void:
	# off the roads (a missed jump), the restart is the nearest start point: the nearest city you've
	# found (Luke: "reset to the nearest start-point"); on them, the last city as ever
	var near := -1
	if sim.kind == "network" and sim.pod.off_road:
		var bd := INF
		for k in sim.cities.size():
			var c: Dictionary = sim.cities[k]
			var d := Vector2(c.cx - sim.pod.x, c.cy - sim.pod.y).length()
			if sim.net.found.has(k) and d < bd:
				bd = d
				near = k
	if near >= 0:
		sim.net.from = near
	sim.restart()
	net_air_t0 = -1.0
	if minimap:
		minimap.waypoint = {}
	brake_point = -1.0
	flash_until = -1.0
	_job_started = false


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
	var t_sim := Time.get_ticks_usec()
	while acc >= DT:
		_sim_step()
		acc -= DT
	cpu.sim = (Time.get_ticks_usec() - t_sim) / 1000.0
	_track_braking()
	if not sim.job.is_empty() and not _job_started and sim.job.t0 != null:
		_job_started = true   # the clock's running: you're an emergency
		_flash("SPEED AUTHORIZED  /  SHADE LINE OPEN")
	if engine_audio:
		engine_audio.update(_engine_inp(), delta)
	if wind_audio:
		wind_audio.update(inp, delta)
	if course_audio:
		course_audio.update(delta, dawn.dist if dawn else INF)
	_follow_origin()
	_sync_craft(delta)
	cues.sync(sim, delta)
	dust.sync(sim, delta)
	_place_camera(1.0 - exp(-delta * 6.0))
	craft.sync_cables(sim, delta)   # after the camera: in VR the cables' pod end rides the cockpit
	var t_world := Time.get_ticks_usec()
	_sync_world()   # after the camera: distant anchors scale about its current position
	cpu.world = (Time.get_ticks_usec() - t_world) / 1000.0
	top_kmh = maxf(top_kmh, _kmh())
	var t_hud := Time.get_ticks_usec()
	_update_hud()
	cpu.hud = (Time.get_ticks_usec() - t_hud) / 1000.0
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


## The job to fly: the override ("none": no job, whatever the command line says), else --job=.
static func resolve_job(args: PackedStringArray, override: String) -> String:
	if override == "none":
		return ""
	if override != "":
		return override
	for a in args:
		if a.begins_with("--job="):
			return a.get_slice("=", 1)
	return ""


## Debug start (screenshots): every body on branch 0's sample j, laid out as respawn lays them
## on the main road, at rest.
func _place_on_branch(j: int) -> void:
	var B = sim.branches[0]
	j = clampi(j, 0, B.N - 1)
	var f: int = B.from_i
	sim.respawn(-1, f)
	var dth: float = atan2(B.ty[j], B.tx[j]) - atan2(sim.tty[f], sim.ttx[f])
	for b in sim.bodies:
		var rx: float = b.x - sim.tpx[f]
		var ry: float = b.y - sim.tpy[f]
		var al: float = rx * sim.ttx[f] + ry * sim.tty[f]
		var ac: float = rx * sim.tnx[f] + ry * sim.tny[f]
		b.x = B.px[j] + al * B.tx[j] + ac * B.nx[j]
		b.y = B.py[j] + al * B.ty[j] + ac * B.ny[j]
		b.th += dth
		b.path = 1
		b.hint = mini(B.N - 1, j + roundi(al / 12.0))


func _follow_origin() -> void:
	org_x = sim.pod.x
	org_y = sim.pod.y


## A sim body's point -> render position: on the Network a body's height is its own (the roads'
## heights are real in the sims: the deck lock, the jumps), elsewhere it's over the surface (w3).
func wz(x: float, y: float, z: float) -> Vector3:
	if sim and sim.kind == "network":
		return Vector3(x - org_x, z, -(y - org_y))
	return w3(x, y, z)


## Sim point -> render position, relative to the floating origin. On the shade line (the pod on a
## branch) the point rides its twisted road (CraftModel.road_xf: rolled over, raised).
func w3(x: float, y: float, h := 0.0) -> Vector3:
	if sim and sim.pod.path > 0 and sim.kind != "network":
		return road_xf(x, y) * Vector3(x - org_x, h, -(y - org_y))
	return Vector3(x - org_x, h + surface(x, y).x, -(y - org_y))


## The banked GP's surface under (x, y), on the pod's road: Vector2(height, bank radians, + = down
## to the left). Everything placed with w3 rides it; (0, 0) off the GP. On the shade line: its
## centreline's height (the corkscrews' climb) and no bank (its roll is road_xf's).
func surface(x: float, y: float) -> Vector2:
	if sim and sim.kind == "network" and sim.pod.off_road:
		return Vector2.ZERO   # off the roads: the open ground
	return sim.surface_at(x, y, sim.pod.hint, sim.pod.path) if sim else Vector2.ZERO


## The pod's road's frame at (x, y) (CraftModel.road_xf): identity on the main road.
func road_xf(x: float, y: float) -> Transform3D:
	return CraftModelScript.road_xf(sim, x, y, org_x, org_y)


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
	var green: bool = sim.track_name == "eridanus"
	var lush: bool = green or sim.kind == "network"   # the Network: Eridanus' clear blue-grey air
	# the emergency run is flown before dawn (Luke: a dim look just for the job; free Eridanus keeps
	# its afternoon): both suns under the horizon on the dawn's side (view/dawn.gd), the sky's light
	# carrying the ground so its grain, the asphalt's joints, the dust and the lights still read
	var tw: bool = not sim.job.is_empty()
	light_preset = "twilight" if tw else "afternoon"
	var hz := TWILIGHT_HORIZON if tw else (HORIZON_GREEN if lush else HORIZON)
	if sim.kind == "network" and not tw:
		hz = Color(0.58, 0.68, 0.80)   # the Network: a deeper blue haze (the pale one fused the horizon into a white band)
	var gp_biome: String = GP_BIOME.get(sim.track_name, "")
	if gp_biome != "":
		hz = BIOME_HAZE[gp_biome]
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.50, 0.80) if lush else Color(0.40, 0.55, 0.74)
	sky_mat.sky_horizon_color = hz
	sky_mat.sky_curve = 0.09
	sky_mat.ground_horizon_color = hz
	sky_mat.ground_bottom_color = Color(0.36, 0.44, 0.28) if lush else Color(0.62, 0.5, 0.36)
	sky_mat.sun_angle_max = 1.5
	sky_mat.sun_curve = 0.05
	if tw:
		sky_mat.sky_top_color = TWILIGHT_TOP
		sky_mat.ground_bottom_color = Color(0.07, 0.09, 0.07)
		sky_mat.sun_angle_max = 50.0   # the suns' glow under the dawn's horizon spreads up the sky
		sky_mat.sun_curve = 0.12
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
	en.fog_light_color = hz
	# (the valley's air is clearer than the desert's dust: Eridanus' 12 km boards come up readable)
	en.fog_density = 0.0012 if sim.kind == "circuit" and not sim.course else (0.0002 if green else 0.00035)
	if sim.kind == "network":
		en.fog_density = 0.00016   # the roads stream in 20 km out: the haze takes them there (the skylines carry their own)
	en.fog_sky_affect = 0.0
	en.fog_sun_scatter = 0.05 if sim.kind == "network" else 0.18   # the haze brightens toward the suns (the Network's, less: no white band)
	if tw:
		en.ambient_light_sky_contribution = 1.0
		en.ambient_light_energy = TWILIGHT_AMBIENT
		en.tonemap_exposure = TWILIGHT_EXPOSURE
		en.fog_sun_scatter = 0.0
		en.glow_intensity = 0.7   # the lamps carry more of the scene
	add_child(env)
	if tw:
		# no sun yet: a cool, shadowless light from the high sky stands in for the dome's glow
		var sky_fill := DirectionalLight3D.new()
		sky_fill.rotation_degrees = Vector3(-62, 20, 0)
		sky_fill.light_color = Color(0.62, 0.70, 0.95)
		sky_fill.light_energy = TWILIGHT_FILL
		sky_fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
		add_child(sky_fill)
	else:
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
	ground_mat.set_shader_parameter("verdant", 1.0 if green else 0.0)
	ground_mat.set_shader_parameter("playa_half", RangeWorldScript.PLAYA_HALF)   # the runway's dry lake; scrub beyond
	ground.material_override = ground_mat
	ground.position = Vector3(0, -0.05, 0)
	add_child(ground)
	if tw:
		dawn = DawnScript.new()   # the emergency run's dawn (its suns, its wall, the land it lights)
		add_child(dawn)
		dawn.build(self)
		stars = MeshInstance3D.new()   # the night still over it: a dome of stars 110 km out
		stars.name = "stars"
		var dome := SphereMesh.new()
		dome.radius = 110000.0
		dome.height = 220000.0
		dome.radial_segments = 48
		dome.rings = 24
		stars.mesh = dome
		var sm := ShaderMaterial.new()
		sm.shader = preload("res://view/stars.gdshader")
		var u := Vector2(cos(sim.P.dawnDir), sin(sim.P.dawnDir))
		sm.set_shader_parameter("dawn_dir", Vector3(-u.x, 0.0, u.y))   # toward where it comes from
		stars.material_override = sm
		stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stars.extra_cull_margin = 16384.0
		add_child(stars)

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

	if sim.kind == "network":
		var t0 := Time.get_ticks_msec()
		network_world = NetworkWorldScript.new()
		add_child(network_world)
		network_world.build(sim, self)
		traffic_net = NetworkTrafficScript.new()
		add_child(traffic_net)
		traffic_net.build(sim, self, network_world)
		horizon = HorizonScript.new()
		add_child(horizon)
		horizon.build(self, hz)
		print("NETWORK: %d roads, %d cities (%d towers) set up in %d ms" % [sim.roads.size(), sim.cities.size(), network_world.towers, Time.get_ticks_msec() - t0])
		return

	if green:
		course_world = CourseWorldScript.new()
		add_child(course_world)
		course_world.build(sim, self)
		verdant_world = VerdantWorldScript.new()
		add_child(verdant_world)
		verdant_world.build(sim, self)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for i in sim.N:
			lo = Vector2(minf(lo.x, sim.tpx[i]), minf(lo.y, sim.tpy[i]))
			hi = Vector2(maxf(hi.x, sim.tpx[i]), maxf(hi.y, sim.tpy[i]))
		# the bbox's ellipse cuts its corners (the track ran under the hills there): grow it until
		# every sample is inside, so each ring's front edge stays its full distance off the track
		var c := (lo + hi) / 2.0
		var half := (hi - lo) / 2.0
		var k := 1.0
		for i in sim.N:
			k = maxf(k, Vector2((sim.tpx[i] - c.x) / half.x, (sim.tpy[i] - c.y) / half.y).length())
		horizon = HorizonScript.new()
		add_child(horizon)
		horizon.build_course(self, hz, c, half * k, true)
		return

	if sim.track_name == "gp" or gp_biome != "":
		gp_world = GpWorldScript.new()
		add_child(gp_world)
		gp_world.build(sim, self)
		horizon = HorizonScript.new()
		add_child(horizon)
		horizon.build(self, hz)
		if gp_biome != "":   # a city's GP: its landscape underfoot, its towers round the circuit
			for b in ["ice", "basalt", "mesa"]:
				ground_mat.set_shader_parameter(b, 1.0 if b == gp_biome else 0.0)
			_gp_skyline(gp_biome)
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
	if course_world:
		course_world.sync(org_x, org_y)
	if network_world:
		network_world.sync(org_x, org_y)
		_net_biome()
		if course_audio and course_audio.net_halls.is_empty():
			course_audio.net_halls = network_world.halls
	if traffic_net:
		traffic_net.update(get_process_delta_time())
		if traffic_audio:   # the whooshes: the vehicles within 3 km going by
			var pv := Vector2(sim.pod.vx, sim.pod.vy)
			var cars := []
			for c in traffic_net.cars:
				if absf(c.x - sim.pod.x) < 3000.0 and absf(c.y - sim.pod.y) < 3000.0:
					cars.append([c.id, c.x, c.y, sim.net_height(c.road, c.f) + 2.0, c.v * c.hx, c.v * c.hy])
			traffic_audio.set_speed(pv.length())
			traffic_audio.update(Vector2(sim.pod.x, sim.pod.y), pv.normalized() if pv.length() > 1.0 else Vector2.ZERO, cars, wz, get_process_delta_time())
		if traffic_net.race_result != "":
			_net_race_result()
		if minimap:
			minimap.marks = traffic_net.marks(sim.pod.x, sim.pod.y, 40000.0)
	if verdant_world:
		verdant_world.sync(org_x, org_y)
	if gp_skyline:
		gp_skyline.position = Vector3(-org_x, 0.0, org_y)
	if dawn:
		dawn.sync(sim, get_process_delta_time())
		if stars:   # the stars fade as the front nears
			(stars.material_override as ShaderMaterial).set_shader_parameter("fade", clampf(absf(dawn.dist) / 60000.0, 0.15, 1.0))
		if burn_rect:
			burn_rect.color = Color(1.0, 0.97, 0.9, dawn.burn)
	if landmark:
		landmark.sync(org_x, org_y, sim.time, cam.global_position)


## The Network's ground: each city's landscape, weighted by nearness (inverse distance, 4th power),
## so the land changes from one to the next over tens of km.
func _net_biome() -> void:
	var w := {"desert": 0.0, "verdant": 0.0, "ice": 0.0, "basalt": 0.0, "mesa": 0.0}
	var tot := 0.0
	for c in sim.cities:
		var d := maxf(Vector2(c.cx - org_x, c.cy - org_y).length(), 2000.0) / 1000.0
		var k := 1.0 / (d * d * d * d)
		w[c.biome] = w.get(c.biome, 0.0) + k
		tot += k
	for b in w:
		w[b] = w[b] / tot
	biome = w
	var dv: float = w.desert + w.verdant
	ground_mat.set_shader_parameter("verdant", w.verdant / maxf(dv, 1e-6))
	ground_mat.set_shader_parameter("ice", w.ice)
	ground_mat.set_shader_parameter("basalt", w.basalt)
	ground_mat.set_shader_parameter("mesa", w.mesa)


var biome := {}   # the Network: this frame's landscape weights (tests read it)


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
	cam.far = 120000   # the backdrop peaks sit at 45-57 km; Eridanus' far ranges up to ~100 km away
	add_child(cam)
	var layer := CanvasLayer.new()
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 18)
	hud.add_theme_color_override("font_color", Color(0.1, 0.08, 0.06))
	layer.add_child(hud)
	minimap_2d = Minimap2DScript.new()
	minimap_2d.visible = sim.kind == "circuit" or sim.kind == "network"
	layer.add_child(minimap_2d)
	if light_preset == "twilight":
		hud.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))   # light on the dark sky
	burn_rect = ColorRect.new()   # caught by the dawn: the view burns to white
	burn_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	burn_rect.color = Color(1.0, 0.97, 0.9, 0.0)
	burn_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(burn_rect)
	add_child(layer)


func _sync_craft(delta: float) -> void:
	craft.sync(sim, inp, delta)


var cam_th := 0.0

# Rigidly follow the pod; smooth only the heading. Lerping position lags tens of
# metres at 700 km/h and the craft shrinks to a toy.
func _place_camera(k: float) -> void:
	cam_th = sim.pair_th if k >= 1.0 else cam_th + CraftSimScript.wrap_angle(sim.pair_th - cam_th) * k
	var fwd := Vector3(cos(cam_th), 0, -sin(cam_th))
	var pod_p := wz(sim.pod.x, sim.pod.y, sim.pod.z)
	if eye != Vector3.INF:
		cam.position = w3(eye.x, eye.y, eye.z)
		cam.look_at(w3(look.x, look.y, look.z), Vector3.UP)
		return
	if cam_offset != Vector3.ZERO:
		var left := Vector3(-sin(cam_th), 0, -cos(cam_th))
		var mid := wz((sim.eL.x + sim.eR.x) / 2.0, (sim.eL.y + sim.eR.y) / 2.0, (sim.eL.z + sim.eR.z) / 2.0)
		cam.position = pod_p + fwd * cam_offset.x + left * cam_offset.y + Vector3.UP * cam_offset.z
		cam.look_at(mid, Vector3.UP)
		return
	cam.position = pod_p - fwd * 12.0 + Vector3.UP * 4.5
	cam.look_at(pod_p + fwd * 40.0 + Vector3.UP * 1.0, Vector3.UP)


## Second HUD line: lap info on the circuit, mileage and top speed on the range; the job's line on
## the emergency run.
func _progress_text() -> String:
	if sim.kind == "network":
		return _net_text()
	if not sim.job.is_empty():
		return _job_text()
	if sim.kind == "range":
		var best := "--" if best_saved < 0.0 else "%.2fs" % best_saved
		var braked := "" if brake_point < 0.0 else "   braked %.2f mi out" % (brake_point / 1609.344)
		if sim.time < flash_until:
			return "%s   BEST %s" % [flash_msg, best]
		if sim.run_active:
			var togo: float = sim.BOX_X - sim.pod.x
			var dist := "%.2f mi" % (togo / 1609.344) if absf(togo) >= 160.9344 else "%d ft" % int(togo * 3.28084)
			return "TO BOX %s   RUN %.1fs   BEST %s" % [dist, sim.time - sim.run_start, best]
		if sim.result.get("type", "") == "finish":
			return "STOPPED IN BOX  %.2fs   %.1f ft off%s\nBEST %s   (Y: go again)" % [
				sim.result.t, sim.result.err * 3.28084, braked, best]
		return "READY: push the levers   BEST %s" % best
	var cur: float = 0.0 if sim.lap_start < 0.0 else sim.time - sim.lap_start
	if sim.course:
		var rec := "--" if best_saved < 0.0 else "%.2f" % best_saved
		if sim.time < flash_until:
			return "%s   RECORD %s" % [flash_msg, rec]
		return "LAP %d  %.2fs   LAST %s   RECORD %s" % [sim.lap + 1, cur, "--" if sim.last_lap < 0.0 else "%.2f" % sim.last_lap, rec]
	return "LAP %d  %.2fs   LAST %s  BEST %s" % [sim.lap + 1, cur,
		"--" if sim.last_lap < 0.0 else "%.2f" % sim.last_lap, "--" if sim.best_lap < 0.0 else "%.2f" % sim.best_lap]


## The emergency run's line on the dash, readable at a glance: the briefing (the job, where, and
## when the dawn reaches it), HOLD on the pad counting down, HOME and the dawn's time to the
## deadline, then the result against the best.
func _job_text() -> String:
	var J: Dictionary = sim.job
	var t: float = sim.job_time()
	var dl: Dictionary = sim.job_deadline()
	var dawn := "UNDER COVER" if dl.is_empty() else "DAWN " + _mmss(sim.t_lit(dl.x, dl.y) - t)
	match J.stage:
		"done":
			return "MADE IT  %+.1f s  (%s)\nRUN %s   BEST %s" % [J.margin, "SHADE LINE" if J.route == "shade" else "OPEN", _mmss(J.t, true),
				"--" if best_saved < 0.0 else _mmss(best_saved, true)]
		"failed":
			return ("CAUGHT BY THE DAWN" if J.reason == "dawn" else "WRECKED") + "\nY: GO AGAIN"
		"out":
			if J.held > 0.0:
				return "HOLD  %.1f s" % maxf(0.0, CraftSimScript.PAD_HOLD - float(J.held))
			if sim.time < flash_until:
				return flash_msg
			var gap := _pad_gap()
			if gap != INF:
				var dx: float = sim.pod.x - sim.tpx[sim.pad]
				var dy: float = sim.pod.y - sim.tpy[sim.pad]
				if absf(dx * sim.ttx[sim.pad] + dy * sim.tty[sim.pad]) <= CraftSimScript.PAD_HALF and absf(dx * sim.tnx[sim.pad] + dy * sim.tny[sim.pad]) <= CraftSimScript.PAD_HALF:
					return "STOP ON THE PAD  %s" % dawn
				if gap > 0.0 and gap <= PAD_CALL:
					return "MEDICAL PAD  %s  %s" % [_far(gap), dawn]
				if gap < 0.0 and gap > -3000.0:
					return "PAD BEHIND  %s  %s" % [_far(-gap), dawn]
			return "EMERGENCY  LAKE TOWN MINE  %s" % dawn
	return "HOME  %s" % dawn


const PAD_CALL := 8.0 * 1609.344   # the dash calls the medical pad from this far out (m, along the track)

## How far along the track the medical pad is ahead (m; negative behind), INF off the main road.
func _pad_gap() -> float:
	if sim.pod.path != 0 or sim.pad < 0:
		return INF
	var s: PackedFloat64Array = minimap.s
	var g: float = s[sim.pad] - s[sim.pod.hint]
	var lap: float = s[sim.N]
	return g - lap if g > lap / 2.0 else (g + lap if g < -lap / 2.0 else g)


## A distance as the dash reads it: miles, or feet under 0.2 mi.
static func _far(m: float) -> String:
	var mi := m / 1609.344
	return ("%.1f mi" % mi) if mi >= 0.2 else ("%d ft" % (roundi(m * 3.28084 / 50.0) * 50))


## Seconds as m:ss (or m:ss.s), never negative.
static func _mmss(secs: float, tenths := false) -> String:
	var s := maxf(secs, 0.0)
	if tenths:
		return "%d:%04.1f" % [int(s) / 60, fmod(s, 60.0)]
	return "%d:%02d" % [int(s) / 60, int(s) % 60]


func _update_hud() -> void:
	if minimap_2d and minimap_2d.visible:
		minimap_2d.show_frame(minimap.update(cam_th, get_process_delta_time()))
	var mode_txt: String = {"ramjet": "RAMJET", "burner": "AFTERBURNER"}.get(sim.mode, "RAMJET ARMED" if sim.armed else "")
	hud.text = "%4d mph   %s   %s\nTHR %.2f | %.2f   BRK %.2f | %.2f   HEAT %d%% | %d%%   HP %d%% | %d%%   BAT %d%%   %s\n%s" % [
		_kmh() / 1.609344, cues.readout(), _progress_text(), inp.thrL, inp.thrR, inp.brkL, inp.brkR,
		sim.eL.heat * 100, sim.eR.heat * 100, sim.eL.health * 100, sim.eR.health * 100, sim.battery * 100, mode_txt,
		("Replay: parity lap" if not replay.is_empty() else levers.source) + "   " + handling_text()]
