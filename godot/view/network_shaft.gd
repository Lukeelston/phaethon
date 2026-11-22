## The Network's shafts in the world (Luke: "a vertical shaft that turns over on itself and enters the
## same road it came from"; tools/design_network.py). The sims are flat: a shaft is a paperclip in plan
## whose bulb carries the craft round, and its height is the real altitude along it. This draws the
## plan's stretch between the two feet as the shape it is: from the pull-up a quarter arc R up, V
## straight up, a half arc R over the top (upside down at the apex), V straight down rolling half a
## turn (the right way up again), a quarter arc R out onto the highway the other way. Sample i of the
## road is a point and a frame (t along, l left, n up off the road) in render axes; `lat` m left and
## `up` m off the road lands lat along l and up along n, whichever way up that is. Outside the stretch
## the road is where the sims say.
##   var m := NetworkShaft.new(); m.setup(sim)
##   m.on(road, f)                      is sample f of this road inside a shaft's stretch?
##   m.at(road, f)                      -> [x, y, z (sim axes, 64-bit), t, l, n (render axes)]
##   m.carry(road, f)                   the rotation from the flat road's attitude to the shaft's
extends RefCounted

const OFF := 100.0   # a leg's centreline off the highway's (tools/design_network.py)

var sim
var maps := {}       # road -> {i0, i1, x, y, z (PackedFloat64Array), t, l, n (PackedVector3Array)}


func setup(s) -> void:
	sim = s
	for sh in sim.shafts:
		_build(int(sh[0]), int(sh[1]), int(sh[2]), float(sh[3]), float(sh[4]))
	var twists = sim.get("twists")
	if twists != null:
		for twist in twists:
			_build_twist(int(twist[0]), int(twist[1]), int(twist[2]), float(twist[3]))


## A recovery deck's full roll. The centerline remains the generated road and its
## real altitude; only its cross-section rotates. The existing shaft transport
## API then carries mesh, craft, headset, partner and traffic through one frame.
## This is visual road transport, not the shaft bulb's automatic planar steering.
func _build_twist(r: int, i0: int, i1: int, turns: float) -> void:
	var R = sim.roads[r]
	var xs := PackedFloat64Array()
	var ys := PackedFloat64Array()
	var zs := PackedFloat64Array()
	var ts := PackedVector3Array()
	var ls := PackedVector3Array()
	var ns := PackedVector3Array()
	var total := 0.0
	for i in range(i0, i1):
		total += R.len[i]
	var distance := 0.0
	for i in range(i0, i1 + 1):
		var before := maxi(0, i - 1)
		var after := mini(R.N - 1, i + 1)
		var run: float = R.len[before] + R.len[i]
		var slope: float = (sim.net_height(r, after) - sim.net_height(r, before)) / maxf(run, 0.01)
		var tangent := Vector3(R.tx[i], slope, -R.ty[i]).normalized()
		var left := Vector3(R.nx[i], 0.0, -R.ny[i]).normalized()
		var normal := tangent.cross(left).normalized()
		left = normal.cross(tangent).normalized()
		var fraction := clampf(distance / maxf(total, 1.0), 0.0, 1.0)
		var rotation := TAU * turns * fraction * fraction * (3.0 - 2.0 * fraction)
		xs.append(R.px[i])
		ys.append(R.py[i])
		zs.append(sim.net_height(r, i))
		ts.append(tangent)
		ls.append(left.rotated(tangent, rotation))
		ns.append(normal.rotated(tangent, rotation))
		if i < i1:
			distance += R.len[i]
	maps[r] = {"i0": i0, "i1": i1, "x": xs, "y": ys, "z": zs, "t": ts, "l": ls, "n": ns}


