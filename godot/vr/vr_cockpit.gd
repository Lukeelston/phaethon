## M2 VR seat: seated OpenXR cockpit riding the pod. The pod is your frame of reference;
## the engines, binder and cables run out ahead of you, and the cockpit lists with the pod.
## Touch controllers stand in for the printed levers, in four schemes (QuestControls;
## the quick menu selects them, the choice is saved): trigger throttles, throttle + steer,
## grab the levers, stick levers. Buttons, every scheme:
##   A reignite Â· B arm ramjet Â· X repair Â· thumbstick click recenter (view and seat height)
##   trigger throttles: right stick flick up / down shifts gear; left stick flick up lights the
##   burner (top gear), down puts it out (the triggers never do: Luke, "take the afterburners
##   away from the triggers")
##   the MODE switch on the right console: push it up for SPEEDCRAFT, down for STARFIGHTER (live,
##   mid-lap; STARFIGHTER takes below 1,250 mph). Y hold 1 s flips it too. Y tap: restart
##   menu tap: quick menu (driving partner, controls, camera: the seat or a chase view) Â· menu hold
##   1.5 s: main menu / map selection
##   the start panel across the windscreen's header (vr/overhead_panel.gd): 1 BATT, 2 ENGINE under its
##   red guard, 3 START, 4 PARK. A flight chosen from the menu begins parked, cold and dark, and is
##   started by hand (vr/startup_sequence.gd); COLD START in the quick menu turns that off.
## Haptics: a kick on the sonic boom; a tick in that hand when a lever crosses the burner gate (the
## stick schemes); a thump in the left hand as the burner lights, a softer one as it goes out, a
## double tap when it can't (below top gear).
## The printed levers / a gamepad win whenever they're moving; the keyboard still works.
## While the OpenXR session isn't focused (stopping, the Link menu, the headset off) the controllers
## read as let go: OpenXR holds their last state, and full triggers flew on with nobody aboard.
## Logs OpenXR session events and a frame-timing summary every 10 s; writes a CSV on exit.
extends "res://view/craft_view.gd"

const SEAT := Vector3(0.0, 0.72, 0.6)  # eye point in pod space (pod forward = -Z): a little above the
                                        # cockpit rim (Luke: "sit a bit lower", then "view higher by default")
# The cockpit's furniture is laid out round SEAT (the map's pod, the instruments' sight lines). The pilot
# sits SEAT_RISE over it (Luke, flying the fourteenth: "the default seating position should be about 3/4
# inches higher", and asked which he meant: "3 to 4 inches"; this is three and a half): EYE is where a
# recentred pilot's eyes are, and where the headset's origin stands. The header rail is then 0.26 m over
# the eye and 0.30 m ahead of it (it was 0.35 over), the hood's liner still clear of the head behind it.
const SEAT_RISE := 0.089
const EYE := SEAT + Vector3(0.0, SEAT_RISE, 0.0)
const FLOOR_H := 0.7                    # pod floor above the ground
const QuestControlsScript := preload("res://input/quest_controls.gd")
const SeatFinish := preload("res://view/craft_materials.gd")
const SeatLoft := preload("res://view/traffic_models.gd")
const PREFS := "user://vr_prefs.json"
const Y_HOLD := 1.0
const MENU_HOLD := 1.5   # hold the left menu button this long to return to map selection
const DashboardScript := preload("res://vr/dashboard.gd")
const GaugeClusterScript := preload("res://vr/gauge_cluster.gd")
const WagMeterScript := preload("res://vr/wag_meter.gd")
const CockpitInteriorScript := preload("res://vr/cockpit_interior.gd")
const ModeSwitchScript := preload("res://vr/mode_switch.gd")
const CanopyScript := preload("res://view/canopy.gd")
const MinimapPanelScript := preload("res://vr/minimap_panel.gd")
const ScreenReflectionScript := preload("res://view/screen_reflection.gd")
const Kit := preload("res://view/mesh_kit.gd")
const BrakeDiagnosticsScript := preload("res://vr/brake_diagnostics.gd")
const StartupScript := preload("res://vr/startup_sequence.gd")
const OverheadPanelScript := preload("res://vr/overhead_panel.gd")
const StartupAudioScript := preload("res://audio/startup_audio.gd")
var _brake_trace: RefCounted
static var require_neutral_on_entry := false
var _await_neutral_controls := false

var xr: XRInterface
var rig: Node3D
var shell: Node3D   # the cockpit's fittings (hull, seat, levers, panel): shudders, your head doesn't
var interior   # vr/cockpit_interior.gd
var mode_switch   # vr/mode_switch.gd: the SPEEDCRAFT / STARFIGHTER toggle on the right console
var canopy: Node3D   # view/canopy.gd: the windscreen ahead and the forcefield round the nose
var minimap_panel: Node3D   # vr/minimap_panel.gd
var menu_panel: Node3D      # the main menu's panel (view/main_menu.gd)
var _ride := {}   # CraftModel.ride's smoothing state
const COCKPIT_ROLL_MAX := deg_to_rad(30.0)
const COCKPIT_ROLL_RATE := deg_to_rad(30.0)
const COCKPIT_ROLL_ACCEL := deg_to_rad(90.0)
var _comfort_roll := 0.0
var _comfort_roll_rate := 0.0
# The rear stepping out, made visible (Luke: "is the vehicle kicking the back out at all when turning? ...
# I don't feel it in practice. not full fledged 'drifting', but a little slide"). In a turn the
# cockpit yaws a few degrees further into it about the nose hitch, so the seat swings outward, on a
# lightly damped spring: it steps out, overshoots a touch, and catches as the turn lets go. Looks and
# feel only: the sim's pod, its heading and its walls are where they were.
# What sets it off is the cornering load itself. It first followed the sim's own swing (craft_sim.gd's
# tow_swing), and Luke flew it and "didn't feel the slide": that swing waits for the levers to be
# split by 0.15 and is full at 0.65, and at speed he steers with the air brakes alone, a split of
# 0.03 half the time and under 0.26 for 95 % of a flight, so it never came to a fifth of a degree.
# Those small splits are still real turns: the load goes with the split whatever the speed (0.03:
# 4 g, 0.08: 10 g, 0.17: 21 g, 0.26: 33 g; tests/probe_slide.gd --small). So: nothing while a lane
# is being held, a degree in a gentle turn, most of it by 20 g, all of it by 24.
const SLIDE_MAX := deg_to_rad(7.0)        # the cockpit's extra yaw in a hard turn
const SLIDE_LOAD := Vector2(5.0, 24.0)    # the cornering load it steps out over, g: none at the first, all at the second
const SLIDE_LOAD_T := 0.18                # s: the load is read through this much smoothing (the pair's own quick wag is not a turn)
const SLIDE_ARM := 2.2                    # the pivot this far ahead of your head, m: the seat swings 0.27 m out at full slide
const SLIDE_HZ := 1.6                     # the spring: out in about a fifth of a second ...
const SLIDE_ZETA := 0.5                   # ... lightly damped: one overshoot, then still
const SLIDE_RATE := deg_to_rad(45.0)      # and never faster than this
const SLIDE_SCRUB := 0.22                 # the scrub in your hands while it moves, at most (controller amplitude)
var _rim_flashing := false
static var slide_feel := true             # the SLIDE / GRIP switch on the left console (false: the cockpit keeps the sim's heading exactly)
static var _slide_loaded := false         # (its saved setting is read once a run, as the camera's)
static var map_whole := true              # the map's GLOBAL / LOCAL switch, on its pod: the whole country (false: the roads round the craft, heading up)
static var map_scheme := 0                # ... and its colour button: which of MinimapPanel.SCHEMES the screen is drawn in
static var _map_loaded := false           # (both saved, and read once a run)
# The quick menu's OPTIONS page (Luke, 2026-11-22: "bring back heat and energy as optional consumables.
# I also think we need power-ups in some way"): the gameplay switches, saved as the others are.
#   consumables   HEAT AND ENERGY: the sims' `limits` (the battery the burner and the boost spend, the
#                 engines' heat and their flameouts). Off unless switched on: the flying he has now.
#   power-ups     CraftView.power_ups_on (view/power_ups.gd): the lit gates. On unless switched off.
static var consumables := false
static var _options_loaded := false       # (both read once a run)
# The boost (Luke: "Holding the ramjet arm button should give an extra boost"): B tapped arms or
# disarms the ramjet as it always has (on the way up now, not the way down); held past BOOST_HOLD it
# is the sims' inp.boost for as long as it is held, and arms nothing.
const BOOST_HOLD := 0.35
const BOOST_TICK := 0.12                  # s between the ticks in both hands while it burns
var boosting := false                     # B is being held past BOOST_HOLD
var _b_held := 0.0
var _boost_tick := 0.0
var _menu_page := ""                      # "" the quick menu's first page, "options" its second
var slide_switch                          # vr/mode_switch.gd again: SLIDE up, GRIP down
var _slide := 0.0
var _slide_rate := 0.0
var _slide_load := 0.0                    # the cornering load, smoothed, g (+ a left turn)
# The g-meter on the centre dial (Luke: "a g-force meter"; vr/gauge_cluster.gd). What it reads is the
# pod's own change of velocity, taken against the sim's clock (a frame that ran five steps of the sim
# and one that ran six then read the same) along the pod's nose and across it, and smoothed just
# enough to hold a needle still. The whole load is that with the 1 g the seat holds you up with, so
# it stands at 1 at rest and falls toward 0 over a jump.
const G_TAU := 0.15                       # s
const G_NOT_A_LOAD := 250.0               # g: more than this in a frame is a respawn or a wall struck, not a load to read
var g_along := 0.0                        # along the pod's nose, g: + speeding up
var g_across := 0.0                       # across it, g: + a left turn
var g_turn := 0.0                         # ... with a shaft's carrying taken out (it presses you into the seat, not across it): the slip bar
var g_seat := 1.0                         # the 1 g the seat holds you up with: less as she leaves the ground, none in the air
var _g_from := [0.0, 0.0, -1.0]           # the pod's velocity and the sim's clock at the last reading
var _buzz_hold := {}   # controller -> seconds an event buzz still owns it (the shudder waits)
const SHAKE_M := 0.004   # cockpit shake per unit of air-brake shudder, metres
const GRAB_SHAKE_M := 0.007   # the gear's grab: the cockpit's jolt, metres (fore and aft, a little up)
const GRAB_HZ := 22.0
const GRAB_DECAY := 0.3       # s
var _grab := 0.0              # the grab's shudder, 1 at the grab, decaying
var _grab_t := 0.0
var origin: XROrigin3D
# The camera (Luke: "Will you also add a camera change to the pause menu?"): the seat, or outside
# behind the pod. Outside, the horizon stays level and the view turns with the pod's heading and
# nothing else: the pod banks and shudders in front of you, the world does not. Your head still
# moves in it one for one. Picked in the quick menu, kept through restarts, saved with the controls.
const CAMERAS := ["cockpit", "chase", "far"]
const CAMERA_NAMES := {"cockpit": "COCKPIT", "chase": "CHASE", "far": "FAR CHASE"}
const CAMERA_OFFSETS := {"chase": Vector3(0.0, 1.3, 5.2), "far": Vector3(0.0, 3.6, 12.0)}   # from the seated eye: up, and aft
static var camera := "cockpit"
static var _camera_loaded := false   # the saved choice is read once a run: after that the menu's is the latest
static var _nose_loaded := false     # (the same, for the nose open or closed)
var screen_reflection      # the cockpit, faintly, in the windscreen (view/screen_reflection.gd); null without the roof
var chase_hud: Label3D      # outside, the gauges are out of reading distance: the speed, the Mach line and the guidance, low and left
var hands := {}
var lever_pivots: Array[Node3D] = []
var lever_tips: Array[StandardMaterial3D] = []
var brake_paddles: Array[Node3D] = []
var tow_meter: ShaderMaterial
var dashboard   # the instruments: the gauge cluster (vr/gauge_cluster.gd), or the flat panel (vr/dashboard.gd)
var _skill_readout: Label3D
var _skill_award: Label3D
var _skill_shown := {}      # the score as it was last drawn (view/skill_display.gd): the cluster's counter and feat line read it too
var _skill_on := true
var wag = WagMeterScript.new()        # the nose wag since the last report (a WAG: line every 10 s)
var wag_all = WagMeterScript.new()    # ... over the whole flight (on exit)
var fade_mat: StandardMaterial3D
var fade_v := 0.0
var edges := {}
var frame_ms := PackedFloat32Array()
var report_t := 0.0
# the report's window: each frame's main-thread work (_process, ms), its parts summed, and the
# renderer's measured CPU and GPU time for the view (both eyes): the split between CPU and GPU
var _w_cpu := PackedFloat32Array()
var _w_gpu := PackedFloat32Array()
var _w_sum := {}
var quest
var _y_held := 0.0
var _menu_held := 0.0
var _menu_fired := false
var _switch_at := -1     # --switch-track-at=FRAMES: switch track by itself (tests the reload path)
var _frames := 0
var _y_fired := false
var _scheme_flash := 0.0
var _turbines := false   # the second stage is running (EngineAudio.turbines_at): the cluster's TURBINES lamp
var hands_live := true   # false while the OpenXR session isn't focused (_on_xr_event); never in a flat run
# The start-up (Luke: "design a 'startup' sequence for the vehicle, similar to a jet startup sequence
# ... a kind of tutorial i can walk people through"): vr/startup_sequence.gd is its logic, the panel
# under the roof's header its controls. A flight chosen from the menu begins cold; a restart, a
# track switched in flight, a replay and every test begin running, as they always did. What the
# pilot's hands ask stays in `inp` (the levers, the dials and the engines' sound follow it); the sim
# is given what the sequence lets through (_sim_step).
static var cold_start := true        # the pilot's choice (the quick menu's COLD START, saved): menu flights begin cold
static var _startup_loaded := false  # (its saved setting is read once a run, as the camera's)
static var school := true            # FLIGHT SCHOOL (the quick menu's, saved): a cold start's run-up is taught, a lesson at a time
                                     # (vr/startup_sequence.gd `school`). On for a pilot who has not passed it; passing it turns it off.
