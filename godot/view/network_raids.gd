## Raids on the Network: hostile raiders attack a city and the pilot shoots them (free flight; the Network only).
## This is the director's hookup: the Off/On option and an empty node the later tasks fill in.
##   var raids := Raids.new(); view.add_child(raids); raids.traffic = view.traffic_net; raids.build(view)
##   raids.update(delta)            every frame, after traffic's own update
##   raids.reset()                  on a restart
##   raids.text()                   the dash's line while a raid is on ("" otherwise)
##   raids.result                   "cleared" | "lost", once, for the view to take
extends Node3D

const Settings := preload("res://release/game_settings.gd")
const MODES := [["off", "Off"], ["on", "On"]]       # the menus' row: [id, name]

static var enabled := false      # raids
static var pinned := false       # a test or a render chose it: the saved choice does not replace it

var traffic
var view
var sim
var result := ""
var tally := {"cleared": 0, "lost": 0}


static func ids(rows: Array) -> Array:
	return rows.map(func(entry): return entry[0])


static func load_saved() -> void:
	if not pinned:
		enabled = Settings.choice("raids", ids(MODES)) == "on"


func build(v) -> void:           # (set `traffic` first: view.traffic_net)
	view = v
	sim = v.sim
	name = "network_raids"


func update(_delta: float) -> void:
	pass


func reset() -> void:
	result = ""


func text() -> String:
	return ""
