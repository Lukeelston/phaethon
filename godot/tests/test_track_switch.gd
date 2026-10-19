## Track-switch gate (Luke: "can we get a way to switch to gp mode"): in the headset, the left
## menu button does two things.
##   tap         (released before MENU_HOLD) cycles the control scheme, on release, once
##   hold 1.5 s  switches track once, and letting go after doesn't also cycle the scheme
##   cycle       each hold steps range -> grand prix -> Eridanus -> range
##   override    CraftView.track_override (static: it survives the reload that does the switch)
##               builds the asked-for track, and wins over --track
## The reload itself is exercised end to end by the suite's VR scene run with --switch-track-at.
## Prints TRACK SWITCH PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_track_switch.gd -- --track=range --mute
extends SceneTree

const Cockpit := preload("res://vr/vr_cockpit.gd")
const ViewScript := preload("res://view/craft_view.gd")
var fails := 0
var passed := 0
var frames := 0


func _initialize() -> void:
	var c = Cockpit.new()   # not in the tree: only its button logic runs
	var dt := 1.0 / 72.0
	# a short tap: nothing while held, one scheme step on release
	var during := []
	for i in 20:
		var a: String = c._menu(true, dt)
		if a != "":
			during.append(a)
	var on_release: String = c._menu(false, dt)
	var after: String = c._menu(false, dt)
	_check("a %.2f s tap cycles the scheme once, on release (held: %s, release: '%s', then '%s')" % [20 * dt, during, on_release, after],
		during.is_empty() and on_release == "scheme" and after == "")
	# a long hold: the track switches once at MENU_HOLD; the release doesn't cycle the scheme
	var acts := []
	var at := -1.0
	for i in 160:
		var a: String = c._menu(true, dt)
		if a != "":
			acts.append(a)
			at = (i + 1) * dt
	var rel: String = c._menu(false, dt)
	_check("holding it switches track once at %.2f s (wanted %.1f s; actions %s), and letting go does nothing ('%s')" % [at, Cockpit.MENU_HOLD, acts, rel],
		acts == ["track"] and absf(at - Cockpit.MENU_HOLD) < 2.0 * dt and rel == "")
	c.free()
	var seen := []
	var t := "range"
	for i in 3:
		t = Cockpit.next_track(t)
		seen.append(t)
	_check("each hold steps to the next track: range -> %s (a plain circuit goes to the %s)" % [" -> ".join(seen), Cockpit.next_track("circuit")],
		seen == ["gp", "eridanus", "range"] and Cockpit.next_track("circuit") == "range")
	# the override builds the asked-for track, whatever --track says: one view at a time (a view
	# reads the override in its _ready)
	_next_view()


var asks := ["gp", "eridanus", "range"]
var got := []
var v


func _next_view() -> void:
	ViewScript.track_override = asks[got.size()]
	v = ViewScript.new()
	root.add_child(v)


func _process(_d: float) -> bool:
	frames += 1
	if frames % 2 == 1:
		return false
	got.append(v.sim.track_name if v.sim.course else ("range" if v.sim.kind == "range" else "circuit"))
	v.queue_free()
	if got.size() < asks.size():
		_next_view()
		return false
	ViewScript.track_override = ""
	_check("the override builds the asked-for track over --track=range (asked %s; got %s)" % [asks, got], got == asks)
	var good := fails == 0 and passed == 4
	print("TRACK SWITCH ", "PASS" if good else "FAIL (%d failed, %d passed)" % [fails, passed])
	quit(0 if good else 1)
	return true


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
