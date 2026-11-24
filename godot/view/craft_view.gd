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
##   --partner       the driving partner on (the main menu's DRIVING PARTNER; --no-partner off)
##   --handling=H    speed (default: the 100-mile sprint model) or starfighter (tight, ~1,200 mph)
##   --brake=L,R     with --cruise: hold the air brakes too (screenshots)
##   --at=I          circuits: start at track sample I (screenshots of a given corner)
##   --cam=F,L,U     camera at this offset from the pod (metres forward, left, up), looking at
##                   the engines: close-ups for screenshots
##   --eye=X,Y,H --look=X,Y,H   a fixed camera at that sim point, aimed at the other (scenery shots)
extends Node3D

const CraftSimScript := preload("res://sim/craft_sim.gd")
const GameSettings := preload("res://release/game_settings.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")      # the Network's time of day and weather
const ChaseScript := preload("res://view/network_chase.gd")   # chase mode, and which craft the pilot flies
const LightBarScript := preload("res://view/light_bar.gd")
const LeverInputScript := preload("res://input/lever_input.gd")
const RangeWorldScript := preload("res://view/range_world.gd")
const LandmarkScript := preload("res://view/landmark.gd")
const EngineAudioScript := preload("res://audio/engine_audio.gd")
const WindAudioScript := preload("res://audio/wind_audio.gd")
const CourseAudioScript := preload("res://audio/course_audio.gd")
const TrafficAudioScript := preload("res://audio/traffic_audio.gd")
const SkillScoreScript := preload("res://view/skill_score.gd")
const SkillAudioScript := preload("res://audio/skill_audio.gd")
const SkillDisplayScript := preload("res://view/skill_display.gd")
const CanopyFlash := preload("res://view/canopy.gd")
const ApproachProjector := preload("res://view/approach_projector.gd")
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
const TerminalLighting := preload("res://view/terminal_lighting.gd")
const NetworkTrafficScript := preload("res://view/network_traffic.gd")
const DrivingPartnerScript := preload("res://view/driving_partner.gd")
const RacePilotsScript := preload("res://view/race_pilots.gd")
const MainMenuScript := preload("res://view/main_menu.gd")
const GunneryScript := preload("res://view/gunnery.gd")   # the Basilisk's gun: fire control (view/turret.gd is the mount)
const DT := 1.0 / 480.0
const BOOST_HOLD := 0.35
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
var _arm_held := 0.0
var boosting := false
var engine_audio
var wind_audio
var course_audio             # the halls' and canopy's acoustics, the emergency run's sounds (audio/course_audio.gd)
var traffic_audio            # the Network's traffic going by (audio/traffic_audio.gd)
var skill_score
var skill_audio
var _skill_display := SkillDisplayScript.new()
var _skill_label: Label
var _skill_award_label: Label
var benchmark_flight := false
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
const FLAT_CAMERAS := [["far", "Far chase"], ["near", "Close chase"]]
var flat_camera := "far"
var handling_ask := ""             # the live handling switch: "speed" / "starfighter" (VR: the console
                                   # toggle or Y-hold; keyboard: M), sent with every step
static var vehicle_override := ""
static var track_override := ""    # an in-game track switch (VR: hold the menu button) wins over --track;
                                   # static, so it survives the scene reload that does the switch
static var job_override := ""      # the job to fly ("emergency": the emergency run; "none": no job), wins over --job; static too
static var pad_start := false      # set by a menu as it launches a flight: this one begins on its starting pad (used up in _ready; --pads asks too)
static var spot_override := ""     # the Network road to start on (a scenic road's menu entry: "SCoast", "SDrop"); static too
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
# High on Mount Hyperion (its summit is 48 km up) two things change, and nothing does below LIFT_OFF:
#   lift    the whole world is drawn this far below its true height: this node is let down by it. A place
#           is kept to a 4 mm step at 48,000 m, and the cockpit round the eye shivered by that as the craft
#           climbed; let down, what is near the eye is near zero and drawn exactly. Heights read off the
#           scene's own positions are true again with `lift` added (the shaders': the global world_lift).
#   reach   how far the camera draws: 120 km on the ground, the whole country from 30 km up. The ground
#           plane, the far roads, the cities' skylines and Helios are asked to reach as far (_aloft_world).
const LIFT_FROM := 20000.0
const LIFT_OFF := 16400.0      # (Helios's summit, 16,046 m, is never lifted)
const LIFT_HOLD := 3072.0      # the craft climbs this far from the last lift before the next
const REACH := 120000.0
const REACH_ALOFT := 470000.0
var lift := 0.0
var reach := REACH
var _lift_told := false
var org_y := 0.0
var top_kmh := 0.0

var craft: Node3D
var approach_display: ApproachProjector
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
var autopilot = preload("res://view/autopilot.gd").new()   # the Network's autopilot (Luke: "Add autopilot."): P here, the left stick across in the cockpit
var _autopilot_let_go := false   # the hands have let go of what they held when it was taken: now a lever or a brake takes the craft back
const AUTOPILOT_LET_GO := 0.1    # a lever or a brake under this is let go ...
const AUTOPILOT_TAKE := 0.25     # ... and over this, after that, is the pilot taking her back
var dawn: Node3D             # the emergency run: the dawn's front (view/dawn.gd)
var stars: MeshInstance3D    # the emergency run: the night still over the twilight (view/stars.gdshader)
var light_preset := "afternoon"   # "afternoon", or "twilight" on a job (the emergency run: before dawn)
var sky_zenith := Color(0.19, 0.39, 0.78)   # the afternoon sky overhead (view/sky.gdshader), for whatever fades into it
var burn_rect: ColorRect     # the flat view's burn to white when the dawn catches you
var verdant_world: Node3D    # ... and the green valley round it (view/verdant_world.gd)
var dust: Node3D
var partner: Node3D          # the driving partner (view/driving_partner.gd), null when it's off
var partner_on := false      # common release preference, overridden by launch flags
var race: Node3D             # Eridanus: the racing pilots (view/race_pilots.gd), null when there are none
var chase: Node3D            # chase mode on the Network (view/network_chase.gd), null when it's off
var pad: Node3D              # the starting pad (view/start_pad.gd), when the flight began on one
const StartPadScript := preload("res://view/start_pad.gd")
var light_bars: Array = []   # the pilot's own, in the patrol craft (one on each model of the pod that is built)
var siren: AudioStreamPlayer # ... and its siren
var menu = MainMenuScript.new()   # the main menu (view/main_menu.gd): the flight waits while it's open
var gunnery = null                # the Basilisk's fire control, once its craft has a gun (view/gunnery.gd)
var gun_wanted := false           # ... its switch: out and laid, or stowed (the cockpit's GUN switch; K here)
# Power-ups (view/power_ups.gd): lit gates over the road that give the engines a few seconds' surge.
# Off for a bare view (a test, a render, a replay: --power-ups asks); the headset's cockpit turns
# them on from its OPTIONS page, where they are on unless switched off.
const PowerUpsScript := preload("res://view/power_ups.gd")
static var power_ups_on := false
# The avoidance field (Luke, 2026-11-22: "Add a collision avoidance force field"): the sims' inp.avoid, which
# turns the craft off a wall it is closing on, and inp.avoidPush, the push that misses the traffic and the
# pillars ahead (view/avoidance_field.gd looks for it, once a frame). Off unless switched on (the cockpit's
# OPTIONS page; --avoid-field); never for a replay.
const AvoidanceFieldScript := preload("res://view/avoidance_field.gd")
static var avoid_on := false
var avoid_eyes = AvoidanceFieldScript.new()
var _avoid_push := Vector2.ZERO
var power_ups: Node3D
var surge := 0.0                  # s left of a gate's surge (the sims' inp.surge while it lasts)
var menu_label: Label             # the flat view's panel
var _menu_was_muted := false