static var _school_loaded := false
static var cold_on_entry := false    # set by the menu as it launches a flight: this one begins cold, if the pilot's choice allows
var startup = StartupScript.new()    # (running, until _ready says otherwise)
var coach = preload("res://vr/flight_coach.gd").new()   # the first minute of a taught flight, a line at a time on the glass (off until a taught run-up's brake comes off)
var _coach_armed := false            # this flight began with the school on: the coach takes over when the brake comes off
var overhead                         # vr/overhead_panel.gd; null without the roof (there is no header to hang it from: no cold start then)
var startup_audio                    # audio/startup_audio.gd; null when muted
var _turbine_lamp := false           # the run-up's turbine test has the TURBINES lamp lit
var _run_shake := 0.0                # the cockpit's tremble while an engine starts or strains against the brake


func _ready() -> void:
	_await_neutral_controls = require_neutral_on_entry
	require_neutral_on_entry = false
	quest = QuestControlsScript.new()
	quest.set_gear(0)   # gears on the right stick (triggers), first gear from the start
	super()
	var prefs := _load_prefs()
	if QuestControlsScript.SCHEMES.has(prefs.get("scheme", "")):
		quest.scheme = prefs.scheme
	if not _camera_loaded and CAMERAS.has(prefs.get("camera", "")):
		camera = prefs.camera
	_camera_loaded = true
	if not _nose_loaded and prefs.get("nose", "open") == "closed":   # (once a run: after that the menu's own choice stands)
		set_nose_closed(true)
	_nose_loaded = true
	if not _slide_loaded and prefs.has("slide"):
		slide_feel = prefs.slide != "off"
	_slide_loaded = true
	if not _map_loaded:
		map_whole = String(prefs.get("map", "global")) != "local"
		map_scheme = maxi(0, MinimapPanelScript.scheme_named(String(prefs.get("map_scheme", ""))))
	_map_loaded = true
	if not _startup_loaded and prefs.has("startup"):
		cold_start = prefs.startup != "hot"
	_startup_loaded = true
	var cold := cold_on_entry and cold_start
	cold_on_entry = false
	for a in OS.get_cmdline_user_args():
		if a == "--cold-start":
			cold = true
		elif a == "--hot-start":
			cold = false
	if engine_audio:
		startup_audio = StartupAudioScript.new()
		add_child(startup_audio)
		startup_audio.setup(overhead.pods if overhead != null else {})   # a switch's sound comes from its pod
	if not _school_loaded and prefs.has("school"):
		school = prefs.school != "done"
	_school_loaded = true
	if not _options_loaded:
		consumables = String(prefs.get("consumables", "off")) == "on"
		power_ups_on = String(prefs.get("powerups", "on")) != "off"
	_options_loaded = true
	if bool(sim.P.limits) != consumables:
		sim.set_limits(consumables)
	set_power_ups(power_ups_on)
	if cold and overhead != null and replay.is_empty() and cruise < 0.0:
		startup.school = school and quest.scheme == "triggers"      # (the lessons are the trigger throttles')
		_coach_armed = startup.school
		startup.cold()
		for k in 2:                       # parked: her air brakes were left out, all of them
			craft.flap_open[k] = 1.0
			craft.front_open[k] = 1.0
		craft.pod_flap_open = 1.0
		print("STARTUP: parked, cold and dark")
	_apply_startup(0.0)
	var forced := false
	for a in OS.get_cmdline_user_args():
		forced = forced or a.begins_with("--handling=")
	# the saved handling applies to the range; the grand prix is a STARFIGHTER course
	if not forced and not sim.course and prefs.get("handling", "speed") != sim.P.handling:
		set_handling(prefs.handling)
	handling_ask = sim.P.handling
	quest.sync_handling(sim.hblend)
	_scheme_flash = 6.0
	if wind_audio:
		wind_audio.boomed.connect(_on_boom)
	print("CONTROLS: %s, %s handling" % [quest.scheme, sim.P.handling])
	print("TRACK: %s" % _track())
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--switch-track-at="):
			_switch_at = int(a.get_slice("=", 1))
		if a.begins_with("--brake-trace="):
			_brake_trace = BrakeDiagnosticsScript.new()
			_brake_trace.open(a.trim_prefix("--brake-trace="), _track())


func _sim_step() -> void:
	if startup.is_hot():
		super()
	else:
		# the sim is given what the start-up lets through; the cockpit keeps what the hands ask
		var asked := inp
		inp = startup.gate(asked)
		super()
		inp = asked
	if _brake_trace:
		_brake_trace.observe_step(sim)


func _load_prefs() -> Dictionary:
	if FileAccess.file_exists(PREFS):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PREFS))
		if d is Dictionary:
			return d
	return {}


func _save_prefs() -> void:
	var f := FileAccess.open(PREFS, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"scheme": quest.scheme, "handling": handling_ask if handling_ask != "" else sim.P.handling, "camera": camera,
			"nose": "closed" if CraftModelScript.nose_closed else "open", "slide": "on" if slide_feel else "off",
			"startup": "cold" if cold_start else "hot", "school": "on" if school else "done",
			"consumables": "on" if consumables else "off", "powerups": "on" if power_ups_on else "off",
			"map": "global" if map_whole else "local", "map_scheme": String(MinimapPanelScript.SCHEMES[map_scheme].name)}))


## Thumbstick click (either stick): sit where you are. Recentres the view AND the height, so
## your eyes land on the seat's eye point (Luke: "can I get a vertical height reset somewhere").
## The automatic recentre when the headset goes on keeps your height; this one resets it.
func recenter() -> void:
	XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, false)
	print("RECENTER: view and seat height")
	if hands.has("left"):
		_buzz(hands.left, 0.3, 0.05)
		_buzz(hands.right, 0.3, 0.05)


## A restart: back to first gear (the gearbox, if it's on).
func _respawn() -> void:
	super()
	if quest.gear >= 0:
		quest.sync_handling(sim.hblend, true)


## The forcefield flares round the nose in the headset too.
func _field_flash(amount: float) -> void:
	super(amount)
	if canopy:
		CanopyScript.flash(canopy, amount)


func _buzz(c: XRController3D, amp: float, dur: float, delay := 0.0) -> void:
	c.trigger_haptic_pulse("haptic", 0.0, amp, dur, delay)
	_buzz_hold[c] = dur + delay


## The air brakes shudder (Luke: "should have a shudder to them too"): each side's shudder from
## the wind audio (the same bursts you hear) trembles the hand on that brake (the left brake is
## the left hand in every scheme) and shakes the cockpit around you by a few millimetres. Never
## the view itself: your head stays put. Event buzzes (hits, the gate) win while they last.
static func brake_haptic_strength(shudder: float) -> float:
	var s := clampf(shudder, 0.0, 1.0)
	# A light squeeze must not suddenly cross into the former 20% minimum rumble.
	return 0.8 * s * smoothstep(0.03, 0.12, s)


func _apply_shudder(delta: float) -> void:
	for c in _buzz_hold.keys():
		_buzz_hold[c] = maxf(0.0, _buzz_hold[c] - delta)
	var tremble := _startup_shake(delta)
	if not wind_audio:
		shell.position = _grab_jolt(delta) + tremble
		return
	var s: Array = wind_audio.shudder
	var w: Array = wind_audio.shake
	for k in 2:
		var hand: XRController3D = hands.left if k == 0 else hands.right
		var strength := maxf(brake_haptic_strength(s[k]), SLIDE_SCRUB * slide_scrub(k == 1))   # the brake's shudder, or the slide's scrub
		strength = maxf(strength, startup_rumble(_hand_engine(k)))                            # ... or that hand's engine starting, or straining against the brake
		if strength > 0.0 and _buzz_hold.get(hand, 0.0) <= 0.0:
			hand.trigger_haptic_pulse("haptic", 0.0, strength, 0.05, 0.0)
	var up: float = s[0] * w[0] + s[1] * w[1]
	var side: float = s[0] * w[0] - s[1] * w[1]
	shell.position = Vector3(0.6 * side, up, 0.0) * SHAKE_M + _grab_jolt(delta) + tremble


## The gear's grab: the cockpit jolts fore and aft (a little up), GRAB_HZ, dying over GRAB_DECAY.
func _grab_jolt(delta: float) -> Vector3:
	if _grab <= 0.0:
		return Vector3.ZERO
	_grab_t += delta
	var a := _grab * exp(-_grab_t / GRAB_DECAY)
	if a < 0.02:
		_grab = 0.0
		return Vector3.ZERO
	var o := sin(TAU * GRAB_HZ * _grab_t)
	return Vector3(0.0, 0.35 * o, o) * GRAB_SHAKE_M * a


## Wall contact buzzes the hand that drives the engine that touched (with crossed trigger
## throttles the right engine is the left hand's), both hands for the pod; a scrape is light.
func _on_hit(who: String, strength: float) -> void:
	var hand_for := {"L": "left", "R": "right"}
	if quest.scheme == "triggers":
		hand_for = {"L": "right", "R": "left"}
	var amp := 0.85 * strength
	var dur := 0.14 if strength >= 1.0 else 0.06
	if who == "pod":
		_buzz(hands.left, amp, dur)
		_buzz(hands.right, amp, dur)
	elif hand_for.has(who):
		_buzz(hands[hand_for[who]], amp, dur)


func _on_boom() -> void:
	for side in ["left", "right"]:
		_buzz(hands[side], 1.0, 0.3)
		_buzz(hands[side], 0.55, 1.2, 0.3)


