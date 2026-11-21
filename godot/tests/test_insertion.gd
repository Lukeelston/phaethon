## Choosing where a Network flight begins (Luke: "would also love to be able to choose insertion
## point on the network"; release/release_config.gd INSERTIONS, view/craft_view.gd start_spot):
##   listed    every insertion point names a real city or a real road, a sample on it, and a way to face
##   default   "Last city reached" asks for no spot at all: the Network starts as it always did
##   saved     a menu's row steps to the next and saves it; the Network's course then asks for that spot
##   flown     a flight begun at a city starts at its terminal; one begun out on a road starts on that
##             road at that sample, facing up it (or down it when asked), standing still, on the deck
## Prints INSERTION PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const UI := preload("res://release/release_config.gd")
const Settings := preload("res://release/game_settings.gd")
const Sim := preload("res://sim/craft_sim.gd")
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _run() -> void:
	var before := Settings.choice("network_start", UI.insertion_ids())
	# listed
	var bad := []
	var cities := 0
	var roads := 0
	for entry in UI.INSERTIONS:
		var spot: Array = View.start_spot(entry[2])
		if entry[2] == "":
			if not spot.is_empty():
				bad.append(entry[0])
		elif spot.size() == 1:
			cities += 1
		elif spot.size() == 3 and int(spot[0]) >= 0:
			roads += 1
		else:
			bad.append(entry[0])
	_check("%d insertion points: the last city reached, %d cities by name, %d places out on the roads (unresolved: %s)" % [UI.INSERTIONS.size(), cities, roads, bad],
		bad.is_empty() and cities == 5 and roads >= 9 and UI.INSERTIONS[0][2] == "")
	_check("nothing unknown starts anywhere: a road that is not there %s, a city that is not %s" % [View.start_spot("SNowhere@40"), View.start_spot("city:ATLANTIS")],
		View.start_spot("SNowhere@40").is_empty() and View.start_spot("city:ATLANTIS").is_empty())
	# default and saved
	Settings.set_choice("network_start", "last")
	_check("by default the Network asks for no spot: %s" % [UI.course_overrides("network")], UI.course_overrides("network") == ["network", "none", ""])
	var row := UI.insertion_button()
	root.add_child(row)
	var first := row.text
	row.pressed.emit()
	_check("a press takes the next and saves it: \"%s\" then \"%s\"; the Network's course now asks for %s" % [first, row.text, UI.course_overrides("network")],
		first.ends_with(String(UI.INSERTIONS[0][1])) and row.text.ends_with(String(UI.INSERTIONS[1][1])) and Settings.choice("network_start", UI.insertion_ids()) == UI.INSERTIONS[1][0]
			and UI.course_overrides("network") == ["network", "none", UI.INSERTIONS[1][2]])
	for i in UI.INSERTIONS.size() - 1:
		row.pressed.emit()
	_check("and after the last comes the first again: \"%s\"" % row.text, row.text == first)
	row.queue_free()
	Settings.set_choice("network_start", "wash")
	_check("the scenic roads' own courses are as they were: %s, %s" % [UI.course_overrides("coast"), UI.course_for("network", "SDrop")],
		UI.course_overrides("coast") == ["network", "none", "SCoast"] and UI.course_for("network", "SDrop") == "drop" and UI.course_for("network", "SWash@130") == "network")
	Settings.set_choice("network_start", before)
	# flown: the sim's own start, for a city, a road, and a road faced down
	var placed := []
	var wrong := []
	for entry in UI.INSERTIONS:
		var spot: Array = View.start_spot(entry[2])
		if spot.is_empty():
			continue
		var opts := {"track": "network", "handling": "speed"}
		if spot.size() == 1:
			opts["startCity"] = spot[0]
		else:
			opts["startRoad"] = spot[0]
			opts["startSample"] = spot[1]
			opts["startDir"] = spot[2]
		var sim = Sim.new(opts)
		var P = sim.pod
		var road: int = sim.cities[spot[0]].road if spot.size() == 1 else int(spot[0])
		var at: int = sim.cities[spot[0]].i if spot.size() == 1 else int(spot[1])
		var R = sim.roads[road]
		# (the pod trails its engines by the cables' length: it stands a little behind the sample asked for)
		var off := Vector2(P.x - R.px[at], P.y - R.py[at])
		var along := off.dot(Vector2(R.tx[at], R.ty[at]))
		var across := absf(off.dot(Vector2(R.nx[at], R.ny[at])))
		var facing := Vector2(cos(P.th), sin(P.th)).dot(Vector2(R.tx[at], R.ty[at]))
		var still := Vector2(P.vx, P.vy).length() < 0.01
		if P.path == road and absf(along) < 40.0 and across < 1.0 and facing > 0.99 and still:
			placed.append(entry[0])
		else:
			wrong.append("%s (road %d, %.0f m along, %.1f across, facing %.2f)" % [entry[0], P.path, along, across, facing])
	_check("a flight begun at each starts there, on its road, facing up it, standing still: %d placed; wrong: %s" % [placed.size(), wrong], wrong.is_empty() and placed.size() == UI.INSERTIONS.size() - 1)
	var down = Sim.new({"track": "network", "handling": "speed", "startRoad": View.start_spot("N3@300@-1")[0], "startSample": 300, "startDir": View.start_spot("N3@300@-1")[2]})
	_check("asked to face down a road, it does: heading (%.2f, %.2f) on N3, which runs north" % [cos(down.pod.th), sin(down.pod.th)], sin(down.pod.th) < -0.99)
	print("INSERTION %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
