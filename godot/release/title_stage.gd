## The title: the place the menus stand in (Luke, 2026-11-22, with a box-cover picture: "work on a
## title screen using this as a reference"). The cover, built from the game's own things and stood up
## round the menu: PHAETHON in solid letters over a desert of mesas at sunset, bands of cloud, a far
## city; a wide dark road with a red-and-white kerb, a road on pillars ending in a launch lip on the
## left, a shaft standing up on the right; and two craft with their engines toward you, idling: the
## Phaethon in the cover's navy and orange-red on SPEEDCRAFT's blue links, the Shrike RS in its own
## teal and ivory on STARFIGHTER's magenta. Nothing here is the cover's picture: every part is a mesh
## the game makes, lit by the game's sky.
## Two layouts of the one scene:
##   "vr"    the headset's menu: the pilot stands on a starter's stand in the middle of the road, the
##           menu board in front of him, the word over it and a craft on either hand, nose in
##   "flat"  the desktop menu: one fixed camera between the two craft, composed as the cover is
## And a turntable (Luke, 2026-11-23: "when you choose a vehicle, it rotates in front of the player"): a
## round deck on the apron carrying the pilot craft the menus have chosen, in the paint the next flight
## will wear, turning a full turn in half a minute, its name on a sign behind it. While a craft is being
## chosen (a row or button that changes it has the highlight a moment) it rises out of the road and the
## craft comes down onto it, swung round fast, then settling to the slow turn; a craft chosen then comes
## down the same way. The rest of the time it is put away under the road and the title is as it was. In
## the headset it stands straight ahead, behind the menu board, which swings aside for it
## (release/vr_menu.gd); on the desktop it stands beside the cover's picture and the camera turns to it
## (release/menu.gd).
## The menu board and camera are ready immediately. The stage assembles behind them over several frames.
## Leaving the menu frees the stage, including an unfinished build.
##   var stage := TitleStage.make("vr"); add_child(stage)      null with `enabled` off (timings, tests), or the game
##                                    started with -- --no-title: the menus are then exactly as they were
##   stage.place(eye, forward)        VR: stand it under the pilot's eye, facing the way he faces
##   stage.frame(art, window)         flat: aim the camera so the picture's middle is that part of the window's
##   stage.show_craft(id)             put that pilot craft on the turntable (built over the next frames)
##   stage.attend(on)                 a craft is being chosen: bring the turntable up (flat: and turn the camera to it), or put it away
extends Node3D

