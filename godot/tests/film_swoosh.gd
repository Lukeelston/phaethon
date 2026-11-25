## The swoosh in the tunnels (Luke after flight 35: "the tunnels has a swooshing sound every second and a
## half"): the game's own mix recorded on the Network with every bus captured on its own, so a repeat can be
## found by measurement and pinned to a bus. Found that way: the wind's rush loop (audio/wind_audio.gd), which
## came round every 1.75 s at 1,127 mph and which the halls' roof reverb lifts about 9 dB. A probe for diagnosis:
## nothing in the game uses it, and it is not a gate (it prints no PASS).
## How to run it: windowed, under the engine's movie writer, so its sound keeps step with the frames whatever the
## machine's load (the guarded runner; the scratchpad's split\sw\sw-record.ps1 does this and extracts the WAV):
##   godot-run.ps1 -Name x -Project <worktree>\godot -GodotArgs @('--xr-mode','off','--resolution','960x540',
##     '--fixed-fps','60','--write-movie','<DIR>\film.avi','-s','res://tests/film_swoosh.gd','--','--out=<DIR>',
##     '--scene=fly','--spot=Glacier@1150@-1','--mph=1015','--to=350','--secs=60')
##   then: ffmpeg -i <DIR>\film.avi -vn -acodec pcm_s16le <DIR>\mix.wav  (and delete the film: ~300 MB a minute)
## That example is Glacier's hall flown the way he flew it (samples down), the hand holding about 1,127 mph:
## open air, the hall (samples 841 to 673), open air.
## Arguments: --out=DIR (required)  --scene=fly|park  --spot=ROAD@SAMPLE[@-1] or city:NAME  --mph=N (the hand
## settles ~115 mph over it)  --to=SAMPLE (fly until the pod passes it)  --secs=N (at most)  --cold  --pad
## --raids=on|off  --raid=CITY (call a raid on it now)  --enclose=0|1 (force CourseAudio's roof off or on).
## Writes DIR/stem_<bus>.f32 (float32 stereo, interleaved, at AudioServer's mix rate: 48 kHz under the movie
## writer; the Master stem is the movie's own sound, sample for sample, from the SWOOSH_ARMED frame on),
## DIR/frames.csv (a row a frame: road and sample, speed, the roof's reverb, the seal, the wind layers' levels and
## pitches, the traffic's whooshes, the raid) and DIR/buses.txt (the buses and their effects, and the wind's loops:
## length, RMS and peak). The wind's whistle and drag get plain buses of their own into Wind (the mix is the same).
extends "res://tests/film_unflown.gd"

const RaidsScript := preload("res://view/network_raids.gd")
var _caps := []          # [bus name, AudioEffectCapture, FileAccess]
var _log: FileAccess
var _passes0 := 0
var _armed_frame := -1
var _enclose := -1       # -1: the game's own; 0/1 forced


func _frame() -> void:
	frames += 1
	if _enclose >= 0 and seat and seat.course_audio:
		_force_roof()
	await process_frame
	_drain()


