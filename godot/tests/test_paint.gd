## Every pilot craft takes a paint (Luke, 2026-11-23: "Will you make it so that all vehicles can have a color
## option?"; view/livery.gd, view/fleet_airframe.gd, view/shrike_airframe.gd, view/fleet_finish.gdshader,
## tools/art_livery_masks.py):
##   rows       every craft's paint row starts at Factory; the Phaethon's has no second Ember (its Factory is
##              Ember); each craft is saved under its own key, the Phaethon's the "paint" it always had
##   carried    a paint saved before is the Phaethon's still; the others start at Factory
##   menus      the paint row steps the chosen craft's own paint, round and back, for every craft, leaving the
##              others' alone; in both menus it shows each craft's own as the pilot craft changes
##   colours    the fleet's own colours, as fleet_airframe.gd has them, are what their atlases are painted in;
##              the Shrike's too
##   built      every craft in Factory, Ember, Cobalt and Sunflower: Factory as it was built before (its own
##              finish, meshes and materials, nothing repainted; the Phaethon's Factory hull is Ember's); a
##              livery repaints with the craft's own mask and the livery's colours, set when it is built and
##              left alone a frame after; the Shrike's pod, piping and coaming in its paint
##   flights    unpinned, a flight builds each craft in the menus' choice for that craft
##   pixels     (needs a window) the legacy finish path draws exactly as eddf4f7's shader did; the refined
##              Factory finish changes painted regions only, and keeps its material profile in a livery; in a
##              livery its enamel takes the paint's hue with its own light and dark (not a flat fill), and
##              its metal, rubber, ceramic, cloth, vent and printed tiles do not move a step
##   turntable  the title's turntable shows a fleet craft in its own paint, and a press of the paint row
##              re-dresses it
## Uses its own prefs file; puts the game's and the cockpit's back as it found them.
## Run windowed: --xr-mode off -s res://tests/test_paint.gd -- --mute. Prints PAINT PASS.
extends SceneTree

const Livery := preload("res://view/livery.gd")
const Settings := preload("res://release/game_settings.gd")
const UI := preload("res://release/release_config.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Fleet := preload("res://view/fleet_airframe.gd")
const Shrike := preload("res://view/shrike_airframe.gd")
const CM := preload("res://view/craft_model.gd")
const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Stage := preload("res://release/title_stage.gd")
const Accent := preload("res://view/accent.gd")
const Interior := preload("res://vr/cockpit_interior.gd")
const PREFS := "user://test_paint_prefs.cfg"
const LIVERIES := ["factory", "ember", "cobalt", "sunflower"]
const DT := 1.0 / 120.0
# The fleet's finish as eddf4f7 drew it (view/fleet_finish.gdshader there): Factory must draw exactly so.
const EDDF4F7_FINISH := """shader_type spatial;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_map : filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 enamel : source_color = vec4(1.0);
uniform bool repaint = false;
uniform float normal_depth = 0.74;
uniform float occlusion_on_light : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	vec3 base = texture(albedo_map, UV).rgb;
	vec3 finish = texture(orm_map, UV).rgb;
	if (repaint) {
		ivec2 tile = ivec2(floor(UV * 4.0));
		bool painted = tile == ivec2(0, 0) || tile == ivec2(2, 2);
		float grain = dot(base, vec3(0.2126, 0.7152, 0.0722));
		base = painted ? enamel.rgb * clamp(0.65 + grain, 0.65, 1.35) : base;
	}
	ALBEDO = base;
	AO = finish.r * COLOR.a;
	AO_LIGHT_AFFECT = occlusion_on_light;
	METALLIC = finish.b;
	vec3 dndx = dFdx(NORMAL);
	vec3 dndy = dFdy(NORMAL);
	float kernel = min(0.5 * (dot(dndx, dndx) + dot(dndy, dndy)), 0.18);
	float alpha2 = finish.g * finish.g * finish.g * finish.g;
	ROUGHNESS = sqrt(sqrt(clamp(alpha2 + kernel, 0.0, 1.0)));
	NORMAL_MAP = texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
}
"""
# the fleet atlas's tiles a livery leaves alone, [column, row] (tools/art_pilot_fleet_finish.py TILES): alloy,
# dark, gold, rubber, ceramic, cloth, vent, brushed; and the badge's row
const KEPT_TILES := [[2, 0], [3, 0], [0, 1], [1, 1], [2, 1], [3, 1], [0, 2]]

var failures := 0
var saved := {}


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> bool:
	print(("PASS " if ok else "FAIL ") + label)
	failures += int(not ok)
	return ok


func _clear_prefs() -> void:
	if FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))