func _make_view() -> void:
	xr = XRServer.find_interface("OpenXR")
	var live := xr != null and xr.is_initialized()
	if live:
		get_viewport().use_xr = true
		# MSAA, not TAA/FSR2: temporal AA smears at these speeds and differs eye to eye. 4x costs
		# ~0.6 ms on the 5080 at Quest 3 resolution (1.66 -> 2.23 ms GPU, both eyes, Eridanus start).
		# Shaders must survive it: edge samples see UVs off the quad (view/pylon.gdshader).
		get_viewport().msaa_3d = Viewport.MSAA_4X
		# OpenXR paces frames; desktop vsync caps at 60 Hz and judders (Firefly Catcher, 2026-07-27).
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		for sig in ["session_begun", "session_synchronized", "session_visible", "session_focussed", "session_stopping",
				"session_loss_pending", "instance_exiting", "pose_recentered"]:
			if xr.has_signal(sig):
				xr.connect(sig, _on_xr_event.bind(sig))
		# a track switch reloads the scene mid-session: already focused, no session_focussed to come
		var oxr := xr as OpenXRInterface
		if oxr:
			_set_hands(oxr.get_session_state() == OpenXRInterface.SESSION_STATE_FOCUSED)
		if "display_refresh_rate" in xr:
			xr.set("display_refresh_rate", 90.0)
		# Sound in the headset, not on the desk: Windows' default output may be the PC speakers.
		for dev in AudioServer.get_output_device_list():
			if dev.contains("Oculus Virtual Audio"):
				AudioServer.output_device = dev
				print("AUDIO: output -> ", dev)
				break
		print("OPENXR: initialized, MSAA 4x")
	else:
		print("OPENXR: NOT initialized, running flat (is the Quest on and in Link mode?)")
	# the renderer's own timing of the view, for the report's CPU line (render cpu, gpu: both eyes)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)

	rig = Node3D.new()
	add_child(rig)
	origin = XROrigin3D.new()
	origin.position = EYE
	rig.add_child(origin)
	var xr_cam := XRCamera3D.new()
	xr_cam.far = 120000   # the backdrop peaks sit at 45-57 km; Eridanus' far ranges up to ~100 km away
	origin.add_child(xr_cam)
	cam = xr_cam
	for side in ["left", "right"]:
		var c := XRController3D.new()
		c.tracker = "%s_hand" % side
		origin.add_child(c)
		hands[side] = c
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.04, 0.03, 0.1)
		m.mesh = b
		m.material_override = _mat(Color(0.2, 0.22, 0.25))
		c.add_child(m)
	_build_cockpit()
	if network_world:
		TerminalLighting.mark_craft(rig)
	_build_fade(xr_cam)
	pod_mesh.visible = false   # you are sitting inside it
	craft.pod_frame = rig      # so the cables hook to the cockpit's own nose
	# Entering from the menu preserves an already-focused OpenXR session, so
	# session_focussed will not fire again to place the player in the new seat.
	if live and hands_live:
		recenter.call_deferred()


func _on_xr_event(sig: String) -> void:
	print("OPENXR: ", sig)
	if sig != "pose_recentered":
		_set_hands(sig == "session_focussed")
	if sig == "session_focussed":
		XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
		var trackers := XRServer.get_trackers(XRServer.TRACKER_CONTROLLER)
		for name in trackers:
			var t: XRPositionalTracker = trackers[name]
			print("DIAG tracker: %s profile=%s" % [name, t.profile])


## Focus gone, the controllers are let go: OpenXR keeps reporting their last state, so Luke's log
## (2026-10-20) flew on at full trigger after session_stopping, 7,991 km/h with nobody aboard. A held
## lever (sticks, grab, mixed) goes to idle too, and a button held as it went is no tap.
func _set_hands(on: bool) -> void:
	if on == hands_live:
		return
	hands_live = on
	print("CONTROLS: Quest controllers ", "live" if on else "let go (the session isn't focused)")
	if not on:
		quest.thr_l = 0.0
		quest.thr_r = 0.0
		quest.collective = 0.0
		_y_held = 0.0
		_menu_held = 0.0
		_a_held = 0.0
	elif menu.open:
		_seed_menu_edges()


## A controller's trigger / grip, stick and button, or let go while the session isn't focused.
func _axis(c: XRController3D, input: String) -> float:
	return c.get_float(input) if hands_live and not _await_neutral_controls else 0.0


func _stick(c: XRController3D, input: String) -> Vector2:
	return c.get_vector2(input) if hands_live and not _await_neutral_controls else Vector2.ZERO


func _button(c: XRController3D, input: String) -> bool:
	return hands_live and not _await_neutral_controls and c.is_button_pressed(input)


func _release_menu_controls() -> void:
	if not _await_neutral_controls or not hands_live:
		return
	var tracked := false
	for hand: XRController3D in hands.values():
		if not hand.get_has_tracking_data():
			continue
		tracked = true
		if hand.get_float("trigger") > 0.2 or hand.get_float("grip") > 0.2 or hand.get_vector2("primary").length() > 0.3:
			return
		for button in ["ax_button", "by_button", "menu_button", "primary_click"]:
			if hand.is_button_pressed(button):
				return
	if tracked:
		_await_neutral_controls = false
		print("CONTROLS: menu inputs released; flight controls ready")


var _diag_t := 0.0

# Once a second: every boundary of the input chain, so a dead control shows where it dies.
func _diag(delta: float, l: XRController3D, r: XRController3D, p: Dictionary) -> void:
	_diag_t += delta
	if _diag_t < 1.0:
		return
	_diag_t = 0.0
	var pads := []
	for d in Input.get_connected_joypads():
		pads.append("%d:%s known=%s ax0=%.2f ax1=%.2f" % [d, Input.get_joy_name(d), Input.is_joy_known(d),
			Input.get_joy_axis(d, 0), Input.get_joy_axis(d, 1)])
	print("DIAG input: pads=%s src=%s | L track=%s stick=%s trig=%.2f | R track=%s stick=%s trig=%.2f | hands %s | poll thr=%.2f/%.2f | inp thr=%.2f/%.2f | v=%d km/h" % [
		pads, levers.source,
		l.get_has_tracking_data(), l.get_vector2("primary"), l.get_float("trigger"),
		r.get_has_tracking_data(), r.get_vector2("primary"), r.get_float("trigger"),
		"live" if hands_live else "let go", p.thrL, p.thrR, inp.thrL, inp.thrR,
		int(sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) * 3.6)])
	print("DIAG craft: scheme=%s grip=%.2f/%.2f brk=%.2f/%.2f shudder=%.2f/%.2f shake=%.1fmm hp=%.2f/%.2f pod=%.2f heat=%.2f/%.2f flameout=%s/%s mode=%s bat=%.2f btn X=%s Y=%s A=%s B=%s" % [
		quest.scheme, l.get_float("grip"), r.get_float("grip"), inp.brkL, inp.brkR,
		wind_audio.shudder[0] if wind_audio else 0.0, wind_audio.shudder[1] if wind_audio else 0.0, shell.position.length() * 1000.0,
		sim.eL.health, sim.eR.health, sim.pod.health,
		sim.eL.heat, sim.eR.heat, sim.eL.flameout, sim.eR.flameout, sim.mode, sim.battery,
		l.is_button_pressed("ax_button"), l.is_button_pressed("by_button"), r.is_button_pressed("ax_button"), r.is_button_pressed("by_button")])
	if sim.boost > 0 or sim.P.limits or (power_ups != null and power_ups.took > 0):
		print("DIAG systems: boost=%d held=%s surge=%.1f limits=%s gates=%d" % [sim.boost, boosting, maxf(0.0, surge), sim.P.limits, power_ups.took if power_ups != null else 0])


func _box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rot_x := 0.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = _mat(c)
	m.position = pos
	m.rotation.x = rot_x
	parent.add_child(m)
	return m


## Realism spike: a bucket seat in the old one's envelope: a cushion with a thigh roll, a back
## that narrows to the headrest, and bolsters down both, all in pebbled leather.
func _shaped_seat(colour: Color) -> void:
	var white := Color.WHITE
	var cushion := [[SeatLoft.loft([[0.60, 0.27, 0.10, 0.19, 3.0], [0.66, 0.30, 0.085, 0.215, 3.5], [0.80, 0.30, 0.085, 0.205, 4.0],
		[1.0, 0.30, 0.09, 0.20, 4.0], [1.08, 0.28, 0.115, 0.195, 3.4], [1.12, 0.23, 0.14, 0.185, 3.0]], 28), Transform3D.IDENTITY, white]]   # the tail lifts clear of the hull floor, which rises aft (test_cables)
	var upright := Transform3D(Basis(Vector3.RIGHT, -0.12) * Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0, 0.54, 1.1))
	var back := [[SeatLoft.loft([[-0.39, 0.28, -0.06, 0.06, 3.5], [-0.25, 0.31, -0.065, 0.065, 4.0], [0.15, 0.30, -0.065, 0.065, 4.0],
		[0.30, 0.24, -0.06, 0.06, 3.5], [0.39, 0.17, -0.05, 0.05, 3.0]], 28), upright, white]]
	for s in [-1.0, 1.0]:
		cushion.append([SeatLoft.loft([[0.64, 0.045, 0.14, 0.235, 2.5], [0.75, 0.055, 0.13, 0.26, 2.6], [1.0, 0.055, 0.13, 0.265, 2.6],
			[1.1, 0.045, 0.14, 0.24, 2.5]], 16), Kit.at(Vector3(0.265 * s, 0, 0)), white])
		back.append([SeatLoft.loft([[-0.3, 0.04, 0.02, 0.11, 2.5], [0.0, 0.05, 0.02, 0.13, 2.6], [0.2, 0.04, 0.02, 0.11, 2.5]], 16),
			upright * Kit.at(Vector3(0.27 * s, 0, 0)), white])
	for piece in [["seat_back", back], ["seat_cushion", cushion]]:
		var m := MeshInstance3D.new()
		m.name = piece[0]
		m.mesh = Kit.compound(piece[1])
		m.material_override = SeatFinish.tinted("leather", colour)
		shell.add_child(m)


func _rbox(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rot_x := 0.0, n := 6.0, rough := 0.7) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = Kit.rounded_box(size, n)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = rough
	m.material_override = mat
	m.position = pos
	m.rotation.x = rot_x
	parent.add_child(m)
	return m