const Letters := preload("res://release/title_letters.gd")
const SimScript := preload("res://sim/craft_sim.gd")
const ModelScript := preload("res://view/craft_model.gd")
const Kit := preload("res://view/mesh_kit.gd")
const Livery := preload("res://view/livery.gd")
const Accent := preload("res://view/accent.gd")
const Shrike := preload("res://view/shrike_airframe.gd")
const Outlook := preload("res://view/outlook.gd")
const Shaft := preload("res://view/network_shaft.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Fleet := preload("res://view/fleet_airframe.gd")
const Settings := preload("res://release/game_settings.gd")
const Chase := preload("res://view/network_chase.gd")

const EYE := 1.6                 # the pilot's eye over the stand's deck, m: what the scene is laid out round
const STAND_H := 2.0             # the stand's deck over the road (from it the craft's painted tops show, as on the cover)
const STAND := Vector2(3.4, 3.8) # the deck's half-width, and how far it runs ahead of the pilot (it runs 3 m behind)
const WORD := "PHAETHON"
const STRAP := "TWIN-THROTTLE RACING"
# the hour: the cover's sunset. The sun is low on the left: just clear of the menu board's edge in the headset,
# and where the cover has it for the desktop's camera.
const SUN_AZ := {"vr": -31.0, "flat": -14.0}      # degrees right of straight ahead
const SUN_EL := 2.6              # ... and up: its disc in the sky
const SUN_LIGHT_EL := 8.0        # ... and the height its light comes from (a sun on the horizon lights nothing's top)
const ZENITH := Color(0.08, 0.44, 0.56)      # (lighter than it looks: the sky mixes it with the horizon's orange in light, not in paint)
const HORIZON := Color(0.86, 0.50, 0.33)      # (duller than the cover's: its orange is the suns' glow on this; a redder horizon turns the whole sky mauve)
const LAND := Color(0.36, 0.17, 0.10)
const CLOUD_BASE := 4200.0
const CLOUD_DRIFT := Vector2(9.0, 3.5)     # m/s: the deck's slide over the land
const ASPHALT_PERIOD := 64000.0
const KERB_RED := Color(0.80, 0.10, 0.06)
const KERB_WHITE := Color(0.93, 0.92, 0.87)
const CONCRETE := Color(0.50, 0.50, 0.49)
const TARMAC := Color(0.085, 0.085, 0.09)
const AMBER := Color(1.0, 0.62, 0.08)
const VR_BERTHS := [[-57.0, 11.5], [57.0, 12.0]]      # the headset: where each craft's noses come to, [degrees right of ahead, m from the pilot]: clear of the board's edges (28 degrees)
const FLAT_EYE := Vector3(0.0, 7.2, 0.0)      # the desktop's camera, over the road: high enough that the engines' painted tops run up the picture, as the cover's do
const FLAT_PITCH := 7.5          # ... looking this far down, degrees: the horizon two fifths of the way down the picture
const FLAT_ACROSS := 100.0       # ... through this wide a lens across the picture (the cover's is an illustrator's: wider still)
const FLAT_BERTHS := [Vector3(-4.9, 0.0, -8.0), Vector3(5.5, 0.0, -9.6)]      # ... and where the two craft's noses come to in front of it
const IDLE := 0.34               # the craft's levers: enough to spin the fans, light the links and stand a flame in each pipe
const BOB := 0.035               # m: how far a hovering craft rides up and down
const BOARD_FIRST_USEC := 50000  # Give the first menu frame and immediate input priority over any preview file reads.
# the turntable
const SHOW_AT := {"vr": Vector3(0.0, 0.0, -26.5), "flat": Vector3(40.0, 0.0, 8.0)}      # its middle: the headset's straight ahead, behind the board; the desktop's beside the cover's picture, out of it
const SHOW_R := 16.2             # the deck's radius, m: the longest craft (the Orrery's 17 m tow) reaches 15.5 m from its middle
const SHOW_H := 0.32             # the deck's top over the road
const SHOW_SINK := 0.5           # put away, it lies this far down: under the road, out of sight (the title is then as it was)
const SHOW_UP_S := 0.9           # s to bring it up (the deck rises, then the craft comes down onto it) ...
const SHOW_DOWN_S := 0.6         # ... and to put it away
const SHOW_SPIN := 12.0          # degrees a second: a turn in half a minute
const SHOW_WHIP := 240.0         # ... a craft just chosen comes round this much faster than that ...
const SHOW_WHIP_S := 1.2         # ... settling to the slow turn over this long, s
const SHOW_DROP := 2.6           # m: ... and comes down onto the deck from this high ...
const SHOW_DROP_S := 0.7         # ... over this long
const SHOW_KEEP := 4             # craft already built kept (hidden) for going back to: each is its own meshes
const SHOW_EYE := Vector3(6.7, 11.0, 1.3)      # the desktop's camera when it has turned to the turntable (34 m off it, 11 up) ...
const SHOW_LOOK := 2.0           # ... looking at this height over its middle ...
const SHOW_ACROSS := 60.0        # ... through this wide a lens across the picture: the longest craft's reach is at most 27 degrees off its middle from there, however it is turned
const SHOW_TURN_S := 0.8         # ... turning there (and back) over this long
const PLATE_SIZE := {"vr": 2.4, "flat": 1.7}      # the name sign behind the turntable: read from 48 m in the headset, 47 m on the desktop

static var enabled := true       # (timings and tests: off, the menus are as they were before the title)
static var _display_bodies := {} # port and starboard Phaethon fairings in the box-cover paint
static var _show_bodies := {}    # ... and the turntable's, in each paint it has shown ("ember/-1", ...): built once, not on every menu entry
const CLOUD_COVER := "res://art/sky/cloud_cover.png"

var layout := "vr"
var sun_az := -31.0              # SUN_AZ for this layout
var world: Node3D                # all that stands on the land: its origin is on the road under the pilot
var environment: WorldEnvironment
var sky_material: ShaderMaterial
var sun: DirectionalLight3D
var clouds: MeshInstance3D
var letters: MeshInstance3D
var word: Node3D                 # the letters' place: scaled to their cap height, turned and leaned
var craft: Array = []            # each {holder, model, sim, berth, inp, phase, rest, owed (s since its parts were last posed)}
var stand: MeshInstance3D        # (the headset's layout only)
var camera: Camera3D             # (the desktop's layout only)
var turntable_base: Node3D       # the turntable: its fixed ring, the deck and the name sign (sunk out of sight when put away)
var turntable: Node3D            # ... its deck, which turns and carries the craft on show
var plate: Node3D                # ... its name sign, behind it, facing whoever looks at it
var reveal := 0.0                # 0 put away, 1 up with the craft on it (and between, coming or going)
var showcase := {}               # the craft on show: an entry as `craft`'s are, with its "key" (vehicle/livery)
var show_vehicle := ""           # what the turntable is to hold (the menus' pilot craft) ...
var show_livery := ""            # ... in this paint
var attention := 0.0             # the desktop: 0 the cover's view, 1 the camera turned to the turntable
var attend_wanted := false
signal build_frame

var build_ms := 0                # wall time from menu entry to the full, animated scene
var build_split := {}            # longest uninterrupted assembly work and number of frames
var art_ready := false
var _entry_usec := 0
var _board_draw_pending := true
var _flight_livery := ""
var _slice_name := "sky"
var _building_vehicle := ""
var _loading_path := ""
var _sources := {}               # keep the threaded reads available to the normal model builders for this menu only
var _clock := 0.0
var _frame := 0
var _shrike_was_loaded := false
var _accents_before := {}
var _globals_at := Basis.IDENTITY
var _show_cache := {}            # key -> a built entry (hidden unless on show)
var _show_order := []            # ... the keys, the longest unused first
var _show_job := ""              # the key being built ("" when none)
var _whip := 0.0                 # 1 when a craft has just come on show, falling to 0
var _drop := 0.0                 # ... the same, for its coming down onto the deck
var _frame_art := Rect2()        # the desktop: the window's part the picture is composed in ...
var _frame_window := Vector2.ZERO
var _frame_across := 100.0       # ... and its lens there


## What the craft model asks of the view it is built in: a material, and where a place in its sim is.
class Berth extends RefCounted:
	var sim
	var ox := 0.0
	var oy := 0.0

	func _mat(c: Color, unshaded := false) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if unshaded:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		return m

	func wz(x: float, y: float, z: float) -> Vector3:
		return Vector3(x - ox, z, -(y - oy))

	func surface(_x: float, _y: float) -> Vector2:
		return Vector2.ZERO


static func make(for_layout: String) -> Node3D:
	if not enabled or "--no-title" in OS.get_cmdline_user_args():
		return null
	var stage: Node3D = load("res://release/title_stage.gd").new()
	stage.build(for_layout)
	return stage


func build(for_layout: String) -> void:
	_entry_usec = Time.get_ticks_usec()
	layout = for_layout
	sun_az = SUN_AZ[layout]
	name = "TitleStage"
	_shrike_was_loaded = not Shrike.meshes.is_empty()
	for key in Accent._made:
		_accents_before[key] = true
	world = Node3D.new()
	world.name = "world"
	world.position.y = -STAND_H if layout == "vr" else 0.0
	add_child(world)
	if layout == "flat":
		camera = Camera3D.new()
		camera.name = "TitleCamera"
		camera.position = FLAT_EYE
		camera.rotation_degrees = Vector3(-FLAT_PITCH, 0.0, 0.0)
		camera.near = 0.1
		camera.far = 200000.0
		camera.fov = 70.0
		add_child(camera)
	build_split = {"frames": 0, "max_slice_ms": 0.0, "slowest": "", "work_ms": 0.0, "by_part": {}}
	_assemble()


func _assemble() -> void:
	# This signal belongs to the stage. An early launch frees pending work with the menu.
	await build_frame
	await _retain_source(CLOUD_COVER)
	_slice_name = "sky"
	_build_sky()
	await build_frame
	_slice_name = "title and stand"
	if layout == "vr":
		_build_word(Vector3(0.0, EYE + 78.0 * tan(deg_to_rad(17.3)), -78.0), 11.5, Vector3(0.10, deg_to_rad(22.0), deg_to_rad(7.0)))
		_build_stand()
	else:
		_build_word(FLAT_EYE + Vector3(9.4, 15.3, -43.5), 10.0, Vector3(0.15, deg_to_rad(20.7), deg_to_rad(11.6)))
	await build_frame
	_slice_name = "roads"
	_build_roads()
	await build_frame
	_slice_name = "land and skyline"
	_build_land()
	_build_skyline()
	await build_frame
	_slice_name = "structures"
	_build_structures()
	for i in 2:
		await build_frame
		if i == 0:
			await _retain_source(ModelScript.CanopyScript.ROOF)
			await _retain_source("res://art/engine/nacelle.glb")
		else:
			await _retain_source("res://art/shrike/bodywork.glb")
			await _retain_source("res://art/shrike/enamel.tres")
			await _retain_source("res://art/cockpit/shrike_coaming.webp")
		var az := deg_to_rad(float(VR_BERTHS[i][0])) if layout == "vr" else 0.0
		var nose: Vector3 = _radial(VR_BERTHS[i][0], VR_BERTHS[i][1]) if layout == "vr" else FLAT_BERTHS[i]
		await _add_craft("phaethon" if i == 0 else "shrike", "boxcover" if i == 0 else "ember", "speed" if i == 0 else "starfighter", nose, az)
	_sync_craft(0.0)
	await build_frame
	_slice_name = "turntable"
	_build_turntable()
	if show_vehicle.is_empty():
		show_craft(Settings.selected_craft())
	await _build_showcase(false)
	build_ms = ceili((Time.get_ticks_usec() - _entry_usec) / 1000.0)
	art_ready = true


func _retain_source(path: String) -> void:
	if _sources.has(path):
		return
	if ResourceLoader.load_threaded_request(path) != OK:
		push_error("Could not request title resource " + path)
		return
	_loading_path = path
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await build_frame
	_finish_source()


func _finish_source() -> void:
	if _loading_path.is_empty():
		return
	var source := ResourceLoader.load_threaded_get(_loading_path)
	if source != null:
		_sources[_loading_path] = source
	_loading_path = ""


## A place on the road `dist` m from the pilot, `az` degrees right of straight ahead: where a craft's
## engines' noses come to.
static func _radial(az: float, dist: float) -> Vector3:
	var a := deg_to_rad(az)
	return Vector3(sin(a), 0.0, -cos(a)) * dist


# ---- the sky, its light and the hour ----

func _sun_to(az: float, el: float) -> Vector3:      # a DirectionalLight3D's rotation for a sun there
	return Vector3(-deg_to_rad(el), PI - deg_to_rad(az), 0.0)


## The shaders' own suns and haze (project.godot [shader_globals], as view/outlook.gd sets them for an
## hour): the sky, the cloud deck and the towers all read these, in the world's own axes.
func _set_globals() -> void:
	_globals_at = global_basis if is_inside_tree() else basis
	var to_sun: Vector3 = _globals_at * Basis.from_euler(_sun_to(sun_az, SUN_EL)).z
	var to_sun2: Vector3 = _globals_at * Basis.from_euler(_sun_to(sun_az + 9.0, SUN_EL + 3.4)).z
	Outlook._globals({"sky_sun": to_sun, "sky_sun2": to_sun2, "sky_sun_glow": Vector3(1.0, 0.55, 0.24) * 1.1, "sky_sun2_glow": Vector3(1.0, 0.42, 0.18) * 0.6,
		"sky_haze": Vector3(HORIZON.r, HORIZON.g, HORIZON.b), "sky_haze_scale": 1.0, "sky_wet": 0.0, "sky_snow": 0.0})
	if sky_material != null:      # (the sky's own light on the scene is filtered once: tell it the suns have moved)
		sky_material.set_shader_parameter("zenith", ZENITH)


func _build_sky() -> void:
	_set_globals()
	sky_material = ShaderMaterial.new()
	sky_material.shader = preload("res://view/sky.gdshader")
	sky_material.set_shader_parameter("zenith", ZENITH)
	sky_material.set_shader_parameter("horizon", HORIZON)
	sky_material.set_shader_parameter("ground", LAND)
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment = WorldEnvironment.new()
	var en := Environment.new()
	environment.environment = en
	en.background_mode = Environment.BG_SKY
	en.sky = sky
	# as a flight's own (view/craft_view.gd): the sky fills the shadows, AgX rolls the bright off, a soft bloom
	en.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	en.ambient_light_sky_contribution = 0.9
	en.ambient_light_color = Color(0.85, 0.78, 0.7)
	en.ambient_light_energy = 0.95
	en.tonemap_mode = Environment.TONE_MAPPER_AGX
	en.tonemap_exposure = 1.10
	en.tonemap_white = 6.0
	en.glow_enabled = true
	en.glow_intensity = 0.55
	en.glow_strength = 0.9
	en.glow_bloom = 0.02
	en.glow_hdr_threshold = 1.5      # (a flight's is 0.95: here the menu board's own white must not bloom)
	en.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	for lv in 7:
		en.set_glow_level(lv, 1.0 if lv in [1, 2, 3, 4] else 0.0)
	en.adjustment_enabled = true
	en.adjustment_saturation = 1.12
	en.adjustment_contrast = 1.06
	en.fog_enabled = true
	en.fog_light_color = HORIZON
	en.fog_density = 0.00011
	en.fog_sky_affect = 0.0
	en.fog_aerial_perspective = 0.55
	en.fog_sun_scatter = 0.12
	add_child(environment)
	# the primary sun, low: it casts the long shadows that sit the craft on the road
	sun = DirectionalLight3D.new()
	sun.name = "sun"
	sun.rotation = _sun_to(sun_az, SUN_LIGHT_EL)
	sun.light_color = Color(1.0, 0.56, 0.28)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.0
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(sun)
	# the suns' discs (the world has two: the white primary and its small orange companion)
	for d in [[sun_az, SUN_EL, Color(1.0, 0.78, 0.46), 1.9, 7.0], [sun_az + 9.0, SUN_EL + 3.4, Color(1.0, 0.56, 0.30), 0.55, 4.0]]:
		var disc := DirectionalLight3D.new()
		disc.rotation = _sun_to(float(d[0]), float(d[1]))
		disc.light_color = d[2]
		disc.light_angular_distance = float(d[3])
		disc.light_energy = float(d[4])
		disc.sky_mode = DirectionalLight3D.SKY_MODE_SKY_ONLY
		add_child(disc)
	# what comes back off the land behind the pilot: a soft warm light on the faces turned to him (no shadows)
	var fill := DirectionalLight3D.new()
	fill.name = "fill"
	fill.rotation_degrees = Vector3(-24.0, 12.0, 0.0)
	fill.light_color = Color(0.95, 0.93, 0.90)
	fill.light_energy = 0.55
	fill.light_specular = 0.4
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(fill)
	# the Network's own cloud deck, in the evening's colours
	clouds = MeshInstance3D.new()
	clouds.name = "clouds"
	var plane := PlaneMesh.new()
	plane.size = Vector2(360000, 360000)
	clouds.mesh = plane
	clouds.position.y = CLOUD_BASE
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cm := ShaderMaterial.new()
	cm.shader = preload("res://view/network_clouds.gdshader")
	cm.set_shader_parameter("cloud_cover", _sources.get(CLOUD_COVER))
	cm.set_shader_parameter("zenith", ZENITH)
	cm.set_shader_parameter("horizon", HORIZON)
	cm.set_shader_parameter("lit_col", Vector3(0.86, 0.36, 0.15))
	cm.set_shader_parameter("shade_col", Vector3(0.20, 0.10, 0.15))
	cm.set_shader_parameter("cover", 0.60)
	cm.set_shader_parameter("cirrus", 0.35)
	cm.set_shader_parameter("world_offset", Vector2(41000.0, 9000.0))
	clouds.material_override = cm
	world.add_child(clouds)


# ---- the land ----

func _build_land() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(60000, 60000)
	ground.mesh = plane
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://view/ground.gdshader")
	gm.set_shader_parameter("mesa", 1.0)      # the Network's red sandstone country
	ground.material_override = gm
	ground.position.y = -0.05
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(ground)
	# mesas and buttes all round, flat-topped and banded, clear of the road's line
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261122
	var made := 0
	var tries := 0
	while made < 40 and tries < 600:
		tries += 1
		var az := rng.randf() * TAU
		var dist := rng.randf_range(650.0, 4600.0)
		var at := Vector3(sin(az) * dist, 0.0, -cos(az) * dist)
		var wide := dist * rng.randf_range(0.07, 0.17)
		var tall := dist * rng.randf_range(0.035, 0.075)
		if rng.randf() < 0.3:      # a butte: narrow and high
			wide *= 0.34
			tall *= 1.25
		if absf(at.x - road_x(at.z)) < wide * 1.9 + 120.0:
			continue
		var off_sun := wrapf(rad_to_deg(az) - sun_az, -180.0, 180.0)
		if off_sun > -9.0 and off_sun < 16.0:
			continue      # (nor across the suns: they set on open desert)
		var fly_a: Vector3 = FLY_FROM[layout]
		var fly_b: Vector3 = FLY_TO[layout]
		var on_fly := fly_a + (fly_b - fly_a) * clampf((at - fly_a).dot(fly_b - fly_a) / (fly_b - fly_a).length_squared(), 0.0, 1.0)
		if Vector2(at.x - LOOP_AT.x, at.z - LOOP_AT.z).length() < wide * 1.9 + 260.0 or at.distance_to(on_fly) < wide * 1.9 + 170.0:
			continue      # (not through the shaft or the road on pillars)
		_butte(st, rng, at, wide, tall)
		made += 1
	var land := MeshInstance3D.new()
	land.name = "mesas"
	land.mesh = st.commit()
	var mm := Kit.vertex_colors()
	mm.roughness = 0.95
	land.material_override = mm
	land.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(land)


## A mesa: a wandering outline stepped up from a talus skirt through banded cliffs to a flat cap.
static func _butte(st: SurfaceTool, rng: RandomNumberGenerator, at: Vector3, radius: float, height: float) -> void:
	var n := 18
	var phase := rng.randf() * TAU
	var squash := rng.randf_range(0.55, 1.0)
	var turn := rng.randf() * PI
	var outline := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		var r := radius * (1.0 + 0.20 * sin(a * 2.0 + phase) + 0.11 * sin(a * 5.0 + phase * 2.3) + rng.randf_range(-0.05, 0.05))
		outline.append(Vector2(cos(a) * r, sin(a) * r * squash).rotated(turn))
	# [the outline's share, the height's share, the band's colour below this level]
	var levels := [[1.85, 0.0, Color.BLACK], [1.22, 0.36, Color(0.50, 0.24, 0.14)], [1.13, 0.40, Color(0.62, 0.30, 0.16)],
		[1.08, 0.70, Color(0.70, 0.31, 0.15)], [1.04, 0.74, Color(0.56, 0.23, 0.12)], [1.0, 1.0, Color(0.74, 0.35, 0.17)]]
	for k in range(1, levels.size()):
		var lo: Array = levels[k - 1]
		var hi: Array = levels[k]
		for i in n:
			var j := (i + 1) % n
			var a := at + Vector3(outline[i].x * float(lo[0]), height * float(lo[1]), outline[i].y * float(lo[0]))
			var b := at + Vector3(outline[j].x * float(lo[0]), height * float(lo[1]), outline[j].y * float(lo[0]))
			var c := at + Vector3(outline[j].x * float(hi[0]), height * float(hi[1]), outline[j].y * float(hi[0]))
			var d := at + Vector3(outline[i].x * float(hi[0]), height * float(hi[1]), outline[i].y * float(hi[0]))
			var out := (a + b) / 2.0 - at
			var face := (b - a).cross(d - a).normalized()
			if face.dot(Vector3(out.x, 0.4 * out.length(), out.z)) < 0.0:
				face = -face
			_quad(st, a, b, c, d, face, hi[2])
	var top := at + Vector3(0.0, height, 0.0)
	for i in n:
		var j := (i + 1) % n
		_tri(st, top, top + Vector3(outline[i].x, 0.0, outline[i].y), top + Vector3(outline[j].x, 0.0, outline[j].y), Vector3.UP, Color(0.78, 0.44, 0.24))


# ---- the road ----

## The main road's centre line: straight through the stand, sweeping away to the right beyond it.
static func road_x(z: float) -> float:
	var d := -z - 220.0
	return 0.00045 * d * d if d > 0.0 else 0.0


## ... and its half-width: a 46 m road, opening to an apron 120 m across where the craft stand.
static func road_half(z: float) -> float:
	return 23.0 + 37.0 * smoothstep(-130.0, -55.0, z) * (1.0 - smoothstep(35.0, 100.0, z))


func _build_roads() -> void:
	var zs := PackedFloat64Array()
	var z := 900.0
	while z > -3700.0:
		zs.append(z)
		z -= 10.0 if absf(z) <= 220.0 else (25.0 if z > -900.0 else 100.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	var was_c := Vector3.ZERO
	var was_l := Vector3.ZERO
	var was_h := 0.0
	var was_s := 0.0
	for i in zs.size():
		var c := Vector3(road_x(zs[i]), 0.0, zs[i])
		var ahead := Vector3(road_x(zs[i] - 1.0), 0.0, zs[i] - 1.0)
		var left := Vector3.UP.cross((ahead - c).normalized()).normalized()
		var half := road_half(zs[i])
		if i > 0:
			along += c.distance_to(was_c)
			# (the asphalt's own lay: metres along the road, metres left of its middle; view/asphalt.gdshader)
			_quad(st, was_c + was_l * was_h, was_c - was_l * was_h, c - left * half, c + left * half, Vector3.UP, Color.WHITE,
				[Vector2(was_s, was_h), Vector2(was_s, -was_h), Vector2(along, -half), Vector2(along, half)])
		was_c = c
		was_l = left
		was_h = half
		was_s = along
	var road := MeshInstance3D.new()
	road.name = "road"
	road.mesh = st.commit()
	var asphalt := preload("res://art/road/asphalt.tres").duplicate() as ShaderMaterial
	asphalt.set_shader_parameter("period", ASPHALT_PERIOD)
	asphalt.set_shader_parameter("base", Vector3(0.21, 0.205, 0.205))
	asphalt.set_shader_parameter("spec", 0.3)
	asphalt.set_shader_parameter("lane_half", 22.0)
	road.material_override = asphalt
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(road)
	# the kerb down both edges: red and white blocks, three metres each (the cover's)
	var kt := SurfaceTool.new()
	kt.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := 0
	z = 330.0
	while z > -520.0:
		var c := Vector3(road_x(z), 0.0, z)
		var ahead := Vector3(road_x(z - 3.0), 0.0, z - 3.0)
		var fwd := (ahead - c).normalized()
		var left := Vector3.UP.cross(fwd).normalized()
		var half := (road_half(z) + road_half(z - 3.0)) / 2.0
		var frame := Basis(-left, Vector3.UP, -fwd)
		for side in [-1.0, 1.0]:
			_slab(kt, (c + ahead) / 2.0 + left * side * (half + 0.7) + Vector3(0.0, 0.05, 0.0), Vector3(1.4, 0.16, c.distance_to(ahead)), KERB_RED if k % 2 == 0 else KERB_WHITE, frame)
		k += 1
		z -= 3.0
	# the headset's layout: a stop bar across the apron in front of each craft, where its engines hold short
	for holder_at: Array in (_berths() if layout == "vr" else []):
		var at: Vector3 = holder_at[0]
		var yaw: float = holder_at[1]
		var facing := Basis(Vector3.UP, yaw)
		_slab(kt, at + facing * Vector3(0.0, 0.012, 1.6), Vector3(11.0, 0.02, 0.45), KERB_WHITE, facing)
	var kerb := MeshInstance3D.new()
	kerb.name = "kerb"
	kerb.mesh = kt.commit()
	var km := Kit.vertex_colors()
	km.roughness = 0.8
	kerb.material_override = km
	kerb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(kerb)


## Where each craft's engines' noses come to, and the way it faces: [place, yaw] (yaw 0 faces +z, the camera's way).
func _berths() -> Array:
	if layout == "vr":
		return [[_radial(VR_BERTHS[0][0], VR_BERTHS[0][1]), -deg_to_rad(VR_BERTHS[0][0])], [_radial(VR_BERTHS[1][0], VR_BERTHS[1][1]), -deg_to_rad(VR_BERTHS[1][0])]]
	return [[FLAT_BERTHS[0], 0.0], [FLAT_BERTHS[1], 0.0]]


# ---- the stand ----

## The starter's stand in the middle of the road (the headset's layout): a slab two metres up with a
## pad's yellow border on its deck and the kerb's red and white round its rim.
func _build_stand() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mid_z := (3.0 - STAND.y) / 2.0
	var long := STAND.y + 3.0
	_slab(st, Vector3(0.0, STAND_H / 2.0 - 0.02, mid_z), Vector3(STAND.x * 2.0, STAND_H - 0.04, long), Color(0.30, 0.31, 0.32))
	_slab(st, Vector3(0.0, STAND_H - 0.03, mid_z), Vector3(STAND.x * 2.0, 0.06, long), Color(0.17, 0.175, 0.18))
	# the deck's plates: a seam every 1.7 m, and a ring painted where the pilot stands
	var seam := Color(0.07, 0.07, 0.075)
	for i in range(-1, 2):
		_slab(st, Vector3(1.7 * i, STAND_H + 0.002, mid_z), Vector3(0.03, 0.004, long - 0.9), seam)
	for i in range(-1, 3):
		_slab(st, Vector3(0.0, STAND_H + 0.002, 1.7 * i - 0.85), Vector3(STAND.x * 2.0 - 0.9, 0.004, 0.03), seam)
	for i in 28:
		var a := TAU * (float(i) + 0.5) / 28.0
		_slab(st, Vector3(cos(a) * 0.62, STAND_H + 0.004, sin(a) * 0.62), Vector3(0.05, 0.004, 0.145), KERB_WHITE, Basis(Vector3.UP, -a))
	for edge in [[Vector3(0.0, STAND_H + 0.005, mid_z - long / 2.0 + 0.35), Vector3(STAND.x * 2.0 - 0.5, 0.01, 0.14)], [Vector3(0.0, STAND_H + 0.005, mid_z + long / 2.0 - 0.35), Vector3(STAND.x * 2.0 - 0.5, 0.01, 0.14)],
			[Vector3(-STAND.x + 0.32, STAND_H + 0.005, mid_z), Vector3(0.14, 0.01, long - 0.5)], [Vector3(STAND.x - 0.32, STAND_H + 0.005, mid_z), Vector3(0.14, 0.01, long - 0.5)]]:
		_slab(st, edge[0], edge[1], Color(0.92, 0.72, 0.10))
	# the rim: a kerb's blocks round the deck's edge
	var k := 0
	var x := -STAND.x
	while x < STAND.x - 0.01:
		for zz in [mid_z - long / 2.0, mid_z + long / 2.0]:
			_slab(st, Vector3(x + 0.425, STAND_H - 0.16, zz), Vector3(0.85, 0.32, 0.10), KERB_RED if k % 2 == 0 else KERB_WHITE)
		k += 1
		x += 0.85
	k = 0
	var zc := mid_z - long / 2.0
	while zc < mid_z + long / 2.0 - 0.01:
		for xx in [-STAND.x, STAND.x]:
			_slab(st, Vector3(xx, STAND_H - 0.16, zc + 0.425), Vector3(0.10, 0.32, 0.85), KERB_WHITE if k % 2 == 0 else KERB_RED)
		k += 1
		zc += 0.85
	stand = MeshInstance3D.new()
	stand.name = "stand"
	stand.mesh = st.commit()
	var sm := Kit.vertex_colors()
	sm.roughness = 0.85
	stand.material_override = sm
	world.add_child(stand)


# ---- the road on pillars, and the shaft ----

# the road on pillars: from out on the left to its lip, short of the main road. (The headset's ends clear of the
# menu board's edge; the desktop's is where the cover has it, a fifth of the way in from the picture's middle.)
const FLY_FROM := {"vr": Vector3(-740.0, 0.0, -330.0), "flat": Vector3(-700.0, 0.0, -350.0)}
const FLY_TO := {"vr": Vector3(-100.0, 0.0, -170.0), "flat": Vector3(-65.0, 0.0, -178.0)}
const FLY_H := 28.0
const FLY_HALF := 15.0
const LIP_RUN := 74.0            # the last of it turns up into a launch lip ...
const LIP_RISE := 13.0           # ... this high
const LOOP_AT := Vector3(205.0, 0.0, -282.0)        # the shaft's foot, on the right
const LOOP_R := 31.0             # its arcs (view/network_shaft.gd's shape: a quarter up, straight up, a half over, down, a quarter out)
const LOOP_V := 46.0             # ... and its straights
const LOOP_HALF := 12.0
const LOOP_LEAD := 150.0         # road on the ground before the pull-up, and after the pull-out


func _build_structures() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# the road on pillars
	var fly_from: Vector3 = FLY_FROM[layout]
	var run: Vector3 = FLY_TO[layout] - fly_from
	var length := run.length()
	var fwd := run / length
	var rows := []
	var s := 0.0
	while s <= length + 0.01:
		var into := maxf(0.0, s - (length - LIP_RUN)) / LIP_RUN
		var slope := 2.0 * LIP_RISE * into / LIP_RUN
		var tangent := (fwd + Vector3.UP * slope).normalized()
		var left := Vector3.UP.cross(fwd).normalized()
		rows.append([fly_from + fwd * s + Vector3.UP * (FLY_H + LIP_RISE * into * into), left, tangent.cross(left).normalized()])
		s += 6.0 if s > length - LIP_RUN - 6.0 else 20.0
	_deck(st, rows, FLY_HALF, 2.6, 2)
	# its lip's end: a board of amber and black chevrons across it, facing the way the jump goes
	var tip: Array = rows[rows.size() - 1]
	var tip_up: Vector3 = tip[2]
	var tip_left: Vector3 = tip[1]
	var tip_fwd := tip_up.cross(tip_left).normalized() * -1.0
	var face := Basis(-tip_left, tip_up, tip_fwd)      # (its z is the way out of the lip)
	for i in 10:
		_slab(st, (tip[0] as Vector3) + tip_fwd * 0.2 - tip_up * 1.5 + tip_left * (FLY_HALF - 1.5 - 3.0 * i), Vector3(3.0, 3.0, 0.3), AMBER if i % 2 == 0 else Color(0.05, 0.05, 0.05), face)
	# its pillars: a pair under the deck every sixty metres, a beam across their heads
	s = 40.0
	while s < length - 20.0:
		var into := maxf(0.0, s - (length - LIP_RUN)) / LIP_RUN
		var under := FLY_H + LIP_RISE * into * into - 2.6
		var c := fly_from + fwd * s
		var left := Vector3.UP.cross(fwd).normalized()
		var frame := Basis(-left, Vector3.UP, -fwd)
		for side in [-1.0, 1.0]:
			_slab(st, c + left * side * 8.5 + Vector3.UP * (under / 2.0), Vector3(3.2, under, 4.2), CONCRETE, frame)
		_slab(st, c + Vector3.UP * (under - 1.1), Vector3(24.0, 2.2, 4.8), CONCRETE.darkened(0.08), frame)
		s += 60.0
	# the shaft: the Network's own shape, standing on the right, a road in along the ground and a road out
	var out := Vector3(0.94, 0.0, 0.34).normalized()      # the way the road runs in to the pull-up: across the view and a little toward it, so the climbing leg's road shows
	var side_way := Vector3.UP.cross(out).normalized()
	var total := 2.0 * PI * LOOP_R + 2.0 * LOOP_V
	rows = []
	var d := -LOOP_LEAD
	while d <= total + LOOP_LEAD + 0.01:
		var sh: Array = Shaft.shape(d, LOOP_R, LOOP_V)
		var across := lerpf(-17.0, 17.0, clampf(d / total, 0.0, 1.0))      # (in and out lie side by side: the shape steps across as it goes over)
		var tangent: Vector3 = out * (sh[2] as Vector2).x + Vector3.UP * (sh[2] as Vector2).y
		var up: Vector3 = out * (sh[3] as Vector2).x + Vector3.UP * (sh[3] as Vector2).y
		rows.append([LOOP_AT + out * float(sh[0]) + Vector3.UP * (float(sh[1]) + 0.3) + side_way * across, up.cross(tangent).normalized(), up])
		d += 4.0 if d > -8.0 and d < total + 8.0 else 24.0
	_deck(st, rows, LOOP_HALF, 1.8, 3)
	var built := MeshInstance3D.new()
	built.name = "structures"
	built.mesh = st.commit()
	var bm := Kit.vertex_colors()
	bm.roughness = 0.82
	built.material_override = bm
	built.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF      # (a sun this low would lay the pillars' shadows a quarter of a kilometre, over the craft)
	world.add_child(built)


## A road's deck along `rows` ([its middle, its left, its up] each): tarmac on top between two kerb
## lines (red and white, changing every `kerb_every` rows), concrete down its sides and under it.
static func _deck(st: SurfaceTool, rows: Array, half: float, thick: float, kerb_every: int) -> void:
	for i in range(1, rows.size()):
		var a: Array = rows[i - 1]
		var b: Array = rows[i]
		var ca: Vector3 = a[0]
		var cb: Vector3 = b[0]
		var la: Vector3 = a[1]
		var lb: Vector3 = b[1]
		var ua: Vector3 = a[2]
		var ub: Vector3 = b[2]
		var up := (ua + ub).normalized()
		var kerb := KERB_RED if (i / kerb_every) % 2 == 0 else KERB_WHITE
		var inner := half - 1.6
		_quad(st, ca + la * inner, ca - la * inner, cb - lb * inner, cb + lb * inner, up, TARMAC)
		for side in [-1.0, 1.0]:
			_quad(st, ca + la * side * half, ca + la * side * inner, cb + lb * side * inner, cb + lb * side * half, up, kerb)
			var out: Vector3 = ((la + lb) * side).normalized()
			_quad(st, ca + la * side * half, cb + lb * side * half, cb + lb * side * half - ub * thick, ca + la * side * half - ua * thick, out, CONCRETE)
		_quad(st, ca + la * half - ua * thick, ca - la * half - ua * thick, cb - lb * half - ub * thick, cb + lb * half - ub * thick, -up, CONCRETE.darkened(0.25))


# ---- the far city ----

func _build_skyline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	var centre := _radial(13.0, 6400.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = Kit.box(Vector3.ONE)
	mm.instance_count = 64
	for k in mm.instance_count:
		var off := Vector3(rng.randf_range(-1100.0, 1100.0), 0.0, rng.randf_range(-700.0, 700.0))
		var tall := lerpf(820.0, 170.0, clampf(absf(off.x) / 1100.0, 0.0, 1.0)) * rng.randf_range(0.5, 1.1)
		var foot := rng.randf_range(60.0, 150.0)
		mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(foot, tall, foot * rng.randf_range(0.6, 1.4))).rotated(Vector3.UP, rng.randf() * PI), centre + off + Vector3(0.0, tall / 2.0, 0.0)))
		mm.set_instance_color(k, Color(0.78, 0.82, 0.80).lerp(Color(0.42, 0.55, 0.50), rng.randf()))
	var city := MultiMeshInstance3D.new()
	city.name = "skyline"
	city.multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = preload("res://view/skyline.gdshader")
	m.set_shader_parameter("crown", Vector3(1.0, 0.55, 0.3))
	m.set_shader_parameter("haze_col", Vector3(HORIZON.r, HORIZON.g, HORIZON.b))
	m.set_shader_parameter("zenith", Vector3(ZENITH.r, ZENITH.g, ZENITH.b))
	m.set_shader_parameter("haze", 0.00007)
	m.set_shader_parameter("suns", 0.7)
	m.set_shader_parameter("night", 0.0)
	city.material_override = m
	city.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	city.custom_aabb = AABB(centre + Vector3(-1500.0, 0.0, -1000.0), Vector3(3000.0, 4000.0, 2000.0))
	world.add_child(city)


