## Time of day and weather on the Network (Luke: "Can we also get time of day and weather
## settings?"). The world is built for a fair afternoon, and stays exactly that unless another time or
## weather is chosen; then this turns what was built: the suns (or the moon), their discs, the sky,
## the ambient light and exposure, the haze and fog, the cloud deck, the towers' windows, the stars,
## the headlights, the wet road and the rain. Shaders that draw their own haze or sun read the
## project's shader globals (project.godot [shader_globals], whose defaults are the afternoon).
##   Outlook.apply(view)          once the world is built, and again whenever a choice changes
##   Outlook.tick(view, delta)    every frame: the rain streams past at the craft's speed
##   Outlook.darkness()           0 by day .. 1 at night: what the lit things go by
##   Outlook.fog_scale(), Outlook.haze(colour)   the land's own fog, which it sets every frame
## Only the Network, and not the emergency run's own twilight. Elsewhere apply() puts the globals
## back to the afternoon and touches nothing.
extends RefCounted

const Settings := preload("res://release/game_settings.gd")
const TIMES := [["afternoon", "Afternoon"], ["dawn", "Dawn"], ["noon", "Noon"], ["dusk", "Dusk"], ["night", "Night"]]         # the menus' rows: [id, name]
const WEATHERS := [["fair", "Fair"], ["clear", "Clear"], ["overcast", "Overcast"], ["fog", "Fog"], ["rain", "Rain"], ["snow", "Snow"]]

