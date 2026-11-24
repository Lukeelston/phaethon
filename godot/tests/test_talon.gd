## The Phaethon Talon (sim/pilot_craft.gd TALON: Codex's starfighter reshape of the Phaethon, e2675a1, as its own
## craft; its body is view/talon_airframe.gd).
##   on paper   its place after the Phaethon in the selector, its name and line (and no "Starfighter": that is a
##              handling mode), the Phaethon's tuning and sim, sound banks and instrument deck; which craft are
##              Phaethons underneath; its palette (factory: Codex's colours; a livery: its paint and accent)
##   flat view  the Phaethon's engines (nacelle, legend, lights) with Codex's fins fixed in them in place of the dorsal
##              fin and stabiliser and their moving parts, the strobe on the dorsal fin's tip and the nav lamp on the
##              outboard fin's; the Phaethon's hull with his plating as its last surface, his ventral brakes in place of
##              the pod's flaps and following the brake; both noses; the paint in the hull's cache; the Phaethon's own
##              hull as it was (eight surfaces, no plating)
##   VR seat    the Phaethon's own cockpit (no fleet deck, no auxiliary meter), sat in the plated hull, the brakes on it
##   title      the turntable's fairing for the Talon is its own, built once
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_talon.gd -- --mute
## Prints TALON PASS.
extends SceneTree

const Pilot := preload("res://sim/pilot_craft.gd")
const Sim := preload("res://sim/craft_sim.gd")
const View := preload("res://view/craft_view.gd")
const Seat := preload("res://vr/vr_cockpit.gd")
const CM := preload("res://view/craft_model.gd")
const Talon := preload("res://view/talon_airframe.gd")
const Livery := preload("res://view/livery.gd")
const Fleet := preload("res://view/fleet_airframe.gd")
const FleetDeck := preload("res://vr/fleet_flight_deck.gd")
const Title := preload("res://release/title_stage.gd")
const PREFS := "user://vr_prefs.json"
var failures := 0
var passes := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	if ok:
		passes += 1
	else:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)


## Does a mesh surface's vertex colours include `want` (8-bit: within a step or two)?
static func has_colour(mesh: ArrayMesh, surface: int, want: Color) -> bool:
	for c: Color in mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]:
		if absf(c.r - want.r) < 0.01 and absf(c.g - want.g) < 0.01 and absf(c.b - want.b) < 0.01:
			return true
	return false


func _run() -> void:
	var prefs_existed := FileAccess.file_exists(PREFS)
	var prefs := FileAccess.get_file_as_bytes(PREFS) if prefs_existed else PackedByteArray()
	Livery.pinned = true
	Livery.current = Livery.FACTORY      # (the Talon in its factory finish; the Phaethon's parts in Ember, Factory's table)
	_on_paper()
	await _flat_view()
	await _vr_seat()
	_title()
	if prefs_existed:
		var file := FileAccess.open(PREFS, FileAccess.WRITE)
		file.store_buffer(prefs)
		file.close()
	elif FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("TALON %s (%d checks, %d failed)" % ["PASS" if failures == 0 else "FAIL", passes + failures, failures])
	quit(0 if failures == 0 else 1)


