## One phase for all anti-alias levels of a fleet engine layer. Control frames
## specify destinations; consecutive audio samples follow a log-frequency ramp.
extends AudioStreamPlayer

const RATE := 44100
const RESERVE := 1024               # 23 ms of scheduling margin at headset frame rates
const SLEW := 794                   # 18 ms pitch, gain and mip interpolation
var sources: Array[AudioStreamWAV] = []  # configured mip assets, in order
var _pcm: Array[PackedFloat32Array] = []
var _length := 0
var _phase := 0.0
var _playback: AudioStreamGeneratorPlayback
var _capacity := 0
var _quantum := 0
var _block := PackedVector2Array()
var _pitch := 1.0
var _gain := 0.0
var _level := 0.0                  # continuous mip coordinate, e.g. 2.25
var _want_pitch := 1.0
var _want_gain := 0.0
var _want_level := 0.0
var _steps := 0
var _fresh_target := false
var _last_drive_us := 0
var _mute_ramp := 0
var _skips := 0


## The other engine side may share the decoded arrays. All supplied WAVs must
## carry the same mono PCM16 performance, with identical length and sample rate.
func configure(streams: Array, start_fraction: float, shared_with = null) -> bool:
	if streams.is_empty() or not sources.is_empty():
		return false
	if shared_with != null:
		if shared_with.sources != streams:
			return false
		_pcm = shared_with._pcm
		_length = shared_with._length
		if _pcm.size() != streams.size() or _length == 0:
			return false
	else:
		for wav: AudioStreamWAV in streams:
			if not wav or wav.stereo or wav.format != AudioStreamWAV.FORMAT_16_BITS or wav.mix_rate != RATE:
				return false
			var bytes := wav.data
			var count := bytes.size() / 2
			if count < 2 or (_length != 0 and count != _length):
				return false
			_length = count
			var samples := PackedFloat32Array()
			samples.resize(count + 1)
			for i in count:
				samples[i] = bytes.decode_s16(2*i) / 32768.0
			samples[count] = samples[0]    # interpolate through the seam
			_pcm.append(samples)
	sources.assign(streams)
	_phase = fposmod(start_fraction, 1.0) * _length
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = RATE
	generator.buffer_length = .095
	stream = generator
	# Generator streams must run on the mixer, including when a platform's
	# default is sample playback. Start after receiving the first target.
	playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	set_process(false)
	return true


func drive(pitch_ratio: float, gain: float, weights: PackedFloat64Array) -> void:
	var now := Time.get_ticks_usec()
	var interval := clampi(roundi((now-_last_drive_us)*RATE/1000000.0), 0, 2880) if _last_drive_us else SLEW
	_last_drive_us = now
	var starting := not playing and not stream_paused
	var sum := 0.0
	var coordinate := 0.0
	for i in weights.size():
		sum += weights[i]
		coordinate += weights[i]*i
	coordinate /= maxf(sum, .00001)
	var target_gain := sum*gain      # retain the original correlation correction
	var target_pitch := maxf(.01,pitch_ratio)
	if starting or not _playback:
		_gain = 0
		_steps = SLEW
		_pitch = target_pitch
		_level = coordinate
		play()
		_playback = get_stream_playback() as AudioStreamGeneratorPlayback
		if not _playback:
			return
		_capacity = _playback.get_frames_available()
		# Some drivers drain 4096 samples in one callback. Headset drivers
		# usually drain substantially smaller blocks. Size to the actual device.
		var driver_interval := AudioServer.get_time_since_last_mix() + AudioServer.get_time_to_next_mix()
		_quantum = clampi(roundi(driver_interval*RATE), 128, _capacity-RESERVE)
		_skips = _playback.get_skips()
		set_process(true)
	if target_pitch != _want_pitch or target_gain != _want_gain or coordinate != _want_level:
		_want_pitch = target_pitch
		_want_gain = target_gain
		_want_level = coordinate
		_steps = maxi(SLEW, interval)
		_fresh_target = true
	if starting and _playback:
		_process(0.0)


func _process(delta: float) -> void:
	if stream_paused or not playing or not _playback:
		return
	var available := _playback.get_frames_available()
	# Build the next device block progressively, keeping up-to-date targets
	# even on a high-latency driver and spreading work across video frames.
	var reserve := clampi(ceili(delta*RATE*1.7)+128, RESERVE, 3072)
	var until_mix := clampi(roundi(AudioServer.get_time_to_next_mix()*RATE), 0, _quantum)
	var target := mini(_capacity, _quantum + reserve - (0 if delta == 0 else until_mix))
	var count := mini(available, target - (_capacity - available))
	if count <= 0:
		return
	var skips := _playback.get_skips()
	if skips != _skips:
		# Restart on a short fade if the host starved the mixer.
		_mute_ramp = 96
		_skips = skips
	if _fresh_target:
		# Cover the next control interval and the actual sample batch, even at 30 Hz.
		if delta > 0:
			_steps = maxi(_steps, maxi(count, mini(ceili(delta*RATE*1.1), 2880)))
		_fresh_target = false
	_render(count)
	_playback.push_buffer(_block)


func _render(count: int) -> void:
	_block.resize(count)
	var ratio := pow(_want_pitch/_pitch,1.0/maxi(_steps,1))
	var dg := (_want_gain-_gain)/maxi(_steps,1)
	var dl := (_want_level-_level)/maxi(_steps,1)
	if _gain == 0 and _want_gain == 0:
		# The turbine may spool for seconds below its lighting threshold. Sum
		# the geometric pitch ramp exactly without touching any PCM samples.
		var slew_frames := mini(count,_steps)
		var multiplier := pow(ratio,slew_frames)
		var distance := _pitch*slew_frames
		if absf(ratio-1.0) > 1e-9:
			distance = _pitch*ratio*(multiplier-1.0)/(ratio-1.0)
		_phase = fposmod(_phase + distance + (count-slew_frames)*_want_pitch,_length)
		_steps -= slew_frames
		_pitch = _want_pitch if _steps == 0 else _pitch*multiplier
		_level = _want_level if _steps == 0 else _level+slew_frames*dl
		_block.fill(Vector2.ZERO)
		return
	var lo := clampi(int(_level),0,_pcm.size()-1)
	var low := _pcm[lo]
	var high := _pcm[mini(lo+1,_pcm.size()-1)]
	for i in count:
		if _steps > 0:
			_pitch *= ratio
			_gain += dg
			_level += dl
			_steps -= 1
			if _steps == 0:
				_pitch = _want_pitch
				_gain = _want_gain
				_level = _want_level
		var band := int(_level)
		if band != lo:
			lo = band
			low = _pcm[lo]
			high = _pcm[mini(lo+1,_pcm.size()-1)]
		var pos := int(_phase)
		var frac := _phase - pos
		var sample := lerpf(lerpf(low[pos],low[pos+1],frac),
			lerpf(high[pos],high[pos+1],frac),_level-lo)*_gain
		if _mute_ramp > 0:
			sample *= 1.0-float(_mute_ramp)/96.0
			_mute_ramp -= 1
		_block[i] = Vector2(sample,sample)
		_phase += _pitch
		if _phase >= _length:
			_phase = fposmod(_phase,_length)