## What a time of day changes from the afternoon. sun, sun2: [degrees down from level (negative is
## up, as Node3D rotation), bearing, colour, energy]; disc: the suns' discs in the sky, of what
## they were; zenith, horizon: the sky's two colours (the horizon's is the haze's); ambient: [how
## much of it is the sky's, energy]; stars 0..1; night 0..1.
const TIME := {
	"afternoon": {},
	"dawn": {"sun": [-6.0, 52.0, Color(1.0, 0.66, 0.46), 0.80], "sun2": [-2.5, 61.0, Color(1.0, 0.46, 0.26), 0.22], "disc": 0.5,
		"zenith": Color(0.11, 0.20, 0.48), "horizon": Color(0.93, 0.64, 0.52), "ambient": [0.9, 0.85], "exposure": 1.30, "stars": 0.2, "night": 0.3,
		"cloud_lit": Color(1.0, 0.74, 0.62), "cloud_shade": Color(0.30, 0.30, 0.46), "glow": [Color(1.0, 0.72, 0.52), Color(1.0, 0.48, 0.24)]},
	"noon": {"sun": [-63.0, 52.0, Color(1.0, 0.99, 0.96), 1.55], "sun2": [-57.0, 62.0, Color(1.0, 0.80, 0.60), 0.35], "disc": 1.0,
		"zenith": Color(0.13, 0.33, 0.80), "horizon": Color(0.62, 0.73, 0.86), "ambient": [0.75, 0.8], "exposure": 1.16, "stars": 0.0, "night": 0.0,
		"cloud_lit": Color(1.0, 0.99, 0.97), "cloud_shade": Color(0.30, 0.36, 0.50)},
	"dusk": {"sun": [-4.5, 52.0, Color(1.0, 0.50, 0.24), 0.85], "sun2": [-9.0, 60.0, Color(1.0, 0.40, 0.20), 0.30], "disc": 0.6,
		"zenith": Color(0.09, 0.13, 0.36), "horizon": Color(0.97, 0.50, 0.28), "ambient": [0.9, 0.8], "exposure": 1.32, "stars": 0.3, "night": 0.45,
		"cloud_lit": Color(1.0, 0.60, 0.40), "cloud_shade": Color(0.24, 0.22, 0.40), "glow": [Color(1.0, 0.56, 0.30), Color(1.0, 0.40, 0.18)]},
	# (the "sun" is the moon: a cold light high on the same bearing, with shadows; the companion is down)
	"night": {"sun": [-40.0, 52.0, Color(0.56, 0.67, 1.0), 0.13], "sun2": [-24.0, 60.0, Color(1.0, 0.72, 0.45), 0.0], "disc": 0.0, "moon": 1.6,
		"zenith": Color(0.008, 0.013, 0.036), "horizon": Color(0.034, 0.050, 0.095), "ambient": [1.0, 3.0], "exposure": 1.5, "stars": 1.0, "night": 1.0,
		"cloud_lit": Color(0.065, 0.08, 0.125), "cloud_shade": Color(0.012, 0.016, 0.03), "glow": [Color(0.30, 0.36, 0.55), Color(0, 0, 0)]},
}
## What the weather changes. clouds: 0 hides the deck; cover: the deck's (0.62 fair, 1.5 a lid);
## grey, dim: the sky's colours drawn toward their own grey, and darkened; sun: the suns' light, of
## what the time gives; shadows; disc; fog: the fog and haze, thickened by this; sky_fog: how far the
## fog takes the sky itself; wet: the road; rain: the streaks.
const WEATHER := {
	"fair": {},
	"clear": {"clouds": 0.0},
	"overcast": {"cover": 1.5, "grey": 0.82, "dim": 0.80, "sun": 0.22, "shadows": false, "disc": 0.0, "fog": 1.6, "cirrus": 0.0, "sky_fog": 0.25},
	"fog": {"clouds": 0.0, "grey": 0.90, "dim": 0.92, "sun": 0.32, "shadows": false, "disc": 0.0, "fog": 5.0, "sky_fog": 0.9},
	"rain": {"cover": 1.6, "grey": 0.86, "dim": 0.52, "sun": 0.15, "shadows": false, "disc": 0.0, "fog": 2.6, "cirrus": 0.0, "sky_fog": 0.5, "wet": 1.0, "rain": 1.0},
	# snow: a bright grey sky (snow light: not rain's gloom), thick air, flakes, and snow lying ("white": the land, the props, the road in blown streaks)
	"snow": {"cover": 1.5, "grey": 0.92, "dim": 0.90, "sun": 0.28, "shadows": false, "disc": 0.0, "fog": 2.4, "cirrus": 0.0, "sky_fog": 0.6, "snow": 1.0, "white": 1.0},
}
const AFTERNOON_HAZE := Color(0.58, 0.68, 0.80)      # the Network's own, as the land's fog and the shaders have it
const CLOUDS := {"cover": 0.62, "cirrus": 0.42, "lit_col": Vector3(1.0, 0.975, 0.93), "shade_col": Vector3(0.27, 0.33, 0.46)}   # the deck's own (view/network_clouds.gdshader)
const GLOBALS := {"sky_sun": Vector3(0.6824, 0.5, 0.5332), "sky_sun2": Vector3(0.7911, 0.4067, 0.4568), "sky_sun_glow": Vector3(1.0, 0.93, 0.8),
	"sky_sun2_glow": Vector3(1.0, 0.6, 0.28), "sky_haze": Vector3(0.58, 0.68, 0.8), "sky_haze_scale": 1.0, "sky_wet": 0.0, "sky_snow": 0.0}      # as project.godot has them
const RAIN_DROPS := 900
const RAIN_BOX := Vector3(22.0, 12.0, 90.0)          # the streaks' box round the eye: across, up, ahead (m)

static var time := "afternoon"
static var weather := "fair"
static var pinned := false       # a test or a render chose them: the saved choices do not replace them
static var _fog := 1.0
static var _snowing := false     # the box of quads is flakes, not streaks
static var _sky_mat: ShaderMaterial      # the sky's own material, and what the hour and weather last gave it (for _aloft)
static var _zenith_now := Color(0.19, 0.39, 0.78)
static var _starlight_now := 0.0
static var _grey_now := 0.0
static var _aloft_was := -1.0
static var _aloft_view := 0      # the flight whose sky _sky_mat is
static var _applied := false     # apply() found and set this flight's sky (false: the world as built)
static var aloft := 0.0          # how far over the air the eye is: 0 to 6 km, 0.6 at 10 km, 0.9 at 16 km
static var _thin := 1.0          # the eye's height's part in the haze (thin_air)
const AIR_H := 3500.0            # m: the air's scale height (view/air.gdshaderinc has the same)
static var _haze_gain := Color(1, 1, 1)
static var _night := 0.0
static var _travel := 0.0
static var shader_globals := {}   # what the shaders' project-wide inputs were last set to (tests read this: the server gives nothing back without a renderer)