func _on_paper() -> void:
	print("on paper")
	check("the Talon comes after the Phaethon in the selector", Pilot.ORDER[Pilot.ORDER.find(Pilot.STANDARD) + 1] == Pilot.TALON
		and Pilot.next(Pilot.STANDARD) == Pilot.TALON and Pilot.next(Pilot.TALON) == Pilot.SHRIKE)
	check("named \"Phaethon Talon\", with its line", Pilot.NAMES[Pilot.TALON] == "Phaethon Talon"
		and Pilot.DETAILS[Pilot.TALON] == "Swept twin-tail starfighter body  ·  16 m tow")
	var called_starfighter := false
	for id in Pilot.NAMES:
		called_starfighter = called_starfighter or String(Pilot.NAMES[id]).to_lower().contains("starfighter")
	check("no craft is called Starfighter (it is a handling mode)", not called_starfighter)
	check("it is known, chosen by --vehicle=talon, and has the Phaethon's (empty) tuning", Pilot.known("talon") == Pilot.TALON
		and Pilot.resolve(PackedStringArray(["--vehicle=talon"]), "") == Pilot.TALON and Pilot.tuning(Pilot.TALON) == {} and Pilot.tuning(Pilot.STANDARD) == {})
	check("it plays the Phaethon's own sounds and sits at the Phaethon's own instruments", Pilot.sound_bank(Pilot.TALON) == Pilot.STANDARD
		and Pilot.deck_of(Pilot.TALON) == Pilot.STANDARD and not FleetDeck.has_deck(Pilot.TALON) and not Fleet.supports(Pilot.TALON) and not Pilot.armed(Pilot.TALON))
	var based := []
	for id in Pilot.ORDER:
		if Pilot.phaethon_based(id):
			based.append(id)
	check("the Phaethon and the Talon, and no other craft, are Phaethons underneath (%s)" % [based], based == [Pilot.STANDARD, Pilot.TALON])
	var talon := Sim.new({"vehicle": Pilot.TALON, "track": "range"})
	var stock := Sim.new({"vehicle": Pilot.STANDARD, "track": "range"})
	var differ := []
	for key in stock.P:
		if key != "vehicle" and str(talon.P.get(key)) != str(stock.P[key]):
			differ.append(key)
	check("its sim is the Phaethon's, all but its name (%s differ)" % [differ], talon.P.vehicle == Pilot.TALON and differ.is_empty() and talon.P.size() == stock.P.size())
	var ember: Dictionary = Livery.TABLE.ember
	var factory := Talon.palette(Talon.FACTORY)
	check("the factory palette is Codex's: graphite and slate, Ember's orange trim and cream tips", factory.body == Talon.GRAPHITE and factory.panel == Talon.SLATE
		and factory.trim == ember.paint and factory.engine == ember.engine and factory.tip == ember.pin and factory.ink == Talon.TITANIUM.lerp(ember.pin, 0.42)
		and factory.metal == Talon.TITANIUM and factory.cavity == Talon.CAVITY)
	check("built in the factory's unless told otherwise, and an unknown paint is the factory's", Talon.paint == Talon.FACTORY and Talon.palette() == factory and Talon.palette("tartan") == factory)
	var cobalt: Dictionary = Livery.TABLE.cobalt
	var blue := Talon.palette("cobalt")
	check("a livery paints it in the livery's paint, trimmed in its accent", blue.body == cobalt.paint and blue.trim == cobalt.accent and blue.engine == cobalt.engine
		and blue.tip == cobalt.pin and blue.metal == Talon.TITANIUM and blue.keys() == factory.keys())
	var orange := Talon.palette("ember")
	check("... and in its pinstripe where it has no accent (Ember)", orange.body == ember.paint and orange.trim == ember.pin)
	var every := true
	for id in Livery.ids():
		if id == Livery.FACTORY:      # (first on the menus' row: Factory, the palette checked above)
			continue
		every = every and Talon.palette(id).keys() == factory.keys() and Talon.palette(id).body == Livery.TABLE[id].paint
	check("every paint on the menus' row gives a whole palette", every)