# ---- the word ----

func _build_word(at: Vector3, cap: float, turn: Vector3) -> void:
	word = Node3D.new()
	word.name = "word"
	word.position = at
	word.rotation = turn
	word.scale = Vector3.ONE * cap
	add_child(word)
	letters = MeshInstance3D.new()
	letters.name = "letters"
	letters.mesh = Letters.word(WORD)
	letters.position = Vector3(-Letters.width(WORD) / 2.0, 0.0, 0.0)
	var lm := Kit.vertex_colors(true)      # unshaded: the cover's flat cream and orange-red, whatever the light
	lm.disable_fog = true
	letters.material_override = lm
	letters.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	word.add_child(letters)


## The strap line's type: the engine's own font, spaced and made heavier (its lean is the node's that
## carries it: STRAP_LEAN, across per up).
const STRAP_LEAN := 0.22
static func strap_font(spacing := 9) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = 0.7
	font.spacing_glyph = spacing
	font.spacing_space = spacing + 5
	return font


## The strap line as a thing in the world, `wide` m across: TWIN-THROTTLE RACING between two orange
## rules (the headset's menu hangs it under its board).
static func strap_3d(wide: float) -> Node3D:
	var node := Node3D.new()
	node.name = "TitleStrap"
	var lean := Node3D.new()
	lean.name = "lean"
	lean.basis = Basis(Vector3.RIGHT, Vector3(STRAP_LEAN, 1.0, 0.0), Vector3.BACK)
	node.add_child(lean)
	var line := Label3D.new()
	line.name = "words"
	line.text = STRAP
	line.font = strap_font(22)
	line.font_size = 96
	line.outline_size = 0
	line.modulate = Letters.CREAM
	line.shaded = false
	line.double_sided = false
	line.pixel_size = wide * 0.50 / 1700.0      # (the line is some 1,700 px long at this size: half the board's width)
	lean.add_child(line)
	var rule := QuadMesh.new()
	rule.size = Vector2(wide * 0.21, 0.012)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Letters.STROKE
	for side in [-1.0, 1.0]:
		var bar := MeshInstance3D.new()
		bar.mesh = rule
		bar.material_override = rm
		bar.position.x = side * wide * 0.385
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(bar)
	return node


