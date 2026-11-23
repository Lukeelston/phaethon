## Verify the actual samples on both engine players, after changing craft in one session.
extends SceneTree

const Sim := preload("res://sim/craft_sim.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Engines := preload("res://audio/engine_audio.gd")
const Cockpit := preload("res://audio/startup_audio.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool) -> void:
	if not ok:
		printerr("FAIL ", label)
		failures += 1

# The engine loader duplicates imported WAVs to set their loop points. Compare the
# decoded performance, as a duplicated Resource can legitimately lose its path.
func _same_take(stream: AudioStream, path: String) -> bool:
	var actual := stream as AudioStreamWAV
	var expected := load(path) as AudioStreamWAV
	return actual != null and expected != null and actual.mix_rate == expected.mix_rate and actual.data == expected.data

func _unique_take(seen: Dictionary, path: String) -> void:
	# Hash decoded PCM so adding metadata or renaming a duplicate cannot pass this check.
	var take := load(path) as AudioStreamWAV
	if take == null:
		_check(path + " loads as a WAV", false)
		return
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(take.data)
	var hash_key := context.finish().hex_encode()
	_check("%s is distinct from %s" % [path, seen.get(hash_key, "")], not seen.has(hash_key))
	seen[hash_key] = path

func _engine_check(audio: Engines, manifest: Dictionary, bank_dir: String, id: String) -> void:
	for k in 2:
		var side := "EngineL" if k == 0 else "EngineR"
		var voice: Dictionary = audio.voices[k]
		for layer: String in manifest.layers:
			var bands: Array = manifest.layers[layer].bands
			var players: Array = voice.players[layer]
			_check("%s %s %s band count" % [id, side, layer], players.size() == bands.size())
			for i in mini(players.size(), bands.size()):
				var player: AudioStreamPlayer = players[i]
				var tone := player.stream as AudioStreamWAV
				var bus := side + "_" + layer if layer in Engines.FILTERED else side
				_check("%s %s %s band %d" % [id, side, layer, i],
						_same_take(tone, bank_dir + bands[i].file) and player.bus == bus
						and tone.loop_mode == AudioStreamWAV.LOOP_FORWARD
						and tone.loop_begin == 0 and tone.loop_end == tone.data.size() / 2)
		_check("%s %s catch bang" % [id, side],
				_same_take(voice.bang.stream, bank_dir + manifest.oneshots.bang)
				and voice.bang.bus == side + "_second")
		var pops := voice.pops.stream as AudioStreamRandomizer
		var files: Array = manifest.oneshots.pops
		_check("%s %s popping buses" % [id, side], voice.pops.bus == side + "_pops"
				and voice.pops2.bus == side + "_second" and voice.pops2.stream == pops
				and pops.streams_count == files.size())
		for i in mini(files.size(), pops.streams_count):
			_check("%s %s pop %d" % [id, side, i], _same_take(pops.get_stream(i), bank_dir + files[i]))

func _run() -> void:
	# Build Phaethon last so any accidental contamination of the shared startup bank is visible.
	var seen := {}
	for id: String in [Pilot.SHRIKE, Pilot.ORRERY, Pilot.KILN, Pilot.VESPER, Pilot.STANDARD]:
		var fleet := id != Pilot.STANDARD
		var dir := "res://audio/fleet/%s/" % id if fleet else Engines.DIR
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + ("engine.json" if fleet else "manifest.json")))
		var engine := Engines.new()
		root.add_child(engine)
		engine.setup(Sim.new({"track":"range", "vehicle":id}))
		_engine_check(engine, manifest, dir, id)
		if fleet:
			for layer in ["v8", "turbine", "ramtear"]:
				_check("%s has its own %s performance" % [id, layer], manifest.layers.has(layer))
				if manifest.layers.has(layer):
					_unique_take(seen, dir + manifest.layers[layer].bands[0].file)
			for f: String in manifest.oneshots.pops:
				_unique_take(seen, dir + f)
			for f in [manifest.oneshots.bang, "starter_0.wav", "starter_1.wav", "catch.wav", "chime.wav"]:
				_unique_take(seen, dir + str(f))
		var cabin := Cockpit.new()
		root.add_child(cabin)
		cabin.setup({}, id)
		var start_dir := dir if fleet else Cockpit.DIR
		for k in 2:
			var bus := "EngineL_pops" if k == 0 else "EngineR_pops"
			var starter: AudioStreamPlayer = cabin.players.starter[k]
			var catch_player: AudioStreamPlayer = cabin.players["catch"][k]
			_check("%s start side %d" % [id,k], _same_take(starter.stream, start_dir + "starter_%d.wav" % k)
					and _same_take(catch_player.stream, start_dir + "catch.wav")
					and starter.bus == bus and catch_player.bus == bus)
		_check(id + " cockpit check chime", _same_take(cabin.players.chime[0].stream, start_dir + "chime.wav")
				and cabin.players.chime[0].bus == "Cockpit")
		_check(id + " base pump", _same_take(cabin.players.pump[0].stream, Cockpit.DIR + "pump.wav"))
		for player in engine.find_children("*", "AudioStreamPlayer", true, false):
			(player as AudioStreamPlayer).stop()
		cabin.free()
		engine.free()
		await process_frame
	# Let the audio server retire the last voices before the test closes the tree.
	await create_timer(1.25).timeout
	print("FLEET AUDIO ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
