## An engine's exhaust, from how real ones behave (Luke: "study jet vectoring and make the exhaust
## on the vehicle as realistic as possible"). craft_model.gd builds the nozzle from this and asks it,
## every frame, where the vanes should be, how far the nozzle is open, what the gas is doing and
## where the jet goes; view/flame.gdshader draws the gas. What each number rests on:
##   the vanes     Yaw vanes standing in the stream. The F-18 HARV's vanes swung to +25 degrees at
##                 80 degrees a second (NTRS 19920024160); the X-31's paddles went 35 degrees into
##                 the jet for about 15 of turning (NTRS 19960029101). The jet turns less than the
##                 metal: behind post-exit yaw vanes at most 70 % of the vane's angle (NASA TP-2813,
##                 TP-2973), and less on the burner (the F-15 ACTIVE's plume in flight: 75 % at
##                 military power, 50 % at full burner, NTRS 19980228162; here the flaps open past
##                 the vanes' tips, so part of the jet goes by them unturned). No aircraft has flown
##                 moving vanes inside a slot nozzle: these are the nearest things that have.
##   the command   Not the levers alone. Each engine is a finned body: in a turn its fins try to
##                 weathercock it back into the wind and the vanes hold it off, trailing edges toward
##                 the inside of the turn, by an amount that goes with the cornering load. The levers'
##                 split leads; the load holds. (He steers with a few per cent of split and tens of
##                 g: on the split alone the vanes never moved a degree.)
##   the nozzle    Upper and lower flaps, as a two-dimensional nozzle's: wide at idle, pinched down
##                 as dry thrust comes up, wide open for the burner (an F100's throat opens 2.24
##                 times). They move first, and the flame comes by zones after them: an F100's first
##                 segment lights about 0.4 s after its nozzle starts to open and the rest follow
##                 over as much as four seconds (NTRS 19860015882). Here three zones, as an F119
##                 has, the first at 0.3 s and the last inside a second: the sim's thrust is there
##                 at once, and a flame four seconds behind it would be a lie the other way.
##   the gas       Dry exhaust gives off no light worth the name: what shows is the hot metal up the
##                 pipe. On the burner the gas is blue-violet where it is clean (CH and C2) and
##                 orange where soot burns out, at about 1,660 to 2,030 K. It runs through a train of
##                 shock cells, and what fuel is left relights behind each shock: the diamonds. A
##                 flat jet's cells are 2 h sqrt(Mj^2 - 1) / sqrt(1 + h^2/b^2) long (Tam 1988), each
##                 a little shorter than the last. It stays flat: a 3:1 jet is not round until 14 or
##                 more diameters out (NASA TM-106385), past where this one stops glowing.
##   the bend      A jet thrown across a stream is carried round into it: Margason's line (NASA TN
##                 D-4919), x/D = (z/D)^3 / (4 J sin^2 d) + (z/D) cot d, J the jet's dynamic pressure
##                 over the stream's. Standing still the jet runs straight; at Mach 2 its slope has
##                 halved three diameters out. (Measured for 30 degrees and more in subsonic air; it
##                 is carried down to these angles and up to these speeds for want of anything better.)
##   the metal     Nothing shows under 798 K (the Draper point); dull red by 970, cherry by 1,100,
##                 orange by 1,400. How fast it heats and cools is an estimate (thin sheet in a
##                 fast stream: a couple of seconds up, still dull red five seconds after the burner
##                 is shut); no measurement of it was found.
## The sim is not touched: its thrust and its steering are what they were. This is what is seen.
extends RefCounted

const Kit := preload("res://view/mesh_kit.gd")

