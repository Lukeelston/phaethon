## The speed rush (Luke, 2026-11-22: "can you also add a little parallax/zoom effect with speed?").
## A flat-screen racer widens its field of view and pulls its camera back as the speed builds. A headset's
## field of view is the runtime's, and a world moved against the pilot's head makes him ill. So this is
## built from what is comfortable in a headset:
##   the parallax  the cockpit's fittings (vr_cockpit.gd's shell: the dash, the canopy's frame, the nose)
##                 ease a few centimetres away from the pilot as the craft pulls and as its speed builds,
##                 and back toward him under the air brakes: pressed into the seat, thrown into the belts.
##                 Fore and aft only, on a spring, never turned. The head, the world and the horizon are
##                 where they were: nothing the headset's camera hangs from is touched. `ease_surge()`.
##   the zoom      fine streaks in the air alongside, a few metres out: near enough to slide against the
##                 canopy's frame as the head moves, and longer, more of them and brighter as the speed
##                 builds. They stream back along the craft's own way, and none is drawn within CLEAR
##                 degrees of dead ahead: the road is looked at through nothing. `build()`, `sync()`.
## How much: "a little", and then (Luke, 2026-11-23, having flown it: "turn the parallax up a bit more")
## half as much again: every length below is one and a half times what it first was, and the two limits on
## how it moves with them, so it takes the same time to get there. The craft's own fore-and-aft load does
## most of it (a launch is 30 g and more), and a smaller steady part grows with the logarithm of the speed,
## so there is something of it through a whole run and not only off the line (tests/probe_rush.gd is the
## table these were set by).
## The quick menu's OPTIONS page switches it (SPEED RUSH, saved; on unless switched off). Off, the cockpit
## sits exactly where it did and nothing is drawn.
extends Node3D

const EffectExclusion := preload("res://view/effect_exclusion.gd")
const Hour := preload("res://view/outlook.gd")
const MPH := 2.236936
const SPEED_MPH := Vector2(300.0, 10000.0)   # the speed's share of it: none at the first, all at the second, by the logarithm between

# --- the parallax ---
const FWD_MAX := 0.0525       # m: the cockpit's furthest forward of where it rests (the pilot pressed back) ...
const AFT_MAX := 0.0375       # ... and its furthest back toward him (thrown into the belts): the travel's ends, never passed
const LOAD_FWD := 0.024       # m: what the craft's pull moves it, at most ...
const LOAD_G := 14.0          # ... two thirds of that by this many g (it saturates: a launch, 30 g, has nearly all of it)
const LOAD_AFT := 0.039       # m: what braking brings it back, at most (it has the speed's part to take back first) ...
const BRAKE_G := 40.0         # ... two thirds of that by this many g (a light squeeze at speed is 20 g, a hard one 60)
const SPEED_FWD := 0.024      # m: the steady part, at SPEED_MPH.y
const LOAD_T := 0.2           # s: the load is read through this much more smoothing (the g-meter's own is 0.15 s)
const HZ := 1.2               # the spring: there in about half a second ...
const ZETA := 1.0             # ... and no bounce
const RATE_MAX := 0.12        # m/s: never faster than this ...
const ACCEL_MAX := 0.75       # m/s2: ... nor pushed harder (a thirteenth of a g)
var load_g := 0.0             # the fore-and-aft load as the parallax reads it, g (+ speeding up)
var surge := 0.0              # the cockpit's place now, m forward of where it rests (- toward the pilot)
var rate := 0.0               # m/s

