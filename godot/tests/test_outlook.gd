## Time of day and weather on the Network (Luke: "Can we also get time of day and weather
## settings?"; view/outlook.gd):
##   as built   a fair afternoon touches nothing: no record is kept, the shader globals are the project's
##   night      the sun becomes a dim cold moon with shadows, the discs give way to the moon's, the sky
##              and haze go dark, the stars come out, the towers' windows light, the headlights light
##              the road, the instruments dim; and back to the afternoon everything is as it was built
##   weather    rain: a lid of cloud, no sun's shadow, thicker fog (the land's own, set every frame,
##              follows), a wet road, the streaks; clear: no cloud deck; fair: as built again
##   elsewhere  off the Network nothing is turned, whatever is chosen
##   chosen     the menus' rows and the quick menu's lines step through the choices and save them; the
##              quick menu's turns the world where you sit
## Prints OUTLOOK PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Outlook := preload("res://view/outlook.gd")
const UI := preload("res://release/release_config.gd")
const Settings := preload("res://release/game_settings.gd")
var failures := 0


func _initialize() -> void:
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_outlook_")
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _global(name: String):      # (what Outlook last set: the rendering server gives nothing back when there is no renderer)
	return Outlook.shader_globals.get(name)


func _lights(v) -> Dictionary:
	var out := {"discs": []}
	for child in v.get_children():
		if child is WorldEnvironment:
			out["env"] = child.environment
		elif child is DirectionalLight3D and child.sky_mode == DirectionalLight3D.SKY_MODE_SKY_ONLY:
			out.discs.append(child)
		elif child is DirectionalLight3D and absf(child.rotation_degrees.y - 52.0) < 0.01:
			out["sun"] = child
	return out