func _ready() -> void:
	var opts := {"obstacleCollisions": GameSettings.obstacle_collisions_enabled()}
	var on_pad := pad_start      # (a menu's word for this flight alone, whatever course it is)
	pad_start = false
	Outlook.load_saved()     # the menus' time of day and weather
	ChaseScript.load_saved() # ... and the craft, and whether chase mode is on
	opts["vehicle"] = CraftSimScript.PilotCraft.resolve(OS.get_cmdline_user_args(), vehicle_override)
	if not Livery.pinned:    # ... and the paint they chose for this pilot craft (a test or a render that has chosen one keeps it)
		Livery.current = Livery.built(opts["vehicle"])
	if ChaseScript.craft == "patrol":
		Livery.current = "police"       # the patrol craft comes in its own black and white
	if opts["vehicle"] == CraftSimScript.PilotCraft.TALON:
		CraftModelScript.Talon.paint = Livery.current      # (the Talon's plating in the same paint: Factory is Codex's graphite)
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
		# A flight chosen from a menu begins on its pad, at the roadside, and a crash puts it back on one
		# (tests and direct launches keep the centre line unless they ask: --pads).
		opts["pads"] = (on_pad or "--pads" in OS.get_cmdline_user_args()) and "--no-pads" not in OS.get_cmdline_user_args()
		var spot := start_spot(spot_override)
		if spot.size() == 1:     # a city chosen on the menu: its terminal, whichever was last reached
			opts["startCity"] = spot[0]
		elif spot.size() == 3:   # out on a road: a scenic road's own menu entry (at the foot of it), or an insertion point
			opts["startRoad"] = spot[0]
			opts["startSample"] = spot[1]
			opts["startDir"] = spot[2]
	partner_on = GameSettings.resolve_driving_partner(OS.get_cmdline_user_args())
	if "--pod=heavy" in OS.get_cmdline_user_args():   # preserve each chassis's thrust-to-weight ratio with the heavy pod
		var chassis := CraftSimScript.PilotCraft.tuning(opts.vehicle)
		var engines := 2.0 * float(chassis.get("engineMass", CraftSimScript.DEFAULTS.engineMass))
		opts["podMass"] = 1500.0
		opts["forceScale"] = (engines + 1500.0) / (engines + float(chassis.get("podMass", CraftSimScript.DEFAULTS.podMass)))
	sim = CraftSimScript.new(opts)
	if sim.kind == "network":
		for k in sim.net.found:
			net_found[k] = true
		net_target = _net_next_target()
	if start_at >= 0 and sim.kind == "circuit":
		sim.respawn(-1, start_at)
	if branch_at >= 0 and not sim.branches.is_empty():
		_place_on_branch(branch_at)
	if sim.kind != "circuit" and not benchmark_flight:
		replay = []
	levers = LeverInputScript.new()
	minimap = MiniMapScript.new()
	minimap.gp_cities = CITY_GP.keys()   # (the whole map marks their GPs)
	minimap.setup(sim)
	minimap.target = net_target
	_load_best()
	skill_score = SkillScoreScript.new()
	skill_score.setup(sim, best_dir + "skills_%s.json" % sim.track_name)
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
	set_power_ups(power_ups_on or "--power-ups" in OS.get_cmdline_user_args())
	if "--avoid-field" in OS.get_cmdline_user_args():
		avoid_on = true
	dust.build(self)
	if sim.kind == "network":
		dust.road_spray()
	if not mute and shot_path == "":
		skill_audio = SkillAudioScript.new()
		add_child(skill_audio)
		skill_audio.setup()
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
	set_partner(partner_on)
	if RacePilotsScript.available(sim) and replay.is_empty() and RacePilotsScript.wanted(OS.get_cmdline_user_args()):
		set_racers(true)
	Outlook.apply(self)      # the world is built for a fair afternoon: turn it to the hour and weather chosen (the Network's only)
	if ChaseScript.craft == "patrol":
		if craft and craft.canopy:
			add_light_bar(craft.canopy)
		if engine_audio != null:
			siren = AudioStreamPlayer.new()
			siren.stream = ChaseScript.wail()
			siren.volume_db = -21.0
			add_child(siren)
	if sim.kind == "network" and bool(sim.P.get("pads", false)):
		pad = StartPadScript.new()
		add_child(pad)
		pad.build(self)
	if ChaseScript.enabled and traffic_net:
		chase = ChaseScript.new()
		add_child(chase)
		chase.traffic = traffic_net
		chase.build(self)
		traffic_net.chase = chase


func _sim_step() -> void:
	if not replay.is_empty() and sub % 8 == 0:
		var u: Array = replay[mini(replay_i, replay.size() - 1)]
		inp = {"thrL": u[0], "thrR": u[1], "brkL": u[2], "brkR": u[3], "repair": false, "reignite": true}
		if u.size() == 5:   # recorded courses carry the handling request as a fifth channel
			handling_ask = ["", "speed", "starfighter"][int(u[4])]
		replay_i += 1
	sub += 1
	if handling_ask != "":
		inp["handling"] = handling_ask
	if surge > 0.0:               # a power-up's surge, while it lasts
		surge -= DT
		inp["surge"] = true
	elif inp.has("surge"):
		inp.erase("surge")
	if avoid_on and replay.is_empty():      # the avoidance field, and what its eyes asked for this frame
		inp["avoid"] = true
		inp["avoidPush"] = [_avoid_push.x, _avoid_push.y]
	elif inp.has("avoid"):
		inp.erase("avoid")
		inp.erase("avoidPush")
	sim.step(inp, DT)
	for e in sim.events:
		_on_event(e)
	sim.events.clear()
	if skill_score:
		skill_score.step(DT)


func _on_event(e: Dictionary) -> void:
	if skill_score:
		skill_score.on_event(e)
	if e.type == "avoid":   # the avoidance field takes hold (of a wall, of the traffic): it flares, and is in the log below
		_field_flash(0.8)
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
		return best_dir + "%s_best.json" % sim.track_name   # one record: every lap flies both modes
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
	var overdrive := bool(inp.get("gearOverdrive", false)) and int(inp.get("gearIndex", -1)) == 4
	for k in ["thrL", "thrR"]:
		var lever := minf(float(inp[k]), gate) / gate
		var spool: float = preload("res://input/quest_controls.gd").engine_spool(float(inp.gearRpm), lever, overdrive)
		out[k] = (spool * gate) if float(inp[k]) < gate else float(inp[k])   # (the burner's detent: as it was)
		if overdrive and float(inp[k]) < gate:
			# Audio-only rev target: normalized levers still govern gains/load and repair.
			out["gearSpoolL" if k == "thrL" else "gearSpoolR"] = spool
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
	if menu.open:
		return
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_M:
		toggle_handling()
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_T:
		net_cycle_target()
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_P:
		set_autopilot(not autopilot.on)
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_G:
		enter_city_gp()
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_K and craft and craft.turret:
		gun_wanted = not gun_wanted


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
	spot_override = ""   # (back from the GP you are at this city, not out on a scenic road)
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
	m.set_shader_parameter("night", 1.0 if light_preset == "twilight" else 0.0)
	m.set_shader_parameter("suns", 0.0 if light_preset == "twilight" else 1.0)
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


## The patrol craft's light bar goes on its roof (pod-local, under `canopy`).
func add_light_bar(canopy_root: Node3D) -> void:
	var bar := LightBarScript.new()
	canopy_root.add_child(bar)
	bar.build(LightBarScript.ON_ROOF)
	light_bars.append(bar)


## Is the pilot, in the patrol craft, on a runner's tail just now? (Its lights and siren go by this.)
func pursuing() -> bool:
	return chase != null and chase.state == "on" and chase.role == "pursuit"


## How strongly a patrol behind lights the cabin: 0 none, 1 on the tail. (There is no mirror: its lamps
## washing over the rim light, and its siren, are how the pilot knows it is there.)
func patrol_wash() -> float:
	if chase == null or chase.role != "getaway" or chase.state != "on" or chase.car == null:
		return 0.0
	return clampf(1.0 - (chase.gap - 60.0) / 340.0, 0.0, 1.0)


func _patrol_lights() -> void:
	var on := pursuing()
	for bar in light_bars:
		bar.flash(on, Time.get_ticks_msec() / 1000.0)
	if siren and siren.playing != on:
		if on:
			siren.play()
		else:
			siren.stop()