## The shape at d m past the pull-up: [u out, w up, t (u, w), n (u, w), roll toward the landing's way up].
static func shape(d: float, R: float, V: float) -> Array:
	var q := PI * R / 2.0
	if d <= 0.0:
		return [d, 0.0, Vector2(1, 0), Vector2(0, 1), 0.0]
	if d < q:   # the pull-up
		var a := d / R
		return [R * sin(a), R * (1.0 - cos(a)), Vector2(cos(a), sin(a)), Vector2(-sin(a), cos(a)), 0.0]
	if d < q + V:   # straight up
		return [R, R + d - q, Vector2(0, 1), Vector2(-1, 0), 0.0]
	if d < 3.0 * q + V:   # over the top
		var a := (d - q - V) / R + PI / 2.0
		return [R * sin(a), R + V - R * cos(a), Vector2(cos(a), sin(a)), Vector2(-sin(a), cos(a)), 0.0]
	if d < 3.0 * q + 2.0 * V:   # straight down, rolling half a turn
		var k := (d - 3.0 * q - V) / V
		return [-R, R + V - (d - 3.0 * q - V), Vector2(0, -1), Vector2(1, 0), PI * k * k * (3.0 - 2.0 * k)]
	if d < 4.0 * q + 2.0 * V:   # the pull-out
		var a := (d - 3.0 * q - 2.0 * V) / R
		return [-2.0 * R + R * cos(a), R - R * sin(a), Vector2(-sin(a), -cos(a)), Vector2(-cos(a), sin(a)), PI]
	return [-2.0 * R - (d - 4.0 * q - 2.0 * V), 0.0, Vector2(-1, 0), Vector2(0, 1), PI]


func _build(r: int, i0: int, i1: int, R: float, V: float) -> void:
	var Rd = sim.roads[r]
	var ux: float = Rd.tx[i0 - 1]   # (the flat leg's way out: i0's own chord is the bulb's first)
	var uy: float = Rd.ty[i0 - 1]
	var yx := -uy   # the left of the way out
	var yy := ux
	var ox: float = Rd.px[i0] + yx * OFF   # on the highway's line
	var oy: float = Rd.py[i0] + yy * OFF
	var n := i1 - i0 + 1
	var xs := PackedFloat64Array()
	var ys := PackedFloat64Array()
	var zs := PackedFloat64Array()
	var ts := PackedVector3Array()
	var ls := PackedVector3Array()
	var ns := PackedVector3Array()
	var q := PI * R / 2.0
	var d := 0.0
	for i in n:
		var S := shape(d, R, V)
		var u: float = S[0]
		var w: float = S[1]
		var across := 2.0 * q + 2.0 * V
		var ky := clampf((d - q) / across, 0.0, 1.0)
		var y := -OFF + 2.0 * OFF * ky * ky * (3.0 - 2.0 * ky)   # across from the way out's side to the way back's, over the top
		xs.append(ox + ux * u + yx * y)
		ys.append(oy + uy * u + yy * y)
		zs.append(w)
		# the frame in (u, Y, w), right-handed; before the roll the left is +Y
		var t3 := Vector3(S[2].x, 0.0, S[2].y)
		var n3 := Vector3(S[3].x, 0.0, S[3].y)
		var l3 := Vector3(0.0, 1.0, 0.0)
		var ro: float = S[4]
		if ro >= PI:   # rolled: the pull-out's up is its own, the left is the other way now
			l3 = Vector3(0.0, -1.0, 0.0)
		elif ro != 0.0:
			var n2 := n3 * cos(ro) + t3.cross(n3) * sin(ro)
			var l2 := l3 * cos(ro) + t3.cross(l3) * sin(ro)
			n3 = n2
			l3 = l2
		# The road also crosses the highway's line on its way over, 200 m in all: the frame's forward is
		# the centreline's own direction, that crossing included. (It was the shape's alone, so over the
		# top the lanes ran up to 0.8 degrees across the nose of a craft flying dead straight, and at
		# 4,000 mph the road slid 20 m/s sideways under it: Luke, "going fast makes it shift slightly".)
		var slope := 2.0 * OFF * 6.0 * ky * (1.0 - ky) / across      # dy/dd
		if slope != 0.0:
			var axis := t3.cross(Vector3(0.0, 1.0, 0.0)).normalized()
			var tilt := atan(slope)
			t3 = t3.rotated(axis, tilt)
			n3 = n3.rotated(axis, tilt)
			l3 = l3.rotated(axis, tilt)
		ts.append(_render(t3, ux, uy, yx, yy))
		ls.append(_render(l3, ux, uy, yx, yy))
		ns.append(_render(n3, ux, uy, yx, yy))
		if i < n - 1:
			d += Rd.len[i0 + i]
	maps[r] = {"i0": i0, "i1": i1, "x": xs, "y": ys, "z": zs, "t": ts, "l": ls, "n": ns}


