## Where the game's sound goes: the headset's own playback device, not whatever Windows has as its default (which may
## be the PC's speakers). Chosen once the headset's session is up (release/vr_boot.gd), so the menu and the garage are
## heard in the headset and not only a flight (Luke, 2026-11-26: "put the audio back in the headset": the device used
## to be chosen only as a flight's cockpit loaded, and since the menu's split a pilot stands in the garage first).
## A game started with -- --audio-out=<words of a device's name, joined by +> plays through that device instead
## (Luke, 2026-11-22: headphones on the PC's own jack, "so that I can judge the sound by device not code").
extends RefCounted

const HEADSET := "Oculus Virtual Audio"


## The device to play through: the one asked for when there is one named like it, else the headset's; "" for none
## (the driver's default stays).
static func pick(devices: PackedStringArray, asked: String) -> String:
	if asked.strip_edges() != "":
		for d in devices:
			if d != "Default" and matches(d, asked):
				return d
	for d in devices:
		if d.contains(HEADSET):
			return d
	return ""


## Whether a device's name holds every word asked for.
static func matches(device: String, asked: String) -> bool:
	var words := 0
	for w in asked.split("+", false):
		if w.strip_edges() == "":
			continue
		words += 1
		if not device.containsn(w.strip_edges()):
			return false
	return words > 0 and device != ""


## Send the sound there now, and say so in the log. Safe to call again: a device already in use is not set a second
## time (setting it restarts the stream). Returns the device chosen ("" none).
static func route() -> String:
	var asked := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--audio-out="):
			asked = a.trim_prefix("--audio-out=")
	var devices := AudioServer.get_output_device_list()
	var dev := pick(devices, asked)
	if dev != "":
		if AudioServer.output_device != dev:
			AudioServer.output_device = dev
		print("AUDIO: output -> ", dev, "" if asked == "" else "  (asked for: %s)" % asked)
	if asked != "" and not matches(dev, asked):
		print("AUDIO: no playback device is named like '%s'; the devices are: %s" % [asked, ", ".join(devices)])
	return dev
