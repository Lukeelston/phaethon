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

func _engine_check(audio: Engines, manifest: Dictionary, bank_dir: String, id: String, base_layers: Dictionary) -> void:
	var layers := base_layers.merged(manifest.layers, true)
	for k in 2:
		var side := "EngineL" if k == 0 else "EngineR"
		var voice: Dictionary = audio.voices[k]
		for layer: String in layers:
			var bands: Array = layers[layer].bands
			var layer_dir := bank_dir if manifest.layers.has(layer) else Engines.DIR
			var bus := side + "_" + layer if layer in Engines.FILTERED else side
			if not Pilot.phaethon_based(id) and layer in ["v8", "v12", "second", "turbine", "rotor"]:
				var glide := voice.glides.get(layer) as Glide
				_check("%s %s %s uses a single continuous voice" % [id, side, layer],
						glide != null and glide.bus == bus and voice.players.get(layer, []).is_empty())
				if glide == null:
					continue
				_check("%s %s %s decoded band count" % [id, side, layer], glide.sources.size() == bands.size())
				for i in mini(glide.sources.size(), bands.size()):
					_check("%s %s %s band %d matches PCM" % [id, side, layer, i],
							_same_take(glide.sources[i], layer_dir + bands[i].file))
				continue
			var players: Array = voice.players[layer]
			_check("%s %s %s band count" % [id, side, layer], players.size() == bands.size())
			for i in mini(players.size(), bands.size()):
				var player: AudioStreamPlayer = players[i]
				var tone := player.stream as AudioStreamWAV
				_check("%s %s %s band %d" % [id, side, layer, i],
						_same_take(tone, layer_dir + bands[i].file) and player.bus == bus
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
	# Lift while pitch is still rising. Count real periods on both sides of
	# the input change: a new straight ramp would reverse the slope instantly.
	player.drive(3, 1, high)
	player._render(roundi(Glide.RATE * .010))
	var crest := player._block.duplicate()
	var pivot := crest.size()
	player.drive(1, 1, low)
	player._render(roundi(Glide.RATE * .015))
	crest.append_array(player._block)
	var last_cross := -1.0
	var first_hz_after_lift := 0.0
	var last_hz_after_lift := 0.0
	for i in range(1, crest.size()):
		var prev := crest[i - 1].x
		var next := crest[i].x
		if prev < 0 and next >= 0:
			var cross := i - 1 - prev / (next - prev)
			if last_cross >= pivot and cross <= pivot + Glide.RATE * .004:
				var hz := Glide.RATE / (cross - last_cross)
				if first_hz_after_lift == 0:
					first_hz_after_lift = hz
				last_hz_after_lift = hz
			last_cross = cross
	_check("a lift rounds off the rising pitch before it falls",
			first_hz_after_lift > 1100 and last_hz_after_lift > first_hz_after_lift * 1.015)
	player.stop()
	player.free()

func _check_twin_rejoin() -> void:
	# A 100 Hz loop makes each shaft's RPM measurable directly from its output.
	var wav := AudioStreamWAV.new()
	wav.mix_rate = Glide.RATE
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	var frames := Glide.RATE / 100
	var pcm := PackedByteArray()
	pcm.resize(frames * 2)
	for i in frames:
		pcm.encode_s16(i * 2, roundi(20000 * sin(TAU * i / frames)))
	wav.data = pcm
	var left := Glide.new()
	var right := Glide.new()
	root.add_child(left)
	root.add_child(right)
	var weights := PackedFloat64Array([1.0])
	var configured := left.configure([wav], 0.0) and right.configure([wav], 0.0, left)
	var format_lifetime: WeakRef = weakref(left.stream)
	_check("paired tone probe loads", configured)
	if configured:
		for player: Glide in [left, right]:
			player.drive(2.0, 1.0, weights)
			player.stream_paused = true
			# Discard the device-specific prefill. Both offline queues start at sample zero.
			player._phase = 0.0
		_check("both engines share one format and keep independent playback rings",
				left.stream == right.stream and left.get_stream_playback() != right.get_stream_playback())
		for stage: String in ["matched", "split", "rejoined"]:
			right.drive(3.17 if stage == "split" else 2.0, 1.0, weights)
			var left_cycles := 0
			var right_cycles := 0
			var last_left := 0.0
			var last_right := 0.0
			var difference := 0.0
			var power := 0.0
			for block in 37:
				# Both read heads are at the same output time, independent of device latency.
				right._align_pair_if_ready(0)
				left._render(frames)
				right._render(frames)
				if block < 27:
					continue
				for i in frames:
					var l := left._block[i].x
					var r := right._block[i].x
					left_cycles += int(last_left < 0 and l >= 0)
					right_cycles += int(last_right < 0 and r >= 0)
					difference += (l - r) * (l - r)
					power += l*l + r*r
					last_left = l
					last_right = r
			var split := stage == "split"
			_check(stage + " twin pitches match their independent inputs",
					absi(left_cycles - 20) <= 1 and absi(right_cycles - (32 if split else 20)) <= 1)
			var residual := difference / maxf(power, .00001)
			_check(stage + " twin output phase", power > 1.0 and (residual > .4 if split else residual < .001))
	left.free()
	right.free()
	_check("the generator remains alive for mixer callbacks after the scene releases both voices",
			format_lifetime != null and format_lifetime.get_ref() != null)

func _run() -> void:
	_check_glide_waveform()
	_check_twin_rejoin()
	# Build Phaethon last so any accidental contamination of the shared startup bank is visible.
	var seen := {}
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Engines.DIR + "manifest.json"))
	for id: String in [Pilot.SHRIKE, Pilot.ORRERY, Pilot.KILN, Pilot.VESPER, Pilot.STANDARD]:
		var fleet := id != Pilot.STANDARD
		var dir := "res://audio/fleet/%s/" % id if fleet else Engines.DIR
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + ("engine.json" if fleet else "manifest.json")))
		var engine := Engines.new()
		root.add_child(engine)
		engine.setup(Sim.new({"track":"range", "vehicle":id}))
		_engine_check(engine, manifest, dir, id, base.layers)
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
	# The Basilisk (merged 2026-11-23, after these banks) has none of its own: its engine and its start-up play
	# the Kiln's (sim/pilot_craft.gd SOUND_BANKS), and load without error.
	var kiln_dir := "res://audio/fleet/%s/" % Pilot.KILN
	var kiln_bank: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(kiln_dir + "engine.json"))
	var gunship := Engines.new()
	root.add_child(gunship)
	gunship.setup(Sim.new({"track":"range", "vehicle":Pilot.BASILISK}))
	_engine_check(gunship, kiln_bank, kiln_dir, Pilot.BASILISK, base.layers)
	var gun_cabin := Cockpit.new()
	root.add_child(gun_cabin)
	gun_cabin.setup({}, Pilot.BASILISK)
	_check("basilisk starts on the Kiln's starter and catch", _same_take(gun_cabin.players.starter[0].stream, kiln_dir + "starter_0.wav")
			and _same_take(gun_cabin.players["catch"][0].stream, kiln_dir + "catch.wav"))
	for player in gunship.find_children("*", "AudioStreamPlayer", true, false):
		(player as AudioStreamPlayer).stop()
	gun_cabin.free()
	gunship.free()
	await process_frame
	# The Talon (2026-11-24) is a Phaethon in another body: its engines and its start-up are the Phaethon's own
	# (sim/pilot_craft.gd sound_bank), not a res://audio/fleet/ bank, and they load without error.
	var talon := Engines.new()
	root.add_child(talon)
	talon.setup(Sim.new({"track":"range", "vehicle":Pilot.TALON}))
	_check("talon plays the Phaethon's own engines, unpaired", not talon._paired_fleet and talon.fleet_voice.is_empty())
	_engine_check(talon, base, Engines.DIR, Pilot.TALON, base.layers)
	var talon_cabin := Cockpit.new()
	root.add_child(talon_cabin)
	talon_cabin.setup({}, Pilot.TALON)
	_check("talon starts on the Phaethon's own starter, catch and chime", _same_take(talon_cabin.players.starter[0].stream, Cockpit.DIR + "starter_0.wav")
			and _same_take(talon_cabin.players.starter[1].stream, Cockpit.DIR + "starter_1.wav")
			and _same_take(talon_cabin.players["catch"][0].stream, Cockpit.DIR + "catch.wav")
			and _same_take(talon_cabin.players.chime[0].stream, Cockpit.DIR + "chime.wav"))
	for player in talon.find_children("*", "AudioStreamPlayer", true, false):
		(player as AudioStreamPlayer).stop()
	talon_cabin.free()
	talon.free()
	await process_frame
	# Let the audio server retire the last voices before the test closes the tree.
	await create_timer(1.25).timeout
	print("FLEET AUDIO ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
