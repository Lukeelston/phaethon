## The craft's paint (Luke: "What about color settings for the vehicle?"; view/livery.gd,
## view/accent.gd, CraftModel.pod_hull()):
##   liveries  Factory and eight on the menus' row, and the patrol's; every one names all five parts;
##             Factory's colours are Ember's
##   ember     the craft as it always was: the constants it was built from, and no accent
##   hulls     each livery has its own hull, open nose and closed, built once and kept; its paint
##             surface is in that livery's paint and stripe and nothing else; Ember's is untouched by
##             building another
##   accent    under Ember a fitting keeps its own material; under another livery its enamel and
##             thread are drawn in the accent over the fitting's own maps, one material per fitting kept
##   cockpit   a cockpit built in another livery wears it: hull, coaming, grips, tub, dash, roof,
##             binnacle; built in Ember again, nothing is overridden
##   saved     the menus' row steps through the Phaethon's paints (Factory, which is Ember, and seven
##             more) and saves the choice (every craft's own: tests/test_paint.gd)
##   vesper    Codex's Star Command: on the Vesper's row only, after Factory, saved as its paint; the Vesper built in
##             it wears its own atlas (not a repaint); the other craft's rows and choices untouched
## Prints LIVERY PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const CM := preload("res://view/craft_model.gd")
const Livery := preload("res://view/livery.gd")
const Accent := preload("res://view/accent.gd")
const UI := preload("res://release/release_config.gd")
const Settings := preload("res://release/game_settings.gd")
var failures := 0


func _initialize() -> void:
	View.track_override = "range"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_livery_")
	Livery.pinned = true
	Livery.current = "ember"
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


## The colours on a hull's paint surface (5), each rounded to the palette it was built from.
func _paint_colours(hull: ArrayMesh) -> Dictionary:
	var seen := {}
	for c: Color in hull.surface_get_arrays(5)[Mesh.ARRAY_COLOR]:
		seen[Color(snappedf(c.r, 0.01), snappedf(c.g, 0.01), snappedf(c.b, 0.01))] = true
	return seen


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.011 and absf(a.g - b.g) < 0.011 and absf(a.b - b.b) < 0.011


