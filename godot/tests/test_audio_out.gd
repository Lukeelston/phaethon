## Where a flight's sound goes (vr/vr_cockpit.gd audio_out_pick; Luke, 2026-11-22: "Will you put the audio on the
## headphones plugged into the headphone jack instead of the quest, so that I can judge the sound by device not
## code?"). The headset's own device unless the flight was started with -- --audio-out=<words joined by +>:
##   nothing asked     the headset's device when there is one, else none chosen (the driver's default stays)
##   a device asked    the one whose name holds every word, any case; never the entry called "Default"
##   one not there     the headset's device still, and the cockpit says which devices there are
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_audio_out.gd
## Prints AUDIO OUT PASS.
extends SceneTree

const Cockpit := preload("res://vr/vr_cockpit.gd")
# this PC's playback devices on 2026-11-22, as Windows names them
const DEVICES := ["Default", "D39hn-D0 (NVIDIA High Definition Audio)", "Headphones (AB13X USB Audio)",
	"Headphones (Oculus Virtual Audio Device)", "Headphones (Realtek USB Audio)", "SPDIF Interface (Realtek USB Audio)",
	"Speakers (Steam Streaming Speakers)"]
var failures := 0
var checks := 0


func _initialize() -> void:
	var all := PackedStringArray(DEVICES)
	var headset := "Headphones (Oculus Virtual Audio Device)"
	var jack := "Headphones (Realtek USB Audio)"
	_check("nothing asked: the headset's own device (%s)" % Cockpit.audio_out_pick(all, ""), Cockpit.audio_out_pick(all, "") == headset)
	_check("headphones+realtek: the board's jack and not its SPDIF (%s)" % Cockpit.audio_out_pick(all, "headphones+realtek"),
		Cockpit.audio_out_pick(all, "headphones+realtek") == jack)
	_check("the words in any case and any order (REALTEK+Headphones: %s)" % Cockpit.audio_out_pick(all, "REALTEK+Headphones"),
		Cockpit.audio_out_pick(all, "REALTEK+Headphones") == jack)
	_check("ab13x: the USB adapter (%s)" % Cockpit.audio_out_pick(all, "ab13x"), Cockpit.audio_out_pick(all, "ab13x") == "Headphones (AB13X USB Audio)")
	_check("one word that several hold takes the first of them, in the driver's order (realtek: %s)" % Cockpit.audio_out_pick(all, "realtek"),
		Cockpit.audio_out_pick(all, "realtek") == jack)
	_check("a device that is not there: the headset's still (%s), and it does not count as a match" % Cockpit.audio_out_pick(all, "sennheiser"),
		Cockpit.audio_out_pick(all, "sennheiser") == headset and not Cockpit.audio_out_matches(headset, "sennheiser"))
	_check("\"default\" asked is not the entry called Default (%s)" % Cockpit.audio_out_pick(all, "default"), Cockpit.audio_out_pick(all, "default") == headset)
	_check("only plus signs asked is nothing asked (%s)" % Cockpit.audio_out_pick(all, "++"), Cockpit.audio_out_pick(all, "++") == headset)
	var no_headset := PackedStringArray(["Default", "Headphones (Realtek USB Audio)"])
	_check("no headset and nothing asked: none chosen, the driver's default stays (\"%s\")" % Cockpit.audio_out_pick(no_headset, ""),
		Cockpit.audio_out_pick(no_headset, "") == "")
	_check("no devices at all: none chosen", Cockpit.audio_out_pick(PackedStringArray(), "headphones") == "")
	print("AUDIO OUT ", "PASS (%d checks, 0 failures)" % checks if failures == 0 else "FAIL (%d failed of %d)" % [failures, checks])
	quit(0 if failures == 0 else 1)


func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)