func _run() -> void:
	for path in [Settings.PREFS, Cockpit.PREFS]:
		saved[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	Settings.prefs_path = PREFS
	_clear_prefs()
	View.track_override = "range"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_paint_")
	_rows()
	_carried()
	await _menus()
	_colours()
	unload_current_scene()
	await process_frame
	await _built()
	await _flights()
	if check("a window to draw in (run with -Windowed)", DisplayServer.get_name() != "headless"):
		await _pixels()
	await _turntable()
	Livery.pinned = false
	Livery.current = Livery.FACTORY
	_clear_prefs()
	Settings.prefs_path = Settings.PREFS
	for path in saved:
		if saved[path] == null:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(saved[path])
			file.close()
	print("PAINT %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(int(failures > 0))


# ---- the row and what it saves ----

func _rows() -> void:
	var wrong := []
	var keys := {}
	for craft: String in Pilot.ORDER:
		var ids := Livery.ids_for(craft)
		var phaethon := craft == Pilot.STANDARD
		var right: bool = ids[0] == Livery.FACTORY and not ids.has("police") and not ids.has("boxcover") \
			and (ids.size() == Livery.CHOICES.size() - 1 and not ids.has("ember") if phaethon else ids.size() == Livery.CHOICES.size() + Livery.OWN.get(craft, []).size() and ids.has("ember"))
		if not right:
			wrong.append("%s %s" % [craft, ids])
		keys[Livery.key_for(craft)] = craft
	check("every craft's paint row starts at Factory; the Phaethon's has no second Ember, the others all eight paints (and their own: the Vesper's Star Command) (wrong: %s)" % [wrong], wrong.is_empty())
	check("each craft saves its own paint, the Phaethon's under the \"paint\" it always had (%s)" % [keys],
		keys.size() == Pilot.ORDER.size() and keys.get("paint") == Pilot.STANDARD)


func _carried() -> void:
	_clear_prefs()
	Settings.set_choice("paint", "cobalt")      # a choice saved before every craft had one
	var others := []
	for craft: String in Pilot.ORDER:
		if craft != Pilot.STANDARD:
			others.append(Livery.saved_for(craft))
	check("a paint saved before is the Phaethon's (%s, built in %s); the others start at Factory (%s)" % [Livery.saved_for(Pilot.STANDARD), Livery.built(Pilot.STANDARD), others],
		Livery.saved_for(Pilot.STANDARD) == "cobalt" and Livery.built(Pilot.STANDARD) == "cobalt" and others.all(func(id): return id == Livery.FACTORY)
			and Livery.built(Pilot.KILN) == Livery.FACTORY)
	Settings.set_choice("paint", "ember")       # the old default: the Phaethon's Factory
	Settings.set_choice("paint_kiln", "police")  # not on any row
	check("a saved Ember is the Phaethon's Factory, built in Ember (%s, %s); a paint not on the row is Factory (%s)" % [Livery.saved_for(Pilot.STANDARD), Livery.built(Pilot.STANDARD), Livery.saved_for(Pilot.KILN)],
		Livery.saved_for(Pilot.STANDARD) == Livery.FACTORY and Livery.built(Pilot.STANDARD) == "ember" and Livery.saved_for(Pilot.KILN) == Livery.FACTORY)
	_clear_prefs()


func _menus() -> void:
	# the row itself, for every craft: round its paints and back, then left on one of its own
	var trips := []
	var kept := {}
	for k in Pilot.ORDER.size():
		var craft: String = Pilot.ORDER[k]
		Settings.set_selected_craft(craft)
		var row := UI.paint_button()
		root.add_child(row)
		var names := Livery.choices_for(craft)
		var seen := [row.text]
		var ids := []
		for i in names.size():
			row.pressed.emit()
			seen.append(row.text)
			ids.append(Livery.saved_for(craft))
		var round_trip: bool = seen[0].ends_with("Factory") and seen[1].ends_with(names[1][1]) and ids[0] == names[1][0] \
			and ids.back() == Livery.FACTORY and seen.back() == seen[0] and ids.size() == names.size()
		if not round_trip:
			trips.append("%s %s %s" % [craft, seen, ids])
		for i in k + 1:      # leave each craft on a paint of its own (the k+1th after Factory)
			row.pressed.emit()
		kept[craft] = names[k + 1][0]
		row.queue_free()
	var now := {}
	for craft: String in Pilot.ORDER:
		now[craft] = Livery.saved_for(craft)
	check("the paint row steps the chosen craft's paints and round to Factory, showing and saving each, for every craft (wrong: %s)" % [trips], trips.is_empty())
	check("... and each craft keeps its own choice while the others are chosen (%s)" % [now], now == kept)
	# the menus (title off: they are as they were before it): the row follows the pilot craft
	Stage.enabled = false
	for scene in [UI.MENU_SCENE, UI.VR_MENU_SCENE]:
		Settings.set_selected_craft(Pilot.STANDARD)
		change_scene_to_file(scene)
		await scene_changed
		await process_frame
		var menu = current_scene
		var paint: Button = null
		for b: Button in menu.find_children("*", "Button", true, false):
			if b.text.begins_with("Paint:"):
				paint = b
		var shown := []
		for i in Pilot.ORDER.size():
			var craft: String = menu.craft_selector.selected
			shown.append(paint.text.ends_with(Livery.choices_for(craft)[Livery.ids_for(craft).find(kept[craft])][1]))
			menu.craft_selector.button.pressed.emit()
		Settings.set_selected_craft(Pilot.VESPER)
		menu.craft_selector.selected = Pilot.VESPER
		menu.craft_selector.button.pressed.emit()      # (the Basilisk)
		paint.pressed.emit()
		var basilisk := Livery.saved_for(Pilot.BASILISK)
		var others_kept := true
		for craft: String in Pilot.ORDER:
			others_kept = others_kept and (craft == Pilot.BASILISK or Livery.saved_for(craft) == kept[craft])
		var ids := Livery.ids_for(Pilot.BASILISK)
		check("%s: the paint row shows each pilot craft's own paint as the craft changes (%s); a press there is that craft's alone (%s to %s)" % [scene.get_file(), shown, kept[Pilot.BASILISK], basilisk],
			paint != null and not shown.has(false) and basilisk == ids[(ids.find(kept[Pilot.BASILISK]) + 1) % ids.size()] and others_kept)
		Settings.set_choice(Livery.key_for(Pilot.BASILISK), kept[Pilot.BASILISK])
	Stage.enabled = true


# ---- the colours the craft are painted in ----

## The mean colour of an atlas over a rectangle, as displayed (sRGB).
func _mean(image: Image, rect: Rect2i) -> Color:
	var sum := Color(0, 0, 0)
	var n := 0
	for y in range(rect.position.y, rect.end.y, 2):
		for x in range(rect.position.x, rect.end.x, 2):
			sum += image.get_pixel(x, y)
			n += 1
	return Color(sum.r / n, sum.g / n, sum.b / n)


func _close(a: Color, b: Color, within: float) -> bool:
	return absf(a.r - b.r) < within and absf(a.g - b.g) < within and absf(a.b - b.b) < within


func _colours() -> void:
	var off := []
	for id: String in Fleet.OWN:
		var image := ((load(Fleet.ASSET_DIR + id + ".tres") as StandardMaterial3D).albedo_texture as Texture2D).get_image()
		if image.is_compressed():
			image.decompress()
		var own: Array = Fleet.OWN[id]
		# the enamel tile, the accent tile, the gold (trim) tile: their middles
		for k in 3:
			var at: Vector2i = [Vector2i(64, 64), Vector2i(320, 64), Vector2i(64, 320)][k]
			var seen := _mean(image, Rect2i(at, Vector2i(128, 128)))
			if not _close(seen, own[k], 0.05):      # (block compression moves a dark channel up to 10/255)
				off.append("%s %d: %s, not %s" % [id, k, seen.to_html(false), (own[k] as Color).to_html(false)])
	var shrike := ((load("res://art/shrike/enamel.tres") as StandardMaterial3D).albedo_texture as Texture2D).get_image()
	if shrike.is_compressed():
		shrike.decompress()
	for pair in [[Rect2i(1580, 1580, 160, 160), Shrike.ATLAS_TEAL], [Rect2i(600, 1620, 300, 300), Shrike.ATLAS_IVORY]]:
		var seen := _mean(shrike, pair[0])
		if not _close(seen, pair[1], 0.05):
			off.append("shrike %s, not %s" % [seen.to_html(false), (pair[1] as Color).to_html(false)])
	check("the fleet's and the Shrike's own colours, as their airframes have them, are what their atlases are painted in (off: %s)" % [off], off.is_empty())


# ---- every craft, built ----

func _build(craft: String) -> Node:
	View.vehicle_override = craft
	var v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	return v


func _finish_of(mesh: Mesh) -> ShaderMaterial:
	return mesh.surface_get_material(0) as ShaderMaterial if mesh != null else null


## Is this finish the factory one (nothing repainted) and, if not, the livery's own?
func _dressed_right(finish: ShaderMaterial, livery: String, mask: String, own: Array) -> bool:
	if finish == null:
		return false
	if Livery.is_factory(livery):
		return not (finish.get_shader_parameter("repaint") == true) and finish.get_shader_parameter("livery_mask") == null
	var shown: Texture2D = finish.get_shader_parameter("livery_mask")
	return (finish.get_shader_parameter("repaint") == true) and shown != null and shown.resource_path == mask \
		and finish.get_shader_parameter("from_r") == own[0] and finish.get_shader_parameter("to_r") == Livery.coat("paint", livery) \
		and finish.get_shader_parameter("from_g") == own[1] and finish.get_shader_parameter("to_g") == Livery.coat("pin", livery) \
		and finish.get_shader_parameter("from_b") == own[2] and finish.get_shader_parameter("to_b") == Livery.coat("stripe", livery)


func _built() -> void:
	Livery.pinned = true
	var wrong := []
	var still := []
	var shrike_again := false
	for craft: String in Pilot.ORDER:
		for livery: String in LIVERIES:
			Livery.current = livery
			var v = await _build(craft)
			var hull := v.shell.get_node("PodHull") as MeshInstance3D
			var why := ""
			var finish: ShaderMaterial = null
			match craft:
				Pilot.STANDARD:
					var want := CM.pod_hull_in(Livery.table_id(livery))
					if hull.mesh != want or (Livery.is_factory(livery) and hull.mesh != CM.pod_hull_in("ember")):
						why = "hull"
				Pilot.SHRIKE:
					var fairing := (v.craft.engines[0] as Node3D).get_node("ShrikeFairing") as MeshInstance3D
					finish = _finish_of(fairing.mesh)
					var factory_mesh: bool = fairing.mesh == Shrike.meshes[&"Port"]
					var own := [Shrike.ATLAS_TEAL, Shrike.ATLAS_IVORY, Shrike.ATLAS_GOLD]
					if factory_mesh != Livery.is_factory(livery) or not _dressed_right(finish, livery, Shrike.MASK, own):
						why += " bodywork"
					var coat := hull.get_surface_override_material(5) as StandardMaterial3D
					var piping := hull.get_surface_override_material(6) as ShaderMaterial
					if Livery.is_factory(livery):
						if coat != Shrike.pod_paint or coat.albedo_color != Shrike.PETROL or piping != Shrike.fittings:
							why += " pod"
					elif coat == null or coat.albedo_color != Livery.coat("paint", livery) or piping == null or piping.get_shader_parameter("enamel") != Livery.coat("paint", livery):
						why += " pod"
					if hull.mesh != CM.pod_hull_in("ember", true):
						why += " hull"
					var coaming := v.interior.get_node_or_null("SegmentedCoaming") as MeshInstance3D
					if Interior.hd_parts and coaming != null:
						var on := coaming.get_surface_override_material(0)
						var ok: bool = (on is BaseMaterial3D and ((on as BaseMaterial3D).albedo_texture as Texture2D).resource_path.ends_with("shrike_coaming.webp")) if Livery.is_factory(livery) \
							else (on is ShaderMaterial and (on as ShaderMaterial).shader == Accent.SHADER)
						if not ok:
							why += " coaming"
					if livery == "cobalt":      # (built once more in the same paint: the same copies)
						var first: Mesh = fairing.mesh
						v.queue_free()
						await process_frame
						v = await _build(craft)
						shrike_again = ((v.craft.engines[0] as Node3D).get_node("ShrikeFairing") as MeshInstance3D).mesh == first
						hull = v.shell.get_node("PodHull") as MeshInstance3D
				Pilot.TALON:      # (a Phaethon in Codex's body, no fleet bodywork: its hull's plating in the paint, view/talon_airframe.gd)
					if CM.Talon.paint != livery or hull.mesh != CM.pod_hull_in(livery, false, true):
						why = "hull"
				_:
					finish = _finish_of(v.craft.fleet.part(&"Cab"))
					if not _dressed_right(finish, livery, Fleet.ASSET_DIR + craft + Fleet.MASK, Fleet.OWN[craft]):
						why += " finish"
					if _finish_of(hull.mesh) != finish:      # (the cab seen from the seat is the same bodywork)
						why += " cab"
			if not why.is_empty():
				wrong.append("%s/%s:%s" % [craft, livery, why])
			# a frame or two of flying changes nothing in it
			if finish != null:
				var before: Array = [finish.get_shader_parameter("repaint"), finish.get_shader_parameter("to_r"), finish.get_shader_parameter("to_g")]
				for i in 4:
					v._process(DT)
				if [finish.get_shader_parameter("repaint"), finish.get_shader_parameter("to_r"), finish.get_shader_parameter("to_g")] != before:
					still.append("%s/%s" % [craft, livery])
			v.queue_free()
			await process_frame
	check("every craft in Factory, Ember, Cobalt and Sunflower: Factory as built before, a livery in its own mask and colours, the Shrike's pod, piping and coaming in its paint (wrong: %s)" % [wrong], wrong.is_empty())
	check("... set when it is built, nothing after (changed in flight: %s); a Shrike built again in the same paint takes the same copies (%s)" % [still, shrike_again],
		still.is_empty() and shrike_again)


func _flights() -> void:
	Livery.pinned = false
	_clear_prefs()
	Settings.set_choice("paint", "cobalt")
	Settings.set_choice(Livery.key_for(Pilot.KILN), "sunflower")
	var built := {}
	for craft: String in [Pilot.STANDARD, Pilot.SHRIKE, Pilot.KILN, Pilot.ORRERY]:
		var v = await _build(craft)
		var finish: ShaderMaterial = _finish_of(v.craft.fleet.part(&"Cab")) if v.craft.fleet != null else null
		built[craft] = [Livery.current, (finish.get_shader_parameter("repaint") == true) if finish else null]
		v.queue_free()
		await process_frame
	check("a flight builds each craft in the menus' paint for it (%s)" % [built],
		built[Pilot.STANDARD][0] == "cobalt" and built[Pilot.SHRIKE][0] == Livery.FACTORY and built[Pilot.KILN] == ["sunflower", true] and built[Pilot.ORRERY] == [Livery.FACTORY, false])
	Livery.pinned = true
	Livery.current = Livery.FACTORY
	_clear_prefs()


# ---- the finish, drawn ----

func _capture() -> Image:
	for k in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


## The picture's pixel where the quad shows atlas point `uv` (the quad fills the picture's height, centred).
func _pixel(size: Vector2i, uv: Vector2) -> Vector2i:
	return Vector2i(int((size.x - size.y) / 2.0 + uv.x * size.y), int(uv.y * size.y))


func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _pixels() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.1, 0.1, 0.1)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.5)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.5, 0.3, 0.0)
	stage.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.0
	stage.add_child(cam)
	cam.make_current()
	var quad := MeshInstance3D.new()
	var shape := QuadMesh.new()
	shape.size = Vector2(2, 2)
	quad.mesh = shape
	quad.position = Vector3(0, 0, -2)
	stage.add_child(quad)
	root.msaa_3d = Viewport.MSAA_DISABLED
	var old := Shader.new()
	old.code = EDDF4F7_FINISH
	var same := []
	var kept := []
	var moved := []
	var refined := []
	for id: String in Fleet.OWN:
		var atlas := load(Fleet.ASSET_DIR + id + ".tres") as StandardMaterial3D
		var factory := Fleet.finish_for(atlas, id)
		var legacy := factory.duplicate() as ShaderMaterial
		legacy.set_shader_parameter("packed_paint_finish", false)
		var before := Fleet.finish_for(atlas)
		before.shader = old
		Livery.current = "cobalt"
		var cobalt := Fleet.finish_for(atlas, id)
		Fleet.repaint(cobalt, load(Fleet.ASSET_DIR + id + Fleet.MASK), Fleet.colours(id))
		Livery.current = Livery.FACTORY
		var shots := []
		for mat in [factory, legacy, before, cobalt]:
			quad.material_override = mat
			shots.append(await _capture())
		# Compare livery grain without lighting: dielectric specular is white,
		# so it contributes different relative contrast on cream and dark blue.
		# The four lit renders above still check coat, profile and fixed surfaces.
		for mat: ShaderMaterial in [factory, cobalt]:
			var unlit := mat.duplicate() as ShaderMaterial
			unlit.shader = Shader.new()
			unlit.shader.code = mat.shader.code.replace("shader_type spatial;", "shader_type spatial;\nrender_mode unshaded;")
			quad.material_override = unlit
			shots.append(await _capture())
		var size: Vector2i = shots[0].get_size()
		# Legacy mode retains the old response; the authored finish is intentional.
		var differ := 0
		for y in range(0, size.y, 2):
			for x in range(0, size.x, 2):
				differ += int(shots[1].get_pixel(x, y) != shots[2].get_pixel(x, y))
		same.append("%s %d" % [id, differ])
		# the tiles a livery leaves alone: not a step, in their middles
		var stepped := 0
		for tile: Array in KEPT_TILES:
			for j in 12:
				for i in 12:
					# The cloth tile now shares its right half with recolourable vinyl.
					var span := 0.35 if tile == [3, 1] else 0.8
					var p := _pixel(size, (Vector2(tile[0], tile[1]) + Vector2(0.1 + span * i / 11.0, 0.1 + 0.8 * j / 11.0)) / 4.0)
					stepped += int(shots[0].get_pixel(p.x, p.y) != shots[3].get_pixel(p.x, p.y))
					# The paint coat and craft-specific roughness must not coat metal or fabric.
					stepped += int(shots[0].get_pixel(p.x, p.y) != shots[1].get_pixel(p.x, p.y))
		kept.append("%s %d" % [id, stepped])
		# the enamel tile: cobalt's hue, and the factory's own light and dark (their correlation, their spread)
		var a := []
		var b := []
		var blue := 0
		var changed := 0
		for j in 24:
			for i in 24:
				var p := _pixel(size, Vector2(0.025 + 0.2 * i / 23.0, 0.025 + 0.2 * j / 23.0))
				var f: Color = shots[4].get_pixel(p.x, p.y)
				var c: Color = shots[5].get_pixel(p.x, p.y)
				changed += int(shots[0].get_pixel(p.x, p.y) != shots[1].get_pixel(p.x, p.y))
				a.append(_lum(f))
				b.append(_lum(c))
				blue += int(c.b > c.g and c.g > c.r)
		var r := _correlation(a, b)
		var spread_f := _spread(a)
		var spread_c := _spread(b)
		moved.append("%s blue %d/576 r %.2f spread %.3f/%.3f" % [id, blue, r, spread_c, spread_f])
		refined.append(changed > 100)
		if blue < 560 or r < 0.6 or spread_c < 0.4 * spread_f:
			moved[-1] += " (WRONG)"
	stage.queue_free()
	await process_frame
	check("the legacy finish path draws exactly as eddf4f7's did (pixels that differ: %s)" % [same], same.all(func(s): return s.ends_with(" 0")))
	check("each refined factory finish visibly changes painted surfaces", refined.all(func(value): return value))
	check("in Cobalt their metal, rubber, ceramic, cloth and vent tiles do not move a step (pixels that do: %s)" % [kept], kept.all(func(s): return s.ends_with(" 0")))
	check("... and their enamel takes Cobalt's hue with its own light and dark, not a flat fill (%s)" % [moved], not str(moved).contains("WRONG"))