# ---- the craft ----

## A craft standing at idle: its engines' noses at `nose` on the road, the whole of it turned `az` (rad,
## + to the pilot's right) from facing straight back down the -z axis at him. Built in `livery`
## (view/livery.gd), flown by nobody: a sim that is never stepped holds it where the range would
## spawn it, and the game's own model is posed from that each frame, as a flight's is.
func _add_craft(vehicle: String, livery: String, handling: String, nose: Vector3, az: float) -> void:
	# the holder's +x is the craft's nose (the range runs along +x): turn it to face the pilot, and stand its
	# pod so far back that the engines' noses come to `nose`
	var heading := Basis(Vector3.UP, -az) * Vector3(0.0, 0.0, 1.0)
	var place := func(holder: Node3D, reach: float) -> void:
		holder.basis = Basis(heading, Vector3.UP, heading.cross(Vector3.UP))
		holder.position = nose - heading * reach
	var c := await _build_craft(vehicle, livery, handling, world, "craft_" + vehicle, place, _display_body)
	c.phase = float(craft.size()) * 2.1
	(c.holder as Node3D).show()
	craft.append(c)


## A craft standing at idle under `parent`, in a holder named `holder_name` that `place` stands (it is
## given the holder and how far the engines' intake lips are ahead of the pod's middle, along the holder's
## +x), built over the frames that follow and left hidden. `reuse_body`: the Phaethon's engine fairings
## to use (title_stage._display_body: the cover's, in its own paint), or none to build its own.
func _build_craft(vehicle: String, livery: String, handling: String, parent: Node3D, holder_name: String, place: Callable, reuse_body := Callable()) -> Dictionary:
	_building_vehicle = vehicle
	_slice_name = vehicle + " bodywork and engine parts"
	var sim = SimScript.new({"track": "range", "vehicle": vehicle, "handling": handling})
	var berth := Berth.new()
	berth.sim = sim
	berth.ox = sim.pod.x
	berth.oy = sim.pod.y
	for k in 2:      # the links' ends, as a step would leave them (CraftSim.step: the tow links are drawn from these)
		var e = sim.eL if k == 0 else sim.eR
		var side := 1.0 if k == 0 else -1.0
		var aw: float = side * sim.P.podAnchorW * sim.P.podWidth / 2.0
		sim.cables[k] = {"ex": e.x - cos(e.th) * sim.P.engineLen / 2.0, "ey": e.y - sin(e.th) * sim.P.engineLen / 2.0,
			"px": sim.pod.x + cos(sim.pod.th) * sim.P.podLen / 2.0 - sin(sim.pod.th) * aw, "py": sim.pod.y + sin(sim.pod.th) * sim.P.podLen / 2.0 + cos(sim.pod.th) * aw, "f": 0.0, "slack": false}
	for e in [sim.eL, sim.eR]:
		e.thrust = IDLE
		e.heat = 0.36
	var reach: float = sim.eL.x - sim.pod.x + 3.85      # the pod's middle to the intake lips
	var holder := Node3D.new()
	holder.name = holder_name
	place.call(holder, reach)
	parent.add_child(holder)
	holder.hide()
	_flight_livery = Livery.current
	Livery.current = livery      # (a craft's colours are in its meshes: built in its livery, then back)
	var model = ModelScript.new()
	model.name = "model"
	holder.add_child(model)
	await model.build(berth, _pause_craft.bind(livery), reuse_body)
	Livery.current = _flight_livery
	# a pilot in the seat: helmet, visor, shoulders (the cover's; in a flight the pilot is you)
	var pilot := MeshInstance3D.new()
	pilot.name = "pilot"
	var suit: Color = Shrike.PETROL if vehicle == "shrike" else Livery.coat("paint", livery)
	pilot.mesh = Kit.compound([
		[Kit.rounded_box(Vector3(0.54, 0.30, 0.28), 4.0, 8), Kit.at(Vector3(0.0, -0.20, 0.05)), suit],
		[Kit.cyl(0.07, 0.08, 0.10, 10), Kit.at(Vector3(0.0, -0.03, 0.02)), Color(0.07, 0.07, 0.08)],
		[Kit.ball(0.15, 14), Kit.at(Vector3(0.0, 0.12, 0.0), Vector3.ZERO, Vector3(1.0, 1.06, 1.12)), Color(0.93, 0.92, 0.88)],
		[Kit.ball(0.125, 12), Kit.at(Vector3(0.0, 0.125, -0.06), Vector3.ZERO, Vector3(1.04, 0.60, 1.0)), Color(0.04, 0.05, 0.07)]])
	pilot.material_override = Kit.polished(0.15, 0.32)
	pilot.position = Vector3(0.0, 0.09, 0.62)      # the head where VRCockpit.EYE is in the pod
	model.pod.add_child(pilot)
	return {"holder": holder, "model": model, "sim": sim, "berth": berth, "inp": {"brkL": 0.0, "brkR": 0.0, "park": false},
		"phase": 0.0, "rest": holder.position, "owed": 0.0, "reach": reach}