func _build_cockpit() -> void:
	var leather := Color(0.13, 0.12, 0.12)
	# You sit in the pod itself: the same polished hull the flat view shows, open cockpit,
	# rubber lip, matte trim inside, the nose and its cable hardpoints out ahead.
	shell = Node3D.new()
	shell.name = "shell"
	rig.add_child(shell)
	var hull := MeshInstance3D.new()
	hull.name = "PodHull"
	var shrike: bool = sim != null and sim.P.vehicle == CraftModelScript.PilotCraft.SHRIKE
	hull.mesh = CraftModelScript.pod_hull(shrike)
	if shrike:
		CraftModelScript.Shrike.dress_pod(hull)
	hull.position = Vector3(0, CraftModelScript.POD_FRAME_UP, 0)
	shell.add_child(hull)
	if shrike and craft:
		# The seat and chase cameras both see the hull on the cockpit rig. Carry the
		# working hinges and lamps with that hull, including its bank and shudder.
		for hinge in craft.pod_flaps:
			hinge.reparent(hull, false)
		craft.tail_lights.reparent(hull, false)
	for s in [-1.0, 1.0]:   # where the cables hook (the hull carries the eyes themselves)
		var mark := Marker3D.new()
		mark.name = "hardpoint_%s" % ("l" if s < 0.0 else "r")
		mark.position = Vector3(0.18 * s, CraftModelScript.POD_FRAME_UP + CraftModelScript.POD_EYE_H, -2.1)
		rig.add_child(mark)   # anchors, not fittings: on the rig, steady through the shudder
	if shrike:
		CraftModelScript.Shrike.fit_seat(shell)
	elif SeatFinish.hd:
		_shaped_seat(leather)
	else:
		_rbox(shell, Vector3(0.62, 0.78, 0.13), Vector3(0, 0.54, 1.1), leather, -0.12, 5.0).name = "seat_back"   # its top is the headrest
		_rbox(shell, Vector3(0.6, 0.12, 0.52), Vector3(0, 0.145, 0.86), leather, 0.0, 5.0).name = "seat_cushion"   # both clear the hull floor (test_cables)
	for s in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.46 * s, 0.1, 0.2)   # beside the seat, clear of the instrument panel
		shell.add_child(pivot)
		var shaft := MeshInstance3D.new()
		if shrike:
			shaft.mesh = CraftModelScript.Shrike.part(&"ThrottleLink")
		else:
			shaft.mesh = Kit.cyl(0.016, 0.016, 0.32, 12)
			if SeatFinish.hd:   # realism spike: a round satin shaft with a ferrule under the grip
				shaft.mesh = Kit.compound([[Kit.cyl(0.016, 0.016, 0.32, 28), Transform3D.IDENTITY, Color(0.75, 0.77, 0.8)],
					[Kit.cyl(0.021, 0.0225, 0.018, 28), Kit.at(Vector3(0, 0.132, 0)), Color(0.42, 0.44, 0.47)]])
			var steel := StandardMaterial3D.new()
			steel.albedo_color = Color(0.75, 0.77, 0.8)
			steel.metallic = 0.9
			steel.roughness = 0.25
			shaft.material_override = SeatFinish.satin() if SeatFinish.hd else steel
			shaft.position = Vector3(0, 0.16, 0)
		pivot.add_child(shaft)
		var knob := MeshInstance3D.new()
		knob.name = "PilotGrip"
		knob.mesh = CraftModelScript.Shrike.part(&"PilotGrip") if shrike else CockpitInteriorScript.deck_mesh("Grip")
		if not shrike:
			CockpitInteriorScript.Accent.dress(knob)      # its anodised band is the livery's
		knob.position = Vector3(0, 0.36, 0)
		pivot.add_child(knob)
		if shrike:
			var paddle := MeshInstance3D.new()
			paddle.name = "BrakePaddle"
			paddle.mesh = CraftModelScript.Shrike.part(&"BrakePaddle")
			paddle.position = Vector3(-s * 0.032, 0.030, -0.021)
			knob.add_child(paddle)
			brake_paddles.append(paddle)
		var indicator := MeshInstance3D.new()
		indicator.name = "GateIndicator"
		indicator.mesh = Kit.rounded_box(Vector3(0.036, 0.012, 0.045), 4.0, 6)
		indicator.position = Vector3(-s * 0.009, 0.054, 0.004)
		var km := StandardMaterial3D.new()
		km.albedo_color = Color(0.16, 0.17, 0.19)
		km.roughness = 0.35
		indicator.material_override = km
		knob.add_child(indicator)
		lever_pivots.append(pivot)
		lever_tips.append(km)
	# instrument panel: curved round the eye, inside the cockpit opening (clear of the hull), up
	# under its rim on the dashboard (the interior builds that), low enough that the nose and its
	# cable hardpoints still show over the top
	CockpitInteriorScript.instrument_rails = not GaugeClusterScript.available()
	interior = CockpitInteriorScript.new()   # floor, frames, consoles, harness, rim light
	shell.add_child(interior)
	interior.build()
	if sim != null and sim.P.vehicle == CraftModelScript.PilotCraft.SHRIKE:
		tow_meter = CraftModelScript.Shrike.dress_coaming(interior.get_node("SegmentedCoaming"), CockpitInteriorScript.hd_parts and ResourceLoader.exists(CockpitInteriorScript.HD_PARTS.Coaming))
	mode_switch = ModeSwitchScript.new()   # SPEEDCRAFT / STARFIGHTER, on the front of the right console
	shell.add_child(mode_switch)
	mode_switch.transform = ModeSwitchScript.mount()
	mode_switch.build()
	# The slide's own switch (Luke: "can you make the slide a physical thing in the cockpit?"): the same
	# guarded toggle, on the front of the left console. Up is SLIDE, down is GRIP (no slide).
	slide_switch = ModeSwitchScript.new()
	slide_switch.name = "SlideSwitch"
	slide_switch.legends = ["SLIDE", "GRIP"]
	slide_switch.colours = [Color(1.0, 0.62, 0.15), Color(0.75, 0.9, 1.0)]
	slide_switch.throws = ["slide", "grip"]
	shell.add_child(slide_switch)
	slide_switch.transform = ModeSwitchScript.mount(-1.0)
	slide_switch.build()
	canopy = CanopyScript.build()
	canopy.position = Vector3(0, CraftModelScript.POD_FRAME_UP, 0)
	shell.add_child(canopy)
	if ChaseScript.craft == "patrol":      # the patrol craft: the cockpit's own roof carries the light bar too
		add_light_bar(canopy)
	if sim.kind == "network" or CanopyScript.roof_available():   # (under the roof on every course: it throws the start-up's checklist on the glass too)
		_mount_approach_projector(canopy)
	if CanopyScript.roof_available() and OverheadPanelScript.fitted:      # the start panel: a pod either side of the projector, on the header rail
		overhead = OverheadPanelScript.new()
		canopy.add_child(overhead)
		overhead.build()
	dashboard = GaugeClusterScript.new() if GaugeClusterScript.available() else DashboardScript.new()
	if dashboard is GaugeClusterScript:
		dashboard.ivory_thrust_dials = tow_meter != null
	shell.add_child(dashboard)
	dashboard.transform = DashboardScript.mount()
	dashboard.build()
	minimap_panel = MinimapPanelScript.new()   # the path ahead, up and left of the instrument panel
	shell.add_child(minimap_panel)
	minimap_panel.transform = MinimapPanelScript.mount(SEAT)
	minimap_panel.build()
	minimap_panel.set_scheme(map_scheme, false)
	minimap_panel.set_live(sim.kind == "circuit" or sim.kind == "network")
	if ScreenReflectionScript.available():   # last: it takes its picture of everything the cockpit holds
		screen_reflection = ScreenReflectionScript.new()
		# what the glass is to show, besides the coaming along its foot: the instruments and the map
		var inv: Transform3D = canopy.global_transform.affine_inverse()
		screen_reflection.build(canopy, shell, [[inv * dashboard.global_position + Vector3(0.0, 0.12, 0.0), 0.3], [inv * minimap_panel.global_position, 0.17]])
	menu_panel = Node3D.new()   # the main menu: a dark panel and its words, a metre out, never behind anything
	menu_panel.name = "main_menu"
	menu_panel.position = Vector3(0.0, 0.02, -1.1)   # on the origin: in front of whichever camera is up (in the seat, over the dash)
	menu_panel.visible = false
	if origin:
		origin.add_child(menu_panel)
	else:   # (a cockpit built on its own, for the fittings' checks: there is no camera to hang it from)
		menu_panel.position += EYE
		shell.add_child(menu_panel)
	var back := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(1.05, 0.72)      # (eight lines now: the hour and the weather joined them)
	back.mesh = bq
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(0.03, 0.05, 0.09, 0.98)
	bm.no_depth_test = true
	bm.render_priority = 120   # above minimap (40) and world destination markers (100)
	back.material_override = bm
	menu_panel.add_child(back)
	var words := Label3D.new()
	words.name = "words"
	words.font_size = 40
	words.pixel_size = 0.0011
	words.no_depth_test = true
	words.render_priority = 121   # below the comfort fade (127)
	words.outline_size = 0
	words.position = Vector3(-0.47, 0.0, 0.01)
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	menu_panel.add_child(words)
	if origin:
		_build_chase_hud()


## The outside views' readout: on the origin (level with the view, not stuck to the head), low and
## to the left, clear of the pod below and the engines ahead.
func _build_chase_hud() -> void:
	chase_hud = Label3D.new()
	chase_hud.name = "chase_hud"
	chase_hud.font_size = 48
	chase_hud.pixel_size = 0.0011
	chase_hud.outline_size = 8
	chase_hud.outline_modulate = Color(0.015, 0.025, 0.03, 0.9)
	chase_hud.modulate = Color(0.74, 0.96, 0.98)
	chase_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	chase_hud.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	chase_hud.double_sided = false
	chase_hud.no_depth_test = true
	chase_hud.render_priority = 3
	chase_hud.outline_render_priority = 2
	chase_hud.position = Vector3(-0.92, -0.3, -1.6)
	chase_hud.rotation.y = deg_to_rad(24.0)   # square to the eye it sits left of
	chase_hud.visible = false
	origin.add_child(chase_hud)


## Put the origin where the chosen camera is. In the seat it is the rig's own (the eye point). Outside
## it is that point carried up and aft in the pod's heading, level: `level` is the heading's frame
## (carried onto a shaft's shape where there is one) and `floor` the rig's floor point in the world.
func _place_origin(level: Basis, floor_at: Vector3) -> void:
	if camera == "cockpit" or not CAMERA_OFFSETS.has(camera):
		origin.transform = Transform3D(Basis.IDENTITY, EYE)
	else:
		origin.global_transform = global_transform * Transform3D(level, floor_at + level * (EYE + CAMERA_OFFSETS[camera]))
	if chase_hud:
		chase_hud.visible = camera != "cockpit"


## The next camera (the quick menu's CAMERA line).
func next_camera() -> void:
	camera = CAMERAS[(CAMERAS.find(camera) + 1) % CAMERAS.size()]
	_save_prefs()
	print("CAMERA: ", camera)
	_place_camera(1.0)
	_update_hud()


func _build_fade(xr_cam: XRCamera3D) -> void:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.25
	s.height = 0.5
	m.mesh = s
	fade_mat = StandardMaterial3D.new()
	fade_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fade_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fade_mat.no_depth_test = true
	fade_mat.render_priority = 127
	fade_mat.albedo_color = Color(0, 0, 0, 0)
	m.material_override = fade_mat
	xr_cam.add_child(m)


const A_HOLD := 1.0   # s: the Network's A held this long in a city's zone drops you into its GP
var _a_held := 0.0
var _a_fired := false


func _pressed_once(key: String, down: bool) -> bool:
	var fired: bool = down and not edges.get(key, false)
	edges[key] = down
	return fired


func _read_input(delta: float) -> void:
	_release_menu_controls()
	var l: XRController3D = hands.left
	var r: XRController3D = hands.right
	match _menu(_button(l, "menu_button"), delta):
		"quick":
			menu_open(not menu.open)
			_buzz(l, 0.5, 0.08)
			return
		"menu":
			_buzz(l, 0.9, 0.2)
			_buzz(r, 0.9, 0.2)
			return_to_menu()
			return
	if menu.open:
		_menu_hands(l, r)
		return
	var p: Dictionary = levers.poll(delta)
	var c := {"lt": _axis(l, "trigger"), "rt": _axis(r, "trigger"), "lg": _axis(l, "grip"), "rg": _axis(r, "grip"),
		"ls": _stick(l, "primary"), "rs": _stick(r, "primary"), "lz": l.position.z, "rz": r.position.z,
		"speed": sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy), "yaw": (sim.eL.w + sim.eR.w) / 2.0,
		# (the gearbox goes by the speed of the air the craft meets: half its ground speed on the Aurora Line)
		"airspeed": sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) / sim.line_speed(),
		"sf": sim.hblend}
	var q: Dictionary = quest.update(c, delta)
	if q.shift != 0:   # a shift: a click in the right hand (up firmer than down)
		_buzz(r, 0.8 if q.shift > 0 else 0.5, 0.05 if q.shift > 0 else 0.03)
	if q.get("grab", 0.0) > 0.0:   # the next gear grabs: a thump in both hands, the cockpit shudders
		_grab = float(q.grab)
		_grab_t = 0.0
		_buzz(l, 0.9 * _grab, 0.09)
		_buzz(r, 0.9 * _grab, 0.09)
	if q.tickL:
		_buzz(l, 0.35, 0.04)
	if q.tickR:
		_buzz(r, 0.35, 0.04)
	if q.get("burner_change", 0) != 0:   # the burner lit (a thump) or out (softer), in the left hand: its stick
		_buzz(l, 0.85 if q.burner_change > 0 else 0.45, 0.08 if q.burner_change > 0 else 0.05)
	elif q.get("burner_refused", false):   # not below top gear: a double tap
		_buzz(l, 0.4, 0.03)
		_buzz(l, 0.4, 0.03, 0.08)
	if levers.source.begins_with("Gamepad"):   # printed levers or a gamepad in use: they win
		inp = {"thrL": p.thrL, "thrR": p.thrR, "brkL": maxf(p.brkL, q.brkL), "brkR": maxf(p.brkR, q.brkR)}
	else:
		inp = {"thrL": maxf(p.thrL, q.thrL), "thrR": maxf(p.thrR, q.thrR), "brkL": maxf(p.brkL, q.brkL), "brkR": maxf(p.brkR, q.brkR)}
	inp.repair = p.repair or _button(l, "ax_button")
	# (with the consumables on a flamed-out engine relights by itself once it has cooled: A is the
	# Network's target button too, and an engine that waits for it is a surprise, not a consequence)
	inp.reignite = p.reignite or _button(r, "ax_button") or consumables
	if quest.scheme == "triggers" and not levers.source.begins_with("Gamepad"):
		# the burner's the left stick's (the levers stay under the gate); the keyboard's still lights it
		inp.burner = bool(q.get("burner", false)) or (p.thrL >= sim.P.gate and p.thrR >= sim.P.gate)
	if quest.scheme == "triggers" and quest.gear >= 0 and not levers.source.begins_with("Gamepad"):
		inp.thrMul = q.get("mul", 1.0)   # the gearbox's pull
		inp.gearRpm = q.get("rpm", 0.0)   # ... and its revs, for the engine sound
		inp.gearIndex = quest.gear
		inp.gearOverdrive = bool(q.get("overdrive", false))
	# the Network: A tapped, the next city as the target; held in a city's STARFIGHTER zone, its GP
	if sim.kind == "network":
		if _button(r, "ax_button"):
			_a_held += delta
			if _a_held >= A_HOLD and not _a_fired and net_city_gp() != "":
				_a_fired = true
				_buzz(r, 0.9, 0.2)
				enter_city_gp()
		else:
			if _a_held > 0.0 and not _a_fired:
				net_cycle_target()
				_buzz(r, 0.5, 0.06)
			_a_held = 0.0
			_a_fired = false
	if p.arm:
		sim.armed = not sim.armed
	match arm_button(_button(r, "by_button"), delta):
		"arm":
			sim.armed = not sim.armed
		"boost":                     # it lights: a thump in the hand that holds it, a lighter one in the other
			_buzz(r, 0.9, 0.12)
			_buzz(l, 0.6, 0.08)
	_boost_step(delta, l, r)
	# Y: tap restarts, hold flips the handling (live, as the MODE switch)
	if p.respawn:
		_respawn()
	if _button(l, "by_button"):
		_y_held += delta
		if _y_held >= Y_HOLD and not _y_fired:
			_y_fired = true
			toggle_handling()
			_save_prefs()
			_buzz(l, 0.8, 0.15)
	else:
		if _y_held > 0.0 and not _y_fired:
			_respawn()
		_y_held = 0.0
		_y_fired = false
	_frames += 1
	if _switch_at > 0 and _frames == _switch_at and track_override == "":   # once
		switch_track()
	# the MODE switch: either hand can throw it
	if mode_switch and hands_live and not _await_neutral_controls:
		for hand in [l, r]:
			var flip: String = mode_switch.poke(hand, delta)
			if flip != "" and ask_handling(flip):   # (refused inside the cooldown: the lever springs back)
				_save_prefs()
				_buzz(hand, 0.9, 0.06)
				print("HANDLING: switch to ", flip)
	# the SLIDE switch, the same way
	if slide_switch and hands_live and not _await_neutral_controls:
		for hand in [l, r]:
			var thrown: String = slide_switch.poke(hand, delta)
			if thrown != "":
				set_slide(thrown == "slide")
				_buzz(hand, 0.9, 0.06)
	# the map's own switch and button, on its pod
	if minimap_panel and hands_live and not _await_neutral_controls:
		for hand in [l, r]:
			var worked: String = minimap_panel.poke(hand, delta)
			if worked == "global" or worked == "local":
				set_map_whole(worked == "global")
				_buzz(hand, 0.9, 0.06)
			elif worked == "scheme":
				set_map_scheme(map_scheme + 1)
				_buzz(hand, 0.6, 0.04)
	if _pressed_once("recenter", _button(l, "primary_click") or _button(r, "primary_click")):
		recenter()
	# the start panel: either hand can work it
	if overhead and hands_live and not _await_neutral_controls:
		for hand in [l, r]:
			for hit: Array in overhead.poke(hand, delta):
				startup_work(String(hit[0]), int(hit[1]), hand)
	startup.gears = quest.scheme == "triggers" and quest.gear >= 1      # (a gearbox to try in the run-up)
	startup.step(delta, [inp.thrL, inp.thrR], quest.display_gear(), [l.get_float("grip"), r.get_float("grip")])
	if coach.on and not coach.done:
		_coach_step(delta, [l.get_float("grip"), r.get_float("grip")])
	_apply_startup(delta)
	_diag(delta, l, r, p)