static func ids(rows: Array) -> Array:
	return rows.map(func(entry): return entry[0])


## The menus' saved choices (unless pinned).
static func load_saved() -> void:
	if not pinned:
		time = Settings.choice("time", ids(TIMES))
		weather = Settings.choice("weather", ids(WEATHERS))


static func darkness() -> float:
	return _night


static func fog_scale() -> float:
	return _fog


## The air thins with height (view/air.gdshaderinc, whose twin this is): how much of it lies along a
## line of sight between two altitudes, against the same length of line at the ground.
static func air_between(a: float, b: float) -> float:
	a = maxf(a, 0.0)
	b = maxf(b, 0.0)
	var d := absf(b - a)
	if d < 1.0:
		return exp(-a / AIR_H)
	return AIR_H * absf(exp(-a / AIR_H) - exp(-b / AIR_H)) / d


## The eye's height thins the land's haze (NetworkLandscape.sync, every frame): the shaders' haze scale
## is the weather's times this. (shader_globals keeps the weather's own.)
static func thin_air(factor: float) -> void:
	if absf(factor - _thin) < 0.002:
		return
	_thin = factor
	RenderingServer.global_shader_parameter_set("sky_haze_scale", minf(_fog, 3.5) * _thin)


## The land's fog colour for a place, as the hour and weather have it (it is given the afternoon's).
static func haze(afternoon: Color) -> Color:
	return Color(afternoon.r * _haze_gain.r, afternoon.g * _haze_gain.g, afternoon.b * _haze_gain.b)


static func _weathered(c: Color, w: Dictionary) -> Color:
	var g := c.get_luminance()
	return c.lerp(Color(g, g, g), float(w.get("grey", 0.0))) * float(w.get("dim", 1.0))


static func _to(rot: Vector3) -> Vector3:      # the way to a light, from its rotation in degrees
	return Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z))).z


static func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


static func _globals(values: Dictionary) -> void:
	for name in values:
		RenderingServer.global_shader_parameter_set(name, values[name])
		shader_globals[name] = values[name]
	if values.has("sky_haze_scale"):
		_thin = 1.0      # (set afresh: the eye's height thins it again at the next frame)


## What was built, found once and kept on the view: the nodes, and their afternoon values.
static func _record(view) -> Dictionary:
	var base := {"discs": [], "towers": []}
	for child in view.get_children():
		if child is WorldEnvironment:
			base["env"] = child.environment
		elif child is DirectionalLight3D and child.sky_mode == DirectionalLight3D.SKY_MODE_SKY_ONLY:
			base.discs.append([child, child.light_color, child.light_energy])
		elif child is DirectionalLight3D:
			base["sun" if child.shadow_enabled else "sun2"] = [child, child.rotation_degrees, child.light_color, child.light_energy]
	var env: Environment = base.get("env")
	if env == null or not base.has("sun") or not base.has("sun2") or base.discs.size() != 2:
		return {}
	base["sky"] = env.sky.sky_material as ShaderMaterial
	if base.sky == null:
		return {}
	for key in ["zenith", "horizon", "ground"]:
		base[key] = base.sky.get_shader_parameter(key)
	for key in ["ambient_light_sky_contribution", "ambient_light_energy", "tonemap_exposure", "fog_sky_affect", "glow_intensity"]:
		base[key] = env.get(key)
	var landscape = view.get("landscape")
	if landscape != null and landscape.get("clouds") != null:
		base["clouds"] = landscape.clouds
	var world = view.get("network_world")
	if world != null:
		for sk in world.skylines:
			for towers in (sk[0] as Node).get_children():
				if towers is GeometryInstance3D and towers.material_override is ShaderMaterial:
					base.towers.append(towers.material_override)
	var lamp := view.find_child("GuideSignHeadlight", true, false) as SpotLight3D
	if lamp:
		base["lamp"] = [lamp, lamp.light_cull_mask, lamp.light_energy, lamp.spot_range, lamp.light_specular]
	return base