static func _display_body(out: float) -> ArrayMesh:
	if not _display_bodies.has(out):
		_display_bodies[out] = ModelScript._engine_body(out, false)      # (as the model's own: its rudder and stabiliser are parts that turn)
	return _display_bodies[out]


## The turntable Phaethon's fairing in the paint it is being built in (Livery.current while it builds).
static func _show_body(out: float) -> ArrayMesh:
	var key := "%s/%d" % [Livery.current, int(out)]
	if not _show_bodies.has(key):
		_show_bodies[key] = ModelScript._engine_body(out, false)
	return _show_bodies[key]


func _pause_craft(part: String, paint: String) -> void:
	# Leave the selected paint available to the menu and any flight started between slices.
	Livery.current = _flight_livery
	await build_frame
	_slice_name = _building_vehicle + " " + part
	_flight_livery = Livery.current
	Livery.current = paint


func _sync_craft(delta: float) -> void:
	_frame += 1
	var all := craft.duplicate()
	if not showcase.is_empty() and reveal > 0.0:      # (put away, it is not posed: the two either side keep their own rhythm)
		all.append(showcase)
	for i in all.size():
		var c: Dictionary = all[i]
		# idling: the craft rides its repulsors (every frame: the whole of it moves as one) ...
		var lift := 0.0
		if is_same(c, showcase):      # (... and the one on the turntable comes down onto it as it is brought up, or as it is chosen, slowing as it lands)
			var coming := 1.0 - smoothstep(0.4, 1.0, reveal)
			lift = SHOW_DROP * maxf(_drop * _drop, coming * coming)
		(c.holder as Node3D).position = (c.rest as Vector3) + Vector3(0.0, BOB * sin(_clock * 1.1 + float(c.phase)) + lift, 0.0)
		c.owed = float(c.owed) + delta
		if delta > 0.0 and (i + _frame) % all.size() != 0:
			continue      # ... and its moving parts are posed a craft a frame, turn about: fans and arcs ten metres off do not show it, and it is half the work
		var sim = c.sim
		var lever := IDLE + 0.035 * sin(_clock * 0.8 + float(c.phase))      # the levers breathe a little
		sim.eL.thrust = lever
		sim.eR.thrust = lever + 0.012 * sin(_clock * 1.7 + float(c.phase))
		c.model.sync(sim, c.inp, float(c.owed))
		c.model.sync_cables(sim, maxf(float(c.owed), 1.0 / 240.0))
		c.owed = 0.0