## Every bus gets a capture at the end of its chain (after its own effects, before its volume). The wind's whistle
## and drag play straight into "Wind": each is given a plain bus of its own into it first (no effect, 0 dB: the mix
## is the same), so they can be told apart.
func _arm() -> void:
	if seat.wind_audio:
		for layer in ["whistle", "drag"]:
			var name := "Wind" + String(layer).capitalize()
			var i := AudioServer.bus_count
			AudioServer.add_bus(i)
			AudioServer.set_bus_name(i, name)
			AudioServer.set_bus_send(i, "Wind")
			seat.wind_audio.players[layer].bus = name
	var names := []
	var info := FileAccess.open(out_dir.path_join("buses.txt"), FileAccess.WRITE)
	info.store_line("mix_rate %d, fps %d" % [AudioServer.get_mix_rate(), Engine.max_fps if Engine.max_fps > 0 else 60])
	for b in AudioServer.bus_count:
		var name := AudioServer.get_bus_name(b)
		var fx := []
		for k in AudioServer.get_bus_effect_count(b):
			fx.append(AudioServer.get_bus_effect(b, k).get_class())
		info.store_line("%d %s -> %s  vol %.1f dB  %s" % [b, name, AudioServer.get_bus_send(b), AudioServer.get_bus_volume_db(b), ", ".join(fx)])
		var cap := AudioEffectCapture.new()
		cap.buffer_length = 1.0
		AudioServer.add_bus_effect(b, cap)
		var f := FileAccess.open(out_dir.path_join("stem_%s.f32" % name), FileAccess.WRITE)
		_caps.append([name, cap, f])
		names.append(name)
	if seat.wind_audio:
		for layer in seat.wind_audio.streams:
			var s: AudioStreamWAV = seat.wind_audio.streams[layer]
			var d := s.data
			var sq := 0.0
			var top := 0
			for i in range(0, d.size() / 2, 7):
				var v := d.decode_s16(i * 2)
				sq += float(v) * v
				top = maxi(top, absi(v))
			info.store_line("wind %s loop: %.2f s, RMS %.1f dBFS, peak %.1f dBFS (every 7th sample)" % [layer, s.get_length(),
				20.0 * log(sqrt(sq / maxf(ceil(d.size() / 2.0 / 7.0), 1.0)) / 32768.0) / log(10.0), 20.0 * log(maxf(top, 1) / 32768.0) / log(10.0)])
	info.close()
	_log = FileAccess.open(out_dir.path_join("frames.csv"), FileAccess.WRITE)
	_log.store_line("frame,t,road,sample,off_road,mph,wet,enclosed,seal,hum,rush,buffet,whistle,flapL,drag,rush_pitch,whistle_pitch,passes,last_db,cars,lev,brk,ram,near,nearest,raid,raid_lost")
	_passes0 = seat.traffic_audio.passes if seat.traffic_audio else 0
	_armed_frame = frames
	print("SWOOSH_ARMED frame %d, mix rate %d, buses %s" % [frames, AudioServer.get_mix_rate(), names])


func _drain() -> void:
	for c in _caps:
		var cap: AudioEffectCapture = c[1]
		var n := cap.get_frames_available()
		if n > 0:
			(c[2] as FileAccess).store_buffer(cap.get_buffer(n).to_byte_array())
	if _log == null or seat == null:
		return
	var P = seat.sim.pod
	var w = seat.wind_audio
	var ca = seat.course_audio
	var ta = seat.traffic_audio
	var cars := 0
	var near := 0           # cars the whooshes could take: within 3 km along and 120 m across the craft's way
	var nearest := 9999.0   # ... the nearest of them along (m, + ahead)
	if seat.traffic_net:
		cars = seat.traffic_net.cars.size()
		var pv := Vector2(P.vx, P.vy)
		var hd := pv.normalized() if pv.length() > 1.0 else Vector2.ZERO
		for c in seat.traffic_net.cars:
			var d := Vector2(c.x - P.x, c.y - P.y)
			var along := d.dot(hd)
			if hd != Vector2.ZERO and absf(along) < 3000.0 and absf(d.cross(hd)) < 120.0:
				near += 1
				if absf(along) < absf(nearest):
					nearest = along
	var ram := 0.0
	if seat.engine_audio and seat.engine_audio.get("ram_level") != null:
		ram = float(seat.engine_audio.get("ram_level"))
	_log.store_line("%d,%.4f,%s,%.2f,%d,%.1f,%.3f,%d,%.3f,%.3f,%.4f,%.4f,%.4f,%.4f,%.4f,%.3f,%.3f,%d,%.1f,%d,%.2f,%.2f,%.3f,%d,%.0f,%s,%d" % [
		frames - _armed_frame, (frames - _armed_frame) * DT, seat.sim.roads[P.path].name, float(seat.sim._road_f(P)), int(P.off_road), _mph(),
		ca.wet if ca else -1.0, int(ca.enclosed()) if ca else -1, w.seal if w else -1.0, w.hum if w else -1.0,
		w.levels.rush if w else 0.0, w.levels.buffet if w else 0.0, w.levels.whistle if w else 0.0, w.levels.flapL if w else 0.0, w.levels.drag if w else 0.0,
		w.players.rush.pitch_scale if w else 0.0, w.players.whistle.pitch_scale if w else 0.0,
		(ta.passes - _passes0) if ta else 0, ta.last_db if ta else -80.0, cars, levers[0], brakes[0], ram, near, nearest,
		(seat.raids.state if seat.raids and seat.raids.state != "" else "-"), seat.raids.lost if seat.raids else 0])


