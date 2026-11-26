## A pose played through time: key poses (garage/boarding_moves.gd) interpolated channel by channel with monotone
## cubics (Fritsch-Butland), so a hand or a foot held at the same point across keys stays exactly there, nothing
## overshoots between keys, and the motion starts and ends at rest. Channels are floats, Vector3s or Quaternions (each
## component in turn; quaternions kept in one hemisphere and normalised after).
##   var track := PoseTrack.new(keys); var pose := track.sample(1.25)
extends RefCounted

var times := PackedFloat32Array()
var duration := 0.0
var _names: Array[String] = []
var _kinds := {}            # channel -> TYPE_FLOAT / TYPE_VECTOR3 / TYPE_QUATERNION
var _values := {}           # channel -> Array of PackedFloat32Array (one per component), a value per key
var _slopes := {}           # channel -> the same, each key's tangent


func _init(keys: Array) -> void:
	for key: Dictionary in keys:
		times.append(float(key.t))
	duration = times[times.size() - 1] if not times.is_empty() else 0.0
	for name: String in keys[0]:
		if name == "t":
			continue
		_names.append(name)
		var kind := typeof(keys[0][name])
		_kinds[name] = kind
		var width := 1 if kind == TYPE_FLOAT else (3 if kind == TYPE_VECTOR3 else 4)
		var columns: Array = []
		for c in width:
			columns.append(PackedFloat32Array())
		var previous := Quaternion.IDENTITY
		for k in keys.size():
			var value = keys[k].get(name, keys[0][name])
			if kind == TYPE_QUATERNION:
				var q: Quaternion = value
				if k > 0 and q.dot(previous) < 0.0:
					q = -q
				previous = q
				value = q
			for c in width:
				columns[c].append(_component(value, c, kind))
		_values[name] = columns
		var tangents: Array = []
		for c in width:
			tangents.append(_tangents(columns[c]))
		_slopes[name] = tangents


static func _component(value, c: int, kind: int) -> float:
	match kind:
		TYPE_FLOAT: return float(value)
		TYPE_VECTOR3: return (value as Vector3)[c]
		_: return [value.x, value.y, value.z, value.w][c]


## Each key's slope: zero at the ends and wherever the value turns (or holds), else the weighted harmonic mean of the
## two segments' slopes (Fritsch and Butland): monotone between keys.
func _tangents(y: PackedFloat32Array) -> PackedFloat32Array:
	var n := y.size()
	var m := PackedFloat32Array()
	m.resize(n)
	for k in range(1, n - 1):
		var h0 := times[k] - times[k - 1]
		var h1 := times[k + 1] - times[k]
		if h0 <= 0.0 or h1 <= 0.0:
			continue
		var d0 := (y[k] - y[k - 1]) / h0
		var d1 := (y[k + 1] - y[k]) / h1
		if d0 * d1 <= 0.0:
			continue
		m[k] = 3.0 * (h0 + h1) / ((2.0 * h1 + h0) / d0 + (h1 + 2.0 * h0) / d1)
	return m


func sample(t: float) -> Dictionary:
	var out := {}
	var n := times.size()
	var k := 0
	if t <= times[0]:
		k = -1
	elif t >= times[n - 1]:
		k = n
	else:
		while k < n - 2 and times[k + 1] <= t:
			k += 1
	for name in _names:
		var kind: int = _kinds[name]
		var columns: Array = _values[name]
		var tangents: Array = _slopes[name]
		var parts := PackedFloat32Array()
		for c in columns.size():
			var y: PackedFloat32Array = columns[c]
			if k < 0:
				parts.append(y[0])
			elif k >= n:
				parts.append(y[n - 1])
			else:
				var h := times[k + 1] - times[k]
				var s := (t - times[k]) / h if h > 0.0 else 1.0
				var m: PackedFloat32Array = tangents[c]
				var s2 := s * s
				var s3 := s2 * s
				parts.append((2.0 * s3 - 3.0 * s2 + 1.0) * y[k] + (s3 - 2.0 * s2 + s) * h * m[k]
						+ (-2.0 * s3 + 3.0 * s2) * y[k + 1] + (s3 - s2) * h * m[k + 1])
		match kind:
			TYPE_FLOAT: out[name] = parts[0]
			TYPE_VECTOR3: out[name] = Vector3(parts[0], parts[1], parts[2])
			_: out[name] = Quaternion(parts[0], parts[1], parts[2], parts[3]).normalized()
	return out