# --- the streaks ---
const COUNT := 150            # at most (all of them out at SPEED_MPH.y)
const RADIUS := Vector2(1.7, 5.0)        # m from the line through the seated eye along the craft's way: none nearer, none further
const ARC := Vector2(-15.0, 195.0)       # degrees round that line from the pilot's right, over the top, to his left: none under the floor
const AHEAD := 10.0           # m ahead of the eye that one comes in ...
const BEHIND := 3.0           # ... and behind it that it goes out
const END_FADE := 2.0         # m: it comes in and goes out over this
const LENGTH := Vector2(0.8, 4.5)        # m: a streak's length at SPEED_MPH.x and at SPEED_MPH.y (each a little longer or shorter)
const WIDTH := 0.008          # m
const WIDTH_MIN := 0.0012     # radians: never thinner than this to the eye (1.7 of a Quest 3's pixels; thinner, a line crawls)
const CLEAR := Vector2(26.0, 44.0)       # degrees off the craft's way, from the eye: nothing inside the first, all of it outside the second
const STEP_MAX := 0.4         # of its own length: the furthest a streak goes by in a frame (further, it flickers instead of streaming)
const BRIGHT := 0.34          # at full speed, added to what is behind it ...
const BRIGHT_NIGHT := 0.5     # ... and this much of that by night, when what is behind it is dark (Outlook.darkness)
const TINT := Color(0.82, 0.92, 1.0)
const FADE_T := 0.6           # s: switched on or off, they come and go over this
const CYCLES := 4096.0        # (the air's travel is kept under this many passes: a float has the millimetres for it)
static var streaks_drawn := true         # (timings only: false leaves them undrawn, the rest as it is)
var streaks: MeshInstance3D
var mat: ShaderMaterial
var travel := 0.0             # m of air gone by, as the streaks show it
var shown := 0.0              # 0 off .. 1 on, eased
var _view

const STREAK_SHADER := """
// The speed rush's streaks (vr/speed_rush.gd). The mesh is COUNT quads with no shape of their own: each
// vertex carries its streak's lot (VERTEX: where between the radii, where round the arc, where along the
// run; UV2: whether it is out at this speed, how long it is) and its corner (UV). Model space is the
// air's: -Z is the way the craft goes, the origin the seated eye.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
#include "res://view/effect_exclusion.gdshaderinc"
uniform float travel = 0.0;
uniform float amount = 0.0;
uniform float strength = 0.0;
uniform float streak_length = 2.0;
uniform vec3 tint = vec3(0.82, 0.92, 1.0);
uniform vec2 radius = vec2(1.7, 5.0);
uniform vec2 arc = vec2(-0.26, 3.4);
uniform vec2 run = vec2(10.0, 3.0);      // ahead, behind
uniform float end_fade = 2.0;
uniform vec2 width = vec2(0.008, 0.0012);
uniform vec2 clear = vec2(0.45, 0.77);
varying float lit;

void vertex() {
	float span = run.x + run.y;
	float s = VERTEX.z * span + travel;
	float lap = floor(s / span);
	float along = run.x - (s - lap * span);      // m ahead of the eye: it comes in at run.x and goes out at -run.y
	// a new place round the craft each time it comes by
	float lot = fract(sin(VERTEX.y * 91.7 + VERTEX.x * 37.3 + mod(lap, 4096.0) * 17.13) * 43758.5453);
	float ang = mix(arc.x, arc.y, fract(VERTEX.y + lot));
	float rad = mix(radius.x, radius.y, fract(VERTEX.x + lot * 7.0));
	float len = streak_length * (0.55 + 0.9 * UV2.y);
	vec3 p = vec3(cos(ang) * rad, sin(ang) * rad, -along + (UV.y - 0.5) * len);
	vec3 eye = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec3 to_eye = eye - p;
	float reach = max(length(to_eye), 0.001);
	vec3 side = cross(vec3(0.0, 0.0, 1.0), to_eye);
	side = length(side) > 1e-4 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	VERTEX = p + side * (UV.x - 0.5) * max(width.x, reach * width.y);
	effect_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float out_now = smoothstep(UV2.x - 0.04, UV2.x + 0.04, amount);
	float ends = smoothstep(-run.y, -run.y + end_fade, along) * (1.0 - smoothstep(run.x - end_fade, run.x, along));
	// the eye's own ray to it, against the craft's way: dead ahead stays clear for either eye and a head that leans
	float off = acos(clamp(to_eye.z / reach, -1.0, 1.0));
	lit = strength * out_now * ends * smoothstep(clear.x, clear.y, off) * (0.6 + 0.4 * UV2.y);
	if (strength * out_now * ends <= 0.002) {
		VERTEX = vec3(0.0);      // not out at this speed, or at an end of its run: no area, nothing to fill
	}
}

void fragment() {
	if (lit <= 0.002) {
		discard;
	}
	// (a streak is a pixel or two wide: under multisampling its UV is read at pixel centres that lie outside it,
	// so each part is held to 0..1: what is added must never be negative, nor bright where it has run out)
	float across = clamp(1.0 - abs(UV.x * 2.0 - 1.0), 0.0, 1.0);
	// a head at the end it goes by first (the aft one: UV.y 1), and a tail drawn out ahead of it
	float body = smoothstep(0.0, 0.8, UV.y) * (1.0 - smoothstep(0.94, 1.0, UV.y));
	float outside = exterior_effect_visibility(effect_world_position, CAMERA_POSITION_WORLD);
	ALBEDO = tint * (clamp(lit, 0.0, 1.0) * body * across * across * outside);
}
"""