func _process(delta: float) -> void:
	if _board_draw_pending:
		_board_draw_pending = false
		return
	if not art_ready:
		if Time.get_ticks_usec() - _entry_usec < BOARD_FIRST_USEC:
			return
		var before := Time.get_ticks_usec()
		build_frame.emit()
		build_split.frames += 1
		var elapsed := (Time.get_ticks_usec() - before) / 1000.0
		build_split.work_ms += elapsed
		build_split.by_part[_slice_name] = maxf(elapsed, build_split.by_part.get(_slice_name, 0.0))
		if elapsed > float(build_split.max_slice_ms):
			build_split.max_slice_ms = elapsed
			build_split.slowest = _slice_name
	elif not _show_job.is_empty():
		build_frame.emit()      # (a craft being built for the turntable, a slice a frame)
	_clock += delta
	if turntable != null:
		var was_up := reveal
		reveal = move_toward(reveal, 1.0 if attend_wanted else 0.0, delta / (SHOW_UP_S if attend_wanted else SHOW_DOWN_S))
		if was_up < 0.4 and reveal >= 0.4:
			_whip = 1.0      # (the craft comes down onto the deck from here: swing it round as it lands)
		if reveal != was_up:
			_pose_turntable()
		turntable.rotation.y = wrapf(turntable.rotation.y + deg_to_rad(SHOW_SPIN + SHOW_WHIP * _whip * _whip) * delta, -PI, PI)
		_whip = move_toward(_whip, 0.0, delta / SHOW_WHIP_S)
		_drop = move_toward(_drop, 0.0, delta / SHOW_DROP_S)
	_sync_craft(delta)
	if art_ready and _show_job.is_empty() and not show_vehicle.is_empty() and showcase.get("key", "") != _show_key():
		_build_showcase()
	if camera != null:
		var was := attention
		attention = move_toward(attention, 1.0 if attend_wanted else 0.0, delta / SHOW_TURN_S)
		if attention != was:
			_aim_camera()
	if clouds != null:
		var at := Vector2(41000.0, 9000.0) + CLOUD_DRIFT * _clock
		(clouds.material_override as ShaderMaterial).set_shader_parameter("world_offset", at)