# --- the vanes
const VANE_MAX := deg_to_rad(25.0)    # full deflection
const VANE_SLEW := deg_to_rad(80.0)   # the actuators' rate, a second
const VANE_LAG := 0.035               # ... and their lag, s
const SPLIT_FULL := 0.7               # the lever split that asks for all of it
const HOLD_G := 16.0                  # the cornering load, g at full dry thrust, that holds 76 % of it
const TURN_DRY := 0.70                # the jet's turning over the vanes' own, on dry thrust ...
const TURN_BURNER := 0.50             # ... and on the full burner
# --- the nozzle, engine-local metres (forward is -Z)
const PIPE_Z := 3.28                  # the flame holder's face: the floor of the tailpipe
const THROAT_Z := 4.06                # the pipe's mouth, where the flaps hinge
const EXIT_Z := 4.70                  # the flaps' trailing edges: where the jet leaves
const SLOT := Vector2(0.92, 0.25)     # the pipe's half-width and half-height
const EXIT_MIL := 0.185               # the exit's half-height pinched down for full dry thrust ...
const EXIT_MAX := 0.30                # ... and wide open for the burner
const IDLE_OPEN := 0.55               # how far open the flaps stand at idle (0 pinched, 1 wide)
const FLAP_TRAVEL := 0.45             # s, pinched to wide
const FLAP_TEETH := 12                # saw teeth along each flap's trailing edge ...
const FLAP_BITE := 0.05               # ... and how deep they are cut, m
const VANE_Z := 4.02                  # the vanes' pivots
const VANE_CHORD := 0.46
const VANES_AT := [-0.7, 0.0, 0.7]
# --- the burner's lighting
const LIGHT_DELAY := 0.30             # s after it is asked for: the nozzle is opening
const ZONES := 3
const ZONE_TIME := 0.24               # s between one zone's lighting and the next
# --- the gas
const GAMMA := 1.3                    # hot exhaust
const T_AIR := 288.0
const T_DRY := 850.0                  # K, out of the turbine
const T_BURNER := 1850.0              # K: between a typical burner's 1,660 and a J58's 2,030
const T_RAMJET := 2100.0
const D_EQ := 1.12                    # m: the round nozzle of the slot's own area
const REACH_MAX := 11.1               # m: the pod's nose is 12.6 m behind the exit
# --- the metal
const DRAPER := 798.0
const HEAT_TAU := 1.8                 # s, to come up to the gas
const COOL_TAU := 4.5                 # s, to come down


## What the flight computer asks of the vanes, radians (+ = trailing edges right, a right turn): the
## levers' split at once, and the turn's own load held against the fins (`turn_g`: g toward the
## right). A jet with less behind it needs more vane for the same moment.
static func command(split: float, turn_g: float, thrust: float) -> float:
	var stick := clampf(split / SPLIT_FULL, -1.0, 1.0)
	var hold := tanh(turn_g / (HOLD_G * clampf(thrust, 0.45, 1.5)))
	return clampf(stick + hold, -1.0, 1.0) * VANE_MAX


## The vanes a step later: a short lag, and never faster than the actuators go.
static func slew(now: float, want: float, dt: float) -> float:
	return move_toward(now, lerpf(now, want, 1.0 - exp(-dt / VANE_LAG)), VANE_SLEW * dt)


## How much of the vanes' angle the jet takes.
static func turning(lit: float) -> float:
	return lerpf(TURN_DRY, TURN_BURNER, clampf(lit, 0.0, 1.0))


## The fully expanded jet's Mach number for a nozzle pressure ratio.
static func jet_mach(npr: float) -> float:
	return sqrt(maxf(pow(maxf(npr, 1.0), (GAMMA - 1.0) / GAMMA) - 1.0, 0.0) * 2.0 / (GAMMA - 1.0))


## A flat jet's shock cell, m: `h` its height, `b` its width (Tam 1988).
static func cell_length(h: float, b: float, mach: float) -> float:
	return 2.0 * h * sqrt(maxf(mach * mach - 1.0, 0.0)) / sqrt(1.0 + h * h / (b * b))


## How far across the stream a jet has gone `x` m down it, thrown out at `delta` radians to it, with
## `j` times the stream's dynamic pressure (Margason). In still air (j infinite) a straight line.
static func across(x: float, delta: float, j: float, d := D_EQ) -> float:
	var s := sin(absf(delta))
	if s < 1e-5 or x <= 0.0:
		return 0.0
	var cot := cos(absf(delta)) / s
	var a := 0.0 if is_inf(j) else 1.0 / (4.0 * maxf(j, 1e-4) * s * s * d * d)
	var z := x / cot
	for i in 6:      # a z^3 + cot z = x: one root, and Newton from the straight line comes down on it
		z -= (a * z * z * z + cot * z - x) / (3.0 * a * z * z + cot)
	return signf(delta) * z


