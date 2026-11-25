## One phase for all anti-alias levels of a fleet engine layer. Control frames
## specify destinations; consecutive audio samples follow a log-frequency ramp.
extends AudioStreamPlayer

const RATE := 44100
const RESERVE := 1024               # 23 ms of scheduling margin at headset frame rates
const SLICE := 32                   # exact filter endpoints every 0.73 ms
const RESPONSE := RATE * .010       # critical damping; near target in about 47 ms
const SLICE_DECAY := exp(-float(SLICE)/RESPONSE)
# Keep the generator alive while the audio driver finishes playing released voices.
# Each player receives an independent playback ring from this immutable format.
static var _generator_format: AudioStreamGenerator
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
var _log_pitch := 0.0
var _goal_log := 0.0
var _velocity := 0.0               # change in log pitch per filter time constant
var _frame_seconds := 1.0/90.0
var _mute_ramp := 0
var _skips := 0
var _paired_left
var _was_split := false
var _align_remaining := 0
var _align_offset := 0.0
const ALIGN_FRAMES := 1408  # 32 ms between the independent and synchronized read heads


## The other engine side may share the decoded arrays. All supplied WAVs must
## carry the same mono PCM16 performance, with identical length and sample rate.
func configure(streams: Array, start_fraction: float, shared_with = null) -> bool:
	if not _accept_bank(streams, shared_with):
		return false
	if shared_with == null:
		for wav: AudioStreamWAV in streams:
			var raw := wav.data
			var samples := _sample_buffer()
			_decode_range(raw, samples, 0, _length)
			samples[_length] = samples[0]
			_pcm.append(samples)
	_begin_playback(streams, start_fraction)
	return true


## Like configure(), with frame-budget checkpoints while decoding a bank under a live headset.
func configure_sliced(streams: Array, start_fraction: float, shared_with, checkpoint: Callable) -> bool:
	if not _accept_bank(streams, shared_with):
		return false
	if shared_with == null:
		for wav: AudioStreamWAV in streams:
			var raw := wav.data
			var samples := _sample_buffer()
			for first in range(0, _length, 8192):
				await checkpoint.call()
				_decode_range(raw, samples, first, mini(first + 8192, _length))
			samples[_length] = samples[0]
			_pcm.append(samples)
	_begin_playback(streams, start_fraction)
	return true


func _accept_bank(streams: Array, shared_with) -> bool:
	if streams.is_empty() or not sources.is_empty():
		return false
	if shared_with != null:
		if shared_with.sources != streams:
			return false
		_pcm = shared_with._pcm
		_length = shared_with._length
		_paired_left = shared_with
		_was_split = true
		return _pcm.size() == streams.size() and _length > 0
	for wav: AudioStreamWAV in streams:
		if not wav or wav.stereo or wav.format != AudioStreamWAV.FORMAT_16_BITS or wav.mix_rate != RATE:
			return false
		var count := wav.data.size() / 2
		if count < 2 or (_length != 0 and count != _length):
			return false
		_length = count
	return true


func _sample_buffer() -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(_length + 1)
	return samples


static func _decode_range(raw: PackedByteArray, samples: PackedFloat32Array, first: int, end: int) -> void:
	for i in range(first, end):
		samples[i] = raw.decode_s16(2 * i) / 32768.0


func _begin_playback(streams: Array, start_fraction: float) -> void:
	sources.assign(streams)
	_phase = fposmod(start_fraction, 1.0) * _length
	if _generator_format == null:
		_generator_format = AudioStreamGenerator.new()
		_generator_format.mix_rate = RATE
		_generator_format.buffer_length = .095
	stream = _generator_format
	# Generator streams must run on the mixer, including when a platform's
	# default is sample playback. Start after receiving the first target.
	playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	set_process(false)


func drive(pitch_ratio: float, gain: float, weights: PackedFloat64Array) -> void:
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
		_pitch = target_pitch
		_log_pitch = log(target_pitch)
		_velocity = 0
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
	if target_pitch != _want_pitch:
		_goal_log = log(target_pitch)
		_want_pitch = target_pitch
	_want_gain = target_gain
	_want_level = coordinate
	if starting and _playback:
		_process(0.0)


func _process(delta: float) -> void:
	if stream_paused or not playing or not _playback:
		return
	var available := _playback.get_frames_available()
	# Build the next device block progressively, keeping up-to-date targets
	# even on a high-latency driver and spreading work across video frames.
	# A single long graphics frame should not force a block of future audio
	# into the queue and then leave the controls silent until it drains.
	if delta > 0:
		_frame_seconds = lerpf(_frame_seconds, minf(delta,.06), minf(delta*8,.25))
	var reserve := clampi(ceili(_frame_seconds*RATE*1.7)+128, RESERVE, 3072)
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
		_was_split = true
	if _paired_left != null:
		_check_pair()
	_render(count)
	_playback.push_buffer(_block)


## Each shaft runs freely while split. Once the actual pitches settle together,
## recover a consistent mono sum without slewing through a whole engine cycle.
func _check_pair() -> void:
	if not _paired_left._playback:
		return
	# Compare queue tails, not play cursors. If an audio callback drained a
	# queue halfway through this observation, retry on the next game frame.
	var free := _playback.get_frames_available()
	var left_queued: int = _paired_left._capacity - _paired_left._playback.get_frames_available()
	if free != _playback.get_frames_available():
		return
	_align_pair_if_ready(_capacity-free-left_queued)