## How far through the speed's range, 0..1, by the logarithm (300 mph: 0; 1,000: 0.34; 3,000: 0.66;
## 5,000: 0.80; 8,000: 0.94; 10,000: 1).
static func speed_share(mph: float) -> float:
	return clampf(log(maxf(mph, 1.0) / SPEED_MPH.x) / log(SPEED_MPH.y / SPEED_MPH.x), 0.0, 1.0)


## The steady part at this speed, m forward.
static func speed_part(mph: float) -> float:
	return SPEED_FWD * speed_share(mph)


## What this fore-and-aft load asks for, m forward (- toward the pilot, braking).
static func load_part(g: float) -> float:
	if g >= 0.0:
		return LOAD_FWD * (1.0 - exp(-g / LOAD_G))
	return -LOAD_AFT * (1.0 - exp(g / BRAKE_G))


## Where the cockpit is asked to be under this load at this speed, m forward of its rest: inside the travel.
static func target(g: float, mph: float) -> float:
	return clampf(load_part(g) + speed_part(mph), -AFT_MAX, FWD_MAX)


## A frame of the parallax: the cockpit's place, m forward of its rest, eased toward what the load `g_along`
## (g, + speeding up) and the speed ask for; toward its rest while `on` is false. Never past the travel's
## ends, never faster than RATE_MAX, never pushed harder than ACCEL_MAX. Off and at rest it is exactly 0.
func ease_surge(delta: float, g_along: float, mph: float, on: bool) -> float:
	var remaining := clampf(delta, 0.0, 0.05)
	load_g += (g_along - load_g) * (1.0 - exp(-remaining / LOAD_T))
	var want := target(load_g, mph) if on else 0.0
	if not on and surge == 0.0 and rate == 0.0:
		return 0.0
	var w := TAU * HZ
	while remaining > 0.000001:
		var step := minf(remaining, 1.0 / 240.0)
		var accel := clampf(w * w * (want - surge) - 2.0 * ZETA * w * rate, -ACCEL_MAX, ACCEL_MAX)
		rate = clampf(rate + accel * step, -RATE_MAX, RATE_MAX)
		surge += rate * step
		if surge > FWD_MAX or surge < -AFT_MAX:      # (the spring has no bounce and its aim is inside the travel: a stop, in case)
			surge = clampf(surge, -AFT_MAX, FWD_MAX)
			rate = 0.0
		remaining -= step
	if not on and absf(surge) < 0.00002 and absf(rate) < 0.0002:      # home: exactly
		surge = 0.0
		rate = 0.0
	return surge


## How long a streak is at this share of the speed's range, m.
static func streak_length(share: float) -> float:
	return lerpf(LENGTH.x, LENGTH.y, share)


## How many of the streaks are out, 0..1.
static func streak_amount(share: float) -> float:
	return 0.0 if share <= 0.0 else lerpf(0.3, 1.0, share)