func _chase_result() -> void:
	var how: String = chase.result
	chase.result = ""
	var times := int(chase.tally[how])
	match how:
		"caught":
			_flash("RUNNER CAUGHT  (%d)" % times)
			if skill_score:
				skill_score._award("chase", "RUNNER CAUGHT", 2500)
		"lost":
			_flash("RUNNER LOST")
		"busted":
			_flash("BUSTED  (%d)" % times)
		"escaped":
			_flash("PATROL ESCAPED  (%d)" % times)
			if skill_score:
				skill_score._award("chase", "PATROL ESCAPED", 2000)


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
	if sim.in_pressure(sim.pod.path, sim.pod.hint):
		var road = sim.roads[sim.pod.path]
		var forward: bool = sim.pod.vx * road.tx[sim.pod.hint] + sim.pod.vy * road.ty[sim.pod.hint] >= 0
		var target: int = CraftSimScript.NET_PRESSURE[2 if forward else 1]
		var km: float = absf(target - sim.pod.hint) * road.len[sim.pod.hint] / 1000.0
		var kpa := lerpf(75.6, 101.3, sim.pressure_fill())
		return "AURORA LINE   •   %.1f kPa   |   %s LOCK   %.1f km" % [kpa, "NE" if forward else "SW", km]
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
	set_autopilot(false, "RESTART")
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
	if race:
		race.grid()
	if partner:
		partner.placed = false
	if skill_score:
		skill_score.reset_run()
	net_air_t0 = -1.0
	if minimap:
		minimap.waypoint = {}
	brake_point = -1.0
	flash_until = -1.0
	_job_started = false


# --- the main menu and the driving partner ---

## The driving partner on or off, now and from now on (it's the menu's; a launch flag doesn't save).
func set_partner(on: bool, save := false) -> void:
	partner_on = on
	if on and partner == null:
		partner = DrivingPartnerScript.new()
		add_child(partner)
		partner.build(self)
		partner.update(0.0)
	elif not on and partner != null:
		partner.queue_free()
		partner = null
	if save:
		GameSettings.set_driving_partner(on)


## The racing pilots (Eridanus: view/race_pilots.gd) on or off, now and, from a menu, from now on.
func set_racers(yes: bool, save := false) -> void:
	if yes and race == null and RacePilotsScript.available(sim):
		race = RacePilotsScript.new()
		add_child(race)
		race.build(self)
	elif not yes and race != null:
		race.queue_free()
		race = null
		sim.obstacles = []
		if minimap:
			minimap.marks = []
	if save:
		RacePilotsScript.save_wanted(yes)


## Overridable: the racing pilots' line under the lap's (a flat screen's HUD; the VR cockpit puts
## their page on its glass instead).
func _race_suffix() -> String:
	return "" if race == null or race.line() == "" else "\n" + race.line()


## Overridable: the menu's items.
func _menu_items() -> Array:
	return [{"key": "partner", "label": "DRIVING PARTNER", "value": "ON" if partner_on else "OFF"},
		{"key": "resume", "label": "RESUME"}]


func menu_open(on: bool) -> void:
	if on == menu.open:
		return
	_arm_held = 0.0
	boosting = false
	if on:
		_menu_was_muted = AudioServer.is_bus_mute(0)
		AudioServer.set_bus_mute(0, true)
	else:
		AudioServer.set_bus_mute(0, _menu_was_muted)
	menu.open = on
	_set_skill_visible(not on)
	if on:
		menu.at = 0
		menu.items = _menu_items()
	_menu_show()


## Act on the item under the cursor. -> false if that closed the menu.
func menu_choose() -> bool:
	match menu.key():
		"partner":
			set_partner(not partner_on, true)
			menu.items = _menu_items()
		"resume":
			menu_open(false)
			return false
	_menu_show()
	return true


## Overridable: draw the panel.
func _menu_show() -> void:
	if menu_label:
		menu_label.visible = menu.open
		menu_label.text = menu.text()


func _exit_tree() -> void:
	if skill_score:
		skill_score.save_best()
	if menu.open:
		AudioServer.set_bus_mute(0, _menu_was_muted)


## The same gesture on the flat screen and in the cockpit. A tap arms on release.
## A hold reports its onset once (for haptics) and boosts until release.
func arm_button(down: bool, delta: float) -> String:
	if down:
		_arm_held += delta
		var was := boosting
		boosting = _arm_held >= BOOST_HOLD
		return "boost" if boosting and not was else ""
	var tapped := _arm_held > 0.0 and not boosting
	_arm_held = 0.0
	boosting = false
	return "arm" if tapped else ""


## Overridable: fill `inp` for this frame and handle arm/respawn edges.
func _read_input(delta: float) -> void:
	if menu.open:
		return
	var p: Dictionary = levers.poll(delta)
	inp = {"thrL": p.thrL, "thrR": p.thrR, "brkL": p.brkL, "brkR": p.brkR, "repair": p.repair, "reignite": p.reignite}
	_autopilot_hands(maxf(p.thrL, p.thrR), maxf(p.brkL, p.brkR))
	if arm_button(p.arm_down, delta) == "arm":
		sim.armed = not sim.armed
	if boosting and sim.crash_t <= 0.0:
		inp.boost = true
	if p.respawn:
		_respawn()


func _process(delta: float) -> void:
	if replay.is_empty() and cruise < 0.0:
		_read_input(delta)
	if menu.open:
		acc = 0.0
		cpu.sim = 0.0
		cpu.world = 0.0
		cpu.hud = 0.0
		_capture_frame()
		return   # Freeze traffic, partner, effects and audio too; XR tracking is native.
	if autopilot.on and replay.is_empty() and cruise < 0.0:
		_autopilot_frame(delta)
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
	if network_world:   # no road spray up a shaft
		dust.visible = not sim.in_pressure(sim.pod.path, sim.pod.hint) and _shaft_f(sim.pod.x, sim.pod.y) < 0.0
	_place_camera(1.0 - exp(-delta * 6.0))
	craft.update_jet_clearance()
	craft.sync_cables(sim, delta)   # after the camera: in VR the cables' pod end rides the cockpit
	var t_world := Time.get_ticks_usec()
	_sync_world()   # after the camera: distant anchors scale about its current position
	_gun_controls()
	gunnery = GunneryScript.frame(self, gunnery, delta)   # (after the camera and the world: it lays the gun on what the view is on)
	if skill_score:
		if traffic_net:
			skill_score.observe_traffic(traffic_net.cars, minf(delta, 0.05))
		if skill_audio:
			skill_audio.update(delta, skill_score.feedback)
		skill_score.feedback.clear()
	cpu.world = (Time.get_ticks_usec() - t_world) / 1000.0
	top_kmh = maxf(top_kmh, _kmh())
	var t_hud := Time.get_ticks_usec()
	_update_hud()
	cpu.hud = (Time.get_ticks_usec() - t_hud) / 1000.0
	_capture_frame()


func _capture_frame() -> void:
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


## Where a scenic road's flight starts: Vector2i(road, sample), a little way into its scenic
## stretch (still on the open ground: the coast, or the climb, comes to you); (-1, -1) for no such road.
static func scenic_spot(road_name: String) -> Vector2i:
	if road_name == "SAurora":
		return Vector2i(CraftSimScript.NET_PRESSURE[0], CraftSimScript.NET_PRESSURE[1] - 85)
	if road_name == "":
		return Vector2i(-1, -1)
	for entry in CraftSimScript.NET_SCENIC:
		if CraftSimScript.NET_ROADS[int(entry[0])][0] == road_name:
			return Vector2i(int(entry[0]), int(entry[2][0][0]) + 40)
	return Vector2i(-1, -1)