# ---- where it stands ----

## The headset: stand the whole scene so the pilot's eye (`eye`, in the menu's own space) is EYE over the
## stand's deck and -z is the way he faces (`forward`, level). Called when the menu's board is put in
## front of him: nothing moves between those times, and nothing ever moves the camera.
func place(eye: Vector3, forward: Vector3) -> void:
	var f := Vector3(forward.x, 0.0, forward.z)
	f = f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD
	global_transform = Transform3D(Basis.looking_at(f, Vector3.UP), Vector3(eye.x, eye.y - EYE, eye.z))
	if not _globals_at.is_equal_approx(global_basis):
		_set_globals()


## The desktop: aim the camera's picture at `art` (a rect of the window `window`, both in the same
## units), so its middle is the art's middle and its field across the art is `across` degrees: the
## menu's panels cover the rest, and the scene carries on under them.
func frame(art: Rect2, window: Vector2, across := FLAT_ACROSS) -> void:
	if camera == null or art.size.x <= 0.0 or window.y <= 0.0:
		return
	_frame_art = art
	_frame_window = window
	_frame_across = across
	_aim_camera()


## The desktop's camera where `attention` has it: the cover's view at 0, the turntable at 1, and turning
## between them (eased at both ends), its lens narrowing as it goes.
func _aim_camera() -> void:
	if camera == null:
		return
	var e := smoothstep(0.0, 1.0, attention)
	var home := Transform3D(Basis.from_euler(Vector3(-deg_to_rad(FLAT_PITCH), 0.0, 0.0)), FLAT_EYE)
	var look: Vector3 = SHOW_AT["flat"] + Vector3(0.0, SHOW_LOOK, 0.0)
	var there := Transform3D(Basis.looking_at(look - SHOW_EYE, Vector3.UP), SHOW_EYE)
	camera.transform = home.interpolate_with(there, e)
	if _frame_art.size.x <= 0.0 or _frame_window.y <= 0.0:
		return
	var across := lerpf(_frame_across, SHOW_ACROSS, e)
	var near := camera.near
	var per_unit := 2.0 * near * tan(deg_to_rad(across) / 2.0) / _frame_art.size.x      # m on the near plane per unit of window
	var middle := _frame_art.get_center() - _frame_window / 2.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.set_frustum(_frame_window.y * per_unit, Vector2(-middle.x, middle.y) * per_unit, near, camera.far)


## A craft is being chosen (on) or not: bring the turntable up out of the road with the craft on it, or
## put it away; on the desktop, turn the camera to it, or back to the cover's view.
func attend(on: bool) -> void:
	attend_wanted = on and turntable != null


## The turntable where `reveal` has it: put away it lies SHOW_SINK down, under the road and hidden; it
## rises in the first part of coming up, and the craft comes down onto it in the rest (_sync_craft).
func _pose_turntable() -> void:
	if turntable_base == null:
		return
	turntable_base.position.y = -SHOW_SINK * (1.0 - smoothstep(0.0, 0.4, reveal))
	turntable_base.visible = reveal > 0.0


# ---- the turntable ----

## The menus: put this pilot craft on the turntable, in `livery` (by default the paint the next flight will
## wear). It is built over the frames that follow, the craft on show staying until it is ready; one built
## before comes straight back.
func show_craft(vehicle: String, livery := "") -> void:
	show_vehicle = Pilot.known(vehicle)
	show_livery = livery if Livery.TABLE.has(livery) else flight_livery()


## The paint the next flight will be built in (view/craft_view.gd: the menus' paint, or the patrol's own).
static func flight_livery() -> String:
	if Settings.choice("craft", Chase.ids(Chase.CRAFTS)) == "patrol":
		return "police"
	return Settings.choice("paint", Livery.ids())


func _show_key() -> String:
	return show_vehicle + "/" + show_livery


## The deck, which turns, on a fixed ring of the kerb's blocks with an amber lamp line under its lip, and
## the name board at its edge.
func _build_turntable() -> void:
	var at: Vector3 = SHOW_AT[layout]
	var base := Node3D.new()
	base.name = "turntable_base"
	base.position = at
	world.add_child(base)
	turntable_base = base
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 80
	for i in n:
		var a := TAU * (float(i) + 0.5) / float(n)
		var ring_r := SHOW_R + 0.55
		_slab(st, Vector3(sin(a), 0.0, cos(a)) * ring_r + Vector3(0.0, (SHOW_H + 0.06) / 2.0, 0.0), Vector3(TAU * ring_r / float(n) + 0.02, SHOW_H + 0.06, 1.0),
			KERB_RED if i % 2 == 0 else KERB_WHITE, Basis(Vector3.UP, a))
	var ring := MeshInstance3D.new()
	ring.name = "ring"
	ring.mesh = st.commit()
	var rm := Kit.vertex_colors()
	rm.roughness = 0.8
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	base.add_child(ring)
	# the lamp line: a band of amber under the deck's lip, all the way round
	var lamp := SurfaceTool.new()
	lamp.begin(Mesh.PRIMITIVE_TRIANGLES)
	n = 120
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var o0 := Vector3(sin(a0), 0.0, cos(a0))
		var o1 := Vector3(sin(a1), 0.0, cos(a1))
		var r := SHOW_R + 0.02
		_quad(lamp, o0 * r + Vector3.UP * (SHOW_H - 0.12), o1 * r + Vector3.UP * (SHOW_H - 0.12), o1 * r + Vector3.UP * (SHOW_H - 0.05), o0 * r + Vector3.UP * (SHOW_H - 0.05), (o0 + o1).normalized(), AMBER)
	var lamps := MeshInstance3D.new()
	lamps.name = "lamps"
	lamps.mesh = lamp.commit()
	lamps.material_override = Kit.vertex_colors(true)
	lamps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	base.add_child(lamps)
	# a showroom's lamp high over it, a little toward whoever looks: a pool of light on the deck, and the
	# craft's shadow straight under it (the low sun lays its shadow a dozen metres off, and a hovering craft
	# seen from the stand then reads as standing beyond the deck)
	var viewer := Vector3.ZERO if layout == "vr" else SHOW_EYE
	var toward := Vector3(viewer.x - at.x, 0.0, viewer.z - at.z).normalized()
	var spot := SpotLight3D.new()
	spot.name = "spot"
	var from := Vector3.UP * 30.0 + toward * 8.0
	spot.transform = Transform3D(Basis.looking_at(Vector3.UP * 1.0 - from, Vector3.UP), from)
	spot.spot_range = 48.0
	spot.spot_angle = 33.0
	spot.spot_angle_attenuation = 0.6
	spot.spot_attenuation = 0.0
	spot.light_color = Color(1.0, 0.94, 0.86)
	spot.light_energy = 3.2
	spot.light_specular = 0.6
	spot.shadow_enabled = true
	spot.shadow_blur = 1.5
	base.add_child(spot)
	# the deck: concrete-grey plates, a seam every 22.5 degrees and a ring of them halfway out, a pad's
	# yellow border near its edge (it turns: the seams are how the eye sees it turn)
	turntable = Node3D.new()
	turntable.name = "turntable"
	base.add_child(turntable)
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	n = 96
	var top := Vector3.UP * SHOW_H
	for i in n:
		var o0 := Vector3(sin(TAU * float(i) / float(n)), 0.0, cos(TAU * float(i) / float(n)))
		var o1 := Vector3(sin(TAU * float(i + 1) / float(n)), 0.0, cos(TAU * float(i + 1) / float(n)))
		_tri(st, top, top + o0 * SHOW_R, top + o1 * SHOW_R, Vector3.UP, Color(0.34, 0.345, 0.35))
		_quad(st, o0 * SHOW_R, o1 * SHOW_R, top + o1 * SHOW_R, top + o0 * SHOW_R, (o0 + o1).normalized(), Color(0.30, 0.31, 0.32))
	var seam := Color(0.07, 0.07, 0.075)
	for i in 16:
		var a := TAU * float(i) / 16.0
		var along := Vector3(sin(a), 0.0, cos(a))
		_slab(st, top + along * (1.6 + SHOW_R - 1.4) / 2.0 + Vector3.UP * 0.002, Vector3(0.06, 0.004, SHOW_R - 3.0), seam, Basis(Vector3.UP, a))
	for k in 2:
		var ring_at := SHOW_R * 0.5 if k == 0 else SHOW_R - 0.7
		var m := 64 if k == 0 else 96
		for i in m:
			var a := TAU * (float(i) + 0.5) / float(m)
			_slab(st, top + Vector3(sin(a), 0.0, cos(a)) * ring_at + Vector3.UP * 0.003, Vector3(TAU * ring_at / float(m) + 0.01, 0.005, 0.06 if k == 0 else 0.22),
				seam if k == 0 else Color(0.92, 0.72, 0.10), Basis(Vector3.UP, a))
	_slab(st, top + Vector3.UP * 0.05, Vector3(1.6, 0.1, 1.6), Color(0.12, 0.12, 0.13))      # the hub
	var deck := MeshInstance3D.new()
	deck.name = "deck"
	deck.mesh = st.commit()
	var dm := Kit.vertex_colors()
	dm.roughness = 0.7
	dm.metallic = 0.35
	deck.material_override = dm
	turntable.add_child(deck)
	_build_plate(at)
	_pose_turntable()