## What hot metal gives off at `kelvin` (linear light, to add to what it reflects).
static func metal_glow(kelvin: float) -> Color:
	# (view/hot_metal.gdshader's glow(), step for step)
	var c := Color(0.45, 0.02, 0.0) * 0.03 * smoothstep(DRAPER, 950.0, kelvin)
	c = c.lerp(Color(0.90, 0.07, 0.005) * 0.16, smoothstep(950.0, 1100.0, kelvin))
	c = c.lerp(Color(1.0, 0.22, 0.02) * 0.5, smoothstep(1100.0, 1300.0, kelvin))
	c = c.lerp(Color(1.0, 0.38, 0.06) * 1.0, smoothstep(1300.0, 1450.0, kelvin))
	c = c.lerp(Color(1.0, 0.60, 0.20) * 1.8, smoothstep(1450.0, 1600.0, kelvin))
	return Color(c.r, c.g, c.b)


## One engine's nozzle and jet, a frame at a time: an instance of this script (the rest is shared).
var area := IDLE_OPEN      # the flaps: 0 pinched down for full dry thrust, 1 wide for the burner
var exit := 0.25           # the exit's half-height, m
var lit := 0.0             # the burner's flame, 0..1: its zones light one after another
var ram := 0.0             # the ramjet's share, 0..1
var flash := 0.0           # a zone lighting: 1 at the instant, gone in a quarter of a second
var teb := 0.0             # the ramjet's chemical light (a J58 lit on triethylborane: green)
var metal := T_AIR         # the vanes' and the liner's temperature, K
var mach := 1.0            # the jet's fully expanded Mach number
var gas := 600.0           # its speed out of the nozzle, m/s
var j := INF               # its dynamic pressure over the slipstream's
var cell := 1.0            # its first shock cell, m
var shock := 0.0           # how plainly the cells show: how far from matched the nozzle is
var reach := 0.0           # how far it glows, m
var _asked := 0.0          # s since the burner was asked for
var _zones := 0            # zones alight
var _ramming := false

func step(dt: float, burning: bool, mode: String, thrust: float, heat: float, speed: float) -> void:
	var burner: bool = burning and mode != "normal"
	var open := IDLE_OPEN
	if burner:
		open = 1.0
	elif burning:
		open = lerpf(IDLE_OPEN, 0.0, smoothstep(0.08, 0.75, thrust))
	area = move_toward(area, open, dt / FLAP_TRAVEL)
	exit = lerpf(EXIT_MIL, EXIT_MAX, area)
	# the burner: the nozzle leads, then the zones light in turn; shut, it is out at once
	_asked = _asked + dt if burner else 0.0
	var zones := clampi(int(floor((_asked - LIGHT_DELAY) / ZONE_TIME)) + 1, 0, ZONES) if burner and _asked >= LIGHT_DELAY else 0
	if zones > _zones:
		flash = 1.0
	_zones = zones
	if burner:
		lit = move_toward(lit, float(zones) / float(ZONES), dt * 5.0)
	else:
		lit *= exp(-dt / 0.07)
		if lit < 0.002:
			lit = 0.0
	var ramming: bool = burning and mode == "ramjet"
	if ramming and not _ramming:
		teb = 1.0
	_ramming = ramming
	ram = lerpf(ram, 1.0 if ramming else 0.0, 1.0 - exp(-dt * 5.0))
	flash *= exp(-dt / 0.09)
	teb *= exp(-dt / 0.14)
	# the gas
	var m_air := speed / 340.3
	var npr := minf((1.6 + 2.2 * clampf(thrust, 0.0, 1.0)) * (1.0 + 0.08 * m_air * m_air), 14.0)
	mach = jet_mach(npr) if burning else 0.0
	var kelvin := lerpf(lerpf(T_DRY, T_BURNER, lit), T_RAMJET, ram)
	# (an engine that is still pushing throws its gas out faster than the air comes in)
	gas = maxf(sqrt(GAMMA * 287.0 * kelvin) * mach, 1.1 * speed + 120.0) if burning else 0.0
	j = INF if speed < 1.0 else (T_AIR / kelvin) * pow(gas / speed, 2.0)
	cell = maxf(cell_length(2.0 * exit, 2.0 * SLOT.x, mach), 0.35)
	shock = lerpf(0.5, 1.0, clampf(absf(log(npr / 6.0)) / 0.9, 0.0, 1.0)) if burning else 0.0
	# how far it glows: a few diameters dry (and faint), eight or so on the burner, drawn out
	# as the air alongside catches the gas up
	var push := clampf(thrust, 0.0, 1.45)
	var long := lerpf(0.5 + 1.9 * minf(push, 1.0), D_EQ * (3.4 + 3.4 * push), lit) * (1.0 + 0.2 * ram)
	reach = minf(long * (1.0 + 0.3 * clampf(speed / maxf(gas, 1.0), 0.0, 1.0)), REACH_MAX) if burning else 0.0
	# the metal
	var want := T_AIR + 60.0 * heat
	if burning:
		want = lerpf(lerpf(620.0 + 330.0 * clampf(thrust, 0.0, 1.0), 1420.0, lit), 1520.0, ram) + 150.0 * clampf((heat - 0.6) / 0.4, 0.0, 1.0)
	metal = lerpf(metal, want, 1.0 - exp(-dt / (HEAT_TAU if want > metal else COOL_TAU)))


