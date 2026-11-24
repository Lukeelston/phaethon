## Verify the actual samples on both engine players, after changing craft in one session.
extends SceneTree

const Sim := preload("res://sim/craft_sim.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Engines := preload("res://audio/engine_audio.gd")
const Glide := preload("res://audio/fleet_pitch_glide.gd")
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
			var bus := side + "_" + layer if layer in Engines.FILTERED else side
			if id != Pilot.STANDARD and layer in ["v8", "turbine"]:
				var glide := voice.glides.get(layer) as Glide
				_check("%s %s %s uses a single continuous voice" % [id, side, layer],
						glide != null and glide.bus == bus and voice.players.get(layer, []).is_empty())
				if glide == null:
					continue
				_check("%s %s %s decoded band count" % [id, side, layer], glide.sources.size() == bands.size())
				for i in mini(glide.sources.size(), bands.size()):
					_check("%s %s %s band %d matches PCM" % [id, side, layer, i],
							_same_take(glide.sources[i], bank_dir + bands[i].file))
				continue
			var players: Array = voice.players[layer]
			_check("%s %s %s band count" % [id, side, layer], players.size() == bands.size())
			for i in mini(players.size(), bands.size()):
				var player: AudioStreamPlayer = players[i]
				var tone := player.stream as AudioStreamWAV
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

# Measure periods in emitted samples. A pitch setter stepped at game-frame rate
# can pass target/RPM tests while jumping straight from one period to another.
func _check_glide_waveform() -> void:
	var wav := AudioStreamWAV.new()
	wav.mix_rate = Glide.RATE
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	var bytes := PackedByteArray()
	var frames := Glide.RATE / 10  # 100 exact cycles in the loop
	bytes.resize(2*frames)
	for i in frames:
		bytes.encode_s16(2*i, roundi(20000*sin(TAU*100*i/frames)))
	wav.data = bytes
	var player := Glide.new()
	root.add_child(player)
	_check("calibrated pitch probe loads", player.configure([wav,wav], .98))
	var low := PackedFloat64Array([1,0])
	var high := PackedFloat64Array([0,1])
	player.drive(1, 1, low)
	player._render(4096)
	for rising in [true, false]:
		player.drive(3 if rising else 1, 1, high if rising else low)
		player._render(4096)
		var block := player._block
		var prev_cross := -1.0
		var last_hz := 0.0
		var intermediate := 0
		var continuous := true
		for i in range(1, block.size()):
			var prev := block[i-1].x
			var next := block[i].x
			if prev >= 0 or next < 0:
				continue
			var cross := i-1 - prev/(next-prev)
			if prev_cross >= 0:
				var hz := Glide.RATE / (cross-prev_cross)
				if hz > 1150 and hz < 2750:
					intermediate += 1
				if last_hz > 0:
					continuous = continuous and absf(log(hz/last_hz)) < .16
					continuous = continuous and (hz > last_hz*.985 if rising else hz < last_hz*1.015)
				last_hz = hz
			prev_cross = cross
		var expected := 3000.0 if rising else 1000.0
		_check("rendered note glides to %.0f Hz through intermediate periods across the mip seam" % expected,
				continuous and intermediate >= 4 and absf(last_hz/expected-1) < .015)
	player.stop()
	player.free()

func _run() -> void:
	_check_glide_waveform()
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