func _mean_of(values: Array) -> float:
	var s := 0.0
	for v: float in values:
		s += v
	return s / values.size()


## Spread over mean: how much light and dark there is in it, whatever its brightness.
func _spread(values: Array) -> float:
	var m := _mean_of(values)
	var s := 0.0
	for v: float in values:
		s += (v - m) * (v - m)
	return sqrt(s / values.size()) / maxf(m, 0.0001)


func _correlation(a: Array, b: Array) -> float:
	var ma := _mean_of(a)
	var mb := _mean_of(b)
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	for i in a.size():
		sab += (a[i] - ma) * (b[i] - mb)
		saa += (a[i] - ma) * (a[i] - ma)
		sbb += (b[i] - mb) * (b[i] - mb)
	return sab / sqrt(maxf(saa * sbb, 1e-12))


# ---- the title's turntable ----

func _shown(stage, key: String, seconds := 10.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while stage.showcase.get("key", "") != key and Time.get_ticks_msec() < deadline:
		await process_frame
	return stage.showcase.get("key", "") == key


func _turntable() -> void:
	Livery.pinned = false
	_clear_prefs()
	Settings.set_selected_craft(Pilot.KILN)
	change_scene_to_file(UI.MENU_SCENE)
	await scene_changed
	await process_frame
	var menu = current_scene
	var stage = menu.stage
	if not check("the desktop menu stands in the title", stage != null):
		return
	var first: bool = await _shown(stage, "kiln/factory")
	var paint: Button = menu.look_buttons[1]
	var factory_finish: ShaderMaterial = _finish_of(stage.showcase.model.fleet.part(&"Cab")) if first else null
	paint.pressed.emit()
	var second: bool = await _shown(stage, "kiln/ember")
	var finish: ShaderMaterial = _finish_of(stage.showcase.model.fleet.part(&"Cab")) if second else null
	check("the turntable shows the Kiln in its own paint (Factory: %s, nothing repainted %s), and a press of the paint row (\"%s\") re-dresses it (Ember: %s, its enamel in Ember's paint %s)" % [
			first, factory_finish != null and not (factory_finish.get_shader_parameter("repaint") == true), paint.text, second, finish != null and finish.get_shader_parameter("to_r") == Livery.coat("paint", "ember")],
		first and factory_finish != null and not (factory_finish.get_shader_parameter("repaint") == true) and second and finish != null
			and (finish.get_shader_parameter("repaint") == true) and finish.get_shader_parameter("to_r") == Livery.coat("paint", "ember") and paint.text.ends_with("Ember orange")
			and Livery.saved_for(Pilot.STANDARD) == Livery.FACTORY)
	Livery.pinned = true