func _run() -> void:
	var before = FileAccess.get_file_as_bytes(Settings.PREFS) if FileAccess.file_exists(Settings.PREFS) else null
	var incomplete := []
	for id in Livery.TABLE:
		for part in ["name", "paint", "stripe", "pin", "engine", "skin"]:
			if not Livery.TABLE[id].has(part):
				incomplete.append("%s.%s" % [id, part])
	_check("%d liveries, %d of them and Factory on the menus' row, every part named (missing: %s); Factory's are Ember's" % [Livery.TABLE.size(), Livery.CHOICES.size() - 1, incomplete],
		incomplete.is_empty() and Livery.CHOICES.size() == 9 and Livery.TABLE.has("police") and not Livery.ids().has("police") and Livery.ids()[0] == Livery.FACTORY
			and Livery.ids()[1] == "ember" and Livery.coat("paint", Livery.FACTORY) == Livery.coat("paint", "ember") and Livery.accent(Livery.FACTORY) == null)
	_check("Ember is the craft as it was: paint %s, stripe %s, pin %s, engine %s, no accent" % [Livery.coat("paint"), Livery.coat("stripe"), Livery.coat("pin"), Livery.coat("engine")],
		Livery.coat("paint") == CM.PAINT and Livery.coat("stripe") == CM.STRIPE and Livery.coat("pin") == CM.PIN and Livery.coat("engine") == CM.LIVERY
			and Livery.coat("skin") == CM.SILVER and Livery.accent() == null)

	# hulls
	var ember: ArrayMesh = CM.pod_hull()
	var ember_colours := _paint_colours(ember)
	var hulls := {}
	var wrong := []
	for id in Livery.TABLE:
		var hull: ArrayMesh = CM.pod_hull_in(id)
		hulls[id] = hull
		for c: Color in _paint_colours(hull):
			if not _near(c, Livery.coat("paint", id)) and not _near(c, Livery.coat("stripe", id)):
				wrong.append("%s has %s" % [id, c])
	var distinct := {}
	for id in hulls:
		distinct[hulls[id]] = true
	_check("each livery has its own hull (%d of %d), built once (%s), painted in its own paint and stripe only (strays: %s); Ember's is as it was (%s) and the craft's own is still Ember (%s)" % [
			distinct.size(), hulls.size(), CM.pod_hull_in("cobalt") == hulls["cobalt"], wrong.slice(0, 3), _paint_colours(ember) == ember_colours, Livery.current],
		distinct.size() == hulls.size() and CM.pod_hull_in("cobalt") == hulls["cobalt"] and wrong.is_empty() and hulls["ember"] == ember
			and _paint_colours(ember) == ember_colours and Livery.current == "ember" and CM.pod_hull() == ember)
	Livery.current = "cobalt"
	var open: ArrayMesh = CM.pod_hull()
	CM.set_nose_closed(true)
	var closed: ArrayMesh = CM.pod_hull()
	CM.set_nose_closed(false)
	_check("a livery's nose still opens and closes on its own two hulls", open == hulls["cobalt"] and closed != open and CM.pod_hull() == open)
	Livery.current = "ember"

	# accent
	var coaming: Mesh = Cockpit.CockpitInteriorScript.deck_mesh("Coaming")
	var own := coaming.surface_get_material(0)
	var as_ember := Accent.of(own)
	Livery.current = "cobalt"
	var as_cobalt := Accent.of(own)
	var again := Accent.of(own)
	Livery.current = "crimson"
	var as_crimson := Accent.of(own)
	Livery.current = "ember"
	var turned := as_cobalt as ShaderMaterial
	_check("the accent: Ember keeps the coaming's own material; cobalt draws it with the recolour over its own maps, one material kept; crimson has another",
		as_ember == own and turned != null and again == as_cobalt and as_crimson != as_cobalt and turned.get_shader_parameter("albedo_map") == (own as BaseMaterial3D).albedo_texture
			and turned.get_shader_parameter("normal_map") == (own as BaseMaterial3D).normal_texture)

	# cockpit
	Livery.current = "viridian"
	var v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	var dressed := []
	var bare := []
	for path in ["SegmentedCoaming", "SeatTub", "Dashboard"]:
		var part := v.interior.get_node_or_null(path) as MeshInstance3D
		(dressed if part != null and part.get_surface_override_material(0) is ShaderMaterial else bare).append(path)
	var binnacle := v.dashboard.get_node_or_null("binnacle") as MeshInstance3D
	(dressed if binnacle != null and binnacle.get_surface_override_material(0) is ShaderMaterial else bare).append("binnacle")
	var roof := v.canopy.get_node_or_null("roof") as MeshInstance3D
	(dressed if roof != null and roof.material_override is ShaderMaterial else bare).append("roof")
	var grips := 0
	for knob: MeshInstance3D in v.find_children("PilotGrip", "MeshInstance3D", true, false):
		grips += int(knob.get_surface_override_material(0) is ShaderMaterial)
	var hull_worn := false
	for part: MeshInstance3D in v.find_children("*", "MeshInstance3D", true, false):
		hull_worn = hull_worn or part.mesh == hulls["viridian"]
	_check("a cockpit built in racing green wears it: its hull %s, fittings in the accent %s (not: %s), both grips (%d)" % [hull_worn, dressed, bare, grips],
		hull_worn and bare.is_empty() and grips == 2)
	v.queue_free()
	await process_frame
	Livery.current = "ember"
	v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	var overridden := 0
	for part: MeshInstance3D in v.find_children("*", "MeshInstance3D", true, false):
		for s in (part.mesh.get_surface_count() if part.mesh else 0):
			overridden += int(part.get_surface_override_material(s) is ShaderMaterial and (part.get_surface_override_material(s) as ShaderMaterial).shader == Accent.SHADER)
	var ember_roof := v.canopy.get_node_or_null("roof") as MeshInstance3D
	_check("built in Ember again, nothing is recoloured (%d overrides), and the headliner keeps its own glowing material" % overridden,
		overridden == 0 and ember_roof != null and ember_roof.material_override is BaseMaterial3D)
	v.queue_free()
	await process_frame

	# saved
	Settings.set_selected_craft("phaethon")
	Settings.set_choice("paint", "ember")      # (the old default: the Phaethon's Factory)
	var row := UI.paint_button()
	root.add_child(row)
	var first := row.text
	row.pressed.emit()
	var second := row.text
	var saved := Settings.choice("paint", Livery.ids())
	for i in Livery.ids_for("phaethon").size() - 1:
		row.pressed.emit()
	_check("the menus' row: \"%s\", a press \"%s\" and saved as %s, round again to \"%s\"" % [first, second, saved, row.text],
		first.ends_with("Factory") and second.ends_with("Cobalt blue") and saved == "cobalt" and row.text == first)
	# the Vesper's own livery, Codex's Star Command: on its row only, after Factory, saved as its paint
	var phaethon_paint := Livery.saved_for("phaethon")
	Settings.set_choice(Livery.key_for("kiln"), "viridian")
	Settings.set_choice(Livery.key_for("vesper"), Livery.FACTORY)
	Settings.set_selected_craft("vesper")
	UI.refresh_paint(row)
	var vesper_first := row.text
	row.pressed.emit()
	_check("the Vesper's row: \"%s\", a press \"%s\", saved as its paint (%s), built in it (%s)" % [vesper_first, row.text, Livery.saved_for("vesper"), Livery.built("vesper")],
		vesper_first.ends_with("Factory") and row.text.ends_with("Star Command") and Livery.saved_for("vesper") == Livery.STAR_COMMAND
			and Settings.choice(Livery.key_for("vesper"), Livery.ids_for("vesper")) == Livery.STAR_COMMAND and Livery.built("vesper") == Livery.STAR_COMMAND
			and Livery.ids_for("vesper")[1] == Livery.STAR_COMMAND and Livery.ids_for("vesper").size() == Livery.CHOICES.size() + 1)
	var only_its := []
	for craft: String in ["phaethon", "talon", "shrike", "orrery", "kiln", "basilisk"]:
		if Livery.ids_for(craft).has(Livery.STAR_COMMAND):
			only_its.append(craft)
	_check("... on no other craft's row (%s), and theirs are kept (the Phaethon's %s, the Kiln's %s)" % [only_its, Livery.saved_for("phaethon"), Livery.saved_for("kiln")],
		only_its.is_empty() and Livery.saved_for("phaethon") == phaethon_paint and Livery.saved_for("kiln") == "viridian" and not Livery.ids().has(Livery.STAR_COMMAND))
	Livery.current = Livery.built("vesper")
	var special := CM.Fleet.new("vesper")
	Livery.current = Livery.FACTORY
	var original := CM.Fleet.new("vesper")
	Livery.current = "ember"
	var paint := special.part(&"Cab").surface_get_material(0) as ShaderMaterial
	var stock := original.part(&"Cab").surface_get_material(0) as ShaderMaterial
	_check("the Vesper wears its own Star Command atlas on cab and engines, not a repaint; its Factory its own atlas",
		paint.get_shader_parameter("albedo_map").resource_path.ends_with("/vesper_star_command.webp") and not paint.get_shader_parameter("repaint")
			and special.part(&"Starboard").surface_get_material(0) == paint
			and stock.get_shader_parameter("albedo_map").resource_path.ends_with("/vesper.webp"))
	Settings.set_selected_craft("kiln")
	UI.refresh_paint(row)
	var kiln_row := row.text
	Settings.set_selected_craft("vesper")
	UI.refresh_paint(row)
	var recalled := row.text
	row.pressed.emit()
	_check("changing craft shows its own paint (%s), back on the Vesper it is recalled (%s); the next press is Ember, the Vesper's alone (%s; the Phaethon's %s, the Kiln's %s)" % [
			kiln_row, recalled, Livery.saved_for("vesper"), Livery.saved_for("phaethon"), Livery.saved_for("kiln")],
		kiln_row.ends_with("Racing green") and recalled.ends_with("Star Command") and Livery.saved_for("vesper") == "ember"
			and Livery.saved_for("phaethon") == phaethon_paint and Livery.saved_for("kiln") == "viridian")
	Settings.set_selected_craft("phaethon")
	row.queue_free()
	if before == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PREFS))
	else:
		var file := FileAccess.open(Settings.PREFS, FileAccess.WRITE)
		file.store_buffer(before)
		file.close()
	print("LIVERY %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