## Where a Network flight begins, from a menu's spot (release/release_config.gd INSERTIONS):
## [city] for "city:NAME"; [road, sample, way] for a road's name with an optional "@sample" and a
## second "@-1" to face down it (a scenic road named alone: scenic_spot); [] for none or unknown.
static func start_spot(spot: String) -> Array:
	if spot.begins_with("city:"):
		for c in CraftSimScript.NET_CITIES.size():
			if String(CraftSimScript.NET_CITIES[c][0]) == spot.trim_prefix("city:"):
				return [c]
		return []
	var parts := spot.split("@")
	if parts.size() == 1:
		var scenic := scenic_spot(spot)
		return [scenic.x, scenic.y, 1] if scenic.x >= 0 else []
	for r in CraftSimScript.NET_ROADS.size():
		if String(CraftSimScript.NET_ROADS[r][0]) == parts[0]:
			return [r, maxi(int(parts[1]), 0), -1 if parts.size() > 2 and int(parts[2]) < 0 else 1]
	return []


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


## The Network from high up: the world's lift and the camera's reach (see `lift`, above).
func _aloft_world() -> void:
	var h: float = sim.pod.z
	var want := lift
	if h < LIFT_OFF:
		want = 0.0
	elif h > LIFT_FROM and absf(h - lift) > LIFT_HOLD:
		want = snappedf(h, 1024.0)
	if want != lift or not _lift_told:
		_lift_told = true
		lift = want
		position.y = -lift
		RenderingServer.global_shader_parameter_set("world_lift", lift)
		landscape.lift = lift
	var eye := h      # the higher of the craft and the eye (an outside camera can stand well over it)
	if cam != null and cam.is_inside_tree():
		eye = maxf(eye, cam.global_position.y + lift)
	var far_want := snappedf(lerpf(REACH, REACH_ALOFT, smoothstep(5000.0, 30000.0, eye)), 10000.0)
	if far_want != reach:
		reach = far_want
		if cam != null:
			cam.far = reach
		if ground != null and ground.mesh is PlaneMesh:
			(ground.mesh as PlaneMesh).size = Vector2.ONE * (60000.0 if reach <= REACH else reach * 2.0)
		landscape.reach = reach
		if network_world:
			network_world.set_reach(reach)


func _follow_origin() -> void:
	org_x = sim.pod.x
	org_y = sim.pod.y
	var f := _shaft_f(org_x, org_y)
	if f >= 0.0:   # up a shaft: the world's point under the pod, not the sims' plan's
		var A: Array = network_world.shaft.at(sim.pod.path, f)
		org_x = A[0]
		org_y = A[1]


## Where sim plan point (x, y) is on the pod's shaft's stretch (the fractional sample, and sim._n_lat
## its place across), -1 if the pod's not on one or the point's not on it. The sims are flat up there:
## view/network_shaft.gd says where that is in the world.
func _shaft_f(x: float, y: float) -> float:
	if network_world == null or sim.pod.off_road:
		return -1.0
	var r: int = sim.pod.path
	if not network_world.shaft.maps.has(r):
		return -1.0
	sim._nearest_on(r, x, y, sim.pod.hint, 12)   # (the craft and its partner are within a few samples of the pod)
	var f: float = sim._n_i + sim._n_t
	if sim._n_off or absf(sim._n_lat) > 400.0 or not network_world.shaft.on(r, f):
		return -1.0
	return f


## The rotation from an attitude worked out flat (the sims' plane) to the world's at plan point (x, y):
## identity but up a shaft.
func shaft_carry_at(x: float, y: float) -> Basis:
	if sim.kind == "network" and sim.pod.path == CraftSimScript.NET_PRESSURE[0]:
		var station := _pressure_station(x, y)
		if station >= 0.0:
			var road = sim.roads[sim.pod.path]
			var angle := _pressure_angle(road, x, y)
			var fold := smoothstep(0.0, sim.Pressure.APRON, sim.pressure_depth(station))
			var n: Vector2 = sim.Pressure.normal(angle, fold)
			var i: int = CraftSimScript.NET_PRESSURE[1]
			return Basis(Vector3(road.tx[i], 0, -road.ty[i]), atan2(-n.x, n.y))
	var f := _shaft_f(x, y)
	return Basis.IDENTITY if f < 0.0 else network_world.shaft.carry(sim.pod.path, f)


## The same for one of the craft's own bodies at plan point (x, y): its place on the shaft is its own,
## its heading is laid against the road's direction under the POD. The sims carry the craft round a
## shaft's bulb whole, turned with the road under the pod (CraftSim.step: `carried`), so that is the
## direction an engine 22 m up the road still flies along. (Against the road's direction under itself an
## engine flying dead straight was drawn a quarter of a degree toed across, and swung through half a
## degree where the plan's arcs change hands.)
func shaft_carry_body(x: float, y: float) -> Basis:
	if sim.kind != "network" or sim.pod.path == CraftSimScript.NET_PRESSURE[0]:
		return shaft_carry_at(x, y)
	var f := _shaft_f(x, y)
	if f < 0.0:
		return Basis.IDENTITY
	var at_pod := _shaft_f(sim.pod.x, sim.pod.y)
	return network_world.shaft.carry(sim.pod.path, f, at_pod)


## Project on the sealed straight in double precision before moving into the
## floating-origin world. The same chart carries the engines, cables and eyes.
func _pressure_station(x: float, y: float) -> float:
	if sim.pod.off_road:
		return -1.0
	var road = sim.roads[sim.pod.path]
	var i: int = CraftSimScript.NET_PRESSURE[1]
	var along: float = (x - road.px[i]) * road.tx[i] + (y - road.py[i]) * road.ty[i]
	var station: float = i + along / road.len[i]
	# An open feeder curls past the end plane too. It belongs to its own road frame.
	if absf(station - sim.pod.hint) > 64.0 or not sim.in_pressure(sim.pod.path, station):
		return -1.0
	return station


func _pressure_angle(road, x: float, y: float) -> float:
	var i: int = CraftSimScript.NET_PRESSURE[1]
	var lat: float = (x - road.px[i]) * road.nx[i] + (y - road.py[i]) * road.ny[i]
	return (sim.pressure_arc + lat) / sim.Pressure.RADIUS


func _pressure_point(x: float, y: float, clearance: float, station: float) -> Vector3:
	var road = sim.roads[sim.pod.path]
	var i: int = CraftSimScript.NET_PRESSURE[1]
	var along: float = (station - i) * road.len[i]
	var angle := _pressure_angle(road, x, y)
	var fold := smoothstep(0.0, sim.Pressure.APRON, sim.pressure_depth(station))
	var p: Vector2 = sim.Pressure.section(angle, fold) + sim.Pressure.normal(angle, fold) * clearance
	return Vector3(road.px[i] - org_x + road.tx[i] * along + road.nx[i] * p.x,
		sim.net_height(sim.pod.path, station) + p.y,
		org_y - road.py[i] - road.ty[i] * along - road.ny[i] * p.x)


## A sim body's point -> render position: on the Network a body's height is its own (the roads'
## heights are real in the sims: the deck lock, the jumps), elsewhere it's over the surface (w3).
## Where a body is drawn. The sim is flat: it keeps the engines 22 m ahead of the pod in plan, and each
## body rides its own stretch of road, so up a 75 degree wall they were drawn 82 m apart with the cables
## stretched between. On a steep road of the Network the engines are placed from the pod instead, their
## plan offsets laid along the slope at their true length.
func body_place(b, lift := 0.0) -> Vector3:
	var flat := wz(b.x, b.y, b.z + lift)
	if sim.kind != "network" or b == sim.pod or sim.pod.off_road:
		return flat
	var P = sim.pod
	var R = sim.roads[P.path]
	if R.shaft or sim.in_pressure(P.path, P.hint):
		return flat
	var i: int = clampi(P.hint, 1, R.N - 2)
	var grade: float = (sim.net_height(P.path, float(i + 1)) - sim.net_height(P.path, float(i - 1))) / (2.0 * float(R.len[i]))
	if R.deck and sim.deck_rule:
		# Mount Hyperion's road: the slope is the deck's own under the pod, the one the cockpit is pitched by
		# and _deck_place stands things on, not the pod's sample's. A sample's is one slope for 24 m of deck
		# and then the next's: over the lip that is 4.6 degrees at a step, and _deck_place stands the engines
		# off the pod's own slope by the difference over the pitch's cosine, which near the lip's foot is 30
		# to 1. Crept over the lip the engines climbed over the nose through every sample and snapped back
		# down at the next, by half a degree from the eye at first and by 40 at the last (Luke, flying it:
		# "going over the edge slowly goes in chunks rather than just smoothly rolling over").
		var s: float = sim.deck_sine(P.path, sim._road_f(P))
		grade = s / sqrt(1.0 - s * s)
	var steepness := smoothstep(0.15, 0.4, absf(grade))
	if steepness <= 0.0:
		return flat
	var t := Vector2(R.tx[i], R.ty[i])
	var d := Vector2(b.x - P.x, b.y - P.y)
	var along := d.dot(t)
	var across := d - t * along
	var shrink := 1.0 / sqrt(1.0 + grade * grade)
	var carried := wz(P.x + across.x + t.x * along * shrink, P.y + across.y + t.y * along * shrink, P.z + along * grade * shrink + lift)
	return flat.lerp(carried, steepness)