## The ramjet ARM button, a frame: -> "arm" as a tap ends (it came up inside BOOST_HOLD), "boost"
## on the frame a hold becomes the boost, "" otherwise. `boosting` is true while it is held past
## BOOST_HOLD; letting go of a boost arms nothing.
func arm_button(down: bool, delta: float) -> String:
	if down:
		_b_held += delta
		var was := boosting
		boosting = _b_held >= BOOST_HOLD
		return "boost" if boosting and not was else ""
	var tapped := _b_held > 0.0 and not boosting
	_b_held = 0.0
	boosting = false
	return "arm" if tapped else ""


## The boost held: the sims' inp.boost once the craft is released and whole, a tick in both hands
## while the sim is giving it (not when the battery it needs is flat). And the consumables' one
## housekeeping: a burner left lit on a flat battery is put out, as the pilot would (it will not
## recharge while the burner is asked for, and nothing on the dash said why).
func _boost_step(delta: float, l: XRController3D, r: XRController3D) -> void:
	if boosting and startup.is_hot() and sim.crash_t <= 0.0:
		inp.boost = true
	_boost_tick -= delta
	if boosting and sim.boost > 0 and _boost_tick <= 0.0:
		_boost_tick = BOOST_TICK
		_buzz(l, 0.22, 0.04)
		_buzz(r, 0.22, 0.04)
	if consumables and quest.burner and sim.battery <= 0.0:
		quest.burner = false
		inp.burner = false
		_buzz(l, 0.45, 0.05)
		print("SYSTEMS: battery flat, burner out")


## The dash's ARM lamp: lit while the ramjet is armed, and flickering against that while the boost
## burns (it is that button's light).
func arm_lamp() -> bool:
	return sim.armed != (sim.boost > 0 and (Time.get_ticks_msec() / 120) % 2 == 0)


## A gate flown through: a chime, and a kick in both hands.
func power_up(kind: String) -> void:
	super(kind)
	_sound("chime")
	for side in ["left", "right"]:
		if hands.has(side):
			_buzz(hands[side], 0.8, 0.1)


## The consumables, switched where the craft is (the OPTIONS page; a test).
func set_consumables(on: bool) -> void:
	consumables = on
	sim.set_limits(on)
	print("OPTIONS: heat and energy ", "on" if on else "off")


func _track() -> String:   # "range", "gp", "eridanus", "emergency" (Eridanus on the job), "network" (or "circuit")
	if sim.kind == "network":
		return "network"
	if sim.course and not sim.job.is_empty():
		return "emergency"
	return sim.track_name if sim.course else ("range" if sim.kind == "range" else "circuit")


## A tap opens/closes the quick menu. A 1.5 second hold returns to map selection.
## Returns "quick", "menu" or ""; releasing after a hold cannot also open the quick menu.
func _menu(down: bool, delta: float) -> String:
	if down:
		_menu_held += delta
		if _menu_held >= MENU_HOLD and not _menu_fired:
			_menu_fired = true
			return "menu"
		return ""
	var tapped := _menu_held > 0.0 and not _menu_fired
	_menu_held = 0.0
	_menu_fired = false
	return "quick" if tapped else ""