func _flat_view() -> void:
	print("flat view")
	View.track_override = "range"
	View.vehicle_override = Pilot.TALON
	View.job_override = "none"
	var game := View.new()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var craft = game.craft
	check("the flight is the Talon's", game.sim.P.vehicle == Pilot.TALON and craft.fleet == null and craft.fin_parts.is_empty())
	var fairings := true
	var fins_fixed := true
	var lamps := true
	for k in 2:
		var out := -1.0 if k == 0 else 1.0
		var eng: Node3D = craft.engines[k]
		var body := eng.get_node_or_null("TalonFairing") as MeshInstance3D
		fairings = fairings and body != null and not eng.has_node("PhaethonFairing") and eng.has_node("NacelleShell") and not eng.has_node("ShrikeFairing")
		if body:
			var own: AABB = body.mesh.get_aabb()
			var phaethon: AABB = CM._engine_body(out, false).get_aabb()
			# Codex's dorsal fin's tip stands 1.15 m up, his outboard fin's 2.44 m out; the Phaethon's fixed fittings neither
			fins_fixed = fins_fixed and own.end.y > 1.1 and phaethon.end.y < 1.0 and maxf(-own.position.x, own.end.x) > 2.4 and maxf(-phaethon.position.x, phaethon.end.x) < 1.6
		var strobe: Node3D = craft.strobes[k]
		var lights: AABB = (craft.light_meshes[k] as MeshInstance3D).mesh.get_aabb()
		lamps = lamps and strobe.get_parent() == eng and strobe.position.is_equal_approx(Talon.STROBE * Vector3(out, 1.0, 1.0)) and maxf(-lights.position.x, lights.end.x) > Talon.NAV_LAMP.x
	check("both engines are the Phaethon's (its nacelle, as TalonFairing)", fairings)
	check("Codex's fins are fixed in them, where the Phaethon has its dorsal fin and stabiliser", fins_fixed)
	check("... with no rudder or stabiliser to move, and nothing drawn for them", craft.rudders.is_empty() and craft.stabilisers.is_empty() and craft.fin_batches.is_empty()
		and craft.find_children("Rudders", "", true, false).is_empty())
	check("the strobe on the dorsal fin's tip and the nav lamp at the outboard fin's", lamps)
	var hull: ArrayMesh = craft.pod.mesh
	var plating := hull.surface_find_by_name(Talon.SURFACE)
	check("the hull carries Codex's plating as its ninth surface, in the factory's colours", hull.get_surface_count() == 9 and plating == 8 and bool(hull.get_meta(&"talon_hull", false))
		and not bool(hull.get_meta(&"shrike_hull", true)) and has_colour(hull, plating, Talon.GRAPHITE) and has_colour(hull, plating, Livery.TABLE.ember.paint))
	var own := CM.pod_hull()
	check("the Phaethon's own hull is its own: eight surfaces, no plating, not the Talon's", own != hull and own.get_surface_count() == 8 and own.surface_find_by_name(Talon.SURFACE) < 0
		and not own.has_meta(&"talon_hull"))
	# (what it costs to draw, beside the Phaethon: triangles in the hull and in one engine's fixed mesh)
	var tris := func(mesh: Mesh) -> int:
		var n := 0
		for s in mesh.get_surface_count():
			var idx = mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
			n += (idx.size() if idx != null and not (idx as PackedInt32Array).is_empty() else (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		return n
	print("  triangles: hull %d (the Phaethon's %d; plating %d), an engine's fixed mesh %d (the Phaethon's %d)" % [tris.call(hull), tris.call(own),
		(hull.surface_get_arrays(plating)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3, tris.call((craft.engines[1].get_node("TalonFairing") as MeshInstance3D).mesh),
		tris.call(CM._engine_body(1.0, false))])
	var brakes: bool = craft.pod_flaps.size() == 2 and craft.tail_lights == null
	for i in craft.pod_flaps.size():
		var s := -1.0 if i == 0 else 1.0
		var hinge: Node3D = craft.pod_flaps[i]
		var leaf := hinge.get_child(0) as MeshInstance3D
		brakes = brakes and hinge.position.is_equal_approx(Talon.BRAKE_HINGE * Vector3(s, 1.0, 1.0)) and leaf.is_in_group("exterior") and leaf.mesh.get_aabb().size.z > 0.8
	check("Codex's ventral brakes are the pod's (its lamps are in its hull)", brakes)
	var inp := {"thrL": 0.0, "thrR": 0.0, "brkL": 1.0, "brkR": 0.8, "repair": false, "reignite": true}
	game._follow_origin()
	craft.sync(game.sim, inp, 1.0)
	check("... and they open with the lesser brake", is_equal_approx(craft.pod_flap_open, 0.8)
		and is_equal_approx(craft.pod_flaps[1].rotation.y, CM.FLAP_OPEN * 0.8 * 0.8) and is_equal_approx(craft.pod_flaps[0].rotation.y, -CM.FLAP_OPEN * 0.8 * 0.8))
	var closed: bool = craft.nose_closed
	craft.set_nose_closed(not closed, game)
	var other: ArrayMesh = craft.pod.mesh
	check("the nose switch gives it its other hull, still plated", other != hull and other.surface_find_by_name(Talon.SURFACE) == 8 and bool(other.get_meta(&"talon_hull", false)))
	craft.set_nose_closed(closed, game)
	check("... and back", craft.pod.mesh == hull)
	Talon.paint = "cobalt"
	var blue := CM.pod_hull(false, true)
	Talon.paint = Talon.FACTORY
	check("a paint is its own hull (cobalt's plating in cobalt), and the factory's comes back", blue != hull and has_colour(blue, 8, Livery.TABLE.cobalt.paint)
		and not has_colour(blue, 8, Talon.GRAPHITE) and CM.pod_hull(false, true) == hull)
	View.vehicle_override = ""
	game.free()
	await process_frame


func _vr_seat() -> void:
	print("VR seat")
	Seat.track_override = "range"
	Seat.job_override = "none"
	Seat._camera_loaded = true
	Seat.camera = "cockpit"
	Seat._startup_loaded = true
	Seat.cold_start = false
	Seat._nose_loaded = true
	Seat._slide_loaded = true
	Seat._map_loaded = true
	Seat._school_loaded = true
	Seat.vehicle_override = Pilot.TALON
	var game := Seat.new()
	root.add_child(game)
	game.set_process(false)
	for i in 6:
		game._process(1.0 / 120.0)
	var hull := game.shell.get_node("PodHull") as MeshInstance3D
	check("the pilot sits in the plated hull", game.sim.P.vehicle == Pilot.TALON and hull.mesh == CM.pod_hull(false, true) and hull.mesh.surface_find_by_name(Talon.SURFACE) == 8)
	check("... in the Phaethon's own cockpit (no fleet deck, meter, boots or Shrike plate)", game.aux_meter == null and game.dashboard != null and game.dashboard.flight_deck == null
		and game.throttle_gaiters.is_empty() and game.tow_meter == null and game.shell.find_child("ShrikePlate", true, false) == null and not game.interior.has_node("SillFittings"))
	check("the ventral brakes ride on the hull the seat and the chase camera see", game.craft.pod_flaps.all(func(f): return f.get_parent() == hull))
	Seat.vehicle_override = ""
	game.free()
	await process_frame


func _title() -> void:
	print("title")
	var body: ArrayMesh = Title._show_body(1.0, true)
	var phaethon: ArrayMesh = Title._show_body(1.0)
	check("the turntable's Talon wears its own fairing (Codex's fins), built once", body != phaethon and body.get_aabb().end.y > 1.1 and phaethon.get_aabb().end.y < 1.0
		and Title._show_body(1.0, true) == body and Title._show_body(1.0) == phaethon)