## The name sign: on two posts behind the turntable, facing whoever looks at it (the pilot on his stand;
## the desktop's camera when it has turned there), its foot over the far end of the craft as they see it,
## with the craft's name and a line on it. It comes and goes with the turntable.
func _build_plate(at: Vector3) -> void:
	var viewer := Vector3.ZERO if layout == "vr" else SHOW_EYE
	var to_viewer := Vector3(viewer.x - at.x, 0.0, viewer.z - at.z).normalized()
	var size: float = PLATE_SIZE[layout]
	var high: float = {"vr": 5.6, "flat": 6.8}[layout]
	plate = Node3D.new()
	plate.name = "plate"
	plate.position = -to_viewer * (SHOW_R + 5.0)
	plate.basis = Basis.looking_at(-to_viewer, Vector3.UP)      # (its +z toward the viewer)
	turntable_base.add_child(plate)
	var board := Node3D.new()
	board.name = "board"
	board.position.y = high
	plate.add_child(board)
	var st := SurfaceTool.new()      # the board itself, in its own space
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var held := SurfaceTool.new()    # what holds it up, in the plate's
	held.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:      # two posts to the ground
		_slab(held, Vector3(side * 3.4 * size, high / 2.0, -0.25), Vector3(0.35, high, 0.35), CONCRETE)
	var stand_mesh := MeshInstance3D.new()
	stand_mesh.name = "held"
	stand_mesh.mesh = held.commit()
	stand_mesh.material_override = Kit.vertex_colors()
	plate.add_child(stand_mesh)
	_slab(st, Vector3.ZERO, Vector3(8.2, 1.5, 0.12) * size, Color(0.035, 0.045, 0.07))
	_slab(st, Vector3(0.0, 0.69 * size, 0.065 * size), Vector3(8.2 * size, 0.06 * size, 0.01), Letters.STROKE)
	var face := MeshInstance3D.new()
	face.name = "face"
	face.mesh = st.commit()
	var fm := Kit.vertex_colors()
	fm.roughness = 0.6
	face.material_override = fm
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	board.add_child(face)
	for line in [["name", 96, 0.17, Letters.CREAM, 6], ["detail", 44, -0.36, Color(0.78, 0.80, 0.82), 2]]:
		var label := Label3D.new()
		label.name = line[0]
		label.font = strap_font(int(line[4]))
		label.font_size = int(line[1])
		label.outline_size = 0
		label.modulate = line[3]
		label.shaded = false
		label.double_sided = false
		label.pixel_size = 0.0068 * size
		label.position = Vector3(0.0, float(line[2]) * size, 0.07 * size)
		board.add_child(label)
	_name_plate(show_vehicle)


## What the name board says: the craft's name, and its line from the menus.
func _name_plate(vehicle: String) -> void:
	if plate == null or not Pilot.NAMES.has(vehicle):
		return
	(plate.get_node("board/name") as Label3D).text = String(Pilot.NAMES[vehicle]).to_upper()
	(plate.get_node("board/detail") as Label3D).text = Pilot.DETAILS[vehicle]


## Build the craft the menus want for the turntable over the frames that follow (or take it from those
## built already), and put it on show: with `arrive`, coming down onto the deck and swung round.
func _build_showcase(arrive := true) -> void:
	var key := _show_key()
	var vehicle := show_vehicle
	var livery := show_livery
	if not _show_cache.has(key):
		_show_job = key
		if Fleet.supports(vehicle):      # (read on another thread, not in the slice that builds it)
			await _retain_source(Fleet.ASSET_DIR + vehicle + ".glb")
			await _retain_source(Fleet.ASSET_DIR + vehicle + ".tres")
		elif vehicle == Pilot.SHRIKE:
			await _retain_source("res://art/shrike/bodywork.glb")
			await _retain_source("res://art/shrike/enamel.tres")
		else:
			await _retain_source("res://art/engine/nacelle.glb")
		# stood on the deck with its middle (half way from the pod's tail to the intake lips) over the hub
		var place := func(holder: Node3D, reach: float) -> void:
			holder.position = Vector3(-(reach - 2.0) / 2.0, SHOW_H, 0.0)
		var c := await _build_craft(vehicle, livery, "speed", turntable, "showcase_%s_%s" % [vehicle, livery], place, _show_body)
		c.key = key
		c.phase = 4.2
		_show_cache[key] = c
		_show_order.append(key)
		_show_job = ""
		if not showcase.is_empty() and key != _show_key():
			return      # (chosen past while it was built: kept for later, and the one now wanted is built next)
	var entry: Dictionary = _show_cache[key]
	if not showcase.is_empty() and showcase.key != key:
		(showcase.holder as Node3D).hide()
	showcase = entry
	(entry.holder as Node3D).show()
	_show_order.erase(key)
	_show_order.append(key)
	if arrive and reveal >= 0.4:      # (put away, it comes down as the turntable is brought up)
		_whip = 1.0
		_drop = 1.0
	_name_plate(vehicle)
	_sync_craft(0.0)
	while _show_order.size() > SHOW_KEEP:      # let the longest unused go
		var old: String = _show_order.pop_front()
		(_show_cache[old].holder as Node3D).queue_free()
		_show_cache.erase(old)


# ---- when a flight starts ----

func _exit_tree() -> void:
	# Finish the one outstanding file read, if any, before the next scene enters flight.
	_finish_source()
	_sources.clear()
	_show_cache.clear()
	# the afternoon's globals back (a flight sets its own hour over them: view/outlook.gd)
	Outlook._globals(Outlook.GLOBALS)
	# what this loaded that a flight may not want: the Shrike's bodywork and maps (unless the flight now
	# starting is in one: the menus have said so by now), and the nacelle's maps recoloured for the cover's livery
	var flown: String = load("res://view/craft_view.gd").vehicle_override
	if not _shrike_was_loaded and flown != "shrike":
		Shrike.meshes.clear()
	for key in Accent._made.keys():
		if not _accents_before.has(key):
			Accent._made.erase(key)


# ---- mesh helpers ----

## A triangle whose lit side is the side `n` points from (Godot's fronts are clockwise).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color, uvs: Array = []) -> void:
	var flip := (b - a).cross(c - a).dot(n) > 0.0
	var pts := [a, c, b] if flip else [a, b, c]
	var tex := []
	if uvs.size() == 3:
		tex = [uvs[0], uvs[2], uvs[1]] if flip else uvs
	for i in 3:
		st.set_color(col)
		st.set_normal(n)
		if not tex.is_empty():
			st.set_uv(tex[i])
		st.add_vertex(pts[i])


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color, uvs: Array = []) -> void:
	_tri(st, a, b, c, n, col, [uvs[0], uvs[1], uvs[2]] if uvs.size() == 4 else [])
	_tri(st, a, c, d, n, col, [uvs[0], uvs[2], uvs[3]] if uvs.size() == 4 else [])


## A box, `size` along `frame`'s axes, its middle at `at`.
static func _slab(st: SurfaceTool, at: Vector3, size: Vector3, col: Color, frame := Basis.IDENTITY) -> void:
	var h := size / 2.0
	for axis in 3:
		for sign in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sign
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			var v := Vector3.ZERO
			v[(axis + 2) % 3] = 1.0
			var c := n * h[axis]
			var du := u * h[(axis + 1) % 3]
			var dv := v * h[(axis + 2) % 3]
			_quad(st, at + frame * (c - du - dv), at + frame * (c + du - dv), at + frame * (c + du + dv), at + frame * (c - du + dv), frame * n, col)
