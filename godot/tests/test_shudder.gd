## Air-brake shudder gate, through the real VR cockpit (XR off): cruise, then hold the left brake
## at speed. The left side shudders and the right doesn't; the cockpit's fittings shake by a few
## millimetres while your head (the XR camera) is not part of what shakes; brakes in, it all
## goes still. The controller haptics are only checked in the headset. Prints SHUDDER PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_shudder.gd -- --track=range
extends SceneTree

const VRScript := preload("res://vr/vr_cockpit.gd")
var v
var t := 0.0
var fails := 0
var passed := 0
var peak := 0.0
var shud := [0.0, 0.0]


func _initialize() -> void:
	v = VRScript.new()
	v.cruise = 0.7
	root.add_child(v)


func _process(delta: float) -> bool:
	t += delta
	var braking := t > 5.0 and t < 7.0
	v.inp = {"thrL": 0.7, "thrR": 0.7, "brkL": 1.0 if braking else 0.0, "brkR": 0.0, "repair": false, "reignite": true}
	if t > 5.8 and t < 7.0:
		peak = maxf(peak, v.shell.position.length())
		shud = [maxf(shud[0], v.wind_audio.shudder[0]), maxf(shud[1], v.wind_audio.shudder[1])]
	if t < 8.0:
		return false
	var mph: float = sqrt(v.sim.pod.vx * v.sim.pod.vx + v.sim.pod.vy * v.sim.pod.vy) * 2.236936
	_check("left brake at %.0f mph: left shudder %.2f, right %.2f" % [mph, shud[0], shud[1]], shud[0] > 0.3 and shud[1] < 0.02)
	_check("the cockpit shakes a few mm (peak %.1f mm), and your head isn't in what shakes" % (peak * 1000.0),
		peak > 0.0008 and peak < 0.01 and not v.shell.is_ancestor_of(v.cam))
	_check("brakes in: still again (shell %.2f mm, shudder %.3f)" % [v.shell.position.length() * 1000.0, v.wind_audio.shudder[0]],
		v.shell.position.length() < 0.0002 and v.wind_audio.shudder[0] < 0.01)
	var good := fails == 0 and passed == 3
	print("SHUDDER ", "PASS" if good else "FAIL (%d failed, %d passed)" % [fails, passed])
	quit(0 if good else 1)
	return true


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