## How bright they are, 0..BRIGHT: none at SPEED_MPH.x, in over the first tenth of the range.
static func streak_strength(share: float) -> float:
	return BRIGHT * smoothstep(0.0, 0.1, share) * lerpf(0.55, 1.0, share)


## The streaks, built: hidden until there is speed (sync). `view` is the cockpit (for the cabin they stay out of).
func build(view) -> void:
	_view = view
	name = "speed_rush"
	var sh := Shader.new()
	sh.code = STREAK_SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tint", Vector3(TINT.r, TINT.g, TINT.b))
	mat.set_shader_parameter("radius", RADIUS)
	mat.set_shader_parameter("arc", Vector2(deg_to_rad(ARC.x), deg_to_rad(ARC.y)))
	mat.set_shader_parameter("run", Vector2(AHEAD, BEHIND))
	mat.set_shader_parameter("end_fade", END_FADE)
	mat.set_shader_parameter("width", Vector2(WIDTH, WIDTH_MIN))
	mat.set_shader_parameter("clear", Vector2(deg_to_rad(CLEAR.x), deg_to_rad(CLEAR.y)))
	streaks = MeshInstance3D.new()
	streaks.name = "speed_streaks"
	streaks.mesh = streak_mesh()
	streaks.material_override = mat
	streaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	streaks.custom_aabb = AABB(Vector3(-RADIUS.y, -RADIUS.y, -AHEAD - LENGTH.y), Vector3(2.0 * RADIUS.y, 2.0 * RADIUS.y, AHEAD + BEHIND + 2.0 * LENGTH.y))
	# Drawn in its turn by distance, as the rain is, and by this node's own place (the seated eye), not its box's
	# middle: so always after the clouds and the dust it is in front of, whichever way the head is turned. That is
	# after the canopy's glass too, whose shade band does not dim it (drawn under the glass by priority it was
	# drawn under the clouds as well, and went behind them).
	streaks.sorting_use_aabb_center = false
	streaks.visible = false
	add_child(streaks)


## COUNT quads, each vertex carrying its streak's lot (the shader places them).
static func streak_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261122
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var lots := PackedVector2Array()
	var idx := PackedInt32Array()
	for k in COUNT:
		var lot := Vector3(rng.randf(), rng.randf(), rng.randf())
		var more := Vector2((float(k) + 0.5) / float(COUNT), rng.randf())      # (evenly through the count: a tenth more speed, a tenth more of them)
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			verts.append(lot)
			uvs.append(corner)
			lots.append(more)
		for i in [0, 1, 2, 0, 2, 3]:
			idx.append(k * 4 + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = lots
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A frame of the streaks: `flow` is the air's frame in the cockpit's parent's space (its origin the seated
## eye, its -Z the way the craft goes, level), `mph` the craft's speed, `on` whether they are wanted (the
## switch, and the seat's own camera).
func sync(delta: float, mph: float, on: bool, flow: Transform3D) -> void:
	if streaks == null:
		return
	shown = move_toward(shown, 1.0 if on else 0.0, clampf(delta, 0.0, 0.05) / FADE_T)
	var share := speed_share(mph)
	var k := shown * streak_strength(share) * lerpf(1.0, BRIGHT_NIGHT, Hour.darkness())
	streaks.visible = streaks_drawn and k > 0.002
	if not streaks.visible:
		return
	transform = flow
	var long := streak_length(share)
	# as far as the craft has gone, but no further in a frame than a streak can go by and still be seen to stream
	travel = fposmod(travel + minf(mph / MPH * clampf(delta, 0.0, 0.05), STEP_MAX * long), (AHEAD + BEHIND) * CYCLES)
	mat.set_shader_parameter("travel", travel)
	mat.set_shader_parameter("amount", streak_amount(share))
	mat.set_shader_parameter("strength", k)
	mat.set_shader_parameter("streak_length", long)
	EffectExclusion.apply(_view, [mat])