## Turn the world to the chosen time and weather (or back to the afternoon it was built for).
static func apply(view) -> void:
	var on: bool = view.sim.kind == "network" and view.light_preset == "afternoon"
	var t: Dictionary = TIME[time] if on else {}
	var w: Dictionary = WEATHER[weather] if on else {}
	var base: Dictionary = view.get_meta("outlook", {})
	if base.is_empty():
		if t.is_empty() and w.is_empty():      # the world as built: nothing found, nothing touched
			_applied = false
			_aloft_view = 0
			_globals(GLOBALS)
			_fog = 1.0
			_haze_gain = Color(1, 1, 1)
			_night = 0.0
			return
		base = _record(view)
		if base.is_empty():
			push_warning("Outlook: this world has no suns and sky of the afternoon's kind; left as built.")
			return
		view.set_meta("outlook", base)
	var env: Environment = base.env
	var dim: float = float(w.get("sun", 1.0))
	# the suns (or the moon)
	var sun_to := Vector3.ZERO
	var sun2_to := Vector3.ZERO
	for which in ["sun", "sun2"]:
		var was: Array = base[which]
		var now: Array = t.get(which, [was[1].x, was[1].y, was[2], was[3]])
		var light: DirectionalLight3D = was[0]
		light.rotation_degrees = Vector3(now[0], now[1], 0.0)
		light.light_color = now[2]
		light.light_energy = float(now[3]) * dim
		light.visible = light.light_energy > 0.001
		if which == "sun":
			light.shadow_enabled = bool(w.get("shadows", true)) and light.visible
			sun_to = _to(light.rotation_degrees)
		else:
			sun2_to = _to(light.rotation_degrees)
		var disc: Array = base.discs[0 if which == "sun" else 1]
		var face: DirectionalLight3D = disc[0]
		face.rotation_degrees = light.rotation_degrees
		var shown: float = float(t.get("disc", 1.0)) * float(w.get("disc", 1.0))
		face.light_color = (disc[1] as Color).lerp(now[2], 0.0 if t.is_empty() else 0.55)
		face.light_energy = float(disc[2]) * shown
		if which == "sun" and t.has("moon"):          # the moon's own small cold disc
			face.light_color = Color(0.82, 0.88, 1.0)
			face.light_energy = float(t.moon) * float(w.get("disc", 1.0))
		face.visible = face.light_energy > 0.001
	# the sky, and with it the haze
	var zenith: Color = _weathered((t.get("zenith", base.zenith) as Color).lerp(t.get("horizon", base.horizon), 0.55 * float(w.get("grey", 0.0))), w)
	var horizon: Color = _weathered(t.get("horizon", base.horizon), w)
	var level: float = clampf(horizon.get_luminance() / maxf((base.horizon as Color).get_luminance(), 0.001), 0.03, 1.3)
	(base.sky as ShaderMaterial).set_shader_parameter("zenith", zenith)
	_sky_mat = base.sky
	_applied = true
	_aloft_view = view.get_instance_id()
	_zenith_now = zenith
	_grey_now = float(w.get("grey", 0.0))
	_aloft_was = -1.0
	(base.sky as ShaderMaterial).set_shader_parameter("horizon", horizon)
	(base.sky as ShaderMaterial).set_shader_parameter("ground", (base.ground as Color) * level)
	var amb: Array = t.get("ambient", [base.ambient_light_sky_contribution, base.ambient_light_energy])
	env.ambient_light_sky_contribution = maxf(float(amb[0]), 1.0 if w.has("grey") else 0.0)
	env.ambient_light_energy = float(amb[1])
	env.tonemap_exposure = float(t.get("exposure", base.tonemap_exposure))
	env.fog_sky_affect = float(w.get("sky_fog", base.fog_sky_affect))
	env.glow_intensity = float(base.glow_intensity) + 0.15 * float(t.get("night", 0.0))
	_night = float(t.get("night", 0.0))
	_fog = float(w.get("fog", 1.0))
	_haze_gain = Color(horizon.r / AFTERNOON_HAZE.r, horizon.g / AFTERNOON_HAZE.g, horizon.b / AFTERNOON_HAZE.b)
	var glow: Array = t.get("glow", [Color(1.0, 0.93, 0.8), Color(1.0, 0.6, 0.28)])
	var suns: float = float(t.get("disc", 1.0)) * float(w.get("disc", 1.0)) if not t.has("moon") else 0.35 * float(w.get("disc", 1.0))
	_globals({"sky_sun": sun_to, "sky_sun2": sun2_to, "sky_sun_glow": _v3(glow[0]) * suns, "sky_sun2_glow": _v3(glow[1]) * suns,
		"sky_haze": _v3(horizon), "sky_haze_scale": minf(_fog, 3.5), "sky_wet": float(w.get("wet", 0.0)), "sky_snow": float(w.get("white", 0.0))})
	# the cloud deck
	if base.has("clouds"):
		var deck: MeshInstance3D = base.clouds
		deck.visible = float(w.get("clouds", 1.0)) > 0.0
		var m := deck.material_override as ShaderMaterial
		var lit: Color = _weathered(t.get("cloud_lit", Color(1.0, 0.975, 0.93)), {"grey": float(w.get("grey", 0.0)) * 0.7, "dim": lerpf(1.0, float(w.get("dim", 1.0)), 0.8)})
		var shade: Color = _weathered(t.get("cloud_shade", Color(0.27, 0.33, 0.46)), {"grey": float(w.get("grey", 0.0)) * 0.7, "dim": float(w.get("dim", 1.0))})
		m.set_shader_parameter("cover", float(w.get("cover", CLOUDS.cover)))
		m.set_shader_parameter("cirrus", float(w.get("cirrus", CLOUDS.cirrus)))
		m.set_shader_parameter("lit_col", _v3(lit))
		m.set_shader_parameter("shade_col", _v3(shade))
		m.set_shader_parameter("zenith", zenith)
		m.set_shader_parameter("horizon", horizon)
	# the cities' towers: their haze and sky, and their windows by night
	for towers: ShaderMaterial in base.towers:
		towers.set_shader_parameter("haze_col", _v3(horizon))
		towers.set_shader_parameter("zenith", _v3(zenith))
		towers.set_shader_parameter("suns", suns)
		towers.set_shader_parameter("night", _night)
	# the stars
	var stars := view.get_node_or_null("outlook_stars") as MeshInstance3D
	var starlight: float = float(t.get("stars", 0.0)) * (1.0 - float(w.get("grey", 0.0))) * (0.0 if w.has("sky_fog") and float(w.sky_fog) > 0.6 else 1.0)
	_starlight_now = starlight
	if stars == null:      # (always there: from high up they show by day: _aloft)
		stars = _stars(view)
	if stars:
		stars.visible = starlight > 0.0
		(stars.material_override as ShaderMaterial).set_shader_parameter("fade", starlight)
	# the headlights: by night the lamp that lights the signs' sheeting lights the road as well
	if base.has("lamp"):
		var lamp: SpotLight3D = base.lamp[0]
		var lit_road: bool = _night > 0.6
		lamp.light_cull_mask = (int(base.lamp[1]) | 1) if lit_road else int(base.lamp[1])
		lamp.light_energy = 3.5 if lit_road else float(base.lamp[2])
		lamp.spot_range = 900.0 if lit_road else float(base.lamp[3])
		lamp.light_specular = 0.5 if lit_road else float(base.lamp[4])
	# the rain
	var falling: float = maxf(float(w.get("rain", 0.0)), float(w.get("snow", 0.0)))      # (the same box of quads: streaks, or flakes)
	_snowing = float(w.get("snow", 0.0)) > 0.0
	var rain := view.get_node_or_null("outlook_rain") as MeshInstance3D
	if rain == null and falling > 0.0:
		rain = _rain()
		view.add_child(rain)
	if rain:
		rain.visible = falling > 0.0
		(rain.material_override as ShaderMaterial).set_shader_parameter("snow", 1.0 if _snowing else 0.0)
		(rain.material_override as ShaderMaterial).set_shader_parameter("tint", _v3(horizon.lerp(Color(1, 1, 1), 0.5)))


