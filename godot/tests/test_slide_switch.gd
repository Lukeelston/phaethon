## The slide's switch (Luke: "can you make the slide a physical thing in the cockpit?"): the same
## guarded toggle as the handling switch, on the front of the left console. A controller's tip
## pushed down through it throws it to GRIP (no slide), up to SLIDE; the choice is remembered.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Switch := preload("res://vr/mode_switch.gd")
var v
var failures := 0


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_slide_switch_")
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true      # the pilot's saved choices stay out of this
	Cockpit._nose_loaded = true
	Cockpit._slide_loaded = true
	Cockpit.slide_feel = true
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


## A controller's tip moved through the lever's zone from one height to another (panel metres), a
## sixtieth of a second apart: what the switch answers.
func _push(sw: Node3D, hand: Node3D, from_y: float, to_y: float) -> String:
	var answer := ""
	for y: float in [from_y, to_y]:
		hand.global_position = sw.global_transform * Vector3(0.0, y, 0.05) - hand.global_basis * Switch.TIP
		answer = sw.poke(hand, 1.0 / 60.0)
	return answer


func _run() -> void:
	v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	var sw = v.slide_switch
	_check("the cockpit has a slide switch", sw != null and sw.get_script() == Switch)
	if sw == null:
		quit(1)
		return
	var other: Node3D = v.mode_switch
	# (as far out, as high and tilted the same; further aft by PORT_AFT, where it is clear of the map's pod:
	# tests/test_cockpit_clash.gd holds the two apart)
	_check("it stands on the left console as the handling switch stands on the right, %.0f mm further aft: %s against %s" % [Switch.PORT_AFT * 1000.0, sw.position, other.position],
		is_equal_approx(sw.position.x, -other.position.x) and is_equal_approx(sw.position.y, other.position.y) and is_equal_approx(sw.position.z, other.position.z + Switch.PORT_AFT)
		and Switch.PORT_AFT > 0.0 and Switch.PORT_AFT < 0.12 and sw.basis.is_equal_approx(other.basis))
	var words := []
	for label: Label3D in sw.find_children("*", "Label3D", true, false):
		words.append(label.text)
	_check("its legends read SLIDE over GRIP: %s" % [words], words == ["SLIDE", "GRIP"])
	var hand := Node3D.new()
	root.add_child(hand)
	var thrown := _push(sw, hand, 0.03, 0.0)
	_check("a push down throws it to GRIP: \"%s\"" % thrown, thrown == "grip" and sw.down)
	v.set_slide(thrown == "slide")
	_check("GRIP turns the slide off and is saved", not Cockpit.slide_feel and v._load_prefs().get("slide", "") == "off")
	_check("it cannot be thrown straight back (a second's rest between throws)", _push(sw, hand, 0.0, 0.03) == "" and sw.down)
	sw.poke(hand, 1.1)           # the rest
	thrown = _push(sw, hand, 0.0, 0.03)
	_check("a push up throws it to SLIDE: \"%s\"" % thrown, thrown == "slide" and not sw.down)
	v.set_slide(thrown == "slide")
	_check("SLIDE turns it on again and is saved", Cockpit.slide_feel and v._load_prefs().get("slide", "") == "on")
	_check("too slow a push does nothing, nor one outside its guard",
		_push(sw, hand, 0.03, 0.028) == "" and sw.poke(hand, 1.1) == "" and not sw.down)
	# the handling switch is the same panel and still answers as it did
	var mode := _push(other, hand, 0.03, 0.0)
	_check("the handling switch still answers STARFIGHTER for a push down: \"%s\"" % mode, mode == "starfighter")
	other.down = false
	hand.queue_free()
	v.queue_free()
	await process_frame
	print("SLIDE SWITCH %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