func wz(x: float, y: float, z: float) -> Vector3:
	if sim and sim.kind == "network":
		if sim.pod.path == CraftSimScript.NET_PRESSURE[0]:
			var station := _pressure_station(x, y)
			if station >= 0.0:
				return _pressure_point(x, y, z - sim.net_height(sim.pod.path, station), station)
		var f := _shaft_f(x, y)
		if f >= 0.0:
			return network_world.shaft.point(sim.pod.path, f, sim._n_lat, z - sim.net_height(sim.pod.path, f), org_x, org_y)
		if not sim.pod.off_road and sim.roads[sim.pod.path].deck:
			return _deck_place(x, y, z)
		return Vector3(x - org_x, z, -(y - org_y))
	return w3(x, y, z)


## On a deck road (Mount Hyperion's) what stands over the deck stands square to it. The sims' heights are
## straight up: a pod rides 1.5 m over its road and the pilot's eye 2.7 m, and laid straight up on an 88
## degree wall that eye is 9 cm off the wall: in the road. So a place's height over the deck (the deck
## under the pod, carried along its own slope to that place) is laid along the deck's own up. Nothing
## moves where the deck is level, or more than a few hundred metres from the pod.
func _deck_place(x: float, y: float, z: float) -> Vector3:
	var flat := Vector3(x - org_x, z, -(y - org_y))
	var P = sim.pod
	var s: float = sim.deck_sine(P.path, sim._road_f(P))
	if s == 0.0:
		return flat
	var R = sim.roads[P.path]
	var i: int = P.hint
	var along: float = (x - P.x) * R.tx[i] + (y - P.y) * R.ty[i]
	if absf(along) > 400.0 or absf((x - P.x) * R.nx[i] + (y - P.y) * R.ny[i]) > 900.0:
		return flat
	var c := sqrt(1.0 - s * s)
	var over: float = z - ((P.z - sim.P.rideH) + along * s / c)
	return flat + (Vector3(-s * R.tx[i], c, s * R.ty[i]) - Vector3.UP) * over


## Sim point -> render position, relative to the floating origin. On the shade line (the pod on a
## branch) the point rides its twisted road (CraftModel.road_xf: rolled over, raised).
func w3(x: float, y: float, h := 0.0) -> Vector3:
	if sim and sim.pod.path > 0 and sim.kind != "network":
		return road_xf(x, y) * Vector3(x - org_x, h, -(y - org_y))
	if sim and sim.kind == "network":
		if sim.pod.path == CraftSimScript.NET_PRESSURE[0]:
			var station := _pressure_station(x, y)
			if station >= 0.0:
				return _pressure_point(x, y, h, station)
		var f := _shaft_f(x, y)
		if f >= 0.0:
			return network_world.shaft.point(sim.pod.path, f, sim._n_lat, h, org_x, org_y)
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


var landscape: Node3D
var terminal_lighting: TerminalLighting

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
	if not tw:
		# Realism spike: the afternoon's air is a shader (view/sky.gdshader): the blue deepens overhead
		# and away from the suns, the haze thickens toward the horizon, and each sun has its glare.
		# The same colours as before feed it, so every track keeps its own sky.
		var air := ShaderMaterial.new()
		air.shader = preload("res://view/sky.gdshader")
		sky_zenith = Color(sky_mat.sky_top_color.r * 0.64, sky_mat.sky_top_color.g * 0.78, sky_mat.sky_top_color.b * 0.98)
		air.set_shader_parameter("zenith", sky_zenith)
		air.set_shader_parameter("horizon", hz)
		air.set_shader_parameter("ground", sky_mat.ground_bottom_color)
		sky.sky_material = air
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
	# Realism spike: AgX rolls bright sky, paint and chrome off the way a camera does, where
	# ACES pushed them toward saturated primaries.
	en.tonemap_mode = Environment.TONE_MAPPER_AGX
	en.tonemap_exposure = 1.22
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
	en.adjustment_saturation = 1.04
	en.adjustment_contrast = 1.06
	en.fog_enabled = true
	en.fog_light_color = hz
	# (the valley's air is clearer than the desert's dust: Eridanus' 12 km boards come up readable)
	en.fog_density = 0.0012 if sim.kind == "circuit" and not sim.course else (0.0002 if green else 0.00035)
	if sim.kind == "network" or sim.track_name == "carving":
		en.fog_density = 0.00016   # the roads stream in 20 km out: the haze takes them there (the skylines carry their own)
	en.fog_sky_affect = 0.0
	en.fog_aerial_perspective = 0.0 if tw else 0.55   # distance takes the colour of the sky behind it, sunward or not
	en.fog_sun_scatter = 0.05 if sim.kind == "network" or sim.track_name == "carving" else 0.18   # preserve contrast on fast roads
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
		landscape = load("res://view/network_landscape.gd").new()
		add_child(landscape)
		landscape.build(sim, network_world)
		landscape.setup_ground(ground_mat)
		ground.position.y = -8.0
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

	if sim.track_name == "gp" or sim.track_name == "carving" or gp_biome != "":
		gp_world = GpWorldScript.new()
		add_child(gp_world)
		gp_world.build(sim, self)
		horizon = HorizonScript.new()
		add_child(horizon)
		if sim.track_name == "carving":
			# Fixed landscape enclosing the entire long circuit, not the old GP's
			# small origin-centered ring, which would intersect these sweeps.
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for i in sim.N:
				lo = lo.min(Vector2(sim.tpx[i], sim.tpy[i]))
				hi = hi.max(Vector2(sim.tpx[i], sim.tpy[i]))
			horizon.build_course(self, hz, (lo+hi)/2.0, (hi-lo)*0.75, false)
		else:
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
	if landscape:
		_aloft_world()
		landscape.sync(org_x, org_y)
		Outlook.tick(self, get_process_delta_time())
		ground_mat.set_shader_parameter("absolute_org", Vector2(org_x,org_y))
	if gp_world:
		gp_world.sync(org_x, org_y)
	if course_world:
		course_world.sync(org_x, org_y)
	if network_world:
		network_world.sync(org_x, org_y)
		if terminal_lighting:
			terminal_lighting.sync(sim, org_x, org_y)
		_net_biome()
		if course_audio and course_audio.net_halls.is_empty():
			course_audio.net_halls = network_world.halls
	if partner:
		partner.update(get_process_delta_time())
	if race:
		race.update(get_process_delta_time())
		if minimap:
			minimap.marks = race.marks()
	if avoid_on:      # the avoidance field's eyes, for the next frame's steps; and it shows while it works
		_avoid_push = avoid_eyes.look(sim, traffic_net, network_world) if traffic_net else Vector2.ZERO
		if sim.avoid_a > 0.0:
			_field_flash(0.25 + 0.5 * sim.avoid_a / float(sim.P.avoidMaxA))
	if traffic_net:
		traffic_net.update(get_process_delta_time())
		if traffic_audio:   # the whooshes: the vehicles within 3 km going by
			var pv := Vector2(sim.pod.vx, sim.pod.vy)
			var cars := []
			for c in traffic_net.cars:
				if absf(c.x - sim.pod.x) < 3000.0 and absf(c.y - sim.pod.y) < 3000.0:
					cars.append([c.id, c.x, c.y, sim.net_deck(c.road, c.f, c.lat) + 2.0, c.v * c.hx, c.v * c.hy])
			traffic_audio.set_speed(pv.length())
			traffic_audio.update(Vector2(sim.pod.x, sim.pod.y), pv.normalized() if pv.length() > 1.0 else Vector2.ZERO, cars, wz, get_process_delta_time())
		if traffic_net.race_result != "":
			_net_race_result()
		if pad:
			pad.sync(get_process_delta_time())
		if chase:
			chase.update(get_process_delta_time())
			if chase.result != "":
				_chase_result()
		_patrol_lights()
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
	if power_ups:
		power_ups.sync()