func _align_pair_if_ready(queue_lead: int) -> void:
	var target_gap := absf(_want_pitch-_paired_left._want_pitch)/_want_pitch
	if target_gap > .001:
		_was_split = true
		return
	if _align_remaining > 0 or target_gap > .0001:
		return
	# Even a tiny deliberate imbalance accumulates phase over a long turn.
	# At an exactly matched hold also inspect the tails if no large split was
	# flagged. Never phase-correct a persistent small throttle difference.
	if not _was_split and (target_gap > 1e-9 or absf(_pitch-_want_pitch) > 1e-9*_pitch):
		return
	if absf(_pitch-_paired_left._pitch) > .0002*_pitch:
		return
	var aligned := fposmod(float(_paired_left._phase) + queue_lead*_pitch, _length)
	_align_offset = fposmod(aligned-_phase, _length)
	_was_split = false
	if minf(_align_offset, _length-_align_offset) > .5:
		_align_remaining = ALIGN_FRAMES


func _render(count: int) -> void:
	_block.resize(count)
	var silent := _gain == 0 and _want_gain == 0
	if silent:
		_block.fill(Vector2.ZERO)
		if _align_remaining:
			_phase = fposmod(_phase+_align_offset, _length)
			_align_remaining = 0
	if silent and _pitch == _want_pitch and _velocity == 0:
		_phase = fposmod(_phase + count*_pitch,_length)
		_level = _want_level
		return
	var lo := clampi(int(_level),0,_pcm.size()-1)
	var low := _pcm[lo]
	var high := _pcm[mini(lo+1,_pcm.size()-1)]
	var first := 0
	var phase := _phase
	while first < count:
		var frames := mini(SLICE,count-first)
		if _align_remaining:
			frames = mini(frames, _align_remaining)
		var t := frames/RESPONSE
		var decay := SLICE_DECAY if frames == SLICE else exp(-t)
		# Solve a critically damped spring in log frequency. Position AND
		# velocity survive every new input, including at throttle reversals.
		var error := _log_pitch - _goal_log
		var tangent := _velocity + error
		_log_pitch = _goal_log + (error + tangent*t)*decay
		_velocity = (_velocity - tangent*t)*decay
		var end_pitch := exp(_log_pitch)
		if absf(_log_pitch-_goal_log) < 1e-8 and absf(_velocity) < 1e-8:
			_log_pitch = _goal_log
			_velocity = 0
			end_pitch = _want_pitch
		# Log change over a submillisecond slice is so small a linear
		# interpolation of frequency between these endpoints suffices.
		var dp := (end_pitch-_pitch)/frames
		var dg := (_want_gain-_gain)*(1-decay)/frames
		var dl := (_want_level-_level)*(1-decay)/frames
		var pitch := _pitch
		var gain := _gain
		var level := _level
		if silent:
			phase += frames*(pitch+dp*(frames+1)*.5)
		elif _align_remaining:
			# Both heads follow the same interpolated control path, so a new
			# split partway through this brief fade stays continuous as well.
			for i in range(first,first+frames):
				pitch += dp
				gain += dg
				level += dl
				lo = int(level)
				low = _pcm[lo]
				high = _pcm[mini(lo+1,_pcm.size()-1)]
				var next := fposmod(phase+_align_offset,_length)
				var p := int(phase)
				var q := int(next)
				var a := lerpf(lerpf(low[p],low[p+1],phase-p), lerpf(high[p],high[p+1],phase-p),level-lo)
				var b := lerpf(lerpf(low[q],low[q+1],next-q), lerpf(high[q],high[q+1],next-q),level-lo)
				var blend := smoothstep(0.0, 1.0, 1.0 - float(_align_remaining)/ALIGN_FRAMES)
				var sample := lerpf(a,b,blend)*gain
				_block[i] = Vector2(sample,sample)
				phase = fposmod(phase+pitch,_length)
				_align_remaining -= 1
			if not _align_remaining:
				phase = fposmod(phase+_align_offset,_length)
		elif _pcm.size() == 1 or (dl == 0 and level == lo):
			# A one-band rotor and a layer parked at either end of its mip bank
			# need one sample lookup and interpolation.
			for i in range(first,first+frames):
				pitch += dp
				gain += dg
				var pos := int(phase)
				var sample := lerpf(low[pos],low[pos+1],phase-pos)*gain
				_block[i] = Vector2(sample,sample)
				phase += pitch
				if phase >= _length:
					phase = fposmod(phase,_length)
		else:
			for i in range(first,first+frames):
				pitch += dp
				gain += dg
				level += dl
				var band := int(level)
				if band != lo:
					lo = band
					low = _pcm[lo]
					high = _pcm[mini(lo+1,_pcm.size()-1)]
				var pos := int(phase)
				var frac := phase-pos
				var sample := lerpf(lerpf(low[pos],low[pos+1],frac),
					lerpf(high[pos],high[pos+1],frac),level-lo)*gain
				_block[i] = Vector2(sample,sample)
				phase += pitch
				if phase >= _length:
					phase = fposmod(phase,_length)
		if silent and phase >= _length:
			phase = fposmod(phase,_length)
		_pitch = end_pitch
		_gain += dg*frames
		_level += dl*frames
		if absf(_gain-_want_gain) < 1e-7:
			_gain = _want_gain
		first += frames
	_phase = phase
	if _mute_ramp > 0:
		for i in mini(count,_mute_ramp):
			_block[i] *= 1.0-float(_mute_ramp)/96.0
			_mute_ramp -= 1