## --- the nozzle's parts -------------------------------------------------------------------------

const LINER := Color(0.085, 0.08, 0.075, 0.6)     # the pipe's ceramic liner, sooted
const CARBON := Color(0.06, 0.06, 0.065, 0.83)     # the vanes: carbon-carbon, as the X-31's paddles (in the gas: they run at its heat)
const GUTTER := Color(0.11, 0.10, 0.09)
const SKIN := Color(0.30, 0.29, 0.33)        # the flaps' and walls' outer skin: heat-tinted titanium


## The material of everything the gas washes (view/hot_metal.gdshader): its own colour in daylight,
## and its glow when hot (set_metal()), each part at its own share of the heat (_hot()).
static func hot_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://view/hot_metal.gdshader")
	return m


static func set_metal(mat: ShaderMaterial, kelvin: float) -> void:
	mat.set_shader_parameter("kelvin", kelvin)


## A part's colour, carrying in its alpha the share of the metal's rise over the air that the part
## runs at (0.5 to 1.1: the shader's scale).
static func _hot(col: Color, share: float) -> Color:
	return Color(col.r, col.g, col.b, clampf((share - 0.5) / 0.6, 0.0, 1.0))


## A box mesh with its tail opened: every face of `mesh` (sitting `z_at` down the engine) that
## stands in the tailpipe's mouth is left out, so the pipe can be seen into.
static func opened(mesh: ArrayMesh, z_at: float) -> ArrayMesh:
	var arr := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var kept := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		var inside := false
		for k in 3:
			var v := verts[idx[t + k]]
			inside = inside or (v.z + z_at > PIPE_Z + 0.2 and absf(v.x) < SLOT.x + 0.04 and absf(v.y) < SLOT.y + 0.04)
		if not inside:
			kept.append_array(PackedInt32Array([idx[t], idx[t + 1], idx[t + 2]]))
	arr[Mesh.ARRAY_INDEX] = kept
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


## A triangle facing `out`. (Godot's fronts are clockwise.) `shares`: each corner's share of the heat.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3, col: Color, shares := PackedFloat32Array()) -> void:
	var flip := (b - a).cross(c - a).dot(out) > 0.0
	var order := [0, 2, 1] if flip else [0, 1, 2]
	var pts := [a, b, c]
	for i in order:
		st.set_color(col if shares.is_empty() else _hot(col, shares[i]))
		st.set_normal(out.normalized())
		st.add_vertex(pts[i])


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3, col: Color, shares := PackedFloat32Array()) -> void:
	if shares.is_empty():
		_tri(st, a, b, c, out, col)
		_tri(st, a, c, d, out, col)
	else:
		_tri(st, a, b, c, out, col, PackedFloat32Array([shares[0], shares[1], shares[2]]))
		_tri(st, a, c, d, out, col, PackedFloat32Array([shares[0], shares[2], shares[3]]))


