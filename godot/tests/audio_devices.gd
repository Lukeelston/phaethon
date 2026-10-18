## Lists the audio output devices Godot sees (needs a real audio driver, not Dummy).
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --audio-driver WASAPI --path godot -s res://tests/audio_devices.gd
extends SceneTree
func _initialize() -> void:
	print("driver output device now: ", AudioServer.output_device)
	for d in AudioServer.get_output_device_list():
		print("device: ", d)
	quit()
