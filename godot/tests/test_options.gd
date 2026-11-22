## The cockpit's OPTIONS page, the ARM button's tap and hold, and what the cockpit does with the
## boost and the consumables (vr/vr_cockpit.gd; Luke, 2026-11-22: "bring back heat and energy as
## optional consumables", "Holding the ramjet arm button should give an extra boost").
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_options.gd -- --mute
## Prints OPTIONS PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
var failures := 0
var checks := 0


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_options_")
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true      # the pilot's saved choices stay out of this
	Cockpit._nose_loaded = true
	Cockpit._slide_loaded = true
	Cockpit._startup_loaded = true
	Cockpit._map_loaded = true
	Cockpit._school_loaded = true
	Cockpit.cold_start = false
	Cockpit.school = false
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	checks += 1
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _keys(v) -> Array:
	var keys := []
	for item in v.menu.items:
		keys.append(String(item.key))
	return keys


func _go(v, key: String) -> bool:
	for k in v.menu.items.size():
		if String(v.menu.items[k].key) == key:
			v.menu.at = k
			v.menu_choose()
			return true
	return false


func _saved() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(Cockpit.PREFS)) if FileAccess.file_exists(Cockpit.PREFS) else {}
	return d if d is Dictionary else {}


func _run() -> void:
	var prefs_before := FileAccess.get_file_as_string(Cockpit.PREFS) if FileAccess.file_exists(Cockpit.PREFS) else ""
	if prefs_before != "":      # a pilot with nothing saved: what he gets
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	var v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	_check("with nothing saved: heat and energy off (the sim's limits %s), the power-ups on and built (%s)" % [v.sim.P.limits, v.power_ups != null],
		not Cockpit.consumables and not v.sim.P.limits and View.power_ups_on and v.power_ups != null)
	# the page
	v.menu_open(true)
	var first: Array = _keys(v)
	_check("the quick menu's first page is still ten lines: OPTIONS above CHOOSE MAP, NOSE gone to it (%s)" % [first], first.has("options") and first.find("options") == first.find("maps") - 1 and first.size() == 10 and not first.has("nose"))
	_go(v, "options")
	var page: Array = _keys(v)
	var text: String = v.menu.text()
	_check("it opens the second page: %s, headed \"%s\", the cursor on its first line" % [page, text.get_slice("\n", 0)],
		page == ["consumables", "powerups", "field", "autopilot", "rush", "nose", "back"] and text.begins_with("OPTIONS") and v.menu.at == 0 and text.contains("HEAT AND ENERGY   OFF") and text.contains("POWER-UPS   ON"))
	_go(v, "consumables")
	_check("HEAT AND ENERGY switched on: the sim's limits on from that moment, the engines at their resting heat (%.2f), the line reads ON, saved (%s)" % [v.sim.eL.heat, _saved().get("consumables", "")],
		Cockpit.consumables and v.sim.P.limits and v.sim.eL.heat == 0.3 and v.menu.text().contains("HEAT AND ENERGY   ON") and _saved().get("consumables", "") == "on" and v.menu.at == 0)
	_go(v, "powerups")
	await process_frame
	_check("POWER-UPS switched off: the gates gone (%s), saved (%s)" % [v.power_ups == null, _saved().get("powerups", "")],
		not View.power_ups_on and v.power_ups == null and _saved().get("powerups", "") == "off" and v.menu.text().contains("POWER-UPS   OFF"))
	_go(v, "powerups")
	_check("... and on again: built again", View.power_ups_on and v.power_ups != null and _saved().get("powerups", "") == "on")
	# the avoidance field (sim/craft_sim.gd inp.avoid): off until asked for
	var field_first: bool = not View.avoid_on and v.menu.text().contains("AVOIDANCE FIELD   OFF")
	_go(v, "field")
	var field_on: bool = View.avoid_on and _saved().get("field", "") == "on" and v.menu.text().contains("AVOIDANCE FIELD   ON") and v.menu.key() == "field"
	_go(v, "field")
	_check("AVOIDANCE FIELD is off with nothing saved (%s); switched on it is on and saved (%s), and off again (%s)" % [field_first, field_on, _saved().get("field", "")],
		field_first and field_on and not View.avoid_on and _saved().get("field", "") == "off")
	_go(v, "back")
	_check("BACK returns to the first page with the cursor on OPTIONS", _keys(v) == first and v.menu.key() == "options" and v.menu.text().begins_with("FLIGHT HOLD"))
	_go(v, "options")
	v.menu_open(false)
	v.menu_open(true)
	_check("closed on the second page, the menu opens on the first", _keys(v) == first and v.menu.text().begins_with("FLIGHT HOLD"))
	v.menu_open(false)
	v._await_neutral_controls = false
	# the ARM button
	var seen := []
	for k in 10:                         # a tap: down 0.11 s
		seen.append(v.arm_button(true, 1.0 / 90.0))
	seen.append(v.arm_button(false, 1.0 / 90.0))
	_check("B tapped (down a ninth of a second): nothing while it is down, \"arm\" as it comes up, no boost", seen.count("") == 10 and seen[10] == "arm" and not v.boosting)
	seen.clear()
	var lit_at := -1
	for k in 90:                         # held a second
		var what: String = v.arm_button(true, 1.0 / 90.0)
		if what == "boost" and lit_at < 0:
			lit_at = k
		seen.append(what)
	var held: bool = v.boosting
	var up: String = v.arm_button(false, 1.0 / 90.0)
	_check("B held: \"boost\" once, %.2f s in (BOOST_HOLD %.2f), boosting from then; let go it arms nothing (\"%s\") and the boost is over" % [(lit_at + 1) / 90.0, Cockpit.BOOST_HOLD, up],
		seen.count("boost") == 1 and absf((lit_at + 1) / 90.0 - Cockpit.BOOST_HOLD) < 0.03 and held and up == "" and not v.boosting and not seen.has("arm"))
	# what the cockpit gives the sim
	v.inp = {"thrL": 0.87, "thrR": 0.87, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": false}
	v.boosting = true
	var hot: bool = v.startup.is_hot()
	v._boost_step(1.0 / 90.0, v.hands.left, v.hands.right)
	_check("held on a released craft (hot %s) the sim is asked for the boost" % hot, hot and v.inp.get("boost", false) == true)
	v._sim_step()
	_check("... and gives it: a stage, the dash says \"%s\"" % v.boost_text().strip_edges(), v.sim.boost == 1 and v.boost_text() == "   BOOST")
	v.power_up("energy")
	v._sim_step()
	_check("a gate taken with it: both stages, \"%s\", a surge of %.1f s begun" % [v.boost_text().strip_edges(), v.surge],
		v.sim.boost == 2 and v.boost_text() == "   BOOST x2" and v.surge > Cockpit.PowerUpsScript.SURGE_S - 0.1)
	# the consumables' housekeeping: a burner left lit on a flat battery is put out
	v.sim.battery = 0.0
	v.quest.burner = true
	v.boosting = false
	v._boost_step(1.0 / 90.0, v.hands.left, v.hands.right)
	_check("heat and energy on, the battery flat and the burner still asked for: the cockpit puts it out so the battery can charge", not v.quest.burner and v.inp.get("burner", true) == false)
	v.set_consumables(false)
	_check("switched off again: the limits off, the engines cold, the battery full", not v.sim.P.limits and v.sim.eL.heat == 0.0 and v.sim.battery == 1.0)
	v.queue_free()
	await process_frame
	if prefs_before == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	else:
		var out := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
		out.store_string(prefs_before)
		out.close()
	Cockpit.consumables = false
	print("OPTIONS %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