## Menu inputs belong to the menu until released; held A/stick must never become flight input.
func menu_open(on: bool) -> void:
	if on == menu.open:
		return
	_a_held = 0.0
	_a_fired = false
	_y_held = 0.0
	_y_fired = false
	_b_held = 0.0
	boosting = false
	_menu_page = ""
	menu.title = "FLIGHT HOLD"
	if on:
		_seed_menu_edges()
	elif not on:
		_await_neutral_controls = true
		quest.thr_l = 0.0
		quest.thr_r = 0.0
		quest.collective = 0.0
		quest.burner = false
		quest._ramp = [0.0, 0.0]
		quest._brake = [0.0, 0.0]
		quest._grab = [{}, {}]
		quest._dif = 0.0
		quest.split = 0.0
		quest._was = [0.0, 0.0]
		quest._flick = true
		quest._flick_l = true
		edges.clear()
		_menu_held = 0.0
		_menu_fired = false
		inp = {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": false}
	super(on)


func _seed_menu_edges() -> void:
	if not hands.has("right"):
		return
	var r: XRController3D = hands.right
	var y: float = _stick(r, "primary").y
	edges["menu_up"] = y > 0.7
	edges["menu_down"] = y < -0.7
	edges["menu_a"] = _button(r, "ax_button")
	edges["menu_b"] = _button(r, "by_button")


## The main menu in the headset: the right stick steps, A changes, B closes.
func _menu_hands(_l: XRController3D, r: XRController3D) -> void:
	var y: float = _stick(r, "primary").y
	if _pressed_once("menu_up", y > 0.7):
		menu.move(-1)
		_buzz(r, 0.3, 0.03)
		_menu_show()
	if _pressed_once("menu_down", y < -0.7):
		menu.move(1)
		_buzz(r, 0.3, 0.03)
		_menu_show()
	if _pressed_once("menu_a", _button(r, "ax_button")):
		_buzz(r, 0.6, 0.05)
		menu_choose()
	if menu.open and _pressed_once("menu_b", _button(r, "by_button")):
		menu_open(false)


static func _outlook_name(rows: Array, id: String) -> String:
	for row in rows:
		if row[0] == id:
			return String(row[1]).to_upper()
	return id.to_upper()


func _menu_items() -> Array:
	if _menu_page == "options":      # the second page: the gameplay switches
		# (RACING PILOTS is here too, on the Eridanus track: it was built as an eleventh line of the first page)
		return [{"key": "consumables", "label": "HEAT AND ENERGY", "value": "ON" if consumables else "OFF"},
			{"key": "powerups", "label": "POWER-UPS", "value": "ON" if power_ups_on else "OFF"}] + _race_menu_items() + [
			# (NOSE came here from the first page, which is full at ten lines: an eleventh ran off its panel)
			{"key": "nose", "label": "NOSE", "value": "CLOSED" if CraftModelScript.nose_closed else "OPEN"},
			{"key": "back", "label": "BACK"}]
	return [{"key": "partner", "label": "DRIVING PARTNER", "value": "ON" if partner_on else "OFF"},
		{"key": "scheme", "label": "CONTROLS", "value": String(quest.scheme).to_upper()},
		{"key": "camera", "label": "CAMERA", "value": String(CAMERA_NAMES[camera])},
		{"key": "time", "label": "TIME", "value": _outlook_name(Outlook.TIMES, Outlook.time)},
		{"key": "weather", "label": "WEATHER", "value": _outlook_name(Outlook.WEATHERS, Outlook.weather)},
		{"key": "startup", "label": "COLD START", "value": "ON" if cold_start else "OFF"},
		{"key": "school", "label": "FLIGHT SCHOOL", "value": "ON" if school else "OFF"},
		{"key": "options", "label": "OPTIONS"},
		{"key": "maps", "label": "CHOOSE MAP"},
		{"key": "resume", "label": "RESUME"}]


## The quick menu's RACING PILOTS line, where there are any to have (the Eridanus track).
func _race_menu_items() -> Array:
	if not RacePilotsScript.available(sim):
		return []
	return [{"key": "racers", "label": "RACING PILOTS", "value": "ON" if race != null else "OFF"}]


## The glass carries the race, not the dash's strip.
func _race_suffix() -> String:
	return ""


func menu_choose() -> bool:
	match menu.key():
		"scheme":
			quest.next_scheme()
			_save_prefs()
			_scheme_flash = 4.0
			print("CONTROLS: ", quest.scheme)
			var at: int = menu.at
			menu.items = _menu_items()
			menu.at = at
			_menu_show()
			return true
		"camera":
			next_camera()
			var at: int = menu.at
			menu.items = _menu_items()
			menu.at = at
			_menu_show()
			return true
		"nose":
			set_nose_closed(not CraftModelScript.nose_closed)
			_save_prefs()
			var at: int = menu.at
			menu.items = _menu_items()
			menu.at = at
			_menu_show()
			return true
		"time", "weather":
			# The hour or the weather, changed where you sit (the Network's: elsewhere the choice is kept for it).
			var rows: Array = Outlook.TIMES if menu.key() == "time" else Outlook.WEATHERS
			var ids: Array = Outlook.ids(rows)
			var next: String = ids[(ids.find(Outlook.time if menu.key() == "time" else Outlook.weather) + 1) % ids.size()]
			if menu.key() == "time":
				Outlook.time = next
			else:
				Outlook.weather = next
			GameSettings.set_choice(menu.key(), next)
			Outlook.apply(self)
			print("OUTLOOK: ", Outlook.time, ", ", Outlook.weather)
			var at: int = menu.at
			menu.items = _menu_items()
			menu.at = at
			_menu_show()
			return true
		"startup":      # whether a flight chosen from the menu begins cold and dark (this one carries on as it is)
			cold_start = not cold_start
			_save_prefs()
			print("STARTUP: cold start ", "on" if cold_start else "off")
			var at: int = menu.at
			menu.items = _menu_items()
			menu.at = at
			_menu_show()
			return true
		"school":       # whether the next cold start's run-up is taught (this flight carries on as it is)
			school = not school
			_save_prefs()
			print("STARTUP: flight school ", "on" if school else "off")
			var school_at: int = menu.at
			menu.items = _menu_items()
			menu.at = school_at
			_menu_show()
			return true
		"options", "back":           # the second page, and back from it (the cursor returns to OPTIONS)
			_menu_page = "options" if menu.key() == "options" else ""
			menu.title = "OPTIONS" if _menu_page == "options" else "FLIGHT HOLD"
			menu.items = _menu_items()
			menu.at = 0
			for k in menu.items.size():
				if _menu_page == "" and String(menu.items[k].key) == "options":
					menu.at = k
			_menu_show()
			return true
		"consumables":               # the battery and the engines' heat, from this moment
			set_consumables(not consumables)
			_save_prefs()
			var at: int = menu.at
			menu.items = _menu_items()
			menu.at = at
			_menu_show()
			return true
		"powerups":                  # the gates over the road
			set_power_ups(not power_ups_on)
			_save_prefs()
			print("OPTIONS: power-ups ", "on" if power_ups_on else "off")
			var at: int = menu.at
			menu.items = _menu_items()
			menu.at = at
			_menu_show()
			return true
		"racers":      # the racing pilots, now and from now on (switched on mid-lap they start from the grid)
			set_racers(race == null, true)
			print("RACE: pilots ", "on" if race != null else "off")
			var race_at: int = menu.at
			menu.items = _menu_items()
			menu.at = race_at
			_menu_show()
			return true
		"maps":
			return_to_menu()
			return false
	return super()


# --- the start-up ---

## A control on the start panel worked: `control` "batt", "engine" or "park" flicked up (+1) or down
## (-1), or "start" pressed. -> what the sequence made of it ("" nothing, "refused", or what it did).
## The hand that did it feels a click, or the double tap of a refusal.
func startup_work(control: String, dir: int, hand: XRController3D = null) -> String:
	var mph := _kmh() / 1.609344
	var did: String = startup.press_start(mph) if control == "start" else startup.flick(control, dir, mph)
	if hand:
		if did == "refused":
			_buzz(hand, 0.4, 0.03)
			_buzz(hand, 0.4, 0.03, 0.08)
		elif did != "":
			_buzz(hand, 0.9, 0.06)
	if did != "":
		print("STARTUP: %s%s" % [did, (" (%s)" % startup.refusal) if did == "refused" else ""])
	return did


## The hand that works an engine (with crossed trigger throttles the left engine is the right hand's).
func _engine_hand(k: int) -> XRController3D:
	return hands.right if (k == 0) == (quest.scheme == "triggers") else hands.left


## ... and the engine a hand works (0 the left hand, 1 the right).
func _hand_engine(k: int) -> int:
	return 1 - k if quest.scheme == "triggers" else k


## What the sequence has to say, said: its sounds and haptics, the engines' model and voice told
## which of them are dark, turning over or straining against the brake, the panel drawn.
func _apply_startup(delta: float) -> void:
	for e: String in startup.events:
		_startup_event(e)
	startup.events.clear()
	if pad:
		pad.show_startup(startup)      # the pad's lamps, gate and ground power follow the sequence
	var held: bool = startup.held()
	for k in 2:
		var stage: String = startup.stage[k]
		craft.held[k] = stage != "catch" and stage != "run"
		craft.shown_thrust[k] = -1.0
		if stage == "catch":          # the light-off: a burst of flame, settling to a pilot light
			craft.shown_thrust[k] = 0.06 + 0.5 * startup.catch_flare(k)
		elif held:                    # the run-up: the fire follows the lever, the brake holds the craft
			craft.shown_thrust[k] = 0.05 + 0.95 * float(inp.thrL if k == 0 else inp.thrR)
		if engine_audio:
			engine_audio.off[k] = craft.held[k]
			engine_audio.crank[k] = stage == "crank"
	craft.energised = startup.charge
	craft.lights_on = startup.power > 0.5
	if engine_audio:
		engine_audio.test_stage = startup.turbine if held else 0.0
	if startup_audio:                   # the fans: heard on the battery until the engines run
		startup_audio.hum(startup.power, 0.5 * (float(startup.running(0)) + float(startup.running(1))), delta)
	var headlight: Light3D = null       # the lamp that lights the road's signs: the battery's too
	if rig:
		headlight = rig.get_node_or_null("GuideSignHeadlight") as Light3D
	if headlight:
		headlight.visible = startup.power > 0.5
	if overhead:
		overhead.show_state(startup, delta)


func _sound(sound: String, side := 0) -> void:
	if startup_audio:
		startup_audio.play(sound, side)


func _startup_event(e: String) -> void:
	match e:
		"batt_on":                   # the switch, then the contactor and the fans winding up
			_sound("toggle_on")
			_sound("power")
		"batt_off":
			_sound("toggle_off")
			_sound("down")
		"guard_open":
			_sound("guard_up")
		"guard_close":
			_sound("guard_down")
		"master_on":                 # the fuel pumps prime as the binder strikes
			_sound("toggle_on")
			_sound("pump")
			_sound("arc")
		"master_off":
			_sound("toggle_off")
		"shutdown":
			if startup_audio:
				startup_audio.stop("starter")
				startup_audio.stop("catch")
		"start", "dead":
			_sound("button")
		"refused":
			_sound("refuse")
		"park_set":
			_sound("paddle_on")
			_sound("clamp")
		"park_release":
			_sound("paddle_off")
			_sound("release")
			for side in ["left", "right"]:
				_buzz(hands[side], 0.7, 0.1)
		"selftest_done", "turbines_ok":
			_sound("chime")
		"crank0", "crank1":
			_sound("starter", int(e.right(1)))
		"light0", "light1":          # it catches: its first bark, and a kick in the hand that works it
			_sound("catch", int(e.right(1)))
			_buzz(_engine_hand(int(e.right(1))), 1.0, 0.18)
		"check":
			if startup.school:           # a lesson passed: it is told, not only felt
				_sound("chime")
			for side in ["left", "right"]:
				_buzz(hands[side], 0.3, 0.03)
		"cleared":
			print("STARTUP: cleared, %.1f s into the flight" % sim.time)
			if _coach_armed:             # a taught flight: the coach has the glass for its first minute
				_coach_armed = false
				coach.begin()
				print("COACH: on")
		"schooled":                  # every lesson passed and flown away from: the next cold start is the plain one
			school = false
			_save_prefs()
			print("STARTUP: flight school passed")


## The start-up in the hand that works engine k: it turning over, the kick as it lights, and its
## strain against the brake in the run-up.
func startup_rumble(k: int) -> float:
	match startup.stage[k]:
		"crank":
			return 0.16
		"catch":
			return 0.2 + 0.5 * startup.catch_flare(k)
	if startup.held():
		return 0.45 * smoothstep(0.1, 1.0, float(inp.thrL if k == 0 else inp.thrR))
	return 0.0


## ... and in the cockpit: a tremble of a millimetre or two (the fittings', never the view's).
func _startup_shake(delta: float) -> Vector3:
	var strain := 0.0
	if startup.held():
		strain = 0.5 * (float(inp.thrL) + float(inp.thrR))
	for k in 2:
		if startup.stage[k] == "crank":
			strain = maxf(strain, 0.14)
		elif startup.stage[k] == "catch":
			strain = maxf(strain, 0.2 + 0.5 * startup.catch_flare(k))
	_run_shake = lerpf(_run_shake, strain, 1.0 - exp(-clampf(delta, 0.0, 0.05) * 9.0))
	if _run_shake < 0.004:
		return Vector3.ZERO
	var t := Time.get_ticks_msec() * 0.001
	return Vector3(0.5 * sin(t * 61.0), sin(t * 47.0 + 1.0), 0.3 * sin(t * 53.0)) * 0.0016 * _run_shake


## The parking brake holds the air brakes out to their full extent: the flaps show it (Luke: "the
## 'park' lever should also engage the airbrakes to full extents"), every one of them: the four round
## each engine, the pod's, and the front speed brakes that otherwise only come out at speed (Luke:
## "the parking brake should engage all flaps, not just the low speed ones").
func _sync_craft(delta: float) -> void:
	if not startup.park:
		super(delta)
		return
	var shown := inp.duplicate()
	if startup.lesson() in ["right", "left", "brake"]:
		# a taught run-up's grip lessons: each engine's air brakes follow that hand's own squeeze, so the
		# pilot sees which engine a grip drags (the sim still has them all out: the brake is set)
		shown.brkL = float(startup.grips[0])
		shown.brkR = float(startup.grips[1])
	else:
		shown.brkL = 1.0
		shown.brkR = 1.0
		shown.park = true
	craft.sync(sim, shown, delta)


## What the brake needles show: full on the parking brake, the hands' own ask in flight, and in a
## taught run-up's grip lessons each hand's own squeeze.
func _shown_brakes() -> Array:
	if startup.park and startup.lesson() in ["right", "left", "brake"]:
		return [float(startup.grips[0]), float(startup.grips[1])]
	return [1.0, 1.0] if startup.park else [inp.brkL, inp.brkR]


## Where the craft is across its road, for the coach: -1 at the wall on the pilot's left .. 1 at the
## one on his right, 0 where that means nothing (off the Network, in the Aurora tube's bore, on a deck road).
func _across_road() -> float:
	if sim.kind != "network" or sim.pod.off_road:
		return 0.0
	var road: int = sim.pod.path
	var R = sim.roads[road]
	if road == int(sim.NET_PRESSURE[0]) or R.deck:
		return 0.0
	var i: int = clampi(int(sim.pod.hint), 0, int(R.N) - 1)
	var to_left: float = (sim.pod.x - R.px[i]) * R.nx[i] + (sim.pod.y - R.py[i]) * R.ny[i]        # m left of the road's middle, as its samples run
	var way: float = signf(cos(sim.pod.th) * R.tx[i] + sin(sim.pod.th) * R.ty[i])                   # (the pilot may be flying it the other way)
	return clampf(-to_left * (way if way != 0.0 else 1.0) / maxf(1.0, 0.5 * float(R.w[i])), -1.5, 1.5)


## A frame of the coach (vr/flight_coach.gd): what the craft and the hands are doing, and a chime
## and a tick in the hands when the pilot does what its line asked.
func _coach_step(delta: float, grips: Array) -> void:
	var top: bool = quest.gear < 1 or quest.gear >= QuestControlsScript.GEARS.size() - 1
	coach.step(delta, {"mph": _kmh() / 1.609344, "thr": [inp.thrL, inp.thrR], "grip": grips, "gear": quest.display_gear(), "top": top,
		"gears": quest.scheme == "triggers" and quest.gear >= 1, "rpm": quest.rpm, "edge": _across_road(), "crashed": sim.crash_t > 0.0})
	for e: String in coach.events:
		match e:
			"tip_ok":
				_sound("chime")
				for side in ["left", "right"]:
					if hands.has(side):
						_buzz(hands[side], 0.3, 0.03)
			"coached":
				print("COACH: done after %.0f s of flying (%d shifts asked for and made, %d walls steered off)" % [coach.flown, coach.shifts, coach.steers])
	coach.events.clear()


## In the run-up the engines rev to the levers: a gearbox would hold a craft that is standing still
## near idle whatever they asked.
func _engine_inp() -> Dictionary:
	if startup.held():
		return {"thrL": inp.thrL, "thrR": inp.thrR, "repair": inp.get("repair", false)}
	return super()


## The glass and the instrument strip carry the start-up's checklist while there is one; with the
## battery dead they carry nothing.
func _hud_progress(in_cockpit: bool) -> String:
	if approach_display:           # the checklist in motion on the glass ({} once the start-up has nothing to say: then nothing of it is run)
		approach_display.set_checklist(startup.display())
	if startup.power < 0.5:
		if approach_display:
			approach_display.set_message("")
		return ""
	var page: String = startup.message()
	if page != "":
		if approach_display:
			approach_display.set_message(page)
		return startup.line()
	page = coach.message()         # a taught flight's first minute: the coach's line, when it has one
	if page != "":
		if approach_display:
			approach_display.set_message(page)
		return coach.line()
	if sim.kind != "network":      # (the projector is under the roof on every course; only the Network has guidance for it,
		if approach_display:        # and Eridanus its race: the pilot's place and the gaps)
			approach_display.set_message(race.page() if race != null else "")
		return _progress_text()
	return super(in_cockpit)


## Skin the pod's nose over, or open it to its cage again: a spike option, to fly both (Luke: "I'm
## curious how it would look if we enclosed the front of the pod, now that the vehicle tilts and i
## can see apex lines"). Every pod standing in the scene changes with it, and it is remembered.
func set_nose_closed(closed: bool) -> void:
	CraftModelScript.set_nose_closed(closed, get_tree().root if is_inside_tree() else self)
	print("NOSE: ", "closed" if closed else "open")


## The panel in the cockpit: over the dash, in the middle of the view.
func _menu_show() -> void:
	if menu_panel == null:
		return
	menu_panel.visible = menu.open
	(menu_panel.get_node("words") as Label3D).text = menu.text() + "\n\nStick: select   A: change   B: resume"


## End flight and return to the headset menu; keep the nearest selectable destination.
func return_to_menu() -> void:
	menu_open(false)
	var menu_script = load("res://release/vr_menu.gd")
	menu_script.remembered_course = "network" if GP_BIOME.has(_track()) else preload("res://release/release_config.gd").course_for(_track(), spot_override)
	_save_prefs()
	get_tree().call_deferred("change_scene_to_file", "res://release/vr_menu.tscn")


func switch_track() -> void:
	var to := next_track(_track())
	print("TRACK: switching %s -> %s" % [_track(), to])
	var o := overrides_for(to)
	track_override = o[0]
	job_override = o[1]   # "none" on the free stops: a -Job emergency launch's --job mustn't follow you round
	spot_override = ""
	get_tree().call_deferred("reload_current_scene")


## A cycle stop's [track_override, job_override]: the emergency run is Eridanus on the job.
static func overrides_for(to: String) -> Array:
	return ["eridanus", "emergency"] if to == "emergency" else [to, "none"]


## The legacy diagnostic cycle: range -> grand prix -> Eridanus -> the emergency run (Eridanus on the
## job) -> the Network -> range (a plain circuit goes to the range).
static func next_track(cur: String) -> String:
	if GP_BIOME.has(cur):
		return "network"   # a city's GP: back to the Network (at that city)
	var order := ["range", "gp", "eridanus", "emergency", "network"]
	return order[(order.find(cur) + 1) % order.size()]


## Visual lean only. Preserve physical steering and the road's full corkscrew
## frame. A damped spring limits both roll speed and acceleration: reversing a
## brake must decelerate the old lean before rolling the other way.
func _ease_cockpit_roll(raw_roll: float, delta: float) -> float:
	var target := clampf(raw_roll / CraftModelScript.ROLL_MAX, -1.0, 1.0) * COCKPIT_ROLL_MAX
	var remaining := clampf(delta, 0.0, 0.05)
	while remaining > 0.000001:
		var step := minf(remaining, 1.0 / 240.0)
		var accel := clampf(36.0 * (target - _comfort_roll) - 12.0 * _comfort_roll_rate,
			-COCKPIT_ROLL_ACCEL, COCKPIT_ROLL_ACCEL)
		_comfort_roll_rate = clampf(_comfort_roll_rate + accel * step, -COCKPIT_ROLL_RATE, COCKPIT_ROLL_RATE)
		_comfort_roll = clampf(_comfort_roll + _comfort_roll_rate * step, -COCKPIT_ROLL_MAX, COCKPIT_ROLL_MAX)
		remaining -= step
	return _comfort_roll


## The cornering load now, g, + in a left turn: the engines' turn rate times the speed along their
## heading (the sim's own measure of a loaded turn).
func turn_load() -> float:
	var along: float = sim.pod.vx * cos(sim.pair_th) + sim.pod.vy * sin(sim.pair_th)
	return (sim.eL.w + sim.eR.w) * 0.5 * maxf(0.0, along) / 9.81


## Read the load on the pilot for the g-meter (once a frame: g_along, g_across, g_turn, g_seat).
func _read_g() -> void:
	var p = sim.pod
	var dt: float = sim.time - float(_g_from[2])
	if float(_g_from[2]) >= 0.0 and dt > 0.0 and dt < 0.25:
		var ax: float = (p.vx - float(_g_from[0])) / dt / 9.81
		var ay: float = (p.vy - float(_g_from[1])) / dt / 9.81
		var along: float = cos(p.th) * ax + sin(p.th) * ay
		var across: float = -sin(p.th) * ax + cos(p.th) * ay
		if sim.crash_t > 0.0 or absf(along) > G_NOT_A_LOAD or absf(across) > G_NOT_A_LOAD:
			along = 0.0
			across = 0.0
			g_along = 0.0          # (and what went before it is no part of what comes after)
			g_across = 0.0
			g_turn = 0.0
			g_seat = p.grip
		var turn := across
		if sim.kind == "network" and not p.off_road and sim.roads[p.path].shaft:
			turn -= sim.roads[p.path].kap[p.hint] * (p.vx * p.vx + p.vy * p.vy) / 9.81
		var k := 1.0 - exp(-dt / G_TAU)
		g_along += (along - g_along) * k
		g_across += (across - g_across) * k
		g_turn += (turn - g_turn) * k
		g_seat += (float(p.grip) - g_seat) * k      # (smoothed with the rest: a hop over a crest is not a flicker of the needle)
	elif dt != 0.0:                # the first reading, a new sim, a long pause: nothing to go on
		g_along = 0.0
		g_across = 0.0
		g_turn = 0.0
		g_seat = p.grip
	_g_from = [p.vx, p.vy, sim.time]


## The whole load on the pilot, g: the seat's 1 g while the craft rides its hover (none of it once
## she is off the ground), with what the engines, the air brakes and a turn put across that.
func g_load() -> float:
	return sqrt(g_seat * g_seat + g_along * g_along + g_across * g_across)


## The map's switch (Luke, flying the fourteenth: "a switch like the other 2, that switches from 'local'
## to 'global' map"): the whole country north up, or the roads round the craft heading up. Remembered.
func set_map_whole(on: bool) -> void:
	map_whole = on
	_save_prefs()
	print("MAP: ", "global" if on else "local")


## The map's colour button: scheme k of MinimapPanel.SCHEMES (it wraps), and remember it.
func set_map_scheme(k: int) -> void:
	map_scheme = posmod(k, MinimapPanelScript.SCHEMES.size())
	if minimap_panel:
		minimap_panel.set_scheme(map_scheme)
	_save_prefs()
	print("MAP: colours ", MinimapPanelScript.SCHEMES[map_scheme].name)


## Turn the slide on or off (the SLIDE / GRIP switch), and remember it.
func set_slide(on: bool) -> void:
	slide_feel = on
	_save_prefs()
	print("SLIDE: ", "on" if on else "off")


## The slide's angle now, radians, + = the nose further left (a left turn): toward what the
## cornering load asks for, on a spring (see SLIDE_MAX).
func _ease_slide(delta: float) -> float:
	_slide_load += (turn_load() - _slide_load) * (1.0 - exp(-clampf(delta, 0.0, 0.05) / SLIDE_LOAD_T))
	var asked := signf(_slide_load) * smoothstep(SLIDE_LOAD.x, SLIDE_LOAD.y, absf(_slide_load))
	var target := asked * SLIDE_MAX if slide_feel else 0.0
	var w := TAU * SLIDE_HZ
	var remaining := clampf(delta, 0.0, 0.05)
	while remaining > 0.000001:
		var step := minf(remaining, 1.0 / 240.0)
		_slide_rate = clampf(_slide_rate + (w * w * (target - _slide) - 2.0 * SLIDE_ZETA * w * _slide_rate) * step, -SLIDE_RATE, SLIDE_RATE)
		_slide = clampf(_slide + _slide_rate * step, -SLIDE_MAX * 1.25, SLIDE_MAX * 1.25)
		remaining -= step
	return _slide


## How hard the slide scrubs in a hand, 0..1: mostly while the rear is moving, a little while it is
## held out, more in the hand on the outside of the turn.
func slide_scrub(right_hand: bool) -> float:
	var moving := clampf(absf(_slide_rate) / deg_to_rad(30.0), 0.0, 1.0)
	var held := clampf(absf(_slide) / SLIDE_MAX, 0.0, 1.0)
	var outside := (_slide > 0.0) == right_hand    # a left turn swings the seat right
	return clampf(0.8 * moving + 0.2 * held, 0.0, 1.0) * smoothstep(0.08, 0.3, held) * (1.0 if outside else 0.55)


func _place_camera(_k: float) -> void:
	# The cockpit lists with the pod, rolled about your head rather than the floor: the view
	# tilts but your eyes don't swing sideways (a floor pivot moves them ~0.9 m at 60 deg).
	var yaw: float = sim.pod.th - PI / 2.0
	var b_yaw := Basis(Vector3.UP, yaw)
	# the ride over the banking, smoothed (CraftModel.ride: Luke, "going over hills makes the camera very shaky")
	var r := CraftModelScript.ride(self, sim, _ride, get_process_delta_time())
	var roll := _ease_cockpit_roll(craft.bank[2] + r.z, get_process_delta_time())
	var pitch := r.y   # up and down the banking
	var head := EYE + cam.position   # the seated head, whichever camera is up: the cockpit rolls about it
	if sim.pod.path > 0 and sim.kind != "network":
		# the shade line: the cockpit worked out flat, then carried onto the twisted road, where the
		# corkscrews roll it right over (CraftModel.onto_road: past 90 deg, upside down under the canopy)
		var b_flat := Basis.from_euler(Vector3(0.0, yaw, roll))
		var floor_flat := Vector3(sim.pod.x - org_x, sim.pod.z - 0.8 + CraftModelScript.POD_LIFT, -(sim.pod.y - org_y))
		rig.transform = CraftModelScript.onto_road(sim, Transform3D(b_flat, floor_flat + b_yaw * head - b_flat * head), floor_flat,
			_ride.roll, pitch, org_x, org_y)
		# (on the corkscrews there is no level to hold: an outside camera rides the rig, turned over with it)
		origin.transform = Transform3D(Basis.IDENTITY, EYE + (CAMERA_OFFSETS.get(camera, Vector3.ZERO) as Vector3))
		if chase_hud:
			chase_hud.visible = camera != "cockpit"
	else:
		var Q := shaft_carry_at(sim.pod.x, sim.pod.y)   # (identity but up a shaft: there the world turns over round you)
		var slide := _ease_slide(get_process_delta_time())   # the rear stepped out: the cockpit turned further into the turn ...
		var b_slid := Basis(Vector3.UP, yaw + slide)
		var b_full: Basis = Q * Basis.from_euler(Vector3(pitch, yaw + slide, roll))   # lean + the track's banking (capped), and its slope
		var base := wz(sim.pod.x, sim.pod.y, sim.pod.z - 0.8 + CraftModelScript.POD_LIFT) + Q * Vector3.UP * (r.x - surface(sim.pod.x, sim.pod.y).x)   # floor 0.8 m below the pod body centre, lifted with the pod
		var hitch := head + Vector3(0.0, 0.0, -SLIDE_ARM)    # ... about a point ahead of you, so the seat swings outward
		rig.basis = b_full
		var seat_at: Vector3 = Q * (b_yaw * hitch + b_slid * (head - hitch))      # from the floor to the head, the cockpit level
		var outside: Basis = Q * b_yaw                        # (an outside camera keeps the sim's heading, and watches the tail go)
		if sim.kind == "network" and not sim.pod.off_road and sim.roads[sim.pod.path].deck:
			# Mount Hyperion's road: the cockpit pitches with the deck about its floor, not about the pilot's head
			# (a head held straight over the floor's place is in an 88 degree wall, not 2.7 m off it), and an
			# outside camera rides the deck's own slope (level, it stood in the mountain on the wall down)
			seat_at = seat_at.rotated(((Q * b_slid) as Basis).x.normalized(), pitch)
			outside = Q * Basis.from_euler(Vector3(pitch, yaw, 0.0))
		rig.position = base + seat_at - b_full * head
		_place_origin(outside, base)
	var thr := [inp.thrL, inp.thrR]
	for k in 2:
		lever_pivots[k].rotation.x = deg_to_rad(lerpf(30.0, -30.0, thr[k]))
		if not brake_paddles.is_empty():
			var brake: float = inp.brkL if k == 0 else inp.brkR
			brake_paddles[k].rotation.x = deg_to_rad(-18.0) * clampf(brake, 0.0, 1.0)
		lever_tips[k].albedo_color = Color(1.0, 0.55, 0.15) if thr[k] >= sim.P.gate else Color(0.16, 0.17, 0.19)


func _process(delta: float) -> void:
	var t_in := Time.get_ticks_usec()
	super(delta)
	if menu.open:
		return   # OpenXR still updates the tracked camera and controllers while flight waits.
	if _brake_trace:
		_brake_trace.capture(self, delta)
	_apply_shudder(delta)
	interior.set_power(startup.power)
	interior.set_mode(sim.mode, sim.hblend)
	# In pursuit the patrol's lights wash the cabin: the rim light takes the lamp that is lit.
	var wash: float = 1.0 if pursuing() else patrol_wash()      # the craft's own lamps, or a patrol's close behind
	if wash > 0.0:
		var lamp := LightBarScript.showing(Time.get_ticks_msec() / 1000.0)
		var dark := Color(0.05, 0.06, 0.08)
		interior.rim_mat.albedo_color = dark.lerp([dark, Color(1.0, 0.12, 0.08), Color(0.12, 0.35, 1.0)][lamp], wash)
		_rim_flashing = true
	elif _rim_flashing:
		_rim_flashing = false
		interior._mode = ""                # (its own colour again, at the next set_mode)
	# An untracked hand (flat runs, before the first pose) sits at the origin, i.e. on the eye: its
	# box's far face, 5 cm out on the near plane, z-fought into a dark rectangle mid-view.
	for side in hands:
		hands[side].get_child(0).visible = hands[side].get_has_tracking_data()
	CanopyScript.update(canopy, sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy), sim.hblend, sim.mode, delta)
	if mode_switch:
		mode_switch.power = startup.power
		mode_switch.show_state(handling_ask == "starfighter", sim.hblend, handling_ask == "starfighter" and sim.hblend == 0.0)
	if slide_switch:
		slide_switch.power = startup.power
		slide_switch.show_state(not slide_feel, 0.0 if slide_feel else 1.0, false)
	# Crash: fade to black, respawn happens in the dark, fade back up.
	var target := 1.0 if sim.crash_t > 0.0 else 0.0
	fade_v = move_toward(fade_v, target, delta * 4.0)
	fade_mat.albedo_color = Color(0, 0, 0, fade_v)
	if dawn and dawn.burn > 0.0:   # caught by the dawn: burn to white instead
		fade_mat.albedo_color = Color(1.0, 0.97, 0.9, dawn.burn)
	frame_ms.append(delta * 1000.0)
	_w_cpu.append((Time.get_ticks_usec() - t_in) / 1000.0)
	var vp := get_viewport().get_viewport_rid()
	_w_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	var parts := {"sim": cpu.sim, "world": cpu.world, "hud": cpu.hud, "rcpu": RenderingServer.viewport_get_measured_render_time_cpu(vp),
		"stream": network_world.sync_ms if network_world else 0.0, "traffic": traffic_net.update_ms if traffic_net else 0.0}
	for k in parts:
		_w_sum[k] = _w_sum.get(k, 0.0) + parts[k]
	var yaw: float = (sim.eL.w + sim.eR.w) / 2.0
	var spd: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
	var gear_shown: int = quest.display_gear()
	wag.add(delta, yaw, spd, gear_shown)
	wag_all.add(delta, yaw, spd, gear_shown)
	report_t += delta
	if report_t >= 10.0:
		_report()
		report_t = 0.0