## The power-ups, on or off where the craft is (the cockpit's OPTIONS page). Never for a replay or
## a cruise: nothing a test or a recorded lap flies meets a gate.
func set_power_ups(on: bool) -> void:
	power_ups_on = on
	on = on and replay.is_empty() and cruise < 0.0
	if on and power_ups == null:
		power_ups = PowerUpsScript.new()
		add_child(power_ups)
		power_ups.build(self)
	elif not on and power_ups != null:
		power_ups.queue_free()
		power_ups = null
		surge = 0.0


## A gate flown through (view/power_ups.gd): the engines surge for a few seconds; with the
## consumables on the cyan one half fills the battery and the white one cools the engines.
func power_up(kind: String) -> void:
	surge = PowerUpsScript.SURGE_S
	if sim.P.limits:
		if kind == "energy":
			sim.battery = minf(1.0, sim.battery + PowerUpsScript.ENERGY_GIFT)
		elif kind == "coolant":
			for e in [sim.eL, sim.eR]:
				e.heat = maxf(0.0, e.heat - PowerUpsScript.COOLANT_GIFT)
	_flash(String({"energy": "SURGE  /  ENERGY +50%", "coolant": "SURGE  /  ENGINES COOLED"}.get(kind, "SURGE")))
	print("POWER-UP: %s at %.0f mph" % [kind, _kmh() / 1.609344])


## The autopilot taken (true) or given back (view/autopilot.gd): P at a desk, the left stick flicked
## across in the cockpit, the quick menu's OPTIONS page. -> whether it now has the craft. It flies
## to the city the dash points at.
func set_autopilot(want: bool, why := "") -> bool:
	if not want:
		if autopilot.on:
			autopilot.disengage(why)
			_flash("AUTOPILOT OFF" + (("  /  " + why) if why != "" else ""))
			print("AUTOPILOT: off%s" % ((" (" + why + ")") if why != "" else ""))
		return false
	var city := -1
	if sim.kind == "network":
		city = net_target if net_target >= 0 else _net_next_target()
	if not autopilot.engage(sim, city):
		_flash("NO AUTOPILOT  /  " + String(autopilot.why_off))
		print("AUTOPILOT: refused (%s)" % autopilot.why_off)
		return false
	_autopilot_let_go = false
	# (it takes the levers where the pilot's hands have them, and moves them on from there)
	autopilot.hands(float(inp.get("thrL", 0.0)), float(inp.get("thrR", 0.0)), float(inp.get("brkL", 0.0)), float(inp.get("brkR", 0.0)))
	var mph := roundi(float(autopilot.cruise) * 2.236936)
	_flash("AUTOPILOT  /  TO %s AT %d MPH" % [String(sim.cities[autopilot.target].name).to_upper(), mph])
	print("AUTOPILOT: on, to %s at %d mph (%s)" % [sim.cities[autopilot.target].name, mph, autopilot.next_text()])
	return true


## The hands while it flies: once they have let go of what they held when it was taken, a lever or
## a brake moved takes the craft back.
func _autopilot_hands(lever: float, brake: float) -> bool:
	if not autopilot.on:
		return false
	if not _autopilot_let_go:
		_autopilot_let_go = lever < AUTOPILOT_LET_GO and brake < AUTOPILOT_LET_GO
		return false
	if lever > AUTOPILOT_TAKE or brake > AUTOPILOT_TAKE:
		set_autopilot(false, "YOU HAVE HER")
		return true
	return false


## A frame of the autopilot: its levers and brakes in place of the hands', and the handling it wants
## asked for as the MODE switch asks. If it has stopped flying the craft is the pilot's again.
func _autopilot_frame(delta: float) -> void:
	var cars: Array = traffic_net.cars if traffic_net and "cars" in traffic_net else []
	autopilot.pull = float(inp.get("thrMul", 1.0))           # (the cockpit's gearbox, if there is one: what a lever is worth)
	autopilot.overdrive = bool(inp.get("gearOverdrive", false))
	var u: Dictionary = autopilot.fly(sim, net_target if net_target >= 0 else int(autopilot.target), cars, delta)
	for e: String in autopilot.events:
		if e == "arrived" or e == "replanned":
			print("AUTOPILOT: %s, now to %s (%s)" % [e, sim.cities[autopilot.target].name if autopilot.target >= 0 else "?", autopilot.next_text()])
	autopilot.events.clear()
	if u.is_empty():
		_flash("AUTOPILOT OFF  /  " + String(autopilot.why_off))
		print("AUTOPILOT: gave the craft back (%s)" % autopilot.why_off)
		_autopilot_given_back()
		return
	inp.thrL = u.thrL
	inp.thrR = u.thrR
	inp.brkL = u.brkL
	inp.brkR = u.brkR
	inp.burner = false
	inp.boost = false
	inp.reignite = true            # (an engine that goes out is relit: nobody's thumb is on A)
	var have: String = handling_ask if handling_ask != "" else String(sim.hwant)
	if String(u.handling) != have:
		ask_handling(String(u.handling))


## Overridable: it has given the craft back by itself (the route ended, a crash, off the road).
func _autopilot_given_back() -> void:
	pass


## What the boost is doing, for a readout: nothing, one stage (the ARM button held, or a gate's
## surge), or both at once.
func boost_text() -> String:
	return ("" if sim.boost <= 0 else ("   BOOST" if sim.boost == 1 else "   BOOST x2")) + avoid_text()


## ... and the avoidance field, while it is working.
func avoid_text() -> String:
	return "   FIELD" if sim.avoid_a > 0.0 else ""


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
	if network_world or range_world:
		# The lamp follows the vehicle's nose, including on banked decks. The
		# cockpit can look across the road independently of the light in XR.
		var mount: Node3D = craft.pod_frame if craft.pod_frame else pod_mesh
		var lamp := SpotLight3D.new()
		lamp.name = "GuideSignHeadlight"
		lamp.light_cull_mask = NetworkWorldScript.Signs.SHEETING_LAYER
		lamp.light_bake_mode = Light3D.BAKE_DISABLED
		lamp.light_volumetric_fog_energy = 0.0
		lamp.light_specular = 0.10
		lamp.light_energy = 0.93
		lamp.spot_range = 1350.0
		lamp.spot_angle = 58.0
		lamp.spot_angle_attenuation = 1.5
		lamp.spot_attenuation = 0.0
		mount.add_child(lamp)
		lamp.position = Vector3(0, 1.2, -1.8)
	if network_world:
		TerminalLighting.mark_craft(craft)
		terminal_lighting = TerminalLighting.new()
		add_child(terminal_lighting)
		terminal_lighting.build(sim, network_world)
		terminal_lighting.sync(sim, org_x, org_y)


## The Basilisk's gun from the keyboard: K deploys and stows it (_unhandled_key_input), F held fires.
## Overridable: the cockpit has its GUN switch and X.
func _gun_controls() -> void:
	if gunnery:
		gunnery.want_out = gun_wanted
		gunnery.trigger = Input.is_key_pressed(KEY_F)