func _run() -> void:
	var saved_time := Settings.choice("time", Outlook.ids(Outlook.TIMES))
	var saved_weather := Settings.choice("weather", Outlook.ids(Outlook.WEATHERS))
	View.track_override = "network"
	var v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	var L := _lights(v)
	var sun: DirectionalLight3D = L.sun
	var env: Environment = L.env
	var clouds: MeshInstance3D = v.landscape.clouds
	var lamp := v.find_child("GuideSignHeadlight", true, false) as SpotLight3D
	var built := {"energy": sun.light_energy, "rot": sun.rotation_degrees, "exposure": env.tonemap_exposure, "disc": (L.discs[0] as DirectionalLight3D).light_energy,
		"mask": lamp.light_cull_mask if lamp else 0}
	_check("as built, a fair afternoon touches nothing: no record on the view (%s), the sun at %s with %.2f, the haze global %s, dry (%s)" % [
			v.has_meta("outlook"), built.rot, built.energy, _global("sky_haze"), _global("sky_wet")],
		not v.has_meta("outlook") and is_equal_approx(built.energy, 1.35) and sun.shadow_enabled and (_global("sky_haze") as Vector3).is_equal_approx(Vector3(0.58, 0.68, 0.8))
			and is_zero_approx(float(_global("sky_wet"))) and Outlook.darkness() == 0.0 and Outlook.fog_scale() == 1.0 and clouds.visible)

	# night
	Outlook.time = "night"
	Outlook.apply(v)
	var stars := v.get_node_or_null("outlook_stars") as MeshInstance3D
	var lit_windows := 0
	var towers := 0
	for sk in v.network_world.skylines:
		for t in (sk[0] as Node).get_children():
			if t is GeometryInstance3D and t.material_override is ShaderMaterial:
				towers += 1
				lit_windows += int(is_equal_approx(float((t.material_override as ShaderMaterial).get_shader_parameter("night")), 1.0))
	_check("night: a moon of %.2f with shadows (%s), its disc %.1f and the companion's %.1f, exposure %.2f, the haze global %s, stars out (%s), %d of %d skylines' windows lit, headlights on the road (%s), darkness %.1f" % [
			sun.light_energy, sun.shadow_enabled, (L.discs[0] as DirectionalLight3D).light_energy, (L.discs[1] as DirectionalLight3D).light_energy, env.tonemap_exposure,
			_global("sky_haze"), stars != null and stars.visible, lit_windows, towers, lamp != null and (lamp.light_cull_mask & 1) == 1, Outlook.darkness()],
		sun.light_energy < 0.3 and sun.shadow_enabled and sun.rotation_degrees.x < -30.0 and (L.discs[0] as DirectionalLight3D).light_energy < 3.0 and not (L.discs[1] as DirectionalLight3D).visible
			and env.tonemap_exposure > 1.4 and (_global("sky_haze") as Vector3).length() < 0.2 and stars != null and stars.visible and towers > 0 and lit_windows == towers
			and lamp != null and (lamp.light_cull_mask & 1) == 1 and Outlook.darkness() == 1.0)
	Outlook.time = "afternoon"
	Outlook.apply(v)
	_check("and back to the afternoon it is as it was built: the sun at %s with %.2f, its disc %.1f, exposure %.2f, the stars away (%s), the headlight on the signs alone (%s), the haze global %s" % [
			sun.rotation_degrees, sun.light_energy, (L.discs[0] as DirectionalLight3D).light_energy, env.tonemap_exposure, not stars.visible, lamp.light_cull_mask == built.mask, _global("sky_haze")],
		sun.rotation_degrees.is_equal_approx(built.rot) and is_equal_approx(sun.light_energy, built.energy) and sun.shadow_enabled and is_equal_approx((L.discs[0] as DirectionalLight3D).light_energy, built.disc)
			and (L.discs[1] as DirectionalLight3D).visible and is_equal_approx(env.tonemap_exposure, built.exposure) and not stars.visible and lamp.light_cull_mask == built.mask
			and (_global("sky_haze") as Vector3).is_equal_approx(Vector3(0.58, 0.68, 0.8)) and Outlook.darkness() == 0.0)

	# weather
	v.landscape.sync(v.sim.pod.x, v.sim.pod.y)
	var fair_fog: float = env.fog_density
	Outlook.weather = "rain"
	Outlook.apply(v)
	v.landscape.sync(v.sim.pod.x, v.sim.pod.y)
	Outlook.tick(v, 1.0 / 90.0)
	var rain := v.get_node_or_null("outlook_rain") as MeshInstance3D
	var deck := clouds.material_override as ShaderMaterial
	_check("rain: the deck a lid (cover %.2f), the sun %.2f and shadowless (%s), no discs, the land's fog %.1f times the fair day's, the road wet (%s), the streaks out (%s) and riding with the eye" % [
			float(deck.get_shader_parameter("cover")), sun.light_energy, not sun.shadow_enabled, env.fog_density / fair_fog, _global("sky_wet"), rain != null and rain.visible],
		float(deck.get_shader_parameter("cover")) > 1.3 and sun.light_energy < 0.4 and not sun.shadow_enabled and not (L.discs[0] as DirectionalLight3D).visible and env.fog_density > fair_fog * 2.0
			and is_equal_approx(float(_global("sky_wet")), 1.0) and rain != null and rain.visible and rain.global_position.distance_to(v.cam.global_position) < 0.01)
	Outlook.weather = "clear"
	Outlook.apply(v)
	var clear_ok: bool = not clouds.visible and not rain.visible and is_zero_approx(float(_global("sky_wet"))) and sun.shadow_enabled
	Outlook.weather = "fair"
	Outlook.apply(v)
	v.landscape.sync(v.sim.pod.x, v.sim.pod.y)
	_check("clear: no deck, no rain, dry, shadows again (%s); fair: the deck back at its own cover %.2f, the fog as it was (%.6f against %.6f)" % [clear_ok, float(deck.get_shader_parameter("cover")), env.fog_density, fair_fog],
		clear_ok and clouds.visible and is_equal_approx(float(deck.get_shader_parameter("cover")), 0.62) and is_equal_approx(env.fog_density, fair_fog) and is_equal_approx(sun.light_energy, built.energy))

	# the quick menu turns it where you sit
	v.menu_open(true)
	var keys := []
	for item in v.menu.items:
		keys.append(item.key)
	v.menu.at = keys.find("time")
	v.menu_choose()
	var after_time := Outlook.time
	v.menu.at = keys.find("weather")
	v.menu_choose()
	_check("the quick menu's TIME and WEATHER lines take the next and turn the world: %s, %s (the sun now %.2f; the lines read %s / %s; saved %s, %s)" % [
			after_time, Outlook.weather, sun.light_energy, v.menu.items[keys.find("time")].value, v.menu.items[keys.find("weather")].value, Settings.choice("time", Outlook.ids(Outlook.TIMES)), Settings.choice("weather", Outlook.ids(Outlook.WEATHERS))],
		keys.has("time") and keys.has("weather") and after_time == "dawn" and Outlook.weather == "clear" and sun.light_energy < 1.0 and not clouds.visible and v.menu.open
			and v.menu.items[keys.find("time")].value == "DAWN" and Settings.choice("time", Outlook.ids(Outlook.TIMES)) == "dawn" and Settings.choice("weather", Outlook.ids(Outlook.WEATHERS)) == "clear")
	v.menu_open(false)
	v.queue_free()
	await process_frame

	# elsewhere
	Outlook.time = "night"
	Outlook.weather = "rain"
	View.track_override = "range"
	var r = Cockpit.new()
	root.add_child(r)
	await process_frame
	r.set_process(false)
	var RL := _lights(r)
	_check("off the Network nothing is turned: the sprint's sun %.2f, no record, the globals the project's (%s, wet %s), no darkness" % [(RL.sun as DirectionalLight3D).light_energy, _global("sky_haze"), _global("sky_wet")],
		is_equal_approx((RL.sun as DirectionalLight3D).light_energy, 1.35) and not r.has_meta("outlook") and (_global("sky_haze") as Vector3).is_equal_approx(Vector3(0.58, 0.68, 0.8))
			and is_zero_approx(float(_global("sky_wet"))) and Outlook.darkness() == 0.0 and r.get_node_or_null("outlook_rain") == null)
	r.queue_free()
	await process_frame

	# the menus' rows
	Settings.set_choice("time", "afternoon")
	Settings.set_choice("weather", "fair")
	var time_row := UI.time_button()
	var weather_row := UI.weather_button()
	root.add_child(time_row)
	root.add_child(weather_row)
	var first := [time_row.text, weather_row.text]
	time_row.pressed.emit()
	weather_row.pressed.emit()
	weather_row.pressed.emit()
	_check("the menus' rows: %s then \"%s\" (saved %s); \"%s\" after two presses (saved %s)" % [first, time_row.text, Settings.choice("time", Outlook.ids(Outlook.TIMES)), weather_row.text, Settings.choice("weather", Outlook.ids(Outlook.WEATHERS))],
		String(first[0]).ends_with("Afternoon") and String(first[1]).ends_with("Fair") and time_row.text.ends_with("Dawn") and weather_row.text.ends_with("Overcast")
			and Settings.choice("time", Outlook.ids(Outlook.TIMES)) == "dawn" and Settings.choice("weather", Outlook.ids(Outlook.WEATHERS)) == "overcast")
	Outlook.pinned = false
	Outlook.load_saved()
	_check("and a flight reads them: %s, %s" % [Outlook.time, Outlook.weather], Outlook.time == "dawn" and Outlook.weather == "overcast")
	time_row.queue_free()
	weather_row.queue_free()
	Settings.set_choice("time", saved_time)
	Settings.set_choice("weather", saved_weather)
	print("OUTLOOK %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
