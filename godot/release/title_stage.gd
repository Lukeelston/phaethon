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
## It lives in the menu's scene and nowhere else, so a flight starts with all of it freed (and what it
## loaded that a flight may not want is let go: _exit_tree); back at the menu it is built again.
##   var stage := TitleStage.make("vr"); add_child(stage)      null with `enabled` off (timings, tests), or the game
##                                    started with -- --no-title: the menus are then exactly as they were
##   stage.place(eye, forward)        VR: stand it under the pilot's eye, facing the way he faces
##   stage.frame(art, window)         flat: aim the camera so the picture's middle is that part of the window's
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

static var enabled := true       # (timings and tests: off, the menus are as they were before the title)

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
var build_ms := 0
var build_split := {}            # ... and where it went, ms: {"sky", "land", "roads", "structures", "craft and word"}
var _clock := 0.0
var _frame := 0
var _shrike_was_loaded := false
var _accents_before := {}
var _globals_at := Basis.IDENTITY


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
	var t0 := Time.get_ticks_msec()
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
	_build_sky()
	build_split["sky"] = Time.get_ticks_msec() - t0
	_build_land()
	_build_skyline()
	build_split["land"] = Time.get_ticks_msec() - t0 - int(build_split.sky)
	var t1 := Time.get_ticks_msec()
	_build_roads()
	build_split["roads"] = Time.get_ticks_msec() - t1
	t1 = Time.get_ticks_msec()
	_build_structures()
	if layout == "vr":
		_build_stand()
	build_split["structures"] = Time.get_ticks_msec() - t1
	t1 = Time.get_ticks_msec()
	if layout == "vr":
		# a craft on either hand, each nose-in along its own line to the pilot, clear of the board's edges
		_add_craft("phaethon", "boxcover", "speed", _radial(VR_BERTHS[0][0], VR_BERTHS[0][1]), deg_to_rad(VR_BERTHS[0][0]))
		_add_craft("shrike", "ember", "starfighter", _radial(VR_BERTHS[1][0], VR_BERTHS[1][1]), deg_to_rad(VR_BERTHS[1][0]))
		# the word: 78 m off and 11.5 m high, over the board's top edge, its far end away to the right and a little up
		_build_word(Vector3(0.0, EYE + 78.0 * tan(deg_to_rad(17.3)), -78.0), 11.5, Vector3(0.10, deg_to_rad(22.0), deg_to_rad(7.0)))
	else:
		# the cover's blocking: the two abreast and coming on, the camera between and over them, close, through
		# a wide lens; and the word as the cover has it, measured off the picture: its near end low on the left,
		# running away up to the right at 12 degrees, twice as far off at its far end
		_add_craft("phaethon", "boxcover", "speed", FLAT_BERTHS[0], 0.0)
		_add_craft("shrike", "ember", "starfighter", FLAT_BERTHS[1], 0.0)
		_build_word(FLAT_EYE + Vector3(9.4, 15.3, -43.5), 10.0, Vector3(0.15, deg_to_rad(20.7), deg_to_rad(11.6)))
		camera = Camera3D.new()
		camera.name = "TitleCamera"
		camera.position = FLAT_EYE
		camera.rotation_degrees = Vector3(-FLAT_PITCH, 0.0, 0.0)
		camera.near = 0.1
		camera.far = 200000.0
		camera.fov = 70.0
		add_child(camera)
	_sync_craft(0.0)
	build_split["craft and word"] = Time.get_ticks_msec() - t1
	build_ms = Time.get_ticks_msec() - t0


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
	cm.set_shader_parameter("cloud_cover", load("res://art/sky/cloud_cover.png"))
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
	# the holder's +x is the craft's nose (the range runs along +x): turn it to face the pilot, and stand its
	# pod so far back that the engines' noses come to `nose`
	var heading := Basis(Vector3.UP, -az) * Vector3(0.0, 0.0, 1.0)
	var reach: float = sim.eL.x - sim.pod.x + 3.85      # the pod's middle to the intake lips
	var holder := Node3D.new()
	holder.name = "craft_" + vehicle
	holder.basis = Basis(heading, Vector3.UP, heading.cross(Vector3.UP))
	holder.position = nose - heading * reach
	world.add_child(holder)
	var own := Livery.current
	Livery.current = livery      # (a craft's colours are in its meshes: built in its livery, then back)
	var model = ModelScript.new()
	model.name = "model"
	holder.add_child(model)
	model.build(berth)
	Livery.current = own
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
	craft.append({"holder": holder, "model": model, "sim": sim, "berth": berth, "inp": {"brkL": 0.0, "brkR": 0.0, "park": false},
		"phase": float(craft.size()) * 2.1, "rest": holder.position, "owed": 0.0})


func _sync_craft(delta: float) -> void:
	_frame += 1
	for i in craft.size():
		var c: Dictionary = craft[i]
		# idling: the craft rides its repulsors (every frame: the whole of it moves as one) ...
		(c.holder as Node3D).position = (c.rest as Vector3) + Vector3(0.0, BOB * sin(_clock * 1.1 + float(c.phase)), 0.0)
		c.owed = float(c.owed) + delta
		if delta > 0.0 and (i + _frame) % craft.size() != 0:
			continue      # ... and its moving parts are posed a craft a frame, turn about: fans and arcs ten metres off do not show it, and it is half the work
		var sim = c.sim
		var lever := IDLE + 0.035 * sin(_clock * 0.8 + float(c.phase))      # the levers breathe a little
		sim.eL.thrust = lever
		sim.eR.thrust = lever + 0.012 * sin(_clock * 1.7 + float(c.phase))
		c.model.sync(sim, c.inp, float(c.owed))
		c.model.sync_cables(sim, maxf(float(c.owed), 1.0 / 240.0))
		c.owed = 0.0


func _process(delta: float) -> void:
	_clock += delta
	_sync_craft(delta)
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
	var near := camera.near
	var per_unit := 2.0 * near * tan(deg_to_rad(across) / 2.0) / art.size.x      # m on the near plane per unit of window
	var middle := art.get_center() - window / 2.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.set_frustum(window.y * per_unit, Vector2(-middle.x, middle.y) * per_unit, near, camera.far)


# ---- when a flight starts ----

func _exit_tree() -> void:
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
