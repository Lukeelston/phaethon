## The jolt's effects, shared by the flat view and the headset (craft_view.gd, vr/vr_cockpit.gd jolt): a thump synthesised in
## code (no recording), and the red vignette's two shaders (a canvas one for the flat view; a spatial one for a quad
## held before the headset camera: it moves with the head, so it moves nothing).
extends RefCounted

const Synth := preload("res://audio/course_audio.gd")
const SHAKE_S := 0.15            # s the flat view's shake lasts, at the most
const FLASH_S := 0.35            # s the vignette takes to clear
const RED := "vec3(0.92, 0.05, 0.04)"

const CANVAS := "shader_type canvas_item;
uniform float amount = 0.0;
void fragment() {
	float r = length(UV * 2.0 - 1.0);
	COLOR = vec4(" + RED + ", clamp(smoothstep(0.55, 1.2, r) * amount, 0.0, 1.0) * 0.8);
}"

const SPATIAL := "shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, shadows_disabled;
uniform float amount = 0.0;
void fragment() {
	float r = length(UV * 2.0 - 1.0);
	ALBEDO = " + RED + ";
	ALPHA = clamp(smoothstep(0.55, 1.2, r) * amount, 0.0, 1.0) * 0.8;
}"

static var _thump: AudioStreamWAV


## A body blow: a sine falling from 95 to 38 Hz with a short burst of low noise on its front, dying away in 0.4 s.
static func thump(seconds := 0.4, rate := 22050) -> AudioStreamWAV:
	if _thump != null:
		return _thump
	var n := int(seconds * rate)
	var l := PackedFloat32Array()
	l.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1124
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		phase += TAU * lerpf(95.0, 38.0, 1.0 - exp(-t * 14.0)) / rate
		lp += 0.12 * (rng.randf_range(-1.0, 1.0) - lp)
		l[i] = (sin(phase) * exp(-t * 7.0) + 1.6 * lp * exp(-t * 40.0)) * minf(t * 800.0, 1.0)
	_thump = Synth._wav(l, l.duplicate(), rate, 0.85)
	return _thump


static func canvas_material() -> ShaderMaterial:
	var s := Shader.new()
	s.code = CANVAS
	var m := ShaderMaterial.new()
	m.shader = s
	return m


static func spatial_material() -> ShaderMaterial:
	var s := Shader.new()
	s.code = SPATIAL
	var m := ShaderMaterial.new()
	m.shader = s
	m.render_priority = 127
	return m