## The rain's streaks: thin quads in a box that rides with the eye; the shader streams them through it.
static func _rain() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	for k in RAIN_DROPS:
		var at := Vector3(rng.randf_range(-0.5, 0.5) * RAIN_BOX.x, rng.randf_range(-0.5, 0.5) * RAIN_BOX.y, -rng.randf() * RAIN_BOX.z)
		var seed := rng.randf()
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
			st.set_uv(corner)
			st.set_color(Color(seed, 0, 0))
			st.add_vertex(at)
	var mi := MeshInstance3D.new()
	mi.name = "outlook_rain"
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = preload("res://view/rain.gdshader")
	m.set_shader_parameter("box", RAIN_BOX)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	return mi


## Every frame: the rain rides with the eye and streams past at the craft's own speed.
## The stars' dome, made when first wanted.
static func _stars(view) -> MeshInstance3D:
	var stars := view.get_node_or_null("outlook_stars") as MeshInstance3D
	if stars != null:
		return stars
	stars = MeshInstance3D.new()
	stars.name = "outlook_stars"
	var dome := SphereMesh.new()
	dome.radius = 110000.0
	dome.height = 220000.0
	dome.radial_segments = 48
	dome.rings = 24
	stars.mesh = dome
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://view/stars.gdshader")
	sm.set_shader_parameter("dawn_dir", Vector3.DOWN)      # no dawn on any side: the whole dome
	sm.set_shader_parameter("fade", 0.0)
	stars.material_override = sm
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stars.extra_cull_margin = 16384.0
	stars.visible = false
	view.add_child(stars)
	return stars