## Overridable: the flat view's chase camera and 2D HUD.
func _make_view() -> void:
	flat_camera = GameSettings.choice("flat_camera", ["far", "near"])
	CraftModelScript.set_nose_closed(GameSettings.choice("flat_nose", ["open", "closed"]) == "closed", self)
	if sim.kind == "network":
		_mount_approach_projector(craft.canopy)
	cam = Camera3D.new()
	cam.fov = 70
	cam.far = 120000   # the backdrop peaks sit at 45-57 km; Eridanus' far ranges up to ~100 km away
	add_child(cam)
	var layer := CanvasLayer.new()
	menu_label = Label.new()
	menu_label.visible = false
	menu_label.add_theme_font_size_override("font_size", 26)
	menu_label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.09, 0.86)
	sb.set_content_margin_all(24.0)
	menu_label.add_theme_stylebox_override("normal", sb)
	menu_label.position = Vector2(420, 220)
	layer.add_child(menu_label)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 18)
	hud.add_theme_color_override("font_color", Color(0.1, 0.08, 0.06))
	layer.add_child(hud)
	_skill_label = Label.new()
	_skill_award_label = Label.new()
	for label in [_skill_label, _skill_award_label]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size = Vector2(560.0, 70.0)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override("font_color", Color(0.65, 0.96, 0.9))
		label.add_theme_color_override("font_outline_color", Color(0.01, 0.025, 0.03, 0.95))
		label.add_theme_constant_override("outline_size", 5)
		layer.add_child(label)
	_skill_award_label.add_theme_font_size_override("font_size", 21)
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
	var Q := shaft_carry_at(sim.pod.x, sim.pod.y)   # (identity but up a shaft)
	var fwd: Vector3 = Q * Vector3(cos(cam_th), 0, -sin(cam_th))
	var cam_up: Vector3 = Q * Vector3.UP
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
	if flat_camera == "near":
		cam.position = pod_p - fwd * 5.2 + cam_up * 2.2
	else:
		cam.position = pod_p - fwd * 12.0 + cam_up * 4.5
	cam.look_at(pod_p + fwd * 40.0 + cam_up * 1.0, cam_up)


var _net_guidance_lengths := {} # Per-road arc lengths, built only for roads whose signs are needed.
var _net_guidance_entries := {} # Physical parent samples for each (parent, child road, child sample).
var _net_guidance_sim


func _net_guidance_parent_sample(junction: Array, child: int) -> int:
	if _net_guidance_sim != sim:
		_net_guidance_sim = sim
		_net_guidance_lengths.clear()
		_net_guidance_entries.clear()
	var key := Vector3i(int(junction[0]), int(junction[3]), child)
	if _net_guidance_entries.has(key):
		return _net_guidance_entries[key]
	var P = sim.roads[key.x]
	var C = sim.roads[key.y]
	var closest := int(junction[1])
	var distance := INF
	# Junction bounds include shared pavement and padding. Use them only to bound the search;
	# the actual child endpoint determines when the turn is reached, in either travel direction.
	for i in range(int(junction[1]), int(junction[2]) + 1):
		var dx: float = P.px[i] - C.px[child]
		var dy: float = P.py[i] - C.py[child]
		var d := dx * dx + dy * dy
		if d < distance:
			distance = d
			closest = i
	_net_guidance_entries[key] = closest
	return closest


## Signed distance along the current road, including the distance since its nearest sample.
## A projection onto the exit tangent shortens curved approaches and can keep passed signs alive.
func _net_guidance_distance(sample: int, way: int) -> float:
	if _net_guidance_sim != sim:
		_net_guidance_sim = sim
		_net_guidance_lengths.clear()
		_net_guidance_entries.clear()
	var road := int(sim.pod.path)
	var R = sim.roads[road]
	if not _net_guidance_lengths.has(road):
		var lengths := PackedFloat64Array()
		lengths.resize(R.N)
		for i in range(1, R.N):
			lengths[i] = lengths[i - 1] + R.len[i - 1]
		_net_guidance_lengths[road] = lengths
	var lengths: PackedFloat64Array = _net_guidance_lengths[road]
	var here := clampi(sim.pod.hint, 0, R.N - 1)
	var offset: float = (sim.pod.x - R.px[here]) * R.tx[here] + (sim.pod.y - R.py[here]) * R.ty[here]
	return (lengths[sample] - lengths[here] - offset) * way


## Use actual travel, falling back to facing only while stopped. A reverse slide is still reverse.
func _net_guidance_way() -> int:
	var R = sim.roads[sim.pod.path]
	var at := clampi(sim.pod.hint, 0, R.N - 1)
	var along: float = sim.pod.vx * R.tx[at] + sim.pod.vy * R.ty[at]
	if absf(along) < 1.0:
		along = cos(sim.pod.th) * R.tx[at] + sin(sim.pod.th) * R.ty[at]
	return 1 if along >= 0.0 else -1


## Follow the receiving road's actual far-end junction, including interchange jump transfers.
func _net_guidance_destination(road: int, end: int) -> String:
	var R = sim.roads[road]
	for ji in R.jx:
		var J: Array = sim.junctions[ji]
		if int(J[3]) == road and int(J[4]) <= end and end <= int(J[5]):
			var target := int(J[0])
			var at := _net_guidance_parent_sample(J, end)
			return "%s %s" % [sim.roads[target].name.to_upper(), "UPPER" if sim.net_height(target, at) >= 300.0 else "LOWER"]
	return R.name.to_upper()


func _net_guidance_countdown(distance: float, speed: float) -> String:
	var seconds := "-- S"
	if speed >= 1.0:
		var remaining := maxf(0.0, distance) / speed
		seconds = ("%.1f S" if remaining < 10.0 else "%.0f S") % remaining
	return "%s / %s" % [_far(maxf(0.0, distance)).to_upper(), seconds]


## Ordinary interchange exits use the same small readout when there is no jump approach.
## The side comes from the real ramp mouth relative to travel, never its construction order.
func _net_exit_approach_text(travel: int, speed: float, horizon: float) -> String:
	var highway := int(sim.pod.path)
	var H = sim.roads[highway]
	var nearest := INF
	var side := ""
	var destination := ""
	for ji in H.jx:
		var J: Array = sim.junctions[ji]
		if int(J[0]) != highway:
			continue
		var road := int(J[3])
		var R = sim.roads[road]
		if not R.name.begins_with("R"):
			continue
		var end: int = 0 if int(J[4]) == 0 else R.N - 1
		var ramp_way := 1 if end == 0 else -1
		if ramp_way * int(J[6]) != travel:
			continue
		var mouth := _net_guidance_parent_sample(J, end)
		var distance := _net_guidance_distance(mouth, travel)
		if distance < 0.0 or distance > horizon or distance > nearest + 0.01:
			continue
		var lateral: float = ((R.px[end] - H.px[mouth]) * H.nx[mouth] + (R.py[end] - H.py[mouth]) * H.ny[mouth]) * travel
		var branch_side := "LEFT" if lateral > 0.0 else "RIGHT"
		# Equal-distance choices normally have an exit on each side; prefer the right-hand option.
		if absf(distance - nearest) < 0.01 and side == "RIGHT":
			continue
		nearest = distance
		side = branch_side
		destination = _net_guidance_destination(road, R.N - 1 if end == 0 else 0)
	if side.is_empty():
		return ""
	return "%s EXIT  %s\nTO %s\nOPTIONAL / KEEP %s" % [side, _net_guidance_countdown(nearest, speed), destination, side]


