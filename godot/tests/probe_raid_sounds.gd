## The raid's sounds (audio/raid_sounds.gd) made and measured: the time each takes to make, its length, peak and level
## (the RMS of its loudest 100 ms), and with --out=DIR each written there as a WAV for a look at its spectrum (no sound
## is played). Headless: --headless -s res://tests/probe_raid_sounds.gd -- [--out=DIR]
extends SceneTree

const RaidSounds := preload("res://audio/raid_sounds.gd")


func _initialize() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var total := 0.0
	for name: String in RaidSounds.NAMES:
		var w: AudioStreamWAV = RaidSounds.make(name)
		var ms: float = RaidSounds.make_ms[name]
		total += ms
		if w == null:
			print("PROBE %s: not made (%.1f ms)" % [name, ms])
			continue
		var x := RaidSounds.samples(w)
		var peak := 0.0
		for v in x:
			peak = maxf(peak, absf(v))
		var loud := RaidSounds.loudest(x, w.mix_rate)
		print("PROBE %s: %.1f ms, %.2f s, peak %.1f dBFS, loudest 100 ms %.1f dBFS (wanted %.1f), loop %s" % [name, ms,
			x.size() / float(w.mix_rate), linear_to_db(peak), linear_to_db(loud), RaidSounds.LEVELS[name], w.loop_mode != 0])
		if out != "":
			DirAccess.make_dir_recursive_absolute(out)
			w.save_to_wav(out.path_join(name + ".wav"))
	print("PROBE all seven made in %.1f ms" % total)
	quit()