## The pipe's section at a station: a rounded slot.
static func _ring(half: Vector2, z: float, n: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in n:
		var a := TAU * i / n
		pts.append(Vector3(half.x * Kit._sp(cos(a), 0.4), half.y * Kit._sp(sin(a), 0.4), z))
	return pts


## The tailpipe, seen into from behind: its liner from the flame holder back to the mouth, a rim
## round the mouth, the flame holder's two gutters across it, and the gas side of the nozzle's two
## fixed side walls. One mesh, in hot_material().
static func pipe_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		_wall(side, null, st)
	var n := 44
	var stations := [PIPE_Z, PIPE_Z + 0.3, THROAT_Z - 0.25, THROAT_Z]
	for s in stations.size() - 1:
		var r0 := _ring(SLOT, stations[s], n)
		var r1 := _ring(SLOT, stations[s + 1], n)
		var soot: Color = LINER.lightened(0.10 * (1.0 - float(s) / 2.0))
		var h0 := lerpf(1.04, 0.90, inverse_lerp(PIPE_Z, THROAT_Z, stations[s]))
		var h1 := lerpf(1.04, 0.90, inverse_lerp(PIPE_Z, THROAT_Z, stations[s + 1]))
		for i in n:
			var k := (i + 1) % n
			var mid := (r0[i] + r0[k]) * 0.5
			_quad(st, r0[i], r0[k], r1[k], r1[i], Vector3(-mid.x / SLOT.x, -mid.y / SLOT.y, 0.0), soot, PackedFloat32Array([h0, h0, h1, h1]))
	var inner := _ring(SLOT, THROAT_Z - 0.06, n)
	var outer := _ring(SLOT + Vector2(0.13, 0.12), THROAT_Z - 0.06, n)
	for i in n:
		var k := (i + 1) % n
		_quad(st, inner[i], inner[k], outer[k], outer[i], Vector3.BACK, LINER.darkened(0.3), PackedFloat32Array([0.85, 0.85, 0.55, 0.55]))
	var mesh := st.commit()
	var parts := []
	for y in [-0.085, 0.085]:      # V gutters, open to the back, with the flame sitting in them
		for lean in [-0.62, 0.62]:
			parts.append([Kit.box(Vector3(SLOT.x * 2.0 - 0.02, 0.012, 0.085)), Kit.at(Vector3(0.0, y + 0.024 * signf(lean), PIPE_Z + 0.2), Vector3(lean, 0.0, 0.0)), _hot(GUTTER, 1.1)])
	for x in [-0.46, 0.0, 0.46]:   # ... and the struts that carry them
		parts.append([Kit.box(Vector3(0.022, SLOT.y * 2.0 - 0.02, 0.05)), Kit.at(Vector3(x, 0.0, PIPE_Z + 0.16)), _hot(GUTTER, 1.05)])
	return Kit.compound(parts, mesh)


## A flap's plan: `teeth` saw teeth along its trailing edge, `length` from the hinge (z 0) to their
## points. Returns [hinge points, trailing points] across its width.
static func _flap_plan(half_w: float, length: float, teeth: int, bite: float) -> Array:
	var hinge := PackedVector3Array()
	var trail := PackedVector3Array()
	for i in teeth * 2 + 1:
		var x := -half_w + half_w * float(i) / float(teeth)
		hinge.append(Vector3(x, 0.0, 0.0))
		trail.append(Vector3(x, 0.0, length - (bite if i % 2 == 1 else 0.0)))
	return [hinge, trail]


## One flap's outer skin: its inner face lies in the hinge's own plane (y 0) and it stands up from
## there (+y), thick at the hinge and thin at the trailing edge's teeth.
static func flap_skin(length: float) -> ArrayMesh:
	var plan := _flap_plan(SLOT.x - 0.012, length, FLAP_TEETH, FLAP_BITE)
	var hinge: PackedVector3Array = plan[0]
	var trail: PackedVector3Array = plan[1]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var thick := 0.05
	var thin := 0.012
	var up_at := func(p: Vector3) -> Vector3: return Vector3(p.x, lerpf(thick, thin, p.z / length), p.z)
	var slope := Vector3(0.0, 1.0, (thick - thin) / length)
	for i in hinge.size() - 1:
		_quad(st, hinge[i] + Vector3.UP * thick, hinge[i + 1] + Vector3.UP * thick, up_at.call(trail[i + 1]), up_at.call(trail[i]), slope, SKIN)
		_quad(st, trail[i], trail[i + 1], up_at.call(trail[i + 1]), up_at.call(trail[i]), Vector3.BACK, SKIN.darkened(0.25))
	var last := hinge.size() - 1
	_quad(st, hinge[0], trail[0], up_at.call(trail[0]), hinge[0] + Vector3.UP * thick, Vector3.LEFT, SKIN.darkened(0.15))
	_quad(st, hinge[last], trail[last], up_at.call(trail[last]), hinge[last] + Vector3.UP * thick, Vector3.RIGHT, SKIN.darkened(0.15))
	_quad(st, hinge[0], hinge[last], hinge[last] + Vector3.UP * thick, hinge[0] + Vector3.UP * thick, Vector3.FORWARD, SKIN.darkened(0.3))
	return st.commit()


## ... and its liner, the face the gas washes (in hot_material()).
static func flap_liner(length: float) -> ArrayMesh:
	var plan := _flap_plan(SLOT.x - 0.012, length, FLAP_TEETH, FLAP_BITE)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in (plan[0] as PackedVector3Array).size() - 1:
		_quad(st, plan[0][i], plan[0][i + 1], plan[1][i + 1], plan[1][i], Vector3.DOWN, LINER, PackedFloat32Array([0.92, 0.92, 0.70, 0.70]))
	return st.commit()


## The two side walls' outer skins, one mesh.
static func wall_skins() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		_wall(side, st, null)
	return st.commit()


## A side wall, fixed: it closes the nozzle's side between the two flaps, from the mouth back to a
## raked point. `side` -1 left, +1 right. Its outer skin goes into `skin` and the face the gas washes
## into `liner` (either may be null).
static func _wall(side: float, skin: SurfaceTool, liner: SurfaceTool) -> void:
	var x0 := side * SLOT.x
	var x1 := side * (SLOT.x + 0.032)
	var z0 := THROAT_Z - 0.03
	var profile := [Vector2(-0.27, z0), Vector2(0.27, z0), Vector2(0.215, EXIT_Z - 0.2), Vector2(0.0, EXIT_Z - 0.03), Vector2(-0.215, EXIT_Z - 0.2)]   # (y, z)
	var hub0 := Vector3(x0, 0.0, z0 + 0.3)
	var hub1 := Vector3(x1, 0.0, z0 + 0.3)
	for i in profile.size():
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[(i + 1) % profile.size()]
		var cool := func(z: float) -> float: return lerpf(0.90, 0.68, inverse_lerp(z0, EXIT_Z, z))
		if liner:
			_tri(liner, hub0, Vector3(x0, a.x, a.y), Vector3(x0, b.x, b.y), Vector3(-side, 0.0, 0.0), LINER, PackedFloat32Array([cool.call(hub0.z), cool.call(a.y), cool.call(b.y)]))
		if skin == null:
			continue
		_tri(skin, hub1, Vector3(x1, a.x, a.y), Vector3(x1, b.x, b.y), Vector3(side, 0.0, 0.0), SKIN)
		var edge := Vector3(0.0, b.y - a.y, -(b.x - a.x))      # the rim's own outward: across the edge, in the wall's plane
		if edge.dot(Vector3(0.0, (a.x + b.x) * 0.5, (a.y + b.y) * 0.5 - z0 - 0.3)) < 0.0:
			edge = -edge
		_quad(skin, Vector3(x0, a.x, a.y), Vector3(x0, b.x, b.y), Vector3(x1, b.x, b.y), Vector3(x1, a.x, a.y), edge, SKIN.darkened(0.25))


## A vane: a wedge standing in the stream, pivoted at its leading edge (z 0), lower at the trailing
## edge so the flaps can close over it. In hot_material().
static func vane_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stations := [[0.0, 0.232, 0.014], [0.11, 0.226, 0.027], [VANE_CHORD, 0.168, 0.006]]   # [z, half-height, half-thickness]
	for s in stations.size() - 1:
		var a: Array = stations[s]
		var b: Array = stations[s + 1]
		for side in [-1.0, 1.0]:
			var out := Vector3(side, 0.0, (a[2] - b[2]) / (b[0] - a[0]) * 1.0)
			_quad(st, Vector3(side * a[2], -a[1], a[0]), Vector3(side * a[2], a[1], a[0]), Vector3(side * b[2], b[1], b[0]), Vector3(side * b[2], -b[1], b[0]), out, CARBON)
		for up in [-1.0, 1.0]:
			_quad(st, Vector3(-a[2], up * a[1], a[0]), Vector3(a[2], up * a[1], a[0]), Vector3(b[2], up * b[1], b[0]), Vector3(-b[2], up * b[1], b[0]), Vector3(0.0, up, 0.0), CARBON.lightened(0.06))
	var le: Array = stations[0]
	var te: Array = stations[-1]
	_quad(st, Vector3(-le[2], -le[1], 0.0), Vector3(le[2], -le[1], 0.0), Vector3(le[2], le[1], 0.0), Vector3(-le[2], le[1], 0.0), Vector3.FORWARD, CARBON)
	_quad(st, Vector3(-te[2], -te[1], te[0]), Vector3(te[2], -te[1], te[0]), Vector3(te[2], te[1], te[0]), Vector3(-te[2], te[1], te[0]), Vector3.BACK, CARBON)
	return st.commit()


## The flaps' angle out from the pipe's own line (radians) for an exit half-height.
static func flap_angle(exit_half: float) -> float:
	return atan((exit_half - SLOT.y) / (EXIT_Z - THROAT_Z))