## The sky from high up. Over most of the air its blue goes to near black overhead while the horizon
## keeps its pale band, and the stars are out at noon. (Luke: "plateau over the top to something
## spectacular": the top of Helios is 16 km up.)
static func _aloft(view) -> void:
	if view.cam == null:
		return
	if _aloft_view != view.get_instance_id():      # a new flight: its own sky (the world as built is not recorded by apply)
		_aloft_view = view.get_instance_id()
		_aloft_was = -1.0
		if not _applied:
			_sky_mat = null
			_starlight_now = 0.0
			_grey_now = 0.0
			for child in view.get_children():
				if child is WorldEnvironment and child.environment != null and child.environment.sky != null:
					_sky_mat = child.environment.sky.sky_material as ShaderMaterial
			if _sky_mat != null and _sky_mat.get_shader_parameter("zenith") is Color:
				_zenith_now = _sky_mat.get_shader_parameter("zenith")
			else:
				_sky_mat = null
	if _sky_mat == null:
		return
	var height: float = (view.cam as Camera3D).global_position.y
	aloft = 1.0 - exp(-maxf(height - 6000.0, 0.0) / 4200.0)
	if absf(aloft - _aloft_was) < 0.004:
		return
	_aloft_was = aloft
	_sky_mat.set_shader_parameter("zenith", _zenith_now.lerp(_zenith_now * 0.07, aloft))
	var light := maxf(_starlight_now, aloft * aloft * (1.0 - _grey_now))
	var stars := view.get_node_or_null("outlook_stars") as MeshInstance3D
	if stars == null and light > 0.01:
		stars = _stars(view)
	if stars:
		stars.visible = light > 0.01
		(stars.material_override as ShaderMaterial).set_shader_parameter("fade", light)


static func tick(view, delta: float) -> void:
	_aloft(view)
	var rain := view.get_node_or_null("outlook_rain") as MeshInstance3D
	if rain == null or not rain.visible or view.cam == null:
		return
	var p = view.sim.pod
	var speed: float = Vector2(p.vx, p.vy).length()
	_travel = fposmod(_travel + (speed + 14.0) * delta, RAIN_BOX.z)
	rain.global_transform = (view.cam as Camera3D).global_transform
	var m := rain.material_override as ShaderMaterial
	m.set_shader_parameter("travel", _travel)
	m.set_shader_parameter("speed", speed)
	m.set_shader_parameter("fall", fposmod(Time.get_ticks_msec() / 1000.0 * (1.7 if _snowing else 9.0), RAIN_BOX.y))      # (flakes drift down; rain falls)
