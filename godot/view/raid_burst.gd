## A commuter run down in a raid (view/network_raids.gd's commuter_lost): a brief, bright burst where it was, for any
## craft, armed or not (the gun's effects are its own, and a craft may have no gun, or never arm it). A white-hot core,
## gone by half its life, and a red ring going out from it; DUR s in all. SIDE m across and never less than MIN_ANG to
## the eye, so one kilometres off still shows; its middle LIFT of its side over the deck, so most of it stands over the
## road. One batch of quads turned to the eye, with its own shader, made in the director's build (view/network_raids.gd
## build, which only raids on reach: its shader compiled at load, not at the first loss) and hidden until one is lost:
## with raids off there is none. In the world, so the cockpit's frame hides it as it hides the road (nothing on the
## glass, and nothing moves the camera).
##   var b := RaidBurst.new(); director.add_child(b); b.build(view)
##   b.add(Vector3(x, y, deck))     a burst there (the sims' frame: x, y and the deck's height)
##   b.sync(delta)                  every frame (the director's update): their ages, sizes and places (after the origin)
extends MultiMeshInstance3D

const DUR := 0.9                 # s a burst lasts
const MAX := 8                   # at once (the oldest gives way)
const SIDE := 180.0              # m: its quad's side (the ring, at its widest, is most of it)
const MIN_ANG := 0.05            # rad (2.9 degrees): never less than this across, to the eye
const LIFT := 0.38               # of its side: its middle over the deck
const REACH := 400000.0          # m: its box, about the view's origin (a raider hunts wherever it is: so may a burst be)

# Laid over what is behind it, not added to it: added, by day the ring was a pale pink smudge on the sky and the
# city's towers (1.2 km off it read as 30 pixels of nothing much); laid over, it keeps its red against them, as the
# tactical display's lines keep theirs. Its core still runs past white.
const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

varying vec2 q;
varying float age;

void vertex() {
	age = INSTANCE_CUSTOM.r;      // 0 .. 1 of its life
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	q = UV * 2.0 - 1.0;
}

void fragment() {
	float r = length(q);
	float core = pow(max(0.0, 1.0 - r / max(0.04, 0.6 * (1.0 - age))), 2.0) * (1.0 - smoothstep(0.0, 0.55, age));
	float ring_r = 0.18 + 0.78 * sqrt(age);
	float w = 0.04 + 0.08 * (1.0 - age);
	float ring = exp(-((r - ring_r) * (r - ring_r)) / (w * w)) * (1.0 - age * age) * step(r, 1.0);
	float a = max(core, ring);
	ALBEDO = mix(vec3(1.0, 0.16, 0.05), vec3(1.6, 1.45, 1.15), core / max(a, 0.001));
	ALPHA = clamp(a * 1.15, 0.0, 1.0);
}
"""

var view
var bursts: Array = []           # [[Vector3 the sims' place, age s], ...]
var shown := 0                   # drawn this frame ...
var laid: Array = []             # ... each one's [Transform3D, age 0..1] (tests read them: a headless renderer gives nothing back)


func build(v) -> void:
	view = v
	name = "RaidBurst"
	top_level = true             # (its places are the world's: the view's own frame)
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	multimesh = mm
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.render_priority = 1
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-REACH, -REACH, -REACH), Vector3(2.0 * REACH, 2.0 * REACH, 2.0 * REACH))
	visible = false


## A burst at `at` (the sims' frame: x, y, the deck's height there).
func add(at: Vector3) -> void:
	if bursts.size() >= MAX:
		bursts.pop_front()
	bursts.append([at, 0.0])
	_lay()


func sync(delta: float) -> void:
	if bursts.is_empty() and shown == 0:
		return
	for k in range(bursts.size() - 1, -1, -1):
		bursts[k][1] += delta
		if float(bursts[k][1]) >= DUR:
			bursts.remove_at(k)
	_lay()


## Each one's quad: where it is from the view's origin, its side (no less than MIN_ANG from the eye) and its age.
func _lay() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var eye: Vector3 = cam.global_position if cam else Vector3.ZERO
	var mm := multimesh
	var n := 0
	laid.clear()
	for b in bursts:
		var p: Vector3 = b[0]
		var foot := Vector3(p.x - view.org_x, p.z, -(p.y - view.org_y))
		var side := maxf(SIDE, eye.distance_to(foot) * tan(MIN_ANG))
		var xf := Transform3D(Basis().scaled(Vector3.ONE * side), foot + Vector3.UP * side * LIFT)
		var age := float(b[1]) / DUR
		mm.set_instance_transform(n, xf)
		mm.set_instance_custom_data(n, Color(age, 0.0, 0.0, 0.0))
		laid.append([xf, age])
		n += 1
	mm.visible_instance_count = n
	shown = n
	visible = n > 0