## Mount Hyperion's leaps on the dash (CraftSim.NET_LEAPS). Coming down the mountain toward a lane's mouth: how far
## off to one side the lane is, or that the craft is in it (the lane is chosen on the way down: at the foot there
## is no steering into it). On the lane: the lip's count down. "" when neither.
const LEAP_CALL := 100000.0      # m before a lane's mouth that the line begins (the summit is 57 km from one, 98 from the other)
func _net_leap_text() -> String:
	if sim.kind != "network" or sim.pod.off_road or sim.leaps.is_empty():
		return ""
	var speed: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
	var travel := _net_guidance_way()
	var hint := int(sim.pod.hint)
	for lp in sim.leaps:
		var lane := int(lp[0])
		var L = sim.roads[lane]
		if int(sim.pod.path) == lane:
			if travel < 0:
				return ""
			return "LEAP LIP  %s\nHYPERION LEAP > LANDING FIELD\nHOLD IT STRAIGHT | READY" % _net_guidance_countdown(float(L.N - 1 - hint) * 24.0, speed)      # (three lines, as the windscreen's glass lays a page out: ApproachProjector._write)
		for ji in L.jx:
			var J: Array = sim.junctions[ji]
			if int(J[3]) != lane or int(J[4]) != 0 or int(J[0]) != int(sim.pod.path):
				continue
			var P = sim.roads[int(J[0])]
			var way := int(J[6])                                  # the way along the parent that takes a craft onto the lane
			var mouth: int = int(J[1]) if way > 0 else int(J[2])
			var off_end: int = int(J[2]) if way > 0 else int(J[1])   # where the parent's deck has left the lane
			var ahead: float = float((mouth - hint) * way) * 24.0
			if travel != way or ahead > LEAP_CALL or (off_end - hint) * way < 0 or speed < 20.0:
				continue
			var lane_lat: float = (L.px[0] - P.px[mouth]) * P.nx[mouth] + (L.py[0] - P.py[mouth]) * P.ny[mouth]
			var at := clampi(hint, 0, P.N - 1)
			var lat: float = (sim.pod.x - P.px[at]) * P.nx[at] + (sim.pod.y - P.py[at]) * P.ny[at]
			var off := lane_lat - lat                               # the lane's middle, m to the left of the craft the way the parent's samples run
			var head := "HYPERION LEAP  %s" % _net_guidance_countdown(maxf(0.0, ahead), speed)
			if absf(off) <= float(L.w[0]) / 2.0 - 30.0:
				return "%s\nIN THE LEAP LANE\nHOLD IT STRAIGHT | READY" % head
			return "%s\nLEAP LANE %d M TO YOUR %s\nOR KEEP TO THE MIDDLE: THE PLAIN WAY" % [head, roundi(absf(off)), "LEFT" if off * float(way) > 0.0 else "RIGHT"]
	return ""


## One compact approach readout shared by desktop and cockpit. At high speed its lead grows to
## twelve seconds; the action comes first, and the minimum remains a requirement at the lip.
func _net_jump_approach_text() -> String:
	if sim.kind != "network" or sim.pod.off_road:
		return ""
	var travel := _net_guidance_way()
	var speed: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
	var horizon := maxf(13000.0, speed * 12.0)
	var nearest := INF
	var selected: Array = []
	var action := ""
	var lane_cue := ""
	for jp in sim.jumps:
		var launch := int(jp[0])
		var L = sim.roads[launch]
		var on_lane: bool = sim.pod.path == launch
		var on_ramp := false
		var entry := INF
		if on_lane:
			if travel < 0:
				return "WRONG WAY\nASCENT %s | TURN BACK\nJUMP LIP IS BEHIND" % L.name
			entry = _net_guidance_distance(L.N - 1, 1)
		else:
			for ji in L.jx:
				var J: Array = sim.junctions[ji]
				if int(J[3]) != launch or int(J[4]) != 0:
					continue
				var ramp := int(J[0])
				var R = sim.roads[ramp]
				var way := int(J[6])
				var fork := _net_guidance_parent_sample(J, 0)
				if sim.pod.path == ramp:
					if travel == way:
						on_ramp = true
						entry = _net_guidance_distance(fork, way)
					break
				# The launch now forks off an exit ramp, not directly off the highway.
				# Follow that ramp's entrance so the warning begins before leaving the highway.
				var end_sample: int = 0 if way > 0 else R.N - 1
				for rji in R.jx:
					var HJ: Array = sim.junctions[rji]
					if int(HJ[0]) != sim.pod.path or int(HJ[3]) != ramp or int(HJ[4]) > end_sample or end_sample > int(HJ[5]):
						continue
					var highway_way := way * int(HJ[6])
					if travel == highway_way:
						entry = _net_guidance_distance(_net_guidance_parent_sample(HJ, end_sample), highway_way)
		if entry < 0.0 or entry > nearest or (not on_lane and entry > horizon):
			continue
		nearest = entry
		selected = jp
		action = "JUMP LIP" if on_lane else ("JUMP STRAIGHT" if on_ramp else "RIGHT EXIT")
		lane_cue = "" if on_lane or on_ramp else " / KEEP RIGHT"
	if selected.is_empty():
		return _net_exit_approach_text(travel, speed, horizon)
	var minimum := int(selected[2])
	var state := "READY" if speed * 2.236936 >= minimum else "TOO SLOW"
	var catch_road := int(selected[1])
	var destination := _net_guidance_destination(catch_road, sim.roads[catch_road].N - 1)
	return "%s  %s\nASCENT %s > %s%s\nMIN %d,%03d MPH AT LIP | %s" % [action, _net_guidance_countdown(nearest, speed), sim.roads[int(selected[0])].name, destination, lane_cue, minimum / 1000, minimum % 1000, state]


## Second HUD line: lap info on the circuit, mileage and top speed on the range; the job's line on
## the emergency run.
func _progress_text() -> String:
	if sim.kind == "network":
		var leap := _net_leap_text()
		if leap != "":
			return leap
		var ascent := _net_jump_approach_text()
		if ascent != "":
			return ascent
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
		return "LAP %d  %.2fs   LAST %s   RECORD %s" % [sim.lap + 1, cur, "--" if sim.last_lap < 0.0 else "%.2f" % sim.last_lap, rec] + _race_suffix()
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


func _mount_approach_projector(windscreen: Node3D) -> void:
	approach_display = ApproachProjector.new()
	approach_display.build(windscreen)


func _hud_progress(in_cockpit: bool) -> String:
	if approach_display == null:
		return _progress_text()
	var message := _net_leap_text()      # (Mount Hyperion's leaps first: a lane's line is the mountain's road's, no exit's)
	if message.is_empty():
		message = _net_jump_approach_text()
	approach_display.set_message(message)
	if message.is_empty():
		return _net_text()
	return "" if in_cockpit else message


func _update_hud() -> void:
	if minimap_2d and minimap_2d.visible:
		minimap_2d.show_frame(minimap.update(cam_th, get_process_delta_time()))
	var mode_txt: String = {"ramjet": "RAMJET", "burner": "AFTERBURNER"}.get(sim.mode, "RAMJET ARMED" if sim.armed else "")
	mode_txt += boost_text() + autopilot.suffix()
	hud.text = "%4d mph   %s   %s\nTHR %.2f | %.2f   BRK %.2f | %.2f   HEAT %d%% | %d%%   HP %d%% | %d%%   BAT %d%%   %s\n%s" % [
		_kmh() / 1.609344, cues.readout(), _hud_progress(false), inp.thrL, inp.thrR, inp.brkL, inp.brkR,
		sim.eL.heat * 100, sim.eR.heat * 100, sim.eL.health * 100, sim.eR.health * 100, sim.battery * 100, mode_txt,
		("Replay: parity lap" if not replay.is_empty() else levers.source) + "   " + handling_text()]
	if skill_score:
		var display := _skill_display.update(skill_score)
		var weight: float = display.emphasis
		var viewport_size := get_viewport().get_visible_rect().size
		_skill_label.text = display.total
		_skill_label.position = Vector2(viewport_size.x - 115.0, 18.0).lerp(Vector2(viewport_size.x * 0.5, 82.0), weight) - Vector2(280.0, 0.0)
		_skill_label.add_theme_font_size_override("font_size", roundi(lerpf(17.0, 30.0, weight)))
		_skill_label.modulate.a = lerpf(0.52, 1.0, weight)
		_skill_award_label.text = display.award
		_skill_award_label.position = Vector2(viewport_size.x * 0.5 - 280.0, 122.0)
		_skill_award_label.modulate.a = weight


func _set_skill_visible(on: bool) -> void:
	if _skill_label:
		_skill_label.visible = on
	if _skill_award_label:
		_skill_award_label.visible = on