func _close() -> void:
	_drain()
	for c in _caps:
		(c[2] as FileAccess).close()
	_caps.clear()
	if _log:
		_log.close()
		_log = null


## CourseAudio as though under a roof (or not), whatever the road says: its own update eases the reverb.
func _force_roof() -> void:
	var ca = seat.course_audio
	ca.net_halls = {seat.sim.pod.path: [0, 1 << 30]} if _enclose == 1 else {}


## A raid called on `name` now, as the director's _alarm calls one (its pick skips the city the pilot is in, so it
## is set here): within arrive_r of the town zone the director itself places the pack on its next update.
func _call_raid(name: String) -> void:
	var R = seat.raids
	if R == null:
		push_error("No raids in this flight: --raids=on")
		return
	for k in seat.sim.cities.size():
		if String(seat.sim.cities[k].name) == name:
			R.city = k
			R._last_city = k
	R.state = "called"
	R.traffic.race_state = "raid"
	R.traffic.race_t = 0.0
	R.lost = 0
	R.lost_off = 0
	R.kills = 0
	R.fled = 0
	R.pack.clear()
	R._killed.clear()
	R._prey.clear()
	R._tick_t = 0.0
	R._called_t = 0.0
	R._closest = INF
	R._not_closing = 0.0
	R.expire_after = 1e9
	R._t = 0.0
	R._away = 0.0
	R._grace = 0.0
	print("SWOOSH raid called on %s (city %d)" % [name, R.city])


## Hold `mph` with a hand on the levers and air brakes until the pod's sample passes `to` (either way the
## road runs) or `secs` run out.
func _hold(mph: float, to: float, secs: float) -> void:
	var f := 0
	var start := float(seat.sim._road_f(seat.sim.pod))
	var down := to < start
	while f < roundi(secs / DT):
		var at := float(seat.sim._road_f(seat.sim.pod))
		if (down and at <= to) or (not down and at >= to):
			break
		var v := _mph()
		var lever := clampf(0.45 + (mph - v) / 300.0, 0.0, 1.0)
		var brake := clampf((v - mph - 120.0) / 300.0, 0.0, 1.0)
		levers = [lever, lever]
		brakes = [brake, brake]
		await _tick()
		f += 1


func _run() -> void:
	var scene := "fly"
	var spot := "Glacier@1150@-1"
	var mph := 930.0
	var to := 450.0
	var secs := 40.0
	var cold := false
	var pad := false
	var raids := true
	var raid_city := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--scene="):
			scene = arg.trim_prefix("--scene=")
		elif arg.begins_with("--spot="):
			spot = arg.trim_prefix("--spot=")
		elif arg.begins_with("--mph="):
			mph = float(arg.trim_prefix("--mph="))
		elif arg.begins_with("--to="):
			to = float(arg.trim_prefix("--to="))
		elif arg.begins_with("--secs="):
			secs = float(arg.trim_prefix("--secs="))
		elif arg == "--cold":
			cold = true
		elif arg == "--pad":
			pad = true
		elif arg.begins_with("--raids="):
			raids = arg.trim_prefix("--raids=") == "on"
		elif arg.begins_with("--enclose="):
			_enclose = int(arg.trim_prefix("--enclose="))
		elif arg.begins_with("--raid="):
			raid_city = arg.trim_prefix("--raid=")
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	var outlook := preload("res://view/outlook.gd")
	outlook.pinned = true
	outlook.time = "afternoon"
	outlook.weather = "fair"
	preload("res://view/livery.gd").pinned = true
	preload("res://view/network_chase.gd").pinned = true
	RaidsScript.pinned = true
	RaidsScript.enabled = raids
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	caption = Label.new()
	caption.visible = false
	layer.add_child(caption)
	if not await _begin(spot, cold, pad):
		quit(1)
		return
	await _roll(0.5)
	_arm()
	if raid_city != "":
		_call_raid(raid_city)
	print("FILM_BEGIN %.3f" % (frames * DT))
	match scene:
		"fly":
			await _roll(1.0)
			await _hold(mph, to, secs)
		"park":
			levers = [0.0, 0.0]
			brakes = [1.0, 1.0]
			await _roll(secs)
		_:
			push_error("No such scene: " + scene)
	print("FILM_END %.3f" % (frames * DT))
	_close()
	if seat:
		seat.free()
	quit(0)