func _report() -> void:
	var n := frame_ms.size()
	if n == 0:
		return
	var recent := frame_ms.slice(maxi(0, n - 900))
	var sorted := recent.duplicate()
	sorted.sort()
	# The budget is the rate the headset really runs at: Link refuses the 90 Hz ask above and paces
	# at the Link app's setting (72 Hz on 2026-10-19), and a fixed 90 Hz line counted every paced
	# frame as a miss. 4% over the frame time is a miss, as 11.6 ms was at 90 Hz.
	var hz := 0.0
	if xr != null and xr.is_initialized() and "display_refresh_rate" in xr:
		hz = float(xr.get("display_refresh_rate"))
	var hz_src := "headset"
	if hz <= 0.0:
		hz = 90.0
		hz_src = "assumed"
	var budget := 1044.0 / hz
	var total := 0.0
	var slow := 0
	for v in recent:
		total += v
		if v > budget:
			slow += 1
	print("FRAMES: %.1f fps avg, p95 %.2f ms, %.1f%% over %.1f ms (%.0f Hz budget, %s), %d frames total" % [
		1000.0 * recent.size() / total, sorted[int(sorted.size() * 0.95)], 100.0 * slow / recent.size(),
		budget, hz, hz_src, n])
	_report_cpu()
	if wag.t > 0.0:
		print(wag.report())
	wag.reset()