## A direction in (u, Y, w) -> render axes (sim x, z, -y).
static func _render(v: Vector3, ux: float, uy: float, yx: float, yy: float) -> Vector3:
	return Vector3(v.x * ux + v.y * yx, v.z, -(v.x * uy + v.y * yy))


func on(road: int, f: float) -> bool:
	if not maps.has(road):
		return false
	var m: Dictionary = maps[road]
	return f > float(m.i0) and f < float(m.i1)


## The road's point and frame at sample f (on the stretch; clamped to its ends).
func at(road: int, f: float) -> Array:
	var m: Dictionary = maps[road]
	var k := clampf(f - float(m.i0), 0.0, float(int(m.i1) - int(m.i0)))
	var a := mini(int(k), int(m.i1) - int(m.i0) - 1)
	var b := a + 1
	var e := k - a
	return [lerpf(m.x[a], m.x[b], e), lerpf(m.y[a], m.y[b], e), lerpf(m.z[a], m.z[b], e),
		(m.t[a] as Vector3).lerp(m.t[b], e).normalized(),
		(m.l[a] as Vector3).lerp(m.l[b], e).normalized(),
		(m.n[a] as Vector3).lerp(m.n[b], e).normalized()]


## The render-axes point `lat` left of and `up` off sample f, against the floating origin.
func point(road: int, f: float, lat: float, up: float, org_x: float, org_y: float) -> Vector3:
	var A := at(road, f)
	return Vector3(float(A[0]) - org_x, A[2], -(float(A[1]) - org_y)) + (A[4] as Vector3) * lat + (A[5] as Vector3) * up


## The road's frame as a basis (x right, y up, z back: the craft's axes).
func frame(road: int, f: float) -> Basis:
	var A := at(road, f)
	return Basis(-(A[4] as Vector3), A[5] as Vector3, -(A[3] as Vector3))


## The rotation that takes an attitude worked out flat on the road (the sims' plane, render axes) onto
## the shaft at sample f.
## `heading_at`: the sample whose plan direction the attitude is laid against, if not f's own (the
## craft's engines: the pod's. CraftView.shaft_carry_body).
func carry(road: int, f: float, heading_at := -1.0) -> Basis:
	return frame(road, f) * Basis(Vector3.UP, plan_heading(road, heading_at if heading_at >= 0.0 else f) - PI / 2.0).inverse()


## The plan road's own direction at sample f (radians). A shaft's plan is straights and arcs, and each
## sample knows its own curvature (kap): its tangent is its chord's, which is the arc's direction at the
## chord's middle, so along the chord the direction runs half the sample's turn either side of that. This
## is the direction the sims turn the craft with (CraftSim.shaft_turn). (Read as the chord's at its
## start, eased to the next chord's, a craft flying dead straight up a shaft was drawn half a sample's
## turn off the road, 0.12 to 0.19 degrees, and swung through twice that where the plan's arcs change
## hands.) Any other road: its samples' tangents, eased from one to the next, as before.
func plan_heading(road: int, f: float) -> float:
	var R = sim.roads[road]
	var i := clampi(int(f), 0, R.N - 2)
	var e := clampf(f - i, 0.0, 1.0)
	if R.shaft:
		return atan2(R.ty[i], R.tx[i]) + (e - 0.5) * R.kap[i] * R.len[i]
	return atan2(lerpf(R.ty[i], R.ty[i + 1], e), lerpf(R.tx[i], R.tx[i + 1], e))
