## Absolute double-precision poses, interpolated on the receiver's monotonic clock.
## [sequence, respawn_epoch, (x,y,z,qx,qy,qz,qw) * 3, thrustL, thrustR, mode]
extends RefCounted

const SIZE := 26
const DELAY_MS := 100
const STALE_MS := 2000
var frames: Array = []
var last_sequence := -1.0

static func valid_packet(value: Variant) -> bool:
	if not value is PackedFloat64Array or value.size() != SIZE:
		return false
	for number in value:
		if not is_finite(number):
			return false
	for i in 2:
		if value[i] < 0.0 or value[i] > 1e12 or value[i] != floor(value[i]):
			return false
	for body in 3:
		var start := 2 + body * 7
		for j in 3:
			if absf(value[start + j]) > 1e7:
				return false
		var length := 0.0
		for j in range(3, 7):
			length += value[start + j] * value[start + j]
		if absf(length - 1.0) > 0.01:
			return false
	return value[23] >= 0 and value[23] <= 2 and value[24] >= 0 and value[24] <= 2 and value[25] in [0.0, 1.0, 2.0]

func push(value: PackedFloat64Array, received_ms: int) -> bool:
	if not valid_packet(value) or value[0] <= last_sequence:
		return false
	if not frames.is_empty() and value[1] != frames.back().pose[1]:
		frames.clear()
	last_sequence = value[0]
	frames.append({"pose": value.duplicate(), "time": received_ms})
	while frames.size() > 12:
		frames.pop_front()
	return true

func sample(now_ms: int) -> PackedFloat64Array:
	if frames.is_empty() or now_ms - int(frames.back().time) > STALE_MS:
		return PackedFloat64Array()
	var target := now_ms - DELAY_MS
	while frames.size() > 2 and int(frames[1].time) <= target:
		frames.pop_front()
	if frames.size() == 1 or target <= int(frames[0].time):
		return frames[0].pose.duplicate()
	if target >= int(frames.back().time):
		return frames.back().pose.duplicate()
	var a: Dictionary = frames[0]
	var b: Dictionary = frames[1]
	var t := clampf(float(target - int(a.time)) / maxf(1.0, float(b.time - a.time)), 0.0, 1.0)
	var out: PackedFloat64Array = b.pose.duplicate()
	for body in 3:
		var start := 2 + body * 7
		for j in 3:
			out[start + j] = lerpf(a.pose[start + j], b.pose[start + j], t)
		var qa := Quaternion(a.pose[start+3], a.pose[start+4], a.pose[start+5], a.pose[start+6]).normalized()
		var qb := Quaternion(b.pose[start+3], b.pose[start+4], b.pose[start+5], b.pose[start+6]).normalized()
		var q := qa.slerp(qb, t)
		out[start+3] = q.x
		out[start+4] = q.y
		out[start+5] = q.z
		out[start+6] = q.w
	return out