## Where the frame went since the last report: the main thread's work (avg, p95; by part) and the
## renderer's CPU and GPU time. (On the Network: where you are, the traffic, the chunks.)
func _report_cpu() -> void:
	var m := _w_cpu.size()
	if m == 0:
		return
	var c := _w_cpu.duplicate()
	c.sort()
	var g := _w_gpu.duplicate()
	g.sort()
	var avg := {}
	for k in _w_sum:
		avg[k] = _w_sum[k] / m
	var tot := 0.0
	for x in _w_cpu:
		tot += x
	var gt := 0.0
	for x in _w_gpu:
		gt += x
	var at := ""
	if sim.kind == "network":
		at = " | %s mile %.0f, %d cars, %d chunks" % [sim.roads[sim.pod.path].name, sim.pod.hint * 24.0 / 1609.344,
			traffic_net.cars.size() if traffic_net else 0, network_world.chunks.size() if network_world else 0]
	print("CPU: process avg %.2f p95 %.2f ms (sim %.2f, world %.2f: stream %.2f traffic %.2f; hud %.2f) | render cpu %.2f, gpu avg %.2f p95 %.2f ms%s" % [
		tot / m, c[int(m * 0.95)], avg.sim, avg.world, avg.stream, avg.traffic, avg.hud, avg.rcpu, gt / m, g[int(m * 0.95)], at])
	_w_cpu.clear()
	_w_gpu.clear()
	_w_sum.clear()


func _update_hud() -> void:
	var progress := _hud_progress(true)
	_update_skill_readout()
	var kmh := _kmh()
	_turbines = EngineAudio.turbines_at(kmh / 1.609344 / sim.line_speed(), _turbines)   # (by the air's speed, as the engines' voices are)
	# the run-up's turbine test lights the same lamp once they are at their test speed
	_turbine_lamp = startup.held() and (startup.turbine >= 0.97 or (_turbine_lamp and startup.turbine > 0.6))
	var map_live: bool = (sim.kind == "circuit" or sim.kind == "network") and startup.power > 0.5
	if minimap_panel.live != map_live:
		minimap_panel.set_live(map_live)
	_scheme_flash = maxf(0.0, _scheme_flash - get_process_delta_time())
	var ctl: String = QuestControlsScript.HINTS[quest.scheme] if _scheme_flash > 0.0 else QuestControlsScript.NAMES[quest.scheme]
	minimap.whole = map_whole
	if minimap_panel.scheme != map_scheme:      # (the saved choice is read after the cabin is built)
		minimap_panel.set_scheme(map_scheme, false)
	minimap_panel.show_controls(not map_whole, startup.power)
	if minimap_panel.live:
		minimap_panel.show_frame(minimap.update(sim.pod.th, get_process_delta_time()))
	if tow_meter:
		tow_meter.set_shader_parameter("loads", Vector2(craft.cable_strain[0], craft.cable_strain[1]))
	_read_g()
	dashboard.show_state({
		"mph": kmh / 1.609344, "kmh": kmh, "mach": cues.mach, "backlight": lerpf(1.0, 0.5, maxf(1.0 if light_preset == "twilight" else 0.0, Outlook.darkness())), "mach_line": cues.readout() + boost_text(), "progress": progress,
		"footer": "%s   /   %s" % [handling_text(), ctl],
		"points": int(_skill_shown.get("points", 0)) if _skill_on else 0, "feat": String(_skill_shown.get("award", "")) if _skill_on else "", "feat_age": float(_skill_shown.get("age", 1e9)),
		"thr": [inp.thrL * startup.engine_k(0), inp.thrR * startup.engine_k(1)],
		"brk": _shown_brakes(), "heat": [sim.eL.heat, sim.eR.heat],
		"health": [sim.eL.health, sim.eR.health],
		"flameout": [sim.eL.flameout, sim.eR.flameout], "battery": sim.battery,
		"burner": sim.mode == "burner", "armed": arm_lamp(), "ramjet": sim.mode == "ramjet", "turbines": _turbines or _turbine_lamp,
		"power": startup.power, "sweep": startup.selftest / StartupScript.SELFTEST_S if startup.selftest >= 0.0 else -1.0,
		"gear": quest.display_gear(), "overdrive": bool(inp.get("gearOverdrive", false)),
		"g": g_load(), "g_side": g_turn,
		"steps": startup.display(),      # the checklist's rail on the status strip, as the glass has it
		"blink": (Time.get_ticks_msec() / 250) % 2 == 0,
	})
	if screen_reflection:      # in the terminal's hall and before dawn the glass needs less to show
		screen_reflection.set_dark(maxf(terminal_lighting.enclosure if terminal_lighting else 0.0, 0.7 * maxf(1.0 if light_preset == "twilight" else 0.0, Outlook.darkness())))
	if chase_hud and chase_hud.visible:
		var guide: String = approach_display.message if approach_display else ""   # (what the projector over the nose is showing)
		var lit: String = {"ramjet": "RAMJET", "burner": "AFTERBURNER"}.get(sim.mode, "RAMJET ARMED" if sim.armed else "")
		chase_hud.text = "%s MPH\n%s%s%s" % [_thousands(roundi(kmh / 1.609344)), cues.readout(), (("   " + lit) if lit != "" else "") + boost_text(),
			("\n\n" + guide) if guide != "" else ""]


static func _thousands(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


func _update_skill_readout() -> void:
	if not _skill_readout:
		_skill_readout = Label3D.new()
		_skill_readout.name = "SkillReadout"
		_skill_award = Label3D.new()
		_skill_award.name = "SkillAward"
		for label in [_skill_readout, _skill_award]:
			label.font_size = 40
			label.pixel_size = 0.0021
			label.outline_size = 7
			label.outline_render_priority = 1
			label.render_priority = 2
			label.outline_modulate = Color(0.015, 0.025, 0.03, 0.95)
			label.double_sided = false
			label.no_depth_test = true
			cam.add_child(label)
	if skill_score:
		var display := _skill_display.update(skill_score)
		_skill_shown = display
		var weight: float = display.emphasis
		# Leave the centre of the windscreen free while the projector is deployed.
		var guidance_visible := approach_display != null and approach_display.panel.visible
		var active_x := 1.25 if guidance_visible else 0.0
		_skill_readout.position = Vector3(1.25, 0.92, -2.0).lerp(Vector3(active_x, 0.96, -2.0), weight)
		_skill_award.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if guidance_visible else HORIZONTAL_ALIGNMENT_CENTER
		_skill_award.position = Vector3(0.98 if guidance_visible else 0.0, 0.81, -2.0)
		_skill_award.scale = Vector3.ONE * (0.58 if guidance_visible else 0.82)
		_skill_readout.scale = Vector3.ONE * lerpf(0.7, 1.15, weight)
		_skill_readout.text = display.total
		_skill_readout.modulate = Color(0.65, 0.96, 0.9, lerpf(0.52, 1.0, weight))
		_skill_readout.outline_modulate.a = lerpf(0.52, 0.95, weight)
		_skill_award.text = display.award
		_skill_award.modulate = Color(0.65, 0.96, 0.9, weight)
		_skill_award.outline_modulate.a = 0.95 * weight
	# In the seat the gauge cluster's own counter and the strip beside it carry these (Luke: "points on
	# an odometer roller, with a digital readout next to it of the feat"). They float by the view only
	# outside, where the gauges are out of reading distance, and over the flat panel, which has neither.
	var floating: bool = _skill_on and (camera != "cockpit" or not dashboard.has_method("roll"))
	_skill_readout.visible = floating
	_skill_award.visible = floating


func _set_skill_visible(on: bool) -> void:
	super(on)
	_skill_on = on            # (_update_skill_readout shows them, or leaves them to the cluster)
	if _skill_readout and not on:
		_skill_readout.visible = false
		_skill_award.visible = false


func _exit_tree() -> void:
	if _brake_trace:
		_brake_trace.close()
	super()
	_report()
	if wag_all.t > 0.0:
		print(wag_all.report().replace("WAG:", "WAG (the whole flight):"))
	var path := "user://frames_%s.csv" % Time.get_datetime_string_from_system().replace(":", "-")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_line("frame,ms")
		for i in frame_ms.size():
			f.store_line("%d,%.3f" % [i, frame_ms[i]])
		print("FRAMES: csv ", ProjectSettings.globalize_path(path))
